;; M2.2 D-4 verification — record + submit a real frame against
;; llvmpipe. Closes the gap left by text-pipeline-smoke.scm, which
;; exercises pipeline construction but not the draw path.
;;
;; Sandbox layout: there's no /dev/dri/card0 → no display surface →
;; no swapchain. We substitute an off-screen image + framebuffer of
;; the same color format the on-hardware path would use, so the only
;; difference between this test and the real one is "where does the
;; final image go": vkCmdEndRenderPass + vkDeviceWaitIdle here vs.
;; vkQueuePresentKHR there.
;;
;; Run:   ./venv scheme -q --libdirs src/ scripts/draw-smoke.scm
;; Or with validation:
;;        LETLOOP_VULKAN_VALIDATE=1 ./venv scheme -q --libdirs src/ scripts/draw-smoke.scm
(import (chezscheme)
        (letloop desktop vulkan)
        (letloop desktop vulkan low)
        (letloop desktop text-pipeline)
        (letloop desktop font))

(define (foreign-alloc/zero n)
  (let ((p (foreign-alloc n)))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i 0))
    p))
(define (vk-check who r)
  (unless (= r VK_SUCCESS) (error who (vk-result-name r) r)))

;; The full sequence is wrapped in a single let* so internal defines
;; aren't an issue.
(call-with-vulkan-instance "draw-smoke"
  (lambda (instance)
    (let* ((pd  (car (vulkan-physical-devices instance)))
           (qfi (vulkan-pick-graphics-queue-family pd))
           ;; --- Device + queue + command pool -----------------------
           (priorities (foreign-alloc/zero 4))
           (qci (foreign-alloc/zero (ftype-sizeof <VkDeviceQueueCreateInfo>)))
           (qfp (make-ftype-pointer <VkDeviceQueueCreateInfo> qci))
           (dci (foreign-alloc/zero (ftype-sizeof <VkDeviceCreateInfo>)))
           (dfp (make-ftype-pointer <VkDeviceCreateInfo> dci))
           (dout (foreign-alloc/zero 8))
           (_qci (begin
                   (foreign-set! 'float priorities 0 1.0)
                   (ftype-set! <VkDeviceQueueCreateInfo> (sType) qfp
                               VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO)
                   (ftype-set! <VkDeviceQueueCreateInfo> (queueFamilyIndex) qfp qfi)
                   (ftype-set! <VkDeviceQueueCreateInfo> (queueCount) qfp 1)
                   (ftype-set! <VkDeviceQueueCreateInfo> (pQueuePriorities) qfp priorities)
                   (ftype-set! <VkDeviceCreateInfo> (sType) dfp
                               VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO)
                   (ftype-set! <VkDeviceCreateInfo> (queueCreateInfoCount) dfp 1)
                   (ftype-set! <VkDeviceCreateInfo> (pQueueCreateInfos) dfp qci)
                   (vk-check 'vkCreateDevice (vkCreateDevice pd dci 0 dout))
                   #f))
           (device (foreign-ref 'uptr dout 0))
           (qout (foreign-alloc/zero 8))
           (_q (begin (vkGetDeviceQueue device qfi 0 qout) #f))
           (queue (foreign-ref 'uptr qout 0))
           (cpi (foreign-alloc/zero (ftype-sizeof <VkCommandPoolCreateInfo>)))
           (cfp (make-ftype-pointer <VkCommandPoolCreateInfo> cpi))
           (cpout (foreign-alloc/zero 8))
           (_cp (begin
                  (ftype-set! <VkCommandPoolCreateInfo> (sType) cfp
                              VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO)
                  (ftype-set! <VkCommandPoolCreateInfo> (flags) cfp
                              VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT)
                  (ftype-set! <VkCommandPoolCreateInfo> (queueFamilyIndex) cfp qfi)
                  (vk-check 'vkCreateCommandPool
                            (vkCreateCommandPool device cpi 0 cpout))
                  #f))
           (command-pool (foreign-ref 'unsigned-64 cpout 0))
           ;; --- Render pass -----------------------------------------
           ;; Same single-color-attachment shape as window.scm uses,
           ;; but with finalLayout = COLOR_ATTACHMENT_OPTIMAL since
           ;; we're rendering off-screen (no presentation).
           (att (foreign-alloc/zero (ftype-sizeof <VkAttachmentDescription>)))
           (afp (make-ftype-pointer <VkAttachmentDescription> att))
           (ref (foreign-alloc/zero (ftype-sizeof <VkAttachmentReference>)))
           (rfp (make-ftype-pointer <VkAttachmentReference> ref))
           (sub (foreign-alloc/zero (ftype-sizeof <VkSubpassDescription>)))
           (sfp (make-ftype-pointer <VkSubpassDescription> sub))
           (rci (foreign-alloc/zero (ftype-sizeof <VkRenderPassCreateInfo>)))
           (rfp2 (make-ftype-pointer <VkRenderPassCreateInfo> rci))
           (rpout (foreign-alloc/zero 8))
           (_rp (begin
                  (ftype-set! <VkAttachmentDescription> (format) afp VK_FORMAT_B8G8R8A8_UNORM)
                  (ftype-set! <VkAttachmentDescription> (samples) afp VK_SAMPLE_COUNT_1_BIT)
                  (ftype-set! <VkAttachmentDescription> (loadOp) afp VK_ATTACHMENT_LOAD_OP_CLEAR)
                  (ftype-set! <VkAttachmentDescription> (storeOp) afp VK_ATTACHMENT_STORE_OP_STORE)
                  (ftype-set! <VkAttachmentDescription> (initialLayout) afp VK_IMAGE_LAYOUT_UNDEFINED)
                  (ftype-set! <VkAttachmentDescription> (finalLayout) afp VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
                  (ftype-set! <VkAttachmentReference> (attachment) rfp 0)
                  (ftype-set! <VkAttachmentReference> (layout) rfp VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
                  (ftype-set! <VkSubpassDescription> (pipelineBindPoint) sfp VK_PIPELINE_BIND_POINT_GRAPHICS)
                  (ftype-set! <VkSubpassDescription> (colorAttachmentCount) sfp 1)
                  (ftype-set! <VkSubpassDescription> (pColorAttachments) sfp ref)
                  (ftype-set! <VkRenderPassCreateInfo> (sType) rfp2 VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO)
                  (ftype-set! <VkRenderPassCreateInfo> (attachmentCount) rfp2 1)
                  (ftype-set! <VkRenderPassCreateInfo> (pAttachments) rfp2 att)
                  (ftype-set! <VkRenderPassCreateInfo> (subpassCount) rfp2 1)
                  (ftype-set! <VkRenderPassCreateInfo> (pSubpasses) rfp2 sub)
                  (vk-check 'vkCreateRenderPass (vkCreateRenderPass device rci 0 rpout))
                  #f))
           (render-pass (foreign-ref 'unsigned-64 rpout 0))
           ;; --- Off-screen color attachment image -------------------
           (img-info (foreign-alloc/zero (ftype-sizeof <VkImageCreateInfo>)))
           (ifp (make-ftype-pointer <VkImageCreateInfo> img-info))
           (imgout (foreign-alloc/zero 8))
           (_img (begin
                   (ftype-set! <VkImageCreateInfo> (sType) ifp VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO)
                   (ftype-set! <VkImageCreateInfo> (imageType) ifp VK_IMAGE_TYPE_2D)
                   (ftype-set! <VkImageCreateInfo> (format) ifp VK_FORMAT_B8G8R8A8_UNORM)
                   (ftype-set! <VkImageCreateInfo> (extent width) ifp 800)
                   (ftype-set! <VkImageCreateInfo> (extent height) ifp 600)
                   (ftype-set! <VkImageCreateInfo> (extent depth) ifp 1)
                   (ftype-set! <VkImageCreateInfo> (mipLevels) ifp 1)
                   (ftype-set! <VkImageCreateInfo> (arrayLayers) ifp 1)
                   (ftype-set! <VkImageCreateInfo> (samples) ifp VK_SAMPLE_COUNT_1_BIT)
                   (ftype-set! <VkImageCreateInfo> (tiling) ifp VK_IMAGE_TILING_OPTIMAL)
                   (ftype-set! <VkImageCreateInfo> (usage) ifp
                               (bitwise-ior VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
                                            VK_IMAGE_USAGE_TRANSFER_SRC_BIT))
                   (ftype-set! <VkImageCreateInfo> (sharingMode) ifp VK_SHARING_MODE_EXCLUSIVE)
                   (ftype-set! <VkImageCreateInfo> (initialLayout) ifp VK_IMAGE_LAYOUT_UNDEFINED)
                   (vk-check 'vkCreateImage (vkCreateImage device img-info 0 imgout))
                   #f))
           (color-image (foreign-ref 'unsigned-64 imgout 0))
           (memreq (foreign-alloc/zero (ftype-sizeof <VkMemoryRequirements>)))
           (memreq-fp (make-ftype-pointer <VkMemoryRequirements> memreq))
           (_mr (begin (vkGetImageMemoryRequirements device color-image memreq) #f))
           (mai (foreign-alloc/zero (ftype-sizeof <VkMemoryAllocateInfo>)))
           (mp (make-ftype-pointer <VkMemoryAllocateInfo> mai))
           (memout (foreign-alloc/zero 8))
           (_alloc
            (begin
              (ftype-set! <VkMemoryAllocateInfo> (sType) mp VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO)
              (ftype-set! <VkMemoryAllocateInfo> (allocationSize) mp
                          (ftype-ref <VkMemoryRequirements> (size) memreq-fp))
              ;; First memory type that's in the type bitmap. llvmpipe
              ;; exposes type 0 as DEVICE_LOCAL+HOST_VISIBLE+HOST_COHERENT
              ;; so this works without a proper type filter.
              (ftype-set! <VkMemoryAllocateInfo> (memoryTypeIndex) mp 0)
              (vk-check 'vkAllocateMemory (vkAllocateMemory device mai 0 memout))
              #f))
           (color-mem (foreign-ref 'unsigned-64 memout 0))
           (_bind (begin
                    (vk-check 'vkBindImageMemory
                              (vkBindImageMemory device color-image color-mem 0))
                    #f))
           ;; --- View + framebuffer ---------------------------------
           (ivinfo (foreign-alloc/zero (ftype-sizeof <VkImageViewCreateInfo>)))
           (ivp (make-ftype-pointer <VkImageViewCreateInfo> ivinfo))
           (ivout (foreign-alloc/zero 8))
           (_iv (begin
                  (ftype-set! <VkImageViewCreateInfo> (sType) ivp VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO)
                  (ftype-set! <VkImageViewCreateInfo> (image) ivp color-image)
                  (ftype-set! <VkImageViewCreateInfo> (viewType) ivp VK_IMAGE_VIEW_TYPE_2D)
                  (ftype-set! <VkImageViewCreateInfo> (format) ivp VK_FORMAT_B8G8R8A8_UNORM)
                  (ftype-set! <VkImageViewCreateInfo> (subresourceRange aspectMask) ivp VK_IMAGE_ASPECT_COLOR_BIT)
                  (ftype-set! <VkImageViewCreateInfo> (subresourceRange levelCount) ivp 1)
                  (ftype-set! <VkImageViewCreateInfo> (subresourceRange layerCount) ivp 1)
                  (vk-check 'vkCreateImageView (vkCreateImageView device ivinfo 0 ivout))
                  #f))
           (color-view (foreign-ref 'unsigned-64 ivout 0))
           (view-arr (foreign-alloc/zero 8))
           (fbinfo (foreign-alloc/zero (ftype-sizeof <VkFramebufferCreateInfo>)))
           (fbp (make-ftype-pointer <VkFramebufferCreateInfo> fbinfo))
           (fbout (foreign-alloc/zero 8))
           (_fb (begin
                  (foreign-set! 'unsigned-64 view-arr 0 color-view)
                  (ftype-set! <VkFramebufferCreateInfo> (sType) fbp VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO)
                  (ftype-set! <VkFramebufferCreateInfo> (renderPass) fbp render-pass)
                  (ftype-set! <VkFramebufferCreateInfo> (attachmentCount) fbp 1)
                  (ftype-set! <VkFramebufferCreateInfo> (pAttachments) fbp view-arr)
                  (ftype-set! <VkFramebufferCreateInfo> (width) fbp 800)
                  (ftype-set! <VkFramebufferCreateInfo> (height) fbp 600)
                  (ftype-set! <VkFramebufferCreateInfo> (layers) fbp 1)
                  (vk-check 'vkCreateFramebuffer (vkCreateFramebuffer device fbinfo 0 fbout))
                  #f))
           (framebuffer (foreign-ref 'unsigned-64 fbout 0))
           ;; --- Build text pipeline + write a few instances -------
           (tp (build-text-pipeline device pd render-pass queue command-pool))
           (font (text-pipeline-font tp))
           (gw (font-glyph-width font))
           (gh (font-glyph-height font))
           ;; Use a known-mapped glyph ('A') so we know exactly what
           ;; pixels to expect in the readback. The 3 instances are
           ;; placed (100,100), (100+gw,100), (100+2gw,100) in
           ;; white / red / green respectively.
           (info-A (or (font-glyph-info font (char->integer #\A))
                       (error 'draw-smoke "bundled font missing 'A'")))
           (n-written
            (text-pipeline-write-instances! tp
              (list
               (list 100.0 100.0 (exact->inexact gw) (exact->inexact gh)
                     (glyph-info-uv-x info-A) (glyph-info-uv-y info-A)
                     (glyph-info-uv-w info-A) (glyph-info-uv-h info-A)
                     1.0 1.0 1.0 1.0)
               (list (+ 100.0 gw) 100.0 (exact->inexact gw) (exact->inexact gh)
                     (glyph-info-uv-x info-A) (glyph-info-uv-y info-A)
                     (glyph-info-uv-w info-A) (glyph-info-uv-h info-A)
                     1.0 0.3 0.3 1.0)
               (list (+ 100.0 (* 2 gw)) 100.0 (exact->inexact gw) (exact->inexact gh)
                     (glyph-info-uv-x info-A) (glyph-info-uv-y info-A)
                     (glyph-info-uv-w info-A) (glyph-info-uv-h info-A)
                     0.3 1.0 0.3 1.0))))
           ;; --- Readback buffer (host-visible) ---------------------
           (readback-bytes (* 800 600 4))
           (rbi (foreign-alloc/zero (ftype-sizeof <VkBufferCreateInfo>)))
           (rbifp (make-ftype-pointer <VkBufferCreateInfo> rbi))
           (rbout (foreign-alloc/zero 8))
           (_rb (begin
                  (ftype-set! <VkBufferCreateInfo> (sType) rbifp
                              VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO)
                  (ftype-set! <VkBufferCreateInfo> (size) rbifp readback-bytes)
                  (ftype-set! <VkBufferCreateInfo> (usage) rbifp
                              VK_BUFFER_USAGE_TRANSFER_DST_BIT)
                  (ftype-set! <VkBufferCreateInfo> (sharingMode) rbifp
                              VK_SHARING_MODE_EXCLUSIVE)
                  (vk-check 'vkCreateBuffer
                            (vkCreateBuffer device rbi 0 rbout))
                  #f))
           (readback-buffer (foreign-ref 'unsigned-64 rbout 0))
           (rb-mai (foreign-alloc/zero (ftype-sizeof <VkMemoryAllocateInfo>)))
           (rb-mp  (make-ftype-pointer <VkMemoryAllocateInfo> rb-mai))
           (rb-memout (foreign-alloc/zero 8))
           (_rbmem (begin
                     (ftype-set! <VkMemoryAllocateInfo> (sType) rb-mp
                                 VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO)
                     (ftype-set! <VkMemoryAllocateInfo> (allocationSize) rb-mp
                                 readback-bytes)
                     ;; llvmpipe type 0 is host-visible+coherent.
                     (ftype-set! <VkMemoryAllocateInfo> (memoryTypeIndex) rb-mp 0)
                     (vk-check 'vkAllocateMemory
                               (vkAllocateMemory device rb-mai 0 rb-memout))
                     (vk-check 'vkBindBufferMemory
                               (vkBindBufferMemory device readback-buffer
                                                   (foreign-ref 'unsigned-64 rb-memout 0)
                                                   0))
                     #f))
           (readback-mem (foreign-ref 'unsigned-64 rb-memout 0))
           ;; --- Allocate + record + submit one command buffer -----
           (cb-info (foreign-alloc/zero (ftype-sizeof <VkCommandBufferAllocateInfo>)))
           (cbp (make-ftype-pointer <VkCommandBufferAllocateInfo> cb-info))
           (cmdout (foreign-alloc/zero 8))
           (_cb (begin
                  (ftype-set! <VkCommandBufferAllocateInfo> (sType) cbp VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO)
                  (ftype-set! <VkCommandBufferAllocateInfo> (commandPool) cbp command-pool)
                  (ftype-set! <VkCommandBufferAllocateInfo> (level) cbp VK_COMMAND_BUFFER_LEVEL_PRIMARY)
                  (ftype-set! <VkCommandBufferAllocateInfo> (commandBufferCount) cbp 1)
                  (vk-check 'vkAllocateCommandBuffers (vkAllocateCommandBuffers device cb-info cmdout))
                  #f))
           (cmd (foreign-ref 'uptr cmdout 0))
           (begin-info (foreign-alloc/zero (ftype-sizeof <VkCommandBufferBeginInfo>)))
           (bp (make-ftype-pointer <VkCommandBufferBeginInfo> begin-info))
           (cv (foreign-alloc/zero (ftype-sizeof <VkClearValue>)))
           (cvp (make-ftype-pointer <VkClearValue> cv))
           (rpb (foreign-alloc/zero (ftype-sizeof <VkRenderPassBeginInfo>)))
           (rbp (make-ftype-pointer <VkRenderPassBeginInfo> rpb))
           (vp-buf (foreign-alloc/zero (ftype-sizeof <VkViewport>)))
           (vpp (make-ftype-pointer <VkViewport> vp-buf))
           (sc-buf (foreign-alloc/zero (ftype-sizeof <VkRect2D>)))
           (scp (make-ftype-pointer <VkRect2D> sc-buf))
           (push (foreign-alloc/zero 8))
           (vbuf (foreign-alloc/zero 8))
           (voff (foreign-alloc/zero 8))
           (ds (foreign-alloc/zero 8))
           (cmdarr (foreign-alloc/zero 8))
           (si (foreign-alloc/zero (ftype-sizeof <VkSubmitInfo>)))
           (sip (make-ftype-pointer <VkSubmitInfo> si))
           (_record
            (begin
              (ftype-set! <VkCommandBufferBeginInfo> (sType) bp VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO)
              (ftype-set! <VkCommandBufferBeginInfo> (flags) bp VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
              (vk-check 'vkBeginCommandBuffer (vkBeginCommandBuffer cmd begin-info))
              (ftype-set! <VkClearValue> (color float32 0) cvp 0.05)
              (ftype-set! <VkClearValue> (color float32 1) cvp 0.05)
              (ftype-set! <VkClearValue> (color float32 2) cvp 0.10)
              (ftype-set! <VkClearValue> (color float32 3) cvp 1.00)
              (ftype-set! <VkRenderPassBeginInfo> (sType) rbp VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO)
              (ftype-set! <VkRenderPassBeginInfo> (renderPass) rbp render-pass)
              (ftype-set! <VkRenderPassBeginInfo> (framebuffer) rbp framebuffer)
              (ftype-set! <VkRenderPassBeginInfo> (renderArea extent width) rbp 800)
              (ftype-set! <VkRenderPassBeginInfo> (renderArea extent height) rbp 600)
              (ftype-set! <VkRenderPassBeginInfo> (clearValueCount) rbp 1)
              (ftype-set! <VkRenderPassBeginInfo> (pClearValues) rbp cv)
              (vkCmdBeginRenderPass cmd rpb VK_SUBPASS_CONTENTS_INLINE)
              (ftype-set! <VkViewport> (width) vpp 800.0)
              (ftype-set! <VkViewport> (height) vpp 600.0)
              (ftype-set! <VkViewport> (maxDepth) vpp 1.0)
              (ftype-set! <VkRect2D> (extent width) scp 800)
              (ftype-set! <VkRect2D> (extent height) scp 600)
              (vkCmdSetViewport cmd 0 1 vp-buf)
              (vkCmdSetScissor cmd 0 1 sc-buf)
              (vkCmdBindPipeline cmd VK_PIPELINE_BIND_POINT_GRAPHICS
                                 (text-pipeline-pipeline tp))
              (foreign-set! 'unsigned-64 ds 0 (text-pipeline-descriptor-set tp))
              (vkCmdBindDescriptorSets cmd VK_PIPELINE_BIND_POINT_GRAPHICS
                                       (text-pipeline-pipeline-layout tp) 0 1 ds 0 0)
              (foreign-set! 'unsigned-64 vbuf 0 (text-pipeline-instance-buffer tp))
              (vkCmdBindVertexBuffers cmd 0 1 vbuf voff)
              (foreign-set! 'float push 0 800.0)
              (foreign-set! 'float push 4 600.0)
              (vkCmdPushConstants cmd (text-pipeline-pipeline-layout tp)
                                  VK_SHADER_STAGE_VERTEX_BIT 0 8 push)
              (vkCmdDraw cmd 6 n-written 0 0)
              (vkCmdEndRenderPass cmd)
              ;; --- Readback: COLOR_ATTACHMENT_OPTIMAL → TRANSFER_SRC
              ;; → vkCmdCopyImageToBuffer ----------------------------
              (let ((bar  (foreign-alloc/zero (ftype-sizeof <VkImageMemoryBarrier>)))
                    (region (foreign-alloc/zero (ftype-sizeof <VkBufferImageCopy>))))
                (let ((bp (make-ftype-pointer <VkImageMemoryBarrier> bar))
                      (rp (make-ftype-pointer <VkBufferImageCopy> region)))
                  (ftype-set! <VkImageMemoryBarrier> (sType) bp
                              VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER)
                  (ftype-set! <VkImageMemoryBarrier> (srcAccessMask) bp
                              VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
                  (ftype-set! <VkImageMemoryBarrier> (dstAccessMask) bp
                              VK_ACCESS_MEMORY_READ_BIT)
                  (ftype-set! <VkImageMemoryBarrier> (oldLayout) bp
                              VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
                  (ftype-set! <VkImageMemoryBarrier> (newLayout) bp
                              VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
                  (ftype-set! <VkImageMemoryBarrier> (srcQueueFamilyIndex) bp
                              VK_QUEUE_FAMILY_IGNORED)
                  (ftype-set! <VkImageMemoryBarrier> (dstQueueFamilyIndex) bp
                              VK_QUEUE_FAMILY_IGNORED)
                  (ftype-set! <VkImageMemoryBarrier> (image) bp color-image)
                  (ftype-set! <VkImageMemoryBarrier> (subresourceRange aspectMask) bp
                              VK_IMAGE_ASPECT_COLOR_BIT)
                  (ftype-set! <VkImageMemoryBarrier> (subresourceRange levelCount) bp 1)
                  (ftype-set! <VkImageMemoryBarrier> (subresourceRange layerCount) bp 1)
                  (vkCmdPipelineBarrier cmd
                                        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
                                        VK_PIPELINE_STAGE_TRANSFER_BIT
                                        0 0 0 0 0 1 bar)
                  (ftype-set! <VkBufferImageCopy> (imageSubresource aspectMask) rp
                              VK_IMAGE_ASPECT_COLOR_BIT)
                  (ftype-set! <VkBufferImageCopy> (imageSubresource layerCount) rp 1)
                  (ftype-set! <VkBufferImageCopy> (imageExtent width) rp 800)
                  (ftype-set! <VkBufferImageCopy> (imageExtent height) rp 600)
                  (ftype-set! <VkBufferImageCopy> (imageExtent depth) rp 1)
                  (vkCmdCopyImageToBuffer cmd color-image
                                          VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
                                          readback-buffer 1 region))
                (foreign-free region)
                (foreign-free bar))
              (vk-check 'vkEndCommandBuffer (vkEndCommandBuffer cmd))
              (foreign-set! 'uptr cmdarr 0 cmd)
              (ftype-set! <VkSubmitInfo> (sType) sip VK_STRUCTURE_TYPE_SUBMIT_INFO)
              (ftype-set! <VkSubmitInfo> (commandBufferCount) sip 1)
              (ftype-set! <VkSubmitInfo> (pCommandBuffers) sip cmdarr)
              (vk-check 'vkQueueSubmit (vkQueueSubmit queue 1 si 0))
              (vk-check 'vkDeviceWaitIdle (vkDeviceWaitIdle device))
              #f)))
      ;; --- Verify pixels: clear color outside, glyph drawn inside.
      ;; B8G8R8A8_UNORM: byte0=B, byte1=G, byte2=R, byte3=A.
      (let* ((mapped-out (foreign-alloc/zero 8))
             (_ (vk-check 'vkMapMemory
                          (vkMapMemory device readback-mem 0
                                       readback-bytes 0 mapped-out)))
             (px (foreign-ref 'uptr mapped-out 0))
             (pix-at (lambda (x y)
                       (let ((off (* 4 (+ (* y 800) x))))
                         (list (foreign-ref 'unsigned-8 px (+ off 2))
                               (foreign-ref 'unsigned-8 px (+ off 1))
                               (foreign-ref 'unsigned-8 px off)
                               (foreign-ref 'unsigned-8 px (+ off 3))))))
             ;; Outside-the-glyphs pixel — should match clear color.
             ;; Clear was (0.05, 0.05, 0.10, 1.0). Allow ±5 byte tolerance.
             (clear-px (pix-at 5 5))
             (clear-ok? (and (<= (abs (- (car   clear-px) 13)) 6)   ; R≈13
                             (<= (abs (- (cadr  clear-px) 13)) 6)   ; G≈13
                             (<= (abs (- (caddr clear-px) 26)) 6)   ; B≈26
                             (= (cadddr clear-px) 255)))
             ;; In the rect (100..100+gw, 100..100+gh) the white 'A'
             ;; should leave at least one pixel where R > 200.
             (saw-white-A?
              (let scan ((y 100) (found #f))
                (cond
                 (found #t)
                 ((= y (+ 100 gh)) #f)
                 (else
                  (let inner ((x 100) (f #f))
                    (cond
                     (f (scan (+ y 1) #t))
                     ((= x (+ 100 gw))
                      (scan (+ y 1) #f))
                     (else
                      (let ((p (pix-at x y)))
                        (inner (+ x 1)
                               (and (> (car p) 200)
                                    (> (cadr p) 200)
                                    (> (caddr p) 200))))))))))))
        (vkUnmapMemory device readback-mem)
        (foreign-free mapped-out)
        (display (list 'drew n-written 'instances
                       'clear-px-at-5-5 clear-px
                       'clear-ok? clear-ok?
                       'saw-white-A? saw-white-A?))
        (newline)
        (unless (and clear-ok? saw-white-A?)
          (error 'draw-smoke "pixel-level verification failed")))
      ;; Teardown — order matters: text-pipeline first (uses render pass).
      (destroy-text-pipeline! device tp)
      (vkDestroyBuffer device readback-buffer 0)
      (vkFreeMemory device readback-mem 0)
      (vkDestroyFramebuffer device framebuffer 0)
      (vkDestroyImageView device color-view 0)
      (vkFreeMemory device color-mem 0)
      (vkDestroyImage device color-image 0)
      (vkDestroyRenderPass device render-pass 0)
      (vkDestroyCommandPool device command-pool 0)
      (vkDestroyDevice device 0)
      (display "draw-smoke OK") (newline))))
