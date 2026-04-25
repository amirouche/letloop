#!chezscheme
;; M2.1 chunk C — display-plane surface, swapchain, magenta clear loop.
;;
;; window-open builds the full Vulkan rendering chain on top of a
;; (letloop desktop vulkan) instance: physical device → graphics queue
;; family → display + mode + plane → surface → device → swapchain →
;; images → command pool/buffer → sync primitives. Any failure mid-way
;; rolls back already-built objects before re-raising, so a sandbox run
;; with no display still leaves the seat in a clean state.
;;
;; window-render-frame! waits on the in-flight fence, acquires the next
;; image, records a transition+clear+transition command buffer, submits
;; with the standard acquire/present semaphore pair, and queues a
;; present. Color comes from the mutable r/g/b/a slots so a future REPL
;; can mutate live.
(library (letloop desktop window)
  (export
   call-with-window
   window-open
   window-close
   window-run!
   window-render-frame!
   window-clear-color!
   window-draw-text!
   window-clear-text!
   window-fg-color!
   window-attach-keyboard!
   window-set-prompt!
   window-set-line-handler!
   window-set-line-position!
   window-line-buffer
   window?
   window-released?
   window-extent-width
   window-extent-height)
  (import
   (chezscheme)
   (letloop desktop vulkan)
   (letloop desktop vulkan low)
   (letloop desktop text-pipeline)
   (letloop desktop font)
   (letloop desktop evdev)
   (letloop desktop input)
   (letloop desktop keymap))

  (define (pk . args)
    (when (getenv "LETLOOP_DEBUG")
      (display ";; " (current-error-port))
      (write args (current-error-port))
      (newline (current-error-port))
      (flush-output-port (current-error-port)))
    (if (null? args) (void) (car (reverse args))))

  ;; ----------------------------------------------------------------
  ;; Result checking
  ;; ----------------------------------------------------------------

  (define (vk-check who r)
    (unless (= r VK_SUCCESS)
      (error who (vk-result-name r) r))
    r)

  ;; ----------------------------------------------------------------
  ;; Foreign memory helpers
  ;; ----------------------------------------------------------------

  (define (foreign-alloc/zero nbytes)
    (let ((p (foreign-alloc nbytes)))
      (do ((i 0 (+ i 1))) ((= i nbytes))
        (foreign-set! 'unsigned-8 p i 0))
      p))

  (define UINT64_MAX #xFFFFFFFFFFFFFFFF)

  ;; ----------------------------------------------------------------
  ;; Render pass / image view / framebuffer helpers
  ;; ----------------------------------------------------------------

  (define (create-color-render-pass device color-format)
    (let* ((att   (foreign-alloc/zero
                   (ftype-sizeof <VkAttachmentDescription>)))
           (ref   (foreign-alloc/zero
                   (ftype-sizeof <VkAttachmentReference>)))
           (sub   (foreign-alloc/zero
                   (ftype-sizeof <VkSubpassDescription>)))
           (dep   (foreign-alloc/zero
                   (ftype-sizeof <VkSubpassDependency>)))
           (info  (foreign-alloc/zero
                   (ftype-sizeof <VkRenderPassCreateInfo>)))
           (out   (foreign-alloc/zero 8))
           (afp   (make-ftype-pointer <VkAttachmentDescription> att))
           (rfp   (make-ftype-pointer <VkAttachmentReference> ref))
           (sfp   (make-ftype-pointer <VkSubpassDescription> sub))
           (dfp   (make-ftype-pointer <VkSubpassDependency> dep))
           (ifp   (make-ftype-pointer <VkRenderPassCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkAttachmentDescription> (format) afp color-format)
         (ftype-set! <VkAttachmentDescription> (samples) afp VK_SAMPLE_COUNT_1_BIT)
         (ftype-set! <VkAttachmentDescription> (loadOp) afp
                     VK_ATTACHMENT_LOAD_OP_CLEAR)
         (ftype-set! <VkAttachmentDescription> (storeOp) afp
                     VK_ATTACHMENT_STORE_OP_STORE)
         (ftype-set! <VkAttachmentDescription> (stencilLoadOp) afp
                     VK_ATTACHMENT_LOAD_OP_DONT_CARE)
         (ftype-set! <VkAttachmentDescription> (stencilStoreOp) afp
                     VK_ATTACHMENT_STORE_OP_DONT_CARE)
         (ftype-set! <VkAttachmentDescription> (initialLayout) afp
                     VK_IMAGE_LAYOUT_UNDEFINED)
         (ftype-set! <VkAttachmentDescription> (finalLayout) afp
                     VK_IMAGE_LAYOUT_PRESENT_SRC_KHR)
         (ftype-set! <VkAttachmentReference> (attachment) rfp 0)
         (ftype-set! <VkAttachmentReference> (layout) rfp
                     VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
         (ftype-set! <VkSubpassDescription> (pipelineBindPoint) sfp
                     VK_PIPELINE_BIND_POINT_GRAPHICS)
         (ftype-set! <VkSubpassDescription> (colorAttachmentCount) sfp 1)
         (ftype-set! <VkSubpassDescription> (pColorAttachments) sfp ref)
         (ftype-set! <VkSubpassDependency> (srcSubpass) dfp VK_SUBPASS_EXTERNAL)
         (ftype-set! <VkSubpassDependency> (dstSubpass) dfp 0)
         (ftype-set! <VkSubpassDependency> (srcStageMask) dfp
                     VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
         (ftype-set! <VkSubpassDependency> (dstStageMask) dfp
                     VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
         (ftype-set! <VkSubpassDependency> (srcAccessMask) dfp 0)
         (ftype-set! <VkSubpassDependency> (dstAccessMask) dfp
                     VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
         (ftype-set! <VkRenderPassCreateInfo> (sType) ifp
                     VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO)
         (ftype-set! <VkRenderPassCreateInfo> (attachmentCount) ifp 1)
         (ftype-set! <VkRenderPassCreateInfo> (pAttachments) ifp att)
         (ftype-set! <VkRenderPassCreateInfo> (subpassCount) ifp 1)
         (ftype-set! <VkRenderPassCreateInfo> (pSubpasses) ifp sub)
         (ftype-set! <VkRenderPassCreateInfo> (dependencyCount) ifp 1)
         (ftype-set! <VkRenderPassCreateInfo> (pDependencies) ifp dep)
         (vk-check 'vkCreateRenderPass
                   (vkCreateRenderPass device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info)
         (foreign-free dep) (foreign-free sub)
         (foreign-free ref) (foreign-free att)))))

  (define (create-color-image-view device image format)
    (let* ((info (foreign-alloc/zero
                  (ftype-sizeof <VkImageViewCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkImageViewCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkImageViewCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO)
         (ftype-set! <VkImageViewCreateInfo> (image) fp image)
         (ftype-set! <VkImageViewCreateInfo> (viewType) fp VK_IMAGE_VIEW_TYPE_2D)
         (ftype-set! <VkImageViewCreateInfo> (format) fp format)
         ;; components: VK_COMPONENT_SWIZZLE_IDENTITY = 0, struct already zeroed
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange aspectMask) fp
                     VK_IMAGE_ASPECT_COLOR_BIT)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange baseMipLevel) fp 0)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange levelCount) fp 1)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange baseArrayLayer) fp 0)
         (ftype-set! <VkImageViewCreateInfo> (subresourceRange layerCount) fp 1)
         (vk-check 'vkCreateImageView
                   (vkCreateImageView device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info)))))

  (define (create-framebuffer device render-pass view width height)
    (let* ((view-arr (foreign-alloc/zero 8))
           (info     (foreign-alloc/zero
                      (ftype-sizeof <VkFramebufferCreateInfo>)))
           (out      (foreign-alloc/zero 8))
           (fp       (make-ftype-pointer <VkFramebufferCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (foreign-set! 'unsigned-64 view-arr 0 view)
         (ftype-set! <VkFramebufferCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO)
         (ftype-set! <VkFramebufferCreateInfo> (renderPass) fp render-pass)
         (ftype-set! <VkFramebufferCreateInfo> (attachmentCount) fp 1)
         (ftype-set! <VkFramebufferCreateInfo> (pAttachments) fp view-arr)
         (ftype-set! <VkFramebufferCreateInfo> (width) fp width)
         (ftype-set! <VkFramebufferCreateInfo> (height) fp height)
         (ftype-set! <VkFramebufferCreateInfo> (layers) fp 1)
         (vk-check 'vkCreateFramebuffer
                   (vkCreateFramebuffer device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out) (foreign-free info)
         (foreign-free view-arr)))))

  (define (make-semaphore device)
    (let* ((info (foreign-alloc/zero
                  (ftype-sizeof <VkSemaphoreCreateInfo>)))
           (out  (foreign-alloc/zero 8))
           (fp   (make-ftype-pointer <VkSemaphoreCreateInfo> info)))
      (dynamic-wind
       void
       (lambda ()
         (ftype-set! <VkSemaphoreCreateInfo> (sType) fp
                     VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO)
         (vk-check 'vkCreateSemaphore
                   (vkCreateSemaphore device info 0 out))
         (foreign-ref 'unsigned-64 out 0))
       (lambda ()
         (foreign-free out)
         (foreign-free info)))))

  ;; ----------------------------------------------------------------
  ;; The window record
  ;; ----------------------------------------------------------------

  (define-record-type window
    (fields
     (mutable released?)
     instance physical-device queue-family-index
     device queue
     surface swapchain
     format extent-width extent-height
     render-pass
     images                ; list of u64 VkImage
     image-views           ; list of u64 VkImageView, parallel to images
     framebuffers          ; list of u64 VkFramebuffer, parallel to images
     command-pool command-buffer
     image-available-sem render-finished-sem in-flight-fence
     text-pipeline         ; (letloop desktop text-pipeline) record
     (mutable pending-text); list of (string x y) — drawn next render
     ;; line editor state — fed by the keyboard pump in window-run!.
     (mutable kbd-fd)      ; -1 if no keyboard attached
     (mutable shift?)
     (mutable line-buffer) ; string — current edit line
     (mutable line-prompt) ; string — drawn before the line
     (mutable line-handler); proc taking the completed line on Enter
     (mutable line-x)      ; pixel position of the prompt
     (mutable line-y)
     ;; pre-allocated scratch foreign buffers, freed in window-close
     scratch               ; list of foreign-alloc'd addresses
     (mutable r) (mutable g) (mutable b) (mutable a)
     (mutable fg-r) (mutable fg-g) (mutable fg-b) (mutable fg-a)))

  ;; ----------------------------------------------------------------
  ;; window-open
  ;; ----------------------------------------------------------------

  (define (window-open instance)
    ;; rollback: list of zero-arg thunks, run in reverse on failure.
    (define rollback '())
    (define (track! thunk) (set! rollback (cons thunk rollback)))
    (define (do-rollback!)
      (for-each
       (lambda (t)
         (guard (e (#t (void))) (t)))
       rollback))
    ;; scratch: foreign addresses to free in window-close on success.
    (define scratch '())
    (define (alloc/scratch! nbytes)
      (let ((p (foreign-alloc/zero nbytes)))
        (set! scratch (cons p scratch))
        p))
    (guard (e (#t (do-rollback!) (raise e)))
     (let* (;; 1. Pick first physical device.
            (pds (vulkan-physical-devices instance))
            (pd  (if (null? pds)
                     (error 'window-open "no Vulkan physical devices")
                     (car pds)))
            ;; 2. Pick a graphics queue family.
            (qfi (or (vulkan-pick-graphics-queue-family pd)
                     (error 'window-open
                            "physical device has no graphics queue family" pd)))
            ;; 3. Pick the first display.
            (displays (vulkan-display-properties pd))
            (display
             (if (null? displays)
                 (error 'window-open
                        "no Vulkan displays — likely missing DRM master / no GPU")
                 (car displays)))
            ;; 4. Pick the first display mode.
            (modes (vulkan-display-modes pd (vulkan-display-handle display)))
            (mode  (if (null? modes)
                       (error 'window-open
                              "display has no modes" (vulkan-display-name display))
                       (car modes)))
            ;; 5. Pick plane index 0 (always valid for primary display).
            (planes (vulkan-display-plane-properties pd))
            (_planes-check
             (if (null? planes)
                 (error 'window-open "no display planes")
                 #f))
            (plane-index 0)
            ;; 6. Create the display-plane surface.
            (surface
        (let* ((info (foreign-alloc/zero
                      (ftype-sizeof <VkDisplaySurfaceCreateInfoKHR>)))
               (out  (foreign-alloc/zero 8))
               (fp   (make-ftype-pointer <VkDisplaySurfaceCreateInfoKHR> info)))
          (dynamic-wind
           void
           (lambda ()
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (sType) fp
                         VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR)
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (displayMode) fp
                         (vulkan-display-mode-handle mode))
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (planeIndex) fp plane-index)
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (planeStackIndex) fp 0)
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (transform) fp
                         VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR)
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (globalAlpha) fp 1.0)
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (alphaMode) fp
                         VK_DISPLAY_PLANE_ALPHA_OPAQUE_BIT_KHR)
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (imageExtent width) fp
                         (vulkan-display-mode-width mode))
             (ftype-set! <VkDisplaySurfaceCreateInfoKHR> (imageExtent height) fp
                         (vulkan-display-mode-height mode))
             (vk-check 'vkCreateDisplayPlaneSurfaceKHR
                       (vkCreateDisplayPlaneSurfaceKHR instance info 0 out))
             (foreign-ref 'unsigned-64 out 0))
           (lambda ()
             (foreign-free out)
             (foreign-free info)))))
            (_track-surface
             (begin (track! (lambda () (vkDestroySurfaceKHR instance surface 0))) #f))
            ;; 7. Create the device with one graphics queue and the swapchain ext.
            (device
        (let* ((priorities (foreign-alloc/zero 4))         ; one float
               (qci  (foreign-alloc/zero
                      (ftype-sizeof <VkDeviceQueueCreateInfo>)))
               (dci  (foreign-alloc/zero
                      (ftype-sizeof <VkDeviceCreateInfo>)))
               (ext-name (string->utf8 VK_KHR_SWAPCHAIN_EXTENSION_NAME))
               (ext-buf-len (+ (bytevector-length ext-name) 1))
               (ext-buf (foreign-alloc ext-buf-len))
               (ext-arr (foreign-alloc 8))
               (out  (foreign-alloc/zero 8))
               (qfp  (make-ftype-pointer <VkDeviceQueueCreateInfo> qci))
               (dfp  (make-ftype-pointer <VkDeviceCreateInfo> dci)))
          (dynamic-wind
           void
           (lambda ()
             ;; queue priorities (must outlive vkCreateDevice but Vulkan
             ;; reads it synchronously, so freeing afterwards is fine).
             (foreign-set! 'float priorities 0 1.0)
             ;; ext name as a NUL-terminated UTF-8 byte array
             (do ((i 0 (+ i 1))) ((= i (bytevector-length ext-name)))
               (foreign-set! 'unsigned-8 ext-buf i
                             (bytevector-u8-ref ext-name i)))
             (foreign-set! 'unsigned-8 ext-buf (bytevector-length ext-name) 0)
             (foreign-set! 'uptr ext-arr 0 ext-buf)
             ;; queue create info
             (ftype-set! <VkDeviceQueueCreateInfo> (sType) qfp
                         VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO)
             (ftype-set! <VkDeviceQueueCreateInfo> (queueFamilyIndex) qfp qfi)
             (ftype-set! <VkDeviceQueueCreateInfo> (queueCount) qfp 1)
             (ftype-set! <VkDeviceQueueCreateInfo> (pQueuePriorities) qfp priorities)
             ;; device create info
             (ftype-set! <VkDeviceCreateInfo> (sType) dfp
                         VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO)
             (ftype-set! <VkDeviceCreateInfo> (queueCreateInfoCount) dfp 1)
             (ftype-set! <VkDeviceCreateInfo> (pQueueCreateInfos) dfp qci)
             (ftype-set! <VkDeviceCreateInfo> (enabledExtensionCount) dfp 1)
             (ftype-set! <VkDeviceCreateInfo> (ppEnabledExtensionNames) dfp ext-arr)
             (vk-check 'vkCreateDevice
                       (vkCreateDevice pd dci 0 out))
             (foreign-ref 'uptr out 0))
           (lambda ()
             (foreign-free out)
             (foreign-free ext-arr)
             (foreign-free ext-buf)
             (foreign-free dci)
             (foreign-free qci)
             (foreign-free priorities)))))
            (_track-device
             (begin (track! (lambda () (vkDestroyDevice device 0))) #f))
            ;; 8. Get the queue.
            (queue
        (let ((out (foreign-alloc/zero 8)))
          (dynamic-wind
           void
           (lambda ()
             (vkGetDeviceQueue device qfi 0 out)
             (foreign-ref 'uptr out 0))
           (lambda () (foreign-free out)))))
            ;; 9. Surface capabilities + 10. first format — packed as
            ;; a single 7-element list to avoid define-values inside let*.
            (caps+fmt
             (let* ((p   (foreign-alloc/zero
                          (ftype-sizeof <VkSurfaceCapabilitiesKHR>)))
                    (fp  (make-ftype-pointer <VkSurfaceCapabilitiesKHR> p))
                    (count-p (foreign-alloc/zero 4)))
               (dynamic-wind
                void
                (lambda ()
                  (vk-check 'vkGetPhysicalDeviceSurfaceCapabilitiesKHR
                            (vkGetPhysicalDeviceSurfaceCapabilitiesKHR pd surface p))
                  (vk-check 'vkGetPhysicalDeviceSurfaceFormatsKHR/count
                            (vkGetPhysicalDeviceSurfaceFormatsKHR pd surface count-p 0))
                  (let ((n (foreign-ref 'unsigned-32 count-p 0)))
                    (when (zero? n)
                      (error 'window-open "surface reports no formats"))
                    (let* ((sz   (ftype-sizeof <VkSurfaceFormatKHR>))
                           (farr (foreign-alloc/zero (* n sz))))
                      (dynamic-wind
                       void
                       (lambda ()
                         (vk-check 'vkGetPhysicalDeviceSurfaceFormatsKHR/fill
                                   (vkGetPhysicalDeviceSurfaceFormatsKHR
                                    pd surface count-p farr))
                         (let ((ffp (make-ftype-pointer <VkSurfaceFormatKHR> farr)))
                           (list
                            (ftype-ref <VkSurfaceCapabilitiesKHR> (minImageCount) fp)
                            (ftype-ref <VkSurfaceCapabilitiesKHR> (maxImageCount) fp)
                            (ftype-ref <VkSurfaceCapabilitiesKHR> (currentExtent width) fp)
                            (ftype-ref <VkSurfaceCapabilitiesKHR> (currentExtent height) fp)
                            (ftype-ref <VkSurfaceCapabilitiesKHR> (currentTransform) fp)
                            (ftype-ref <VkSurfaceFormatKHR> (format) ffp)
                            (ftype-ref <VkSurfaceFormatKHR> (colorSpace) ffp))))
                       (lambda () (foreign-free farr))))))
                (lambda ()
                  (foreign-free count-p)
                  (foreign-free p)))))
            (cap-min-image-count (list-ref caps+fmt 0))
            (cap-max-image-count (list-ref caps+fmt 1))
            (cap-cur-w           (list-ref caps+fmt 2))
            (cap-cur-h           (list-ref caps+fmt 3))
            (cap-cur-transform   (list-ref caps+fmt 4))
            (fmt-format          (list-ref caps+fmt 5))
            (fmt-color-space     (list-ref caps+fmt 6))
            ;; 11. Decide the swapchain extent.
            (extent-w (if (= cap-cur-w #xFFFFFFFF)
                          (vulkan-display-mode-width mode)
                          cap-cur-w))
            (extent-h (if (= cap-cur-w #xFFFFFFFF)
                          (vulkan-display-mode-height mode)
                          cap-cur-h))
            ;; minImageCount, clamped to maxImageCount when the latter is set.
            (swap-image-count
             (if (and (not (zero? cap-max-image-count))
                      (< cap-max-image-count cap-min-image-count))
                 cap-max-image-count
                 cap-min-image-count))
            ;; 12. Create the swapchain.
            (swapchain
        (let* ((info (foreign-alloc/zero
                      (ftype-sizeof <VkSwapchainCreateInfoKHR>)))
               (out  (foreign-alloc/zero 8))
               (fp   (make-ftype-pointer <VkSwapchainCreateInfoKHR> info)))
          (dynamic-wind
           void
           (lambda ()
             (ftype-set! <VkSwapchainCreateInfoKHR> (sType) fp
                         VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR)
             (ftype-set! <VkSwapchainCreateInfoKHR> (surface) fp surface)
             (ftype-set! <VkSwapchainCreateInfoKHR> (minImageCount) fp swap-image-count)
             (ftype-set! <VkSwapchainCreateInfoKHR> (imageFormat) fp fmt-format)
             (ftype-set! <VkSwapchainCreateInfoKHR> (imageColorSpace) fp fmt-color-space)
             (ftype-set! <VkSwapchainCreateInfoKHR> (imageExtent width) fp extent-w)
             (ftype-set! <VkSwapchainCreateInfoKHR> (imageExtent height) fp extent-h)
             (ftype-set! <VkSwapchainCreateInfoKHR> (imageArrayLayers) fp 1)
             (ftype-set! <VkSwapchainCreateInfoKHR> (imageUsage) fp
                         VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)
             (ftype-set! <VkSwapchainCreateInfoKHR> (imageSharingMode) fp
                         VK_SHARING_MODE_EXCLUSIVE)
             (ftype-set! <VkSwapchainCreateInfoKHR> (preTransform) fp cap-cur-transform)
             (ftype-set! <VkSwapchainCreateInfoKHR> (compositeAlpha) fp
                         VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR)
             (ftype-set! <VkSwapchainCreateInfoKHR> (presentMode) fp
                         VK_PRESENT_MODE_FIFO_KHR)
             (ftype-set! <VkSwapchainCreateInfoKHR> (clipped) fp 1)
             (ftype-set! <VkSwapchainCreateInfoKHR> (oldSwapchain) fp 0)
             (vk-check 'vkCreateSwapchainKHR
                       (vkCreateSwapchainKHR device info 0 out))
             (foreign-ref 'unsigned-64 out 0))
           (lambda ()
             (foreign-free out)
             (foreign-free info)))))
            (_track-swapchain
             (begin (track! (lambda () (vkDestroySwapchainKHR device swapchain 0))) #f))
            ;; 13. Get swapchain images.
            (images
        (let ((count-p (foreign-alloc/zero 4)))
          (dynamic-wind
           void
           (lambda ()
             (vk-check 'vkGetSwapchainImagesKHR/count
                       (vkGetSwapchainImagesKHR device swapchain count-p 0))
             (let ((n (foreign-ref 'unsigned-32 count-p 0)))
               (when (zero? n)
                 (error 'window-open "swapchain returned 0 images"))
               (let ((arr (foreign-alloc (* n 8))))
                 (dynamic-wind
                  void
                  (lambda ()
                    (vk-check 'vkGetSwapchainImagesKHR/fill
                              (vkGetSwapchainImagesKHR device swapchain count-p arr))
                    (let loop ((i 0) (out '()))
                      (if (= i n)
                          (reverse out)
                          (loop (+ i 1)
                                (cons (foreign-ref 'unsigned-64 arr (* i 8))
                                      out)))))
                  (lambda () (foreign-free arr))))))
           (lambda () (foreign-free count-p)))))
            ;; 13a. Render pass — single color attachment, clear-on-load,
            ;; transitions UNDEFINED → COLOR_ATTACHMENT_OPTIMAL → PRESENT_SRC_KHR.
            (render-pass (create-color-render-pass device fmt-format))
            (_track-rp
             (begin (track! (lambda () (vkDestroyRenderPass device render-pass 0))) #f))
            ;; 13b. One image view per swapchain image.
            (image-views
             (map (lambda (img) (create-color-image-view device img fmt-format))
                  images))
            (_track-views
             (begin (track!
                     (lambda ()
                       (for-each (lambda (v) (vkDestroyImageView device v 0))
                                 image-views)))
                    #f))
            ;; 13c. One framebuffer per image view.
            (framebuffers
             (map (lambda (view)
                    (create-framebuffer device render-pass view extent-w extent-h))
                  image-views))
            (_track-fbs
             (begin (track!
                     (lambda ()
                       (for-each (lambda (fb) (vkDestroyFramebuffer device fb 0))
                                 framebuffers)))
                    #f))
            ;; 14. Command pool with reset bit.
            (command-pool
        (let* ((info (foreign-alloc/zero
                      (ftype-sizeof <VkCommandPoolCreateInfo>)))
               (out  (foreign-alloc/zero 8))
               (fp   (make-ftype-pointer <VkCommandPoolCreateInfo> info)))
          (dynamic-wind
           void
           (lambda ()
             (ftype-set! <VkCommandPoolCreateInfo> (sType) fp
                         VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO)
             (ftype-set! <VkCommandPoolCreateInfo> (flags) fp
                         VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT)
             (ftype-set! <VkCommandPoolCreateInfo> (queueFamilyIndex) fp qfi)
             (vk-check 'vkCreateCommandPool
                       (vkCreateCommandPool device info 0 out))
             (foreign-ref 'unsigned-64 out 0))
           (lambda ()
             (foreign-free out)
             (foreign-free info)))))
            (_track-pool
             (begin (track! (lambda () (vkDestroyCommandPool device command-pool 0))) #f))
            ;; 15. One primary command buffer.
            (command-buffer
        (let* ((info (foreign-alloc/zero
                      (ftype-sizeof <VkCommandBufferAllocateInfo>)))
               (out  (foreign-alloc/zero 8))   ; one VkCommandBuffer (pointer)
               (fp   (make-ftype-pointer <VkCommandBufferAllocateInfo> info)))
          (dynamic-wind
           void
           (lambda ()
             (ftype-set! <VkCommandBufferAllocateInfo> (sType) fp
                         VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO)
             (ftype-set! <VkCommandBufferAllocateInfo> (commandPool) fp command-pool)
             (ftype-set! <VkCommandBufferAllocateInfo> (level) fp
                         VK_COMMAND_BUFFER_LEVEL_PRIMARY)
             (ftype-set! <VkCommandBufferAllocateInfo> (commandBufferCount) fp 1)
             (vk-check 'vkAllocateCommandBuffers
                       (vkAllocateCommandBuffers device info out))
             (foreign-ref 'uptr out 0))
           (lambda ()
             (foreign-free out)
             (foreign-free info)))))
            ;; (no rollback for command-buffer alone — destroying the pool frees it)
            ;; 16. Two semaphores + one signaled fence.
            (image-available-sem (make-semaphore device))
            (_track-ia
             (begin (track! (lambda () (vkDestroySemaphore device image-available-sem 0))) #f))
            (render-finished-sem (make-semaphore device))
            (_track-rf
             (begin (track! (lambda () (vkDestroySemaphore device render-finished-sem 0))) #f))
            (in-flight-fence
        (let* ((info (foreign-alloc/zero
                      (ftype-sizeof <VkFenceCreateInfo>)))
               (out  (foreign-alloc/zero 8))
               (fp   (make-ftype-pointer <VkFenceCreateInfo> info)))
          (dynamic-wind
           void
           (lambda ()
             (ftype-set! <VkFenceCreateInfo> (sType) fp
                         VK_STRUCTURE_TYPE_FENCE_CREATE_INFO)
             (ftype-set! <VkFenceCreateInfo> (flags) fp
                         VK_FENCE_CREATE_SIGNALED_BIT)
             (vk-check 'vkCreateFence
                       (vkCreateFence device info 0 out))
             (foreign-ref 'unsigned-64 out 0))
           (lambda ()
             (foreign-free out)
             (foreign-free info)))))
            (_track-fence
             (begin (track! (lambda () (vkDestroyFence device in-flight-fence 0))) #f))
            ;; D-3: text rendering pipeline (atlas + descriptor + pipeline + instance buf).
            (text-pipeline
             (build-text-pipeline device pd render-pass queue command-pool))
            (_track-tp
             (begin (track!
                     (lambda () (destroy-text-pipeline! device text-pipeline)))
                    #f)))
       ;; All built — clear rollback so window-close is the sole owner.
       (set! rollback '())
       (make-window
        #f
        instance pd qfi
        device queue
        surface swapchain
        fmt-format extent-w extent-h
        render-pass
        images image-views framebuffers
        command-pool command-buffer
        image-available-sem render-finished-sem in-flight-fence
        text-pipeline
        '()                              ; pending-text
        -1                               ; kbd-fd (none until attached)
        #f                               ; shift?
        ""                               ; line-buffer
        "> "                             ; line-prompt
        (lambda (line) (void))           ; line-handler — no-op default
        40 200                           ; line-x, line-y
        scratch
        0.05 0.05 0.10 1.0               ; bg dark blue
        1.0 1.0 1.0 1.0))))              ; fg white

  ;; ----------------------------------------------------------------
  ;; window-clear-color!
  ;; ----------------------------------------------------------------

  (define (window-clear-color! w r g b a)
    (window-r-set! w (exact->inexact r))
    (window-g-set! w (exact->inexact g))
    (window-b-set! w (exact->inexact b))
    (window-a-set! w (exact->inexact a)))

  (define (window-fg-color! w r g b a)
    (window-fg-r-set! w (exact->inexact r))
    (window-fg-g-set! w (exact->inexact g))
    (window-fg-b-set! w (exact->inexact b))
    (window-fg-a-set! w (exact->inexact a)))

  ;; Append a text draw to the persistent list. Each entry is rendered
  ;; on every subsequent frame until window-clear-text! is called.
  (define (window-draw-text! w text x y)
    (window-pending-text-set!
     w (append (window-pending-text w)
               (list (list text (exact->inexact x) (exact->inexact y))))))

  (define (window-clear-text! w)
    (window-pending-text-set! w '()))

  ;; ----------------------------------------------------------------
  ;; Line editor wiring
  ;; ----------------------------------------------------------------

  (define (window-attach-keyboard! w fd)
    (window-kbd-fd-set! w fd))

  (define (window-set-prompt! w str)
    (window-line-prompt-set! w str))

  (define (window-set-line-handler! w proc)
    (window-line-handler-set! w proc))

  (define (window-set-line-position! w x y)
    (window-line-x-set! w x)
    (window-line-y-set! w y))

  (define (handle-key-event! w code value)
    (cond
     ;; Modifier tracking — track press/repeat as down, release as up.
     ((or (= code KEY_LEFTSHIFT) (= code KEY_RIGHTSHIFT))
      (window-shift?-set! w (not (= value KEY_VALUE_RELEASE))))
     ;; Anything else only matters on press / repeat.
     ((or (= value KEY_VALUE_PRESS) (= value KEY_VALUE_REPEAT))
      (cond
       ((= code KEY_BACKSPACE)
        (let* ((b (window-line-buffer w))
               (n (string-length b)))
          (when (positive? n)
            (window-line-buffer-set! w (substring b 0 (- n 1))))))
       ((= code KEY_ENTER)
        (let ((line (window-line-buffer w)))
          (window-line-buffer-set! w "")
          ((window-line-handler w) line)))
       (else
        (let ((ch (keymap-printable code (window-shift? w))))
          (when ch
            (window-line-buffer-set!
             w (string-append (window-line-buffer w) (string ch))))))))))

  ;; Build the per-frame instance list from pending text. Each character
  ;; that has a glyph in the atlas becomes an 8-element float list:
  ;;   (x y w h u v uw uh)
  ;; advancing x by glyph-width per character. Characters without
  ;; glyphs are skipped (e.g. zero-width or unsupported codepoints).
  (define (build-instance-list w)
    (let* ((tp    (window-text-pipeline w))
           (font  (text-pipeline-font tp))
           (gw    (font-glyph-width font))
           (gh    (font-glyph-height font))
           ;; Prompt + line buffer treated as one extra draw.
           (line-text (string-append (window-line-prompt w)
                                     (window-line-buffer w)))
           (extras (if (zero? (string-length line-text))
                       '()
                       (list (list line-text
                                   (window-line-x w)
                                   (window-line-y w))))))
      (let loop ((draws (append (window-pending-text w) extras))
                 (acc '()))
        (if (null? draws)
            (reverse acc)
            (let* ((d   (car draws))
                   (txt (car d))
                   (ox  (cadr d))
                   (oy  (caddr d)))
              (loop (cdr draws)
                    (append (reverse (build-instances-for-text font txt ox oy gw gh))
                            acc)))))))

  (define (build-instances-for-text font txt x0 y0 gw gh)
    (let loop ((chars (string->list txt))
               (x x0)
               (acc '()))
      (cond
       ((null? chars) (reverse acc))
       (else
        (let ((info (font-glyph-info font (char->integer (car chars)))))
          (if info
              (loop (cdr chars)
                    (+ x gw)
                    (cons (list (exact->inexact x)
                                (exact->inexact y0)
                                (exact->inexact gw)
                                (exact->inexact gh)
                                (glyph-info-uv-x info)
                                (glyph-info-uv-y info)
                                (glyph-info-uv-w info)
                                (glyph-info-uv-h info))
                          acc))
              ;; Unmapped char — still advance cursor so layout looks
              ;; like a missing-glyph "space".
              (loop (cdr chars) (+ x gw) acc)))))))

  ;; Record the text draws inside the active render pass.
  (define (record-text-draws! w cmd)
    (let* ((tp           (window-text-pipeline w))
           (instances    (build-instance-list w))
           (count        (text-pipeline-write-instances! tp instances)))
      (when (positive? count)
        (let* ((ext-w (window-extent-width w))
               (ext-h (window-extent-height w))
               (vp    (foreign-alloc/zero (ftype-sizeof <VkViewport>)))
               (sc    (foreign-alloc/zero (ftype-sizeof <VkRect2D>)))
               (push  (foreign-alloc/zero 32))    ; vec2 + vec2 + vec4
               (vbuf  (foreign-alloc/zero 8))
               (voff  (foreign-alloc/zero 8))
               (ds    (foreign-alloc/zero 8))
               (vp-ptr (make-ftype-pointer <VkViewport> vp))
               (sc-ptr (make-ftype-pointer <VkRect2D> sc)))
          (dynamic-wind
           void
           (lambda ()
             ;; Dynamic viewport + scissor for the swapchain extent.
             (ftype-set! <VkViewport> (x) vp-ptr 0.0)
             (ftype-set! <VkViewport> (y) vp-ptr 0.0)
             (ftype-set! <VkViewport> (width)  vp-ptr (exact->inexact ext-w))
             (ftype-set! <VkViewport> (height) vp-ptr (exact->inexact ext-h))
             (ftype-set! <VkViewport> (minDepth) vp-ptr 0.0)
             (ftype-set! <VkViewport> (maxDepth) vp-ptr 1.0)
             (ftype-set! <VkRect2D> (extent width)  sc-ptr ext-w)
             (ftype-set! <VkRect2D> (extent height) sc-ptr ext-h)
             ;; Push constants: vec2 viewport (offset 0), vec2 pad (8),
             ;; vec4 fg_color (offset 16).
             (foreign-set! 'float push 0  (exact->inexact ext-w))
             (foreign-set! 'float push 4  (exact->inexact ext-h))
             (foreign-set! 'float push 16 (window-fg-r w))
             (foreign-set! 'float push 20 (window-fg-g w))
             (foreign-set! 'float push 24 (window-fg-b w))
             (foreign-set! 'float push 28 (window-fg-a w))
             (foreign-set! 'unsigned-64 vbuf 0 (text-pipeline-instance-buffer tp))
             (foreign-set! 'unsigned-64 voff 0 0)
             (foreign-set! 'unsigned-64 ds 0 (text-pipeline-descriptor-set tp))
             (vkCmdSetViewport cmd 0 1 vp)
             (vkCmdSetScissor  cmd 0 1 sc)
             (vkCmdBindPipeline cmd VK_PIPELINE_BIND_POINT_GRAPHICS
                                (text-pipeline-pipeline tp))
             (vkCmdBindDescriptorSets cmd VK_PIPELINE_BIND_POINT_GRAPHICS
                                      (text-pipeline-pipeline-layout tp)
                                      0 1 ds 0 0)
             (vkCmdBindVertexBuffers cmd 0 1 vbuf voff)
             (vkCmdPushConstants cmd
                                 (text-pipeline-pipeline-layout tp)
                                 (bitwise-ior VK_SHADER_STAGE_VERTEX_BIT
                                              VK_SHADER_STAGE_FRAGMENT_BIT)
                                 0 32 push)
             (vkCmdDraw cmd 6 count 0 0))
           (lambda ()
             (foreign-free ds)
             (foreign-free voff)
             (foreign-free vbuf)
             (foreign-free push)
             (foreign-free sc)
             (foreign-free vp)))))))

  ;; ----------------------------------------------------------------
  ;; window-render-frame!
  ;; ----------------------------------------------------------------
  ;;
  ;; Allocates per-frame foreign scaffolding inside dynamic-wind so a
  ;; mid-frame raise (e.g. surface lost) doesn't leak. Vulkan call
  ;; overhead dominates this far above any malloc cost.

  (define (window-render-frame! w)
    (define device          (window-device w))
    (define queue           (window-queue w))
    (define swapchain       (window-swapchain w))
    (define cmd             (window-command-buffer w))
    (define framebuffers    (window-framebuffers w))
    (define render-pass     (window-render-pass w))
    (define ia-sem          (window-image-available-sem w))
    (define rf-sem          (window-render-finished-sem w))
    (define fence           (window-in-flight-fence w))
    (define ext-w           (window-extent-width w))
    (define ext-h           (window-extent-height w))

    (define fence-arr        (foreign-alloc/zero 8))
    (define image-index-out  (foreign-alloc/zero 4))
    (define begin-info       (foreign-alloc/zero
                              (ftype-sizeof <VkCommandBufferBeginInfo>)))
    (define rp-begin         (foreign-alloc/zero
                              (ftype-sizeof <VkRenderPassBeginInfo>)))
    (define clear-value      (foreign-alloc/zero
                              (ftype-sizeof <VkClearValue>)))
    (define wait-sem-arr     (foreign-alloc/zero 8))
    (define signal-sem-arr   (foreign-alloc/zero 8))
    (define stage-mask-arr   (foreign-alloc/zero 4))
    (define cmdbuf-arr       (foreign-alloc/zero 8))
    (define submit-info      (foreign-alloc/zero (ftype-sizeof <VkSubmitInfo>)))
    (define present-info     (foreign-alloc/zero (ftype-sizeof <VkPresentInfoKHR>)))
    (define swapchain-arr    (foreign-alloc/zero 8))

    (dynamic-wind
     void
     (lambda ()
       ;; 1. Wait + reset fence.
       (foreign-set! 'unsigned-64 fence-arr 0 fence)
       (vk-check 'vkWaitForFences
                 (vkWaitForFences device 1 fence-arr 1 UINT64_MAX))
       (vk-check 'vkResetFences
                 (vkResetFences device 1 fence-arr))
       ;; 2. Acquire next image.
       (vk-check 'vkAcquireNextImageKHR
                 (vkAcquireNextImageKHR device swapchain UINT64_MAX
                                        ia-sem 0 image-index-out))
       (let* ((image-index (foreign-ref 'unsigned-32 image-index-out 0))
              (framebuffer (list-ref framebuffers image-index)))
         ;; 3. Begin command buffer.
         (let ((bp (make-ftype-pointer <VkCommandBufferBeginInfo> begin-info)))
           (ftype-set! <VkCommandBufferBeginInfo> (sType) bp
                       VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO)
           (ftype-set! <VkCommandBufferBeginInfo> (flags) bp
                       VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT))
         (vk-check 'vkBeginCommandBuffer
                   (vkBeginCommandBuffer cmd begin-info))
         ;; 4. Begin render pass with the configured clear color. The
         ;; render pass takes care of UNDEFINED → COLOR_ATTACHMENT_OPTIMAL
         ;; → PRESENT_SRC_KHR transitions implicitly.
         (let ((cv (make-ftype-pointer <VkClearValue> clear-value))
               (rb (make-ftype-pointer <VkRenderPassBeginInfo> rp-begin)))
           (ftype-set! <VkClearValue> (color float32 0) cv
                       (exact->inexact (window-r w)))
           (ftype-set! <VkClearValue> (color float32 1) cv
                       (exact->inexact (window-g w)))
           (ftype-set! <VkClearValue> (color float32 2) cv
                       (exact->inexact (window-b w)))
           (ftype-set! <VkClearValue> (color float32 3) cv
                       (exact->inexact (window-a w)))
           (ftype-set! <VkRenderPassBeginInfo> (sType) rb
                       VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO)
           (ftype-set! <VkRenderPassBeginInfo> (renderPass) rb render-pass)
           (ftype-set! <VkRenderPassBeginInfo> (framebuffer) rb framebuffer)
           (ftype-set! <VkRenderPassBeginInfo> (renderArea offset x) rb 0)
           (ftype-set! <VkRenderPassBeginInfo> (renderArea offset y) rb 0)
           (ftype-set! <VkRenderPassBeginInfo> (renderArea extent width) rb ext-w)
           (ftype-set! <VkRenderPassBeginInfo> (renderArea extent height) rb ext-h)
           (ftype-set! <VkRenderPassBeginInfo> (clearValueCount) rb 1)
           (ftype-set! <VkRenderPassBeginInfo> (pClearValues) rb clear-value))
         (vkCmdBeginRenderPass cmd rp-begin VK_SUBPASS_CONTENTS_INLINE)
         (record-text-draws! w cmd)
         (vkCmdEndRenderPass cmd)
         (vk-check 'vkEndCommandBuffer
                   (vkEndCommandBuffer cmd))
         ;; 5. Submit, waiting on image-available at COLOR_ATTACHMENT_OUTPUT.
         (foreign-set! 'unsigned-64 wait-sem-arr   0 ia-sem)
         (foreign-set! 'unsigned-64 signal-sem-arr 0 rf-sem)
         (foreign-set! 'unsigned-32 stage-mask-arr 0
                       VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
         (foreign-set! 'uptr        cmdbuf-arr     0 cmd)
         (let ((sp (make-ftype-pointer <VkSubmitInfo> submit-info)))
           (ftype-set! <VkSubmitInfo> (sType) sp VK_STRUCTURE_TYPE_SUBMIT_INFO)
           (ftype-set! <VkSubmitInfo> (waitSemaphoreCount)   sp 1)
           (ftype-set! <VkSubmitInfo> (pWaitSemaphores)      sp wait-sem-arr)
           (ftype-set! <VkSubmitInfo> (pWaitDstStageMask)    sp stage-mask-arr)
           (ftype-set! <VkSubmitInfo> (commandBufferCount)   sp 1)
           (ftype-set! <VkSubmitInfo> (pCommandBuffers)      sp cmdbuf-arr)
           (ftype-set! <VkSubmitInfo> (signalSemaphoreCount) sp 1)
           (ftype-set! <VkSubmitInfo> (pSignalSemaphores)    sp signal-sem-arr))
         (vk-check 'vkQueueSubmit
                   (vkQueueSubmit queue 1 submit-info fence))
         ;; 6. Present.
         (foreign-set! 'unsigned-64 swapchain-arr 0 swapchain)
         (let ((pp (make-ftype-pointer <VkPresentInfoKHR> present-info)))
           (ftype-set! <VkPresentInfoKHR> (sType) pp
                       VK_STRUCTURE_TYPE_PRESENT_INFO_KHR)
           (ftype-set! <VkPresentInfoKHR> (waitSemaphoreCount) pp 1)
           (ftype-set! <VkPresentInfoKHR> (pWaitSemaphores) pp signal-sem-arr)
           (ftype-set! <VkPresentInfoKHR> (swapchainCount) pp 1)
           (ftype-set! <VkPresentInfoKHR> (pSwapchains) pp swapchain-arr)
           (ftype-set! <VkPresentInfoKHR> (pImageIndices) pp image-index-out))
         (let ((r (vkQueuePresentKHR queue present-info)))
           (unless (or (= r VK_SUCCESS) (= r VK_SUBOPTIMAL_KHR))
             (vk-check 'vkQueuePresentKHR r)))))
     (lambda ()
       (foreign-free swapchain-arr)
       (foreign-free present-info)
       (foreign-free submit-info)
       (foreign-free cmdbuf-arr)
       (foreign-free stage-mask-arr)
       (foreign-free signal-sem-arr)
       (foreign-free wait-sem-arr)
       (foreign-free clear-value)
       (foreign-free rp-begin)
       (foreign-free begin-info)
       (foreign-free image-index-out)
       (foreign-free fence-arr))))

  ;; ----------------------------------------------------------------
  ;; window-run!
  ;; ----------------------------------------------------------------
  ;;
  ;; Tight loop. SIGINT is already trapped by call-with-seat (which
  ;; calls seat-release then exit), and (exit 0) unwinds the
  ;; dynamic-wind in call-with-window so window-close runs.

  (define (window-run! w)
    (let loop ()
      (when (window-released? w)
        (error 'window-run! "window has been released"))
      (let ((fd (window-kbd-fd w)))
        (when (>= fd 0)
          (pump-keyboard-events!
           fd
           (lambda (code value) (handle-key-event! w code value)))))
      (window-render-frame! w)
      (loop)))

  ;; ----------------------------------------------------------------
  ;; window-close
  ;; ----------------------------------------------------------------

  (define (silent thunk)
    (guard (e (#t (void))) (thunk)))

  (define (window-close w)
    (unless (window-released? w)
      (window-released?-set! w #t)
      ;; Close the keyboard fd before tearing down GPU state — this
      ;; doesn't block on Vulkan, just releases the input file.
      (let ((fd (window-kbd-fd w)))
        (when (>= fd 0)
          (silent (lambda () (close-keyboard fd)))
          (window-kbd-fd-set! w -1)))
      ;; Ignore individual destroy failures so we always reach
      ;; the foreign-free pass.
      (silent (lambda () (vkDeviceWaitIdle (window-device w))))
      ;; Tear down the text pipeline first — its objects sit on top of
      ;; the render pass / device that we're about to destroy.
      (silent (lambda () (destroy-text-pipeline! (window-device w)
                                                 (window-text-pipeline w))))
      (silent (lambda () (vkDestroyFence (window-device w)
                                         (window-in-flight-fence w) 0)))
      (silent (lambda () (vkDestroySemaphore (window-device w)
                                             (window-render-finished-sem w) 0)))
      (silent (lambda () (vkDestroySemaphore (window-device w)
                                             (window-image-available-sem w) 0)))
      ;; Command buffers are freed automatically by the pool destroy.
      (silent (lambda () (vkDestroyCommandPool (window-device w)
                                               (window-command-pool w) 0)))
      ;; Framebuffers must outlive only the render pass; views must
      ;; outlive only the framebuffers; render pass must outlive the
      ;; pipeline (none yet) and the framebuffers.
      (for-each
       (lambda (fb)
         (silent (lambda () (vkDestroyFramebuffer (window-device w) fb 0))))
       (window-framebuffers w))
      (for-each
       (lambda (v)
         (silent (lambda () (vkDestroyImageView (window-device w) v 0))))
       (window-image-views w))
      (silent (lambda () (vkDestroyRenderPass (window-device w)
                                              (window-render-pass w) 0)))
      (silent (lambda () (vkDestroySwapchainKHR (window-device w)
                                                (window-swapchain w) 0)))
      (silent (lambda () (vkDestroyDevice (window-device w) 0)))
      (silent (lambda () (vkDestroySurfaceKHR (window-instance w)
                                              (window-surface w) 0)))
      (for-each
       (lambda (p) (silent (lambda () (foreign-free p))))
       (window-scratch w))))

  ;; ----------------------------------------------------------------
  ;; call-with-window
  ;; ----------------------------------------------------------------

  (define (call-with-window instance proc)
    (let ((w (window-open instance)))
      (dynamic-wind
       void
       (lambda () (proc w))
       (lambda () (window-close w))))))
