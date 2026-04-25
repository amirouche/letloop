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
   window?
   window-released?
   window-extent-width
   window-extent-height)
  (import
   (chezscheme)
   (letloop desktop vulkan)
   (letloop desktop vulkan low))

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
     images                ; list of u64 VkImage
     command-pool command-buffer
     image-available-sem render-finished-sem in-flight-fence
     ;; pre-allocated scratch foreign buffers, freed in window-close
     scratch               ; list of foreign-alloc'd addresses
     (mutable r) (mutable g) (mutable b) (mutable a)))

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
                         VK_IMAGE_USAGE_TRANSFER_DST_BIT)
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
             (begin (track! (lambda () (vkDestroyFence device in-flight-fence 0))) #f)))
       ;; All built — clear rollback so window-close is the sole owner.
       (set! rollback '())
       (make-window
        #f
        instance pd qfi
        device queue
        surface swapchain
        fmt-format extent-w extent-h
        images
        command-pool command-buffer
        image-available-sem render-finished-sem in-flight-fence
        scratch
        1.0 0.0 1.0 1.0))))

  ;; ----------------------------------------------------------------
  ;; window-clear-color!
  ;; ----------------------------------------------------------------

  (define (window-clear-color! w r g b a)
    (window-r-set! w (exact->inexact r))
    (window-g-set! w (exact->inexact g))
    (window-b-set! w (exact->inexact b))
    (window-a-set! w (exact->inexact a)))

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
    (define images          (window-images w))
    (define ia-sem          (window-image-available-sem w))
    (define rf-sem          (window-render-finished-sem w))
    (define fence           (window-in-flight-fence w))

    (define fence-arr        (foreign-alloc/zero 8))
    (define image-index-out  (foreign-alloc/zero 4))
    (define begin-info       (foreign-alloc/zero
                              (ftype-sizeof <VkCommandBufferBeginInfo>)))
    (define barrier1         (foreign-alloc/zero
                              (ftype-sizeof <VkImageMemoryBarrier>)))
    (define barrier2         (foreign-alloc/zero
                              (ftype-sizeof <VkImageMemoryBarrier>)))
    (define clear-color      (foreign-alloc/zero
                              (ftype-sizeof <VkClearColorValue>)))
    (define range            (foreign-alloc/zero
                              (ftype-sizeof <VkImageSubresourceRange>)))
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
              (image       (list-ref images image-index)))
         ;; 3. Reset + record command buffer.
         (let ((bp (make-ftype-pointer <VkCommandBufferBeginInfo> begin-info)))
           (ftype-set! <VkCommandBufferBeginInfo> (sType) bp
                       VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO)
           (ftype-set! <VkCommandBufferBeginInfo> (flags) bp
                       VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT))
         (vk-check 'vkBeginCommandBuffer
                   (vkBeginCommandBuffer cmd begin-info))
         ;; UNDEFINED → TRANSFER_DST_OPTIMAL
         (let ((bp (make-ftype-pointer <VkImageMemoryBarrier> barrier1)))
           (ftype-set! <VkImageMemoryBarrier> (sType) bp
                       VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER)
           (ftype-set! <VkImageMemoryBarrier> (srcAccessMask) bp 0)
           (ftype-set! <VkImageMemoryBarrier> (dstAccessMask) bp
                       VK_ACCESS_TRANSFER_WRITE_BIT)
           (ftype-set! <VkImageMemoryBarrier> (oldLayout) bp
                       VK_IMAGE_LAYOUT_UNDEFINED)
           (ftype-set! <VkImageMemoryBarrier> (newLayout) bp
                       VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
           (ftype-set! <VkImageMemoryBarrier> (srcQueueFamilyIndex) bp
                       VK_QUEUE_FAMILY_IGNORED)
           (ftype-set! <VkImageMemoryBarrier> (dstQueueFamilyIndex) bp
                       VK_QUEUE_FAMILY_IGNORED)
           (ftype-set! <VkImageMemoryBarrier> (image) bp image)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange aspectMask) bp
                       VK_IMAGE_ASPECT_COLOR_BIT)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange baseMipLevel) bp 0)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange levelCount) bp 1)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange baseArrayLayer) bp 0)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange layerCount) bp 1))
         (vkCmdPipelineBarrier cmd
                               VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT
                               VK_PIPELINE_STAGE_TRANSFER_BIT
                               0
                               0 0
                               0 0
                               1 barrier1)
         ;; clear color
         (let ((cp (make-ftype-pointer <VkClearColorValue> clear-color))
               (rp (make-ftype-pointer <VkImageSubresourceRange> range)))
           (ftype-set! <VkClearColorValue> (float32 0) cp
                       (exact->inexact (window-r w)))
           (ftype-set! <VkClearColorValue> (float32 1) cp
                       (exact->inexact (window-g w)))
           (ftype-set! <VkClearColorValue> (float32 2) cp
                       (exact->inexact (window-b w)))
           (ftype-set! <VkClearColorValue> (float32 3) cp
                       (exact->inexact (window-a w)))
           (ftype-set! <VkImageSubresourceRange> (aspectMask) rp
                       VK_IMAGE_ASPECT_COLOR_BIT)
           (ftype-set! <VkImageSubresourceRange> (baseMipLevel) rp 0)
           (ftype-set! <VkImageSubresourceRange> (levelCount) rp 1)
           (ftype-set! <VkImageSubresourceRange> (baseArrayLayer) rp 0)
           (ftype-set! <VkImageSubresourceRange> (layerCount) rp 1))
         (vkCmdClearColorImage cmd image
                               VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
                               clear-color
                               1 range)
         ;; TRANSFER_DST_OPTIMAL → PRESENT_SRC_KHR
         (let ((bp (make-ftype-pointer <VkImageMemoryBarrier> barrier2)))
           (ftype-set! <VkImageMemoryBarrier> (sType) bp
                       VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER)
           (ftype-set! <VkImageMemoryBarrier> (srcAccessMask) bp
                       VK_ACCESS_TRANSFER_WRITE_BIT)
           (ftype-set! <VkImageMemoryBarrier> (dstAccessMask) bp
                       VK_ACCESS_MEMORY_READ_BIT)
           (ftype-set! <VkImageMemoryBarrier> (oldLayout) bp
                       VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
           (ftype-set! <VkImageMemoryBarrier> (newLayout) bp
                       VK_IMAGE_LAYOUT_PRESENT_SRC_KHR)
           (ftype-set! <VkImageMemoryBarrier> (srcQueueFamilyIndex) bp
                       VK_QUEUE_FAMILY_IGNORED)
           (ftype-set! <VkImageMemoryBarrier> (dstQueueFamilyIndex) bp
                       VK_QUEUE_FAMILY_IGNORED)
           (ftype-set! <VkImageMemoryBarrier> (image) bp image)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange aspectMask) bp
                       VK_IMAGE_ASPECT_COLOR_BIT)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange baseMipLevel) bp 0)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange levelCount) bp 1)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange baseArrayLayer) bp 0)
           (ftype-set! <VkImageMemoryBarrier> (subresourceRange layerCount) bp 1))
         (vkCmdPipelineBarrier cmd
                               VK_PIPELINE_STAGE_TRANSFER_BIT
                               VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT
                               0
                               0 0
                               0 0
                               1 barrier2)
         (vk-check 'vkEndCommandBuffer
                   (vkEndCommandBuffer cmd))
         ;; 4. Submit.
         (foreign-set! 'unsigned-64 wait-sem-arr   0 ia-sem)
         (foreign-set! 'unsigned-64 signal-sem-arr 0 rf-sem)
         (foreign-set! 'unsigned-32 stage-mask-arr 0 VK_PIPELINE_STAGE_TRANSFER_BIT)
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
         ;; 5. Present.
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
           ;; SUBOPTIMAL is acceptable; OUT_OF_DATE means the surface
           ;; needs a new swapchain. We don't recreate yet — re-raise.
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
       (foreign-free range)
       (foreign-free clear-color)
       (foreign-free barrier2)
       (foreign-free barrier1)
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
      ;; Ignore individual destroy failures so we always reach
      ;; the foreign-free pass.
      (silent (lambda () (vkDeviceWaitIdle (window-device w))))
      (silent (lambda () (vkDestroyFence (window-device w)
                                         (window-in-flight-fence w) 0)))
      (silent (lambda () (vkDestroySemaphore (window-device w)
                                             (window-render-finished-sem w) 0)))
      (silent (lambda () (vkDestroySemaphore (window-device w)
                                             (window-image-available-sem w) 0)))
      ;; Command buffers are freed automatically by the pool destroy.
      (silent (lambda () (vkDestroyCommandPool (window-device w)
                                               (window-command-pool w) 0)))
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
