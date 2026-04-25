#!chezscheme
;; M2.2 chunk D-3: Vulkan plumbing for textured instanced-quad text.
;;
;; Builds, on top of an existing logical device + render pass, the
;; complete state needed to draw glyph quads:
;;
;;   * The font atlas: a parsed PSF2 → R8 image with per-glyph UVs.
;;     The atlas pixels live in a TILING_OPTIMAL device-local image.
;;     Upload uses a host-visible staging buffer + a one-shot
;;     command buffer (barrier → copy → barrier) so the runtime
;;     drawing path doesn't have to deal with image transitions.
;;
;;   * Descriptor set layout / pool / set bound to (sampler + view).
;;
;;   * Pipeline layout with a single 32-byte push constant range
;;     readable from both the vertex stage (viewport size) and the
;;     fragment stage (foreground color).
;;
;;   * Graphics pipeline using shader.scm's embedded SPIR-V.  Vertex
;;     input is one binding, INSTANCE rate, two vec4 attributes
;;     (xywh, uv-rect).  Viewport / scissor are dynamic so resizing
;;     wouldn't need a pipeline rebuild.
;;
;;   * Instance buffer: host-visible + host-coherent, persistently
;;     mapped, sized for a configurable max number of glyphs per
;;     frame.
;;
;; build-text-pipeline returns a text-pipeline record.  Failures
;; mid-construction roll back partial state and re-raise.  Once
;; built, the only mutable bits are the mapped instance buffer
;; (written by the renderer on every frame).
(library (letloop desktop text-pipeline)
  (export
   build-text-pipeline
   destroy-text-pipeline!
   text-pipeline?
   text-pipeline-font
   text-pipeline-pipeline
   text-pipeline-pipeline-layout
   text-pipeline-descriptor-set
   text-pipeline-instance-buffer
   text-pipeline-instance-mapped
   text-pipeline-max-instances
   text-pipeline-instance-stride
   text-pipeline-write-instances!)
  (import
   (chezscheme)
   (letloop desktop vulkan low)
   (letloop desktop psf2)
   (letloop desktop font)
   (letloop desktop font-bundled)
   (letloop desktop shader))

  ;; ----------------------------------------------------------------
  ;; Common helpers (small re-implementations to avoid leaking
  ;; private helpers from window.scm).
  ;; ----------------------------------------------------------------

  (define (foreign-alloc/zero nbytes)
    (let ((p (foreign-alloc nbytes)))
      (do ((i 0 (+ i 1))) ((= i nbytes))
        (foreign-set! 'unsigned-8 p i 0))
      p))

  (define (vk-check who r)
    (unless (= r VK_SUCCESS)
      (error who (vk-result-name r) r))
    r)

  ;; Default ASCII range for the bundled atlas. Covers space..~ which
  ;; is enough to render the M2.2 deliverable's English text and any
  ;; printable CLI input. Extending later for Unifont is one bigger
  ;; (range . codepoints) list.
  (define DEFAULT-CODEPOINTS
    (let loop ((i #x20) (acc '()))
      (if (> i #x7E)
          (reverse acc)
          (loop (+ i 1) (cons i acc)))))

  ;; Per-instance data is two vec4s: xywh + uv-rect = 32 bytes.
  (define INSTANCE-STRIDE 32)

  ;; ----------------------------------------------------------------
  ;; The record
  ;; ----------------------------------------------------------------

  (define-record-type text-pipeline
    (fields
     font
     atlas-image
     atlas-memory
     atlas-view
     atlas-sampler
     descriptor-set-layout
     descriptor-pool
     descriptor-set
     pipeline-layout
     pipeline
     vertex-module
     fragment-module
     instance-buffer
     instance-memory
     instance-mapped         ; uptr
     max-instances
     instance-stride))

  (define (text-pipeline-write-instances! tp instances)
    ;; instances is a list/vector of 8-element float lists:
    ;;   (x y w h u v uw uh)
    ;; Returns the number of instances actually written, capped at
    ;; max-instances. Caller passes that count to vkCmdDraw.
    (let* ((cap   (text-pipeline-max-instances tp))
           (m     (text-pipeline-instance-mapped tp))
           (st    (text-pipeline-instance-stride tp)))
      (let loop ((ins instances) (i 0))
        (cond
         ((or (null? ins) (= i cap)) i)
         (else
          (let ((row (car ins))
                (off (* i st)))
            (do ((j 0 (+ j 1))
                 (vs row (cdr vs)))
                ((= j 8))
              (foreign-set! 'float m (+ off (* j 4))
                            (exact->inexact (car vs)))))
          (loop (cdr ins) (+ i 1)))))))

  ;; ----------------------------------------------------------------
  ;; build-text-pipeline
  ;; ----------------------------------------------------------------

  (define (build-text-pipeline device physical-device render-pass
                               graphics-queue command-pool)
    (define rollback '())
    (define (track! t) (set! rollback (cons t rollback)))
    (define (do-rollback!)
      (for-each (lambda (t) (guard (e (#t (void))) (t))) rollback))
    (guard (e (#t (do-rollback!) (raise e)))
     (let* ((psf  (psf2-load bundled-psf2))
            (font (font-build psf DEFAULT-CODEPOINTS))
            (mem-props (read-memory-properties physical-device))
            ;; Atlas image (device-local).
            (atlas-image
             (create-r8-image device
                              (font-atlas-width font)
                              (font-atlas-height font)
                              (bitwise-ior VK_IMAGE_USAGE_TRANSFER_DST_BIT
                                           VK_IMAGE_USAGE_SAMPLED_BIT)))
            (_track-img
             (begin (track! (lambda () (vkDestroyImage device atlas-image 0))) #f))
            (atlas-memory
             (alloc-image-memory device atlas-image mem-props
                                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))
            (_track-mem
             (begin (track! (lambda () (vkFreeMemory device atlas-memory 0))) #f))
            (_bind-img
             (begin
               (vk-check 'vkBindImageMemory
                         (vkBindImageMemory device atlas-image atlas-memory 0))
               #f))
            ;; Upload pixels via staging buffer + one-shot command.
            (_upload
             (begin
               (upload-atlas-pixels! device physical-device mem-props
                                     graphics-queue command-pool
                                     atlas-image
                                     (font-atlas-width font)
                                     (font-atlas-height font)
                                     (font-atlas-pixels font))
               #f))
            ;; Atlas view + sampler.
            (atlas-view
             (create-r8-image-view device atlas-image))
            (_track-view
             (begin (track! (lambda () (vkDestroyImageView device atlas-view 0))) #f))
            (atlas-sampler
             (create-atlas-sampler device))
            (_track-samp
             (begin (track! (lambda () (vkDestroySampler device atlas-sampler 0))) #f))
            ;; Descriptor set layout — 1 combined image sampler in fragment.
            (descriptor-set-layout
             (create-text-descriptor-set-layout device))
            (_track-dsl
             (begin (track!
                     (lambda ()
                       (vkDestroyDescriptorSetLayout device descriptor-set-layout 0)))
                    #f))
            ;; Pipeline layout — 1 set + push constants (32 bytes).
            (pipeline-layout
             (create-text-pipeline-layout device descriptor-set-layout))
            (_track-pl
             (begin (track!
                     (lambda ()
                       (vkDestroyPipelineLayout device pipeline-layout 0)))
                    #f))
            ;; Shader modules.
            (vertex-module   (create-shader-module device text-vertex-spirv))
            (_track-vm
             (begin (track! (lambda () (vkDestroyShaderModule device vertex-module 0))) #f))
            (fragment-module (create-shader-module device text-fragment-spirv))
            (_track-fm
             (begin (track! (lambda () (vkDestroyShaderModule device fragment-module 0))) #f))
            ;; Graphics pipeline.
            (pipeline
             (create-text-graphics-pipeline device pipeline-layout render-pass
                                            vertex-module fragment-module))
            (_track-p
             (begin (track! (lambda () (vkDestroyPipeline device pipeline 0))) #f))
            ;; Descriptor pool + set.
            (descriptor-pool
             (create-text-descriptor-pool device))
            (_track-dp
             (begin (track!
                     (lambda ()
                       (vkDestroyDescriptorPool device descriptor-pool 0)))
                    #f))
            (descriptor-set
             (allocate-text-descriptor-set device descriptor-pool
                                           descriptor-set-layout))
            ;; descriptor set's lifetime is tied to the pool; no separate destroy.
            (_write-ds
             (begin
               (write-text-descriptor-set! device descriptor-set
                                           atlas-view atlas-sampler)
               #f))
            ;; Instance buffer (host visible + coherent, persistently mapped).
            (max-instances 4096)
            (instance-buffer
             (create-host-visible-vertex-buffer device
                                                (* max-instances INSTANCE-STRIDE)))
            (_track-ib
             (begin (track! (lambda () (vkDestroyBuffer device instance-buffer 0))) #f))
            (instance-memory
             (alloc-buffer-memory device instance-buffer mem-props
                                  (bitwise-ior VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
                                               VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)))
            (_track-im
             (begin (track! (lambda () (vkFreeMemory device instance-memory 0))) #f))
            (_bind-ib
             (begin
               (vk-check 'vkBindBufferMemory
                         (vkBindBufferMemory device instance-buffer instance-memory 0))
               #f))
            (instance-mapped
             (let ((out (foreign-alloc/zero 8)))
               (dynamic-wind
                void
                (lambda ()
                  (vk-check 'vkMapMemory
                            (vkMapMemory device instance-memory 0
                                         (* max-instances INSTANCE-STRIDE) 0
                                         out))
                  (foreign-ref 'uptr out 0))
                (lambda () (foreign-free out)))))
            (_track-map
             (begin (track! (lambda () (vkUnmapMemory device instance-memory))) #f)))
       (set! rollback '())
       (make-text-pipeline
        font
        atlas-image atlas-memory atlas-view atlas-sampler
        descriptor-set-layout descriptor-pool descriptor-set
        pipeline-layout pipeline
        vertex-module fragment-module
        instance-buffer instance-memory instance-mapped
        max-instances INSTANCE-STRIDE))))

  ;; ----------------------------------------------------------------
  ;; destroy-text-pipeline! — reverse of the build, swallowing
  ;; individual destroy failures so we always reach the end.
  ;; ----------------------------------------------------------------

  (define (destroy-text-pipeline! device tp)
    (define (silent t) (guard (e (#t (void))) (t)))
    (silent (lambda () (vkUnmapMemory device (text-pipeline-instance-memory tp))))
    (silent (lambda () (vkFreeMemory device (text-pipeline-instance-memory tp) 0)))
    (silent (lambda () (vkDestroyBuffer device (text-pipeline-instance-buffer tp) 0)))
    (silent (lambda () (vkDestroyDescriptorPool device (text-pipeline-descriptor-pool tp) 0)))
    (silent (lambda () (vkDestroyPipeline device (text-pipeline-pipeline tp) 0)))
    (silent (lambda () (vkDestroyShaderModule device (text-pipeline-fragment-module tp) 0)))
    (silent (lambda () (vkDestroyShaderModule device (text-pipeline-vertex-module tp) 0)))
    (silent (lambda () (vkDestroyPipelineLayout device (text-pipeline-pipeline-layout tp) 0)))
    (silent (lambda () (vkDestroyDescriptorSetLayout device (text-pipeline-descriptor-set-layout tp) 0)))
    (silent (lambda () (vkDestroySampler device (text-pipeline-atlas-sampler tp) 0)))
    (silent (lambda () (vkDestroyImageView device (text-pipeline-atlas-view tp) 0)))
    (silent (lambda () (vkFreeMemory device (text-pipeline-atlas-memory tp) 0)))
    (silent (lambda () (vkDestroyImage device (text-pipeline-atlas-image tp) 0))))

  ;; ----------------------------------------------------------------
  ;; Memory type lookup
  ;; ----------------------------------------------------------------

  (define (read-memory-properties physical-device)
    ;; Returns a list of (type-index property-flags heap-index) for each
    ;; memoryType reported by the device.
    (let* ((p   (foreign-alloc/zero
                 (ftype-sizeof <VkPhysicalDeviceMemoryProperties>)))
           (fp  (make-ftype-pointer <VkPhysicalDeviceMemoryProperties> p)))
      (dynamic-wind
       void
       (lambda ()
         (vkGetPhysicalDeviceMemoryProperties physical-device p)
         (let ((n (ftype-ref <VkPhysicalDeviceMemoryProperties> (memoryTypeCount) fp)))
           (let loop ((i 0) (out '()))
             (if (= i n)
                 (reverse out)
                 (loop (+ i 1)
                       (cons (list i
                                   (ftype-ref <VkPhysicalDeviceMemoryProperties>
                                              (memoryTypes i propertyFlags) fp)
                                   (ftype-ref <VkPhysicalDeviceMemoryProperties>
                                              (memoryTypes i heapIndex) fp))
                             out))))))
       (lambda () (foreign-free p)))))

  (define (pick-memory-type mem-props type-bits required-flags)
    ;; type-bits is the memoryTypeBits field from a *MemoryRequirements
    ;; struct: bit i set iff type i is usable. We pick the first type
    ;; that's both usable and has every required-flag bit set.
    (let loop ((tys mem-props))
      (cond
       ((null? tys)
        (error 'pick-memory-type
               "no Vulkan memory type satisfies requirements"
               type-bits required-flags))
       (else
        (let* ((ty (car tys))
               (i  (car ty))
               (flags (cadr ty)))
          (if (and (not (zero? (bitwise-and type-bits
                                            (bitwise-arithmetic-shift-left 1 i))))
                   (= (bitwise-and flags required-flags) required-flags))
              i
              (loop (cdr tys))))))))

  ;; ----------------------------------------------------------------
  ;; Image creation + memory allocation
  ;; ----------------------------------------------------------------

  (define (create-r8-image device width height usage-flags)
    (let* ((info (foreign-alloc/zero (ftype-sizeof <VkImageCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkImageCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkImageCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO)
         (ftype-set! <VkImageCreateInfo> (imageType) fp VK_IMAGE_TYPE_2D)
         (ftype-set! <VkImageCreateInfo> (format) fp VK_FORMAT_R8_UNORM)
         (ftype-set! <VkImageCreateInfo> (extent width) fp width)
         (ftype-set! <VkImageCreateInfo> (extent height) fp height)
         (ftype-set! <VkImageCreateInfo> (extent depth) fp 1)
         (ftype-set! <VkImageCreateInfo> (mipLevels) fp 1)
         (ftype-set! <VkImageCreateInfo> (arrayLayers) fp 1)
         (ftype-set! <VkImageCreateInfo> (samples) fp VK_SAMPLE_COUNT_1_BIT)
         (ftype-set! <VkImageCreateInfo> (tiling) fp VK_IMAGE_TILING_OPTIMAL)
         (ftype-set! <VkImageCreateInfo> (usage) fp usage-flags)
         (ftype-set! <VkImageCreateInfo> (sharingMode) fp VK_SHARING_MODE_EXCLUSIVE)
         (ftype-set! <VkImageCreateInfo> (initialLayout) fp VK_IMAGE_LAYOUT_UNDEFINED)
         (vk-check 'vkCreateImage (vkCreateImage device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda () (foreign-free out) (foreign-free info)))))

  (define (alloc-image-memory device image mem-props required-flags)
    (let* ((req (foreign-alloc/zero (ftype-sizeof <VkMemoryRequirements>)))
           (info (foreign-alloc/zero (ftype-sizeof <VkMemoryAllocateInfo>)))
           (out  (foreign-alloc/zero 8))
           (rfp  (make-ftype-pointer <VkMemoryRequirements> req))
           (ifp  (make-ftype-pointer <VkMemoryAllocateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (vkGetImageMemoryRequirements device image req)
         (let* ((size  (ftype-ref <VkMemoryRequirements> (size) rfp))
                (bits  (ftype-ref <VkMemoryRequirements> (memoryTypeBits) rfp))
                (idx   (pick-memory-type mem-props bits required-flags)))
           (ftype-set! <VkMemoryAllocateInfo> (sType) ifp
                       VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO)
           (ftype-set! <VkMemoryAllocateInfo> (allocationSize) ifp size)
           (ftype-set! <VkMemoryAllocateInfo> (memoryTypeIndex) ifp idx)
           (vk-check 'vkAllocateMemory
                     (vkAllocateMemory device info 0 out))
           (foreign-ref 'unsigned-64 out 0)))
       (lambda ()
         (foreign-free out) (foreign-free info) (foreign-free req)))))

  (define (create-r8-image-view device image)
    (let* ((info (foreign-alloc/zero (ftype-sizeof <VkImageViewCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkImageViewCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkImageViewCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO)
         (ftype-set! <VkImageViewCreateInfo> (image) fp image)
         (ftype-set! <VkImageViewCreateInfo> (viewType) fp VK_IMAGE_VIEW_TYPE_2D)
         (ftype-set! <VkImageViewCreateInfo> (format) fp VK_FORMAT_R8_UNORM)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange aspectMask) fp
                     VK_IMAGE_ASPECT_COLOR_BIT)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange baseMipLevel) fp 0)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange levelCount) fp 1)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange baseArrayLayer) fp 0)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange layerCount) fp 1)
         (vk-check 'vkCreateImageView (vkCreateImageView device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda () (foreign-free out) (foreign-free info)))))

  (define (create-atlas-sampler device)
    (let* ((info (foreign-alloc/zero (ftype-sizeof <VkSamplerCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkSamplerCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkSamplerCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO)
         (ftype-set! <VkSamplerCreateInfo> (magFilter) fp VK_FILTER_NEAREST)
         (ftype-set! <VkSamplerCreateInfo> (minFilter) fp VK_FILTER_NEAREST)
         (ftype-set! <VkSamplerCreateInfo> (mipmapMode) fp
                     VK_SAMPLER_MIPMAP_MODE_NEAREST)
         (ftype-set! <VkSamplerCreateInfo> (addressModeU) fp
                     VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE)
         (ftype-set! <VkSamplerCreateInfo> (addressModeV) fp
                     VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE)
         (ftype-set! <VkSamplerCreateInfo> (addressModeW) fp
                     VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE)
         (ftype-set! <VkSamplerCreateInfo> (maxLod) fp 0.0)
         (ftype-set! <VkSamplerCreateInfo> (minLod) fp 0.0)
         (ftype-set! <VkSamplerCreateInfo> (borderColor) fp
                     VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK)
         (vk-check 'vkCreateSampler (vkCreateSampler device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda () (foreign-free out) (foreign-free info)))))

  ;; ----------------------------------------------------------------
  ;; Buffers
  ;; ----------------------------------------------------------------

  (define (create-host-visible-vertex-buffer device size)
    (let* ((info (foreign-alloc/zero (ftype-sizeof <VkBufferCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkBufferCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkBufferCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO)
         (ftype-set! <VkBufferCreateInfo> (size) fp size)
         (ftype-set! <VkBufferCreateInfo> (usage) fp
                     VK_BUFFER_USAGE_VERTEX_BUFFER_BIT)
         (ftype-set! <VkBufferCreateInfo> (sharingMode) fp
                     VK_SHARING_MODE_EXCLUSIVE)
         (vk-check 'vkCreateBuffer (vkCreateBuffer device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda () (foreign-free out) (foreign-free info)))))

  (define (create-staging-buffer device size)
    (let* ((info (foreign-alloc/zero (ftype-sizeof <VkBufferCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkBufferCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkBufferCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO)
         (ftype-set! <VkBufferCreateInfo> (size) fp size)
         (ftype-set! <VkBufferCreateInfo> (usage) fp
                     VK_BUFFER_USAGE_TRANSFER_SRC_BIT)
         (ftype-set! <VkBufferCreateInfo> (sharingMode) fp
                     VK_SHARING_MODE_EXCLUSIVE)
         (vk-check 'vkCreateBuffer (vkCreateBuffer device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda () (foreign-free out) (foreign-free info)))))

  (define (alloc-buffer-memory device buffer mem-props required-flags)
    (let* ((req (foreign-alloc/zero (ftype-sizeof <VkMemoryRequirements>)))
           (info (foreign-alloc/zero (ftype-sizeof <VkMemoryAllocateInfo>)))
           (out  (foreign-alloc/zero 8))
           (rfp  (make-ftype-pointer <VkMemoryRequirements> req))
           (ifp  (make-ftype-pointer <VkMemoryAllocateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (vkGetBufferMemoryRequirements device buffer req)
         (let* ((size  (ftype-ref <VkMemoryRequirements> (size) rfp))
                (bits  (ftype-ref <VkMemoryRequirements> (memoryTypeBits) rfp))
                (idx   (pick-memory-type mem-props bits required-flags)))
           (ftype-set! <VkMemoryAllocateInfo> (sType) ifp
                       VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO)
           (ftype-set! <VkMemoryAllocateInfo> (allocationSize) ifp size)
           (ftype-set! <VkMemoryAllocateInfo> (memoryTypeIndex) ifp idx)
           (vk-check 'vkAllocateMemory
                     (vkAllocateMemory device info 0 out))
           (foreign-ref 'unsigned-64 out 0)))
       (lambda ()
         (foreign-free out) (foreign-free info) (foreign-free req)))))

  ;; ----------------------------------------------------------------
  ;; Atlas upload — stage to host buffer, copy via one-shot command
  ;; ----------------------------------------------------------------

  (define (upload-atlas-pixels! device physical-device mem-props
                                queue command-pool
                                image width height pixels)
    (let* ((nbytes  (bytevector-length pixels))
           (staging (create-staging-buffer device nbytes))
           (mem (alloc-buffer-memory device staging mem-props
                                     (bitwise-ior VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
                                                  VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)))
           (mapped-out (foreign-alloc/zero 8)))
      (dynamic-wind
       void
       (lambda ()
         (vk-check 'vkBindBufferMemory
                   (vkBindBufferMemory device staging mem 0))
         (vk-check 'vkMapMemory
                   (vkMapMemory device mem 0 nbytes 0 mapped-out))
         (let ((m (foreign-ref 'uptr mapped-out 0)))
           (do ((i 0 (+ i 1))) ((= i nbytes))
             (foreign-set! 'unsigned-8 m i (bytevector-u8-ref pixels i))))
         (vkUnmapMemory device mem)
         ;; Record + submit the copy.
         (run-one-shot-commands! device queue command-pool
           (lambda (cmd)
             (record-image-upload! cmd staging image width height)))
         (vkDestroyBuffer device staging 0)
         (vkFreeMemory device mem 0))
       (lambda ()
         (foreign-free mapped-out)))))

  (define (run-one-shot-commands! device queue command-pool record-proc)
    (let* ((alloc-info (foreign-alloc/zero
                        (ftype-sizeof <VkCommandBufferAllocateInfo>)))
           (begin-info (foreign-alloc/zero
                        (ftype-sizeof <VkCommandBufferBeginInfo>)))
           (cmd-out    (foreign-alloc/zero 8))
           (cmdbuf-arr (foreign-alloc/zero 8))
           (submit-info (foreign-alloc/zero (ftype-sizeof <VkSubmitInfo>)))
           (afp (make-ftype-pointer <VkCommandBufferAllocateInfo> alloc-info))
           (bfp (make-ftype-pointer <VkCommandBufferBeginInfo> begin-info))
           (sfp (make-ftype-pointer <VkSubmitInfo> submit-info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkCommandBufferAllocateInfo> (sType) afp
                     VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO)
         (ftype-set! <VkCommandBufferAllocateInfo> (commandPool) afp command-pool)
         (ftype-set! <VkCommandBufferAllocateInfo> (level) afp
                     VK_COMMAND_BUFFER_LEVEL_PRIMARY)
         (ftype-set! <VkCommandBufferAllocateInfo> (commandBufferCount) afp 1)
         (vk-check 'vkAllocateCommandBuffers
                   (vkAllocateCommandBuffers device alloc-info cmd-out))
         (let ((cmd (foreign-ref 'uptr cmd-out 0)))
           (ftype-set! <VkCommandBufferBeginInfo> (sType) bfp
                       VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO)
           (ftype-set! <VkCommandBufferBeginInfo> (flags) bfp
                       VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
           (vk-check 'vkBeginCommandBuffer (vkBeginCommandBuffer cmd begin-info))
           (record-proc cmd)
           (vk-check 'vkEndCommandBuffer (vkEndCommandBuffer cmd))
           (foreign-set! 'uptr cmdbuf-arr 0 cmd)
           (ftype-set! <VkSubmitInfo> (sType) sfp VK_STRUCTURE_TYPE_SUBMIT_INFO)
           (ftype-set! <VkSubmitInfo> (commandBufferCount) sfp 1)
           (ftype-set! <VkSubmitInfo> (pCommandBuffers) sfp cmdbuf-arr)
           (vk-check 'vkQueueSubmit
                     (vkQueueSubmit queue 1 submit-info 0))
           ;; Sync via vkDeviceWaitIdle — overkill but the path is one-shot.
           (vk-check 'vkDeviceWaitIdle (vkDeviceWaitIdle device))
           (vkFreeCommandBuffers device command-pool 1 cmd-out)))
       (lambda ()
         (foreign-free submit-info)
         (foreign-free cmdbuf-arr)
         (foreign-free cmd-out)
         (foreign-free begin-info)
         (foreign-free alloc-info)))))

  (define (record-image-upload! cmd buffer image width height)
    ;; Two pipeline barriers + one CopyBufferToImage.
    ;;   undef → TRANSFER_DST → SHADER_READ_ONLY
    (let* ((b1 (foreign-alloc/zero (ftype-sizeof <VkImageMemoryBarrier>)))
           (b2 (foreign-alloc/zero (ftype-sizeof <VkImageMemoryBarrier>)))
           (region (foreign-alloc/zero (ftype-sizeof <VkBufferImageCopy>)))
           (b1p (make-ftype-pointer <VkImageMemoryBarrier> b1))
           (b2p (make-ftype-pointer <VkImageMemoryBarrier> b2))
           (rp  (make-ftype-pointer <VkBufferImageCopy> region)))
      (dynamic-wind
       void
       (lambda ()
         (set-image-barrier! b1p image
                             0 VK_ACCESS_TRANSFER_WRITE_BIT
                             VK_IMAGE_LAYOUT_UNDEFINED
                             VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
         (vkCmdPipelineBarrier cmd
                               VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT
                               VK_PIPELINE_STAGE_TRANSFER_BIT
                               0 0 0 0 0 1 b1)
         (ftype-set! <VkBufferImageCopy> (bufferOffset) rp 0)
         (ftype-set! <VkBufferImageCopy> (bufferRowLength) rp 0)
         (ftype-set! <VkBufferImageCopy> (bufferImageHeight) rp 0)
         (ftype-set! <VkBufferImageCopy> (imageSubresource aspectMask) rp
                     VK_IMAGE_ASPECT_COLOR_BIT)
         (ftype-set! <VkBufferImageCopy> (imageSubresource layerCount) rp 1)
         (ftype-set! <VkBufferImageCopy> (imageExtent width) rp width)
         (ftype-set! <VkBufferImageCopy> (imageExtent height) rp height)
         (ftype-set! <VkBufferImageCopy> (imageExtent depth) rp 1)
         (vkCmdCopyBufferToImage cmd buffer image
                                 VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
                                 1 region)
         (set-image-barrier! b2p image
                             VK_ACCESS_TRANSFER_WRITE_BIT
                             VK_ACCESS_SHADER_READ_BIT
                             VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
                             VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
         (vkCmdPipelineBarrier cmd
                               VK_PIPELINE_STAGE_TRANSFER_BIT
                               VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
                               0 0 0 0 0 1 b2))
       (lambda ()
         (foreign-free region) (foreign-free b2) (foreign-free b1)))))

  (define (set-image-barrier! bp image src-access dst-access old-layout new-layout)
    (ftype-set! <VkImageMemoryBarrier> (sType) bp
                VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER)
    (ftype-set! <VkImageMemoryBarrier> (srcAccessMask) bp src-access)
    (ftype-set! <VkImageMemoryBarrier> (dstAccessMask) bp dst-access)
    (ftype-set! <VkImageMemoryBarrier> (oldLayout) bp old-layout)
    (ftype-set! <VkImageMemoryBarrier> (newLayout) bp new-layout)
    (ftype-set! <VkImageMemoryBarrier> (srcQueueFamilyIndex) bp VK_QUEUE_FAMILY_IGNORED)
    (ftype-set! <VkImageMemoryBarrier> (dstQueueFamilyIndex) bp VK_QUEUE_FAMILY_IGNORED)
    (ftype-set! <VkImageMemoryBarrier> (image) bp image)
    (ftype-set! <VkImageMemoryBarrier> (subresourceRange aspectMask) bp
                VK_IMAGE_ASPECT_COLOR_BIT)
    (ftype-set! <VkImageMemoryBarrier> (subresourceRange baseMipLevel) bp 0)
    (ftype-set! <VkImageMemoryBarrier> (subresourceRange levelCount) bp 1)
    (ftype-set! <VkImageMemoryBarrier> (subresourceRange baseArrayLayer) bp 0)
    (ftype-set! <VkImageMemoryBarrier> (subresourceRange layerCount) bp 1))

  ;; ----------------------------------------------------------------
  ;; Descriptor + pipeline plumbing
  ;; ----------------------------------------------------------------

  (define (create-text-descriptor-set-layout device)
    (let* ((bind (foreign-alloc/zero
                  (ftype-sizeof <VkDescriptorSetLayoutBinding>)))
           (info (foreign-alloc/zero
                  (ftype-sizeof <VkDescriptorSetLayoutCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (bp   (make-ftype-pointer <VkDescriptorSetLayoutBinding> bind))
           (ip   (make-ftype-pointer <VkDescriptorSetLayoutCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkDescriptorSetLayoutBinding> (binding) bp 0)
         (ftype-set! <VkDescriptorSetLayoutBinding> (descriptorType) bp
                     VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER)
         (ftype-set! <VkDescriptorSetLayoutBinding> (descriptorCount) bp 1)
         (ftype-set! <VkDescriptorSetLayoutBinding> (stageFlags) bp
                     VK_SHADER_STAGE_FRAGMENT_BIT)
         (ftype-set! <VkDescriptorSetLayoutCreateInfo> (sType) ip
                     VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO)
         (ftype-set! <VkDescriptorSetLayoutCreateInfo> (bindingCount) ip 1)
         (ftype-set! <VkDescriptorSetLayoutCreateInfo> (pBindings) ip bind)
         (vk-check 'vkCreateDescriptorSetLayout
                   (vkCreateDescriptorSetLayout device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info) (foreign-free bind)))))

  (define (create-text-pipeline-layout device dsl)
    (let* ((dsl-arr (foreign-alloc/zero 8))
           (push   (foreign-alloc/zero (ftype-sizeof <VkPushConstantRange>)))
           (info   (foreign-alloc/zero (ftype-sizeof <VkPipelineLayoutCreateInfo>)))
           (out    (foreign-alloc/zero 8))
           (pp (make-ftype-pointer <VkPushConstantRange> push))
           (ip (make-ftype-pointer <VkPipelineLayoutCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (foreign-set! 'unsigned-64 dsl-arr 0 dsl)
         (ftype-set! <VkPushConstantRange> (stageFlags) pp
                     (bitwise-ior VK_SHADER_STAGE_VERTEX_BIT
                                  VK_SHADER_STAGE_FRAGMENT_BIT))
         (ftype-set! <VkPushConstantRange> (offset) pp 0)
         (ftype-set! <VkPushConstantRange> (size) pp 32)
         (ftype-set! <VkPipelineLayoutCreateInfo> (sType) ip
                     VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO)
         (ftype-set! <VkPipelineLayoutCreateInfo> (setLayoutCount) ip 1)
         (ftype-set! <VkPipelineLayoutCreateInfo> (pSetLayouts) ip dsl-arr)
         (ftype-set! <VkPipelineLayoutCreateInfo> (pushConstantRangeCount) ip 1)
         (ftype-set! <VkPipelineLayoutCreateInfo> (pPushConstantRanges) ip push)
         (vk-check 'vkCreatePipelineLayout
                   (vkCreatePipelineLayout device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info)
         (foreign-free push) (foreign-free dsl-arr)))))

  (define (create-shader-module device spv-bv)
    (let* ((nbytes (bytevector-length spv-bv))
           (code-buf (foreign-alloc nbytes))
           (info (foreign-alloc/zero
                  (ftype-sizeof <VkShaderModuleCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkShaderModuleCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (do ((i 0 (+ i 1))) ((= i nbytes))
           (foreign-set! 'unsigned-8 code-buf i (bytevector-u8-ref spv-bv i)))
         (ftype-set! <VkShaderModuleCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO)
         (ftype-set! <VkShaderModuleCreateInfo> (codeSize) fp nbytes)
         (ftype-set! <VkShaderModuleCreateInfo> (pCode) fp code-buf)
         (vk-check 'vkCreateShaderModule
                   (vkCreateShaderModule device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info) (foreign-free code-buf)))))

  (define (create-text-graphics-pipeline device layout render-pass
                                         vertex-module fragment-module)
    (let* ((entry-name (foreign-alloc 5))   ; "main\0"
           (stages (foreign-alloc/zero
                    (* 2 (ftype-sizeof <VkPipelineShaderStageCreateInfo>))))
           (vbinding (foreign-alloc/zero
                      (ftype-sizeof <VkVertexInputBindingDescription>)))
           (vattr (foreign-alloc/zero
                   (* 2 (ftype-sizeof <VkVertexInputAttributeDescription>))))
           (vinfo (foreign-alloc/zero
                   (ftype-sizeof <VkPipelineVertexInputStateCreateInfo>)))
           (iainfo (foreign-alloc/zero
                    (ftype-sizeof <VkPipelineInputAssemblyStateCreateInfo>)))
           (vpinfo (foreign-alloc/zero
                    (ftype-sizeof <VkPipelineViewportStateCreateInfo>)))
           (rsinfo (foreign-alloc/zero
                    (ftype-sizeof <VkPipelineRasterizationStateCreateInfo>)))
           (msinfo (foreign-alloc/zero
                    (ftype-sizeof <VkPipelineMultisampleStateCreateInfo>)))
           (cbatt (foreign-alloc/zero
                   (ftype-sizeof <VkPipelineColorBlendAttachmentState>)))
           (cbinfo (foreign-alloc/zero
                    (ftype-sizeof <VkPipelineColorBlendStateCreateInfo>)))
           (dyn-states (foreign-alloc/zero 8))
           (dyninfo (foreign-alloc/zero
                     (ftype-sizeof <VkPipelineDynamicStateCreateInfo>)))
           (gpinfo (foreign-alloc/zero
                    (ftype-sizeof <VkGraphicsPipelineCreateInfo>)))
           (out    (foreign-alloc/zero 8)))
      (dynamic-wind
       void
       (lambda ()
         ;; "main\0" entry point
         (foreign-set! 'unsigned-8 entry-name 0 (char->integer #\m))
         (foreign-set! 'unsigned-8 entry-name 1 (char->integer #\a))
         (foreign-set! 'unsigned-8 entry-name 2 (char->integer #\i))
         (foreign-set! 'unsigned-8 entry-name 3 (char->integer #\n))
         (foreign-set! 'unsigned-8 entry-name 4 0)
         ;; stages[0] = vertex
         (let ((sp (make-ftype-pointer <VkPipelineShaderStageCreateInfo> stages)))
           (ftype-set! <VkPipelineShaderStageCreateInfo> (sType) sp
                       VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO)
           (ftype-set! <VkPipelineShaderStageCreateInfo> (stage) sp
                       VK_SHADER_STAGE_VERTEX_BIT)
           (ftype-set! <VkPipelineShaderStageCreateInfo> (module) sp vertex-module)
           (ftype-set! <VkPipelineShaderStageCreateInfo> (pName) sp entry-name))
         ;; stages[1] = fragment
         (let ((sp (make-ftype-pointer <VkPipelineShaderStageCreateInfo>
                                       (+ stages
                                          (ftype-sizeof <VkPipelineShaderStageCreateInfo>)))))
           (ftype-set! <VkPipelineShaderStageCreateInfo> (sType) sp
                       VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO)
           (ftype-set! <VkPipelineShaderStageCreateInfo> (stage) sp
                       VK_SHADER_STAGE_FRAGMENT_BIT)
           (ftype-set! <VkPipelineShaderStageCreateInfo> (module) sp fragment-module)
           (ftype-set! <VkPipelineShaderStageCreateInfo> (pName) sp entry-name))
         ;; vertex input binding (instance rate, stride 32)
         (let ((bp (make-ftype-pointer <VkVertexInputBindingDescription> vbinding)))
           (ftype-set! <VkVertexInputBindingDescription> (binding) bp 0)
           (ftype-set! <VkVertexInputBindingDescription> (stride) bp INSTANCE-STRIDE)
           (ftype-set! <VkVertexInputBindingDescription> (inputRate) bp
                       VK_VERTEX_INPUT_RATE_INSTANCE))
         ;; attributes — loc 0 R32G32B32A32 offset 0, loc 1 R32G32B32A32 offset 16
         (let ((ap (make-ftype-pointer <VkVertexInputAttributeDescription> vattr)))
           (ftype-set! <VkVertexInputAttributeDescription> (location) ap 0)
           (ftype-set! <VkVertexInputAttributeDescription> (binding)  ap 0)
           (ftype-set! <VkVertexInputAttributeDescription> (format)   ap
                       VK_FORMAT_R32G32B32A32_SFLOAT)
           (ftype-set! <VkVertexInputAttributeDescription> (offset)   ap 0))
         (let ((ap (make-ftype-pointer <VkVertexInputAttributeDescription>
                                       (+ vattr
                                          (ftype-sizeof <VkVertexInputAttributeDescription>)))))
           (ftype-set! <VkVertexInputAttributeDescription> (location) ap 1)
           (ftype-set! <VkVertexInputAttributeDescription> (binding)  ap 0)
           (ftype-set! <VkVertexInputAttributeDescription> (format)   ap
                       VK_FORMAT_R32G32B32A32_SFLOAT)
           (ftype-set! <VkVertexInputAttributeDescription> (offset)   ap 16))
         ;; vertex input state
         (let ((vp (make-ftype-pointer <VkPipelineVertexInputStateCreateInfo> vinfo)))
           (ftype-set! <VkPipelineVertexInputStateCreateInfo> (sType) vp
                       VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO)
           (ftype-set! <VkPipelineVertexInputStateCreateInfo>
                       (vertexBindingDescriptionCount) vp 1)
           (ftype-set! <VkPipelineVertexInputStateCreateInfo>
                       (pVertexBindingDescriptions) vp vbinding)
           (ftype-set! <VkPipelineVertexInputStateCreateInfo>
                       (vertexAttributeDescriptionCount) vp 2)
           (ftype-set! <VkPipelineVertexInputStateCreateInfo>
                       (pVertexAttributeDescriptions) vp vattr))
         ;; input assembly
         (let ((ap (make-ftype-pointer <VkPipelineInputAssemblyStateCreateInfo> iainfo)))
           (ftype-set! <VkPipelineInputAssemblyStateCreateInfo> (sType) ap
                       VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO)
           (ftype-set! <VkPipelineInputAssemblyStateCreateInfo> (topology) ap
                       VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST))
         ;; viewport state — counts only; viewport+scissor are dynamic
         (let ((vp (make-ftype-pointer <VkPipelineViewportStateCreateInfo> vpinfo)))
           (ftype-set! <VkPipelineViewportStateCreateInfo> (sType) vp
                       VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO)
           (ftype-set! <VkPipelineViewportStateCreateInfo> (viewportCount) vp 1)
           (ftype-set! <VkPipelineViewportStateCreateInfo> (scissorCount) vp 1))
         ;; rasterization
         (let ((rp (make-ftype-pointer <VkPipelineRasterizationStateCreateInfo> rsinfo)))
           (ftype-set! <VkPipelineRasterizationStateCreateInfo> (sType) rp
                       VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO)
           (ftype-set! <VkPipelineRasterizationStateCreateInfo> (polygonMode) rp
                       VK_POLYGON_MODE_FILL)
           (ftype-set! <VkPipelineRasterizationStateCreateInfo> (cullMode) rp
                       VK_CULL_MODE_NONE)
           (ftype-set! <VkPipelineRasterizationStateCreateInfo> (frontFace) rp
                       VK_FRONT_FACE_COUNTER_CLOCKWISE)
           (ftype-set! <VkPipelineRasterizationStateCreateInfo> (lineWidth) rp 1.0))
         ;; multisample
         (let ((mp (make-ftype-pointer <VkPipelineMultisampleStateCreateInfo> msinfo)))
           (ftype-set! <VkPipelineMultisampleStateCreateInfo> (sType) mp
                       VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO)
           (ftype-set! <VkPipelineMultisampleStateCreateInfo> (rasterizationSamples) mp
                       VK_SAMPLE_COUNT_1_BIT))
         ;; color blend attachment — premultiplied-alpha-style blend
         (let ((cp (make-ftype-pointer <VkPipelineColorBlendAttachmentState> cbatt)))
           (ftype-set! <VkPipelineColorBlendAttachmentState> (blendEnable) cp 1)
           (ftype-set! <VkPipelineColorBlendAttachmentState> (srcColorBlendFactor) cp
                       VK_BLEND_FACTOR_SRC_ALPHA)
           (ftype-set! <VkPipelineColorBlendAttachmentState> (dstColorBlendFactor) cp
                       VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
           (ftype-set! <VkPipelineColorBlendAttachmentState> (colorBlendOp) cp
                       VK_BLEND_OP_ADD)
           (ftype-set! <VkPipelineColorBlendAttachmentState> (srcAlphaBlendFactor) cp
                       VK_BLEND_FACTOR_ONE)
           (ftype-set! <VkPipelineColorBlendAttachmentState> (dstAlphaBlendFactor) cp
                       VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
           (ftype-set! <VkPipelineColorBlendAttachmentState> (alphaBlendOp) cp
                       VK_BLEND_OP_ADD)
           (ftype-set! <VkPipelineColorBlendAttachmentState> (colorWriteMask) cp
                       (bitwise-ior VK_COLOR_COMPONENT_R_BIT
                                    VK_COLOR_COMPONENT_G_BIT
                                    VK_COLOR_COMPONENT_B_BIT
                                    VK_COLOR_COMPONENT_A_BIT)))
         (let ((cp (make-ftype-pointer <VkPipelineColorBlendStateCreateInfo> cbinfo)))
           (ftype-set! <VkPipelineColorBlendStateCreateInfo> (sType) cp
                       VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO)
           (ftype-set! <VkPipelineColorBlendStateCreateInfo> (attachmentCount) cp 1)
           (ftype-set! <VkPipelineColorBlendStateCreateInfo> (pAttachments) cp cbatt))
         ;; dynamic state (viewport + scissor)
         (foreign-set! 'unsigned-32 dyn-states 0 VK_DYNAMIC_STATE_VIEWPORT)
         (foreign-set! 'unsigned-32 dyn-states 4 VK_DYNAMIC_STATE_SCISSOR)
         (let ((dp (make-ftype-pointer <VkPipelineDynamicStateCreateInfo> dyninfo)))
           (ftype-set! <VkPipelineDynamicStateCreateInfo> (sType) dp
                       VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO)
           (ftype-set! <VkPipelineDynamicStateCreateInfo> (dynamicStateCount) dp 2)
           (ftype-set! <VkPipelineDynamicStateCreateInfo> (pDynamicStates) dp dyn-states))
         ;; graphics pipeline create info
         (let ((gp (make-ftype-pointer <VkGraphicsPipelineCreateInfo> gpinfo)))
           (ftype-set! <VkGraphicsPipelineCreateInfo> (sType) gp
                       VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (stageCount) gp 2)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pStages) gp stages)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pVertexInputState) gp vinfo)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pInputAssemblyState) gp iainfo)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pViewportState) gp vpinfo)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pRasterizationState) gp rsinfo)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pMultisampleState) gp msinfo)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pColorBlendState) gp cbinfo)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (pDynamicState) gp dyninfo)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (layout) gp layout)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (renderPass) gp render-pass)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (subpass) gp 0)
           (ftype-set! <VkGraphicsPipelineCreateInfo> (basePipelineIndex) gp -1))
         (vk-check 'vkCreateGraphicsPipelines
                   (vkCreateGraphicsPipelines device 0 1 gpinfo 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out)
         (foreign-free gpinfo)
         (foreign-free dyninfo)
         (foreign-free dyn-states)
         (foreign-free cbinfo)
         (foreign-free cbatt)
         (foreign-free msinfo)
         (foreign-free rsinfo)
         (foreign-free vpinfo)
         (foreign-free iainfo)
         (foreign-free vinfo)
         (foreign-free vattr)
         (foreign-free vbinding)
         (foreign-free stages)
         (foreign-free entry-name)))))

  (define (create-text-descriptor-pool device)
    (let* ((size (foreign-alloc/zero (ftype-sizeof <VkDescriptorPoolSize>)))
           (info (foreign-alloc/zero (ftype-sizeof <VkDescriptorPoolCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (sp   (make-ftype-pointer <VkDescriptorPoolSize> size))
           (ip   (make-ftype-pointer <VkDescriptorPoolCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkDescriptorPoolSize> (type) sp
                     VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER)
         (ftype-set! <VkDescriptorPoolSize> (descriptorCount) sp 1)
         (ftype-set! <VkDescriptorPoolCreateInfo> (sType) ip
                     VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO)
         (ftype-set! <VkDescriptorPoolCreateInfo> (maxSets) ip 1)
         (ftype-set! <VkDescriptorPoolCreateInfo> (poolSizeCount) ip 1)
         (ftype-set! <VkDescriptorPoolCreateInfo> (pPoolSizes) ip size)
         (vk-check 'vkCreateDescriptorPool
                   (vkCreateDescriptorPool device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info) (foreign-free size)))))

  (define (allocate-text-descriptor-set device pool dsl)
    (let* ((dsl-arr (foreign-alloc/zero 8))
           (info (foreign-alloc/zero
                  (ftype-sizeof <VkDescriptorSetAllocateInfo>)))
           (out  (foreign-alloc/zero 8))
           (ip (make-ftype-pointer <VkDescriptorSetAllocateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (foreign-set! 'unsigned-64 dsl-arr 0 dsl)
         (ftype-set! <VkDescriptorSetAllocateInfo> (sType) ip
                     VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO)
         (ftype-set! <VkDescriptorSetAllocateInfo> (descriptorPool) ip pool)
         (ftype-set! <VkDescriptorSetAllocateInfo> (descriptorSetCount) ip 1)
         (ftype-set! <VkDescriptorSetAllocateInfo> (pSetLayouts) ip dsl-arr)
         (vk-check 'vkAllocateDescriptorSets
                   (vkAllocateDescriptorSets device info out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info) (foreign-free dsl-arr)))))

  (define (write-text-descriptor-set! device set view sampler)
    (let* ((img-info (foreign-alloc/zero
                     (ftype-sizeof <VkDescriptorImageInfo>)))
           (write    (foreign-alloc/zero
                     (ftype-sizeof <VkWriteDescriptorSet>)))
           (dp (make-ftype-pointer <VkDescriptorImageInfo> img-info))
           (wp (make-ftype-pointer <VkWriteDescriptorSet> write)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkDescriptorImageInfo> (sampler) dp sampler)
         (ftype-set! <VkDescriptorImageInfo> (imageView) dp view)
         (ftype-set! <VkDescriptorImageInfo> (imageLayout) dp
                     VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
         (ftype-set! <VkWriteDescriptorSet> (sType) wp
                     VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET)
         (ftype-set! <VkWriteDescriptorSet> (dstSet) wp set)
         (ftype-set! <VkWriteDescriptorSet> (dstBinding) wp 0)
         (ftype-set! <VkWriteDescriptorSet> (descriptorCount) wp 1)
         (ftype-set! <VkWriteDescriptorSet> (descriptorType) wp
                     VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER)
         (ftype-set! <VkWriteDescriptorSet> (pImageInfo) wp img-info)
         (vkUpdateDescriptorSets device 1 write 0 0))
       (lambda ()
         (foreign-free write) (foreign-free img-info))))))
