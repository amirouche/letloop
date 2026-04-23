#!chezscheme
;; Vulkan 1.0 FFI bindings — just enough surface area to drive a
;; VK_KHR_display swapchain and clear a color. Extended as later milestones
;; (glyph rendering, vertex buffers, descriptor sets) demand it.
;;
;; Conventions
;; -----------
;;   - Struct types are ftype definitions named <VkFoo>; sizes via
;;     (ftype-sizeof <VkFoo>), field access via ftype-set!/ftype-ref.
;;   - Opaque dispatchable handles (VkInstance, VkDevice, VkQueue,
;;     VkCommandBuffer, VkPhysicalDevice) are pointer-sized on Linux, so
;;     we carry them as uptr.
;;   - Non-dispatchable handles (VkSurfaceKHR, VkSwapchainKHR, VkImage,
;;     VkDisplayKHR, VkDisplayModeKHR, VkSemaphore, VkFence) are
;;     uint64_t by spec on every platform; carry them as unsigned-64.
;;   - vk* procedures return the raw VkResult integer; 0 = VK_SUCCESS.
;;     Higher-level wrappers in (letloop desktop vulkan) turn non-zero
;;     into exceptions.
(library (letloop desktop vulkan low)
  (export
   ;; shared object
   libvulkan

   ;; result codes
   VK_SUCCESS
   VK_NOT_READY
   VK_TIMEOUT
   VK_EVENT_SET
   VK_EVENT_RESET
   VK_INCOMPLETE
   VK_SUBOPTIMAL_KHR
   VK_ERROR_OUT_OF_DATE_KHR
   vk-result-name

   ;; structure types
   VK_STRUCTURE_TYPE_APPLICATION_INFO
   VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
   VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
   VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
   VK_STRUCTURE_TYPE_SUBMIT_INFO
   VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
   VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
   VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
   VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
   VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
   VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
   VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
   VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
   VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR

   ;; format / image layout / usage / sharing
   VK_FORMAT_UNDEFINED
   VK_FORMAT_B8G8R8A8_UNORM
   VK_FORMAT_B8G8R8A8_SRGB
   VK_FORMAT_R8G8B8A8_UNORM

   VK_IMAGE_LAYOUT_UNDEFINED
   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
   VK_IMAGE_LAYOUT_PRESENT_SRC_KHR

   VK_IMAGE_USAGE_TRANSFER_DST_BIT
   VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT

   VK_IMAGE_ASPECT_COLOR_BIT

   VK_SHARING_MODE_EXCLUSIVE

   ;; access / pipeline stages
   VK_ACCESS_MEMORY_READ_BIT
   VK_ACCESS_TRANSFER_WRITE_BIT

   VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT
   VK_PIPELINE_STAGE_TRANSFER_BIT
   VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT

   VK_QUEUE_FAMILY_IGNORED

   ;; queue flags, present modes, composite alpha, transform
   VK_QUEUE_GRAPHICS_BIT
   VK_PRESENT_MODE_FIFO_KHR
   VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
   VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR
   VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
   VK_DISPLAY_PLANE_ALPHA_OPAQUE_BIT_KHR

   ;; command buffer
   VK_COMMAND_BUFFER_LEVEL_PRIMARY
   VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
   VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
   VK_FENCE_CREATE_SIGNALED_BIT

   ;; extension name strings
   VK_KHR_SURFACE_EXTENSION_NAME
   VK_KHR_DISPLAY_EXTENSION_NAME
   VK_KHR_SWAPCHAIN_EXTENSION_NAME

   ;; ftypes — small
   <VkExtent2D>
   <VkExtent3D>
   <VkOffset3D>
   <VkImageSubresourceRange>
   <VkSurfaceFormatKHR>
   <VkDisplayModeParametersKHR>
   <VkDisplayModePropertiesKHR>
   <VkDisplayPropertiesKHR>
   <VkDisplayPlanePropertiesKHR>
   <VkQueueFamilyProperties>
   <VkSurfaceCapabilitiesKHR>
   <VkClearColorValue>

   ;; ftypes — create-info / submit / barrier
   <VkApplicationInfo>
   <VkInstanceCreateInfo>
   <VkDeviceQueueCreateInfo>
   <VkDeviceCreateInfo>
   <VkDisplaySurfaceCreateInfoKHR>
   <VkSwapchainCreateInfoKHR>
   <VkSemaphoreCreateInfo>
   <VkFenceCreateInfo>
   <VkCommandPoolCreateInfo>
   <VkCommandBufferAllocateInfo>
   <VkCommandBufferBeginInfo>
   <VkSubmitInfo>
   <VkPresentInfoKHR>
   <VkImageMemoryBarrier>
   <VkPhysicalDeviceProperties>

   ;; vk procedures — instance / device lifecycle
   vkCreateInstance
   vkDestroyInstance
   vkEnumeratePhysicalDevices
   vkGetPhysicalDeviceProperties
   vkGetPhysicalDeviceQueueFamilyProperties
   vkCreateDevice
   vkDestroyDevice
   vkDeviceWaitIdle
   vkGetDeviceQueue

   ;; display
   vkGetPhysicalDeviceDisplayPropertiesKHR
   vkGetDisplayModePropertiesKHR
   vkGetPhysicalDeviceDisplayPlanePropertiesKHR
   vkCreateDisplayPlaneSurfaceKHR
   vkDestroySurfaceKHR

   ;; surface / swapchain
   vkGetPhysicalDeviceSurfaceCapabilitiesKHR
   vkGetPhysicalDeviceSurfaceFormatsKHR
   vkCreateSwapchainKHR
   vkDestroySwapchainKHR
   vkGetSwapchainImagesKHR
   vkAcquireNextImageKHR
   vkQueuePresentKHR

   ;; sync
   vkCreateSemaphore
   vkDestroySemaphore
   vkCreateFence
   vkDestroyFence
   vkWaitForFences
   vkResetFences

   ;; commands
   vkCreateCommandPool
   vkDestroyCommandPool
   vkAllocateCommandBuffers
   vkFreeCommandBuffers
   vkBeginCommandBuffer
   vkEndCommandBuffer
   vkCmdPipelineBarrier
   vkCmdClearColorImage
   vkQueueSubmit)
  (import (chezscheme))

  (define libvulkan (load-shared-object "libvulkan.so.1"))

  ;; ----------------------------------------------------------------
  ;; VkResult
  ;; ----------------------------------------------------------------
  (define VK_SUCCESS                   0)
  (define VK_NOT_READY                 1)
  (define VK_TIMEOUT                   2)
  (define VK_EVENT_SET                 3)
  (define VK_EVENT_RESET               4)
  (define VK_INCOMPLETE                5)
  (define VK_SUBOPTIMAL_KHR            1000001003)
  (define VK_ERROR_OUT_OF_DATE_KHR    -1000001004)

  (define (vk-result-name r)
    (cond ((= r VK_SUCCESS)               "VK_SUCCESS")
          ((= r VK_NOT_READY)             "VK_NOT_READY")
          ((= r VK_TIMEOUT)               "VK_TIMEOUT")
          ((= r VK_EVENT_SET)             "VK_EVENT_SET")
          ((= r VK_EVENT_RESET)           "VK_EVENT_RESET")
          ((= r VK_INCOMPLETE)            "VK_INCOMPLETE")
          ((= r VK_SUBOPTIMAL_KHR)        "VK_SUBOPTIMAL_KHR")
          ((= r VK_ERROR_OUT_OF_DATE_KHR) "VK_ERROR_OUT_OF_DATE_KHR")
          ((= r -1) "VK_ERROR_OUT_OF_HOST_MEMORY")
          ((= r -2) "VK_ERROR_OUT_OF_DEVICE_MEMORY")
          ((= r -3) "VK_ERROR_INITIALIZATION_FAILED")
          ((= r -4) "VK_ERROR_DEVICE_LOST")
          ((= r -5) "VK_ERROR_MEMORY_MAP_FAILED")
          ((= r -6) "VK_ERROR_LAYER_NOT_PRESENT")
          ((= r -7) "VK_ERROR_EXTENSION_NOT_PRESENT")
          ((= r -8) "VK_ERROR_FEATURE_NOT_PRESENT")
          ((= r -9) "VK_ERROR_INCOMPATIBLE_DRIVER")
          (else (format #f "VkResult(~a)" r))))

  ;; ----------------------------------------------------------------
  ;; VkStructureType
  ;; ----------------------------------------------------------------
  (define VK_STRUCTURE_TYPE_APPLICATION_INFO                0)
  (define VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO            1)
  (define VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO        2)
  (define VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO              3)
  (define VK_STRUCTURE_TYPE_SUBMIT_INFO                     4)
  (define VK_STRUCTURE_TYPE_FENCE_CREATE_INFO               8)
  (define VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO           9)
  (define VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER           45)
  (define VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO       39)
  (define VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO   40)
  (define VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO      42)
  (define VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR       1000001000)
  (define VK_STRUCTURE_TYPE_PRESENT_INFO_KHR                1000001001)
  (define VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR 1000002000)

  ;; ----------------------------------------------------------------
  ;; Enums / flags
  ;; ----------------------------------------------------------------
  (define VK_FORMAT_UNDEFINED     0)
  (define VK_FORMAT_B8G8R8A8_UNORM  44)
  (define VK_FORMAT_B8G8R8A8_SRGB   50)
  (define VK_FORMAT_R8G8B8A8_UNORM  37)

  (define VK_IMAGE_LAYOUT_UNDEFINED              0)
  (define VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL   7)
  (define VK_IMAGE_LAYOUT_PRESENT_SRC_KHR        1000001002)

  (define VK_IMAGE_USAGE_TRANSFER_DST_BIT       #x02)
  (define VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT   #x10)

  (define VK_IMAGE_ASPECT_COLOR_BIT             #x01)

  (define VK_SHARING_MODE_EXCLUSIVE              0)

  (define VK_ACCESS_MEMORY_READ_BIT             #x00008000)
  (define VK_ACCESS_TRANSFER_WRITE_BIT          #x00001000)

  (define VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT     #x00000001)
  (define VK_PIPELINE_STAGE_TRANSFER_BIT        #x00001000)
  (define VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT  #x00002000)

  (define VK_QUEUE_FAMILY_IGNORED               #xFFFFFFFF)

  (define VK_QUEUE_GRAPHICS_BIT                 #x01)

  (define VK_PRESENT_MODE_FIFO_KHR               2)
  (define VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR     #x01)
  (define VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR #x01)
  (define VK_COLOR_SPACE_SRGB_NONLINEAR_KHR      0)
  (define VK_DISPLAY_PLANE_ALPHA_OPAQUE_BIT_KHR #x01)

  (define VK_COMMAND_BUFFER_LEVEL_PRIMARY                 0)
  (define VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT    #x01)
  (define VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT #x02)
  (define VK_FENCE_CREATE_SIGNALED_BIT                   #x01)

  ;; ----------------------------------------------------------------
  ;; Extension name strings (Vulkan headers use them as #define literals).
  ;; ----------------------------------------------------------------
  (define VK_KHR_SURFACE_EXTENSION_NAME   "VK_KHR_surface")
  (define VK_KHR_DISPLAY_EXTENSION_NAME   "VK_KHR_display")
  (define VK_KHR_SWAPCHAIN_EXTENSION_NAME "VK_KHR_swapchain")

  ;; ----------------------------------------------------------------
  ;; Small ftypes
  ;; ----------------------------------------------------------------

  (define-ftype <VkExtent2D>
    (struct
     (width  unsigned-32)
     (height unsigned-32)))

  (define-ftype <VkExtent3D>
    (struct
     (width  unsigned-32)
     (height unsigned-32)
     (depth  unsigned-32)))

  (define-ftype <VkOffset3D>
    (struct
     (x integer-32)
     (y integer-32)
     (z integer-32)))

  (define-ftype <VkImageSubresourceRange>
    (struct
     (aspectMask     unsigned-32)
     (baseMipLevel   unsigned-32)
     (levelCount     unsigned-32)
     (baseArrayLayer unsigned-32)
     (layerCount     unsigned-32)))

  (define-ftype <VkSurfaceFormatKHR>
    (struct
     (format     unsigned-32)
     (colorSpace unsigned-32)))

  (define-ftype <VkDisplayModeParametersKHR>
    (struct
     (visibleRegion (struct (width unsigned-32) (height unsigned-32)))
     (refreshRate   unsigned-32)))

  (define-ftype <VkDisplayModePropertiesKHR>
    (struct
     (displayMode unsigned-64)
     (parameters  (struct
                   (visibleRegion (struct (width unsigned-32) (height unsigned-32)))
                   (refreshRate   unsigned-32)))))

  (define-ftype <VkDisplayPropertiesKHR>
    (struct
     (display                   unsigned-64)
     (displayName               uptr)
     (physicalDimensions        (struct (width unsigned-32) (height unsigned-32)))
     (physicalResolution        (struct (width unsigned-32) (height unsigned-32)))
     (supportedTransforms       unsigned-32)
     (planeReorderPossible      unsigned-32)
     (persistentContent         unsigned-32)))

  (define-ftype <VkDisplayPlanePropertiesKHR>
    (struct
     (currentDisplay    unsigned-64)
     (currentStackIndex unsigned-32)))

  (define-ftype <VkQueueFamilyProperties>
    (struct
     (queueFlags                  unsigned-32)
     (queueCount                  unsigned-32)
     (timestampValidBits          unsigned-32)
     (minImageTransferGranularity (struct
                                   (width  unsigned-32)
                                   (height unsigned-32)
                                   (depth  unsigned-32)))))

  (define-ftype <VkSurfaceCapabilitiesKHR>
    (struct
     (minImageCount           unsigned-32)
     (maxImageCount           unsigned-32)
     (currentExtent           (struct (width unsigned-32) (height unsigned-32)))
     (minImageExtent          (struct (width unsigned-32) (height unsigned-32)))
     (maxImageExtent          (struct (width unsigned-32) (height unsigned-32)))
     (maxImageArrayLayers     unsigned-32)
     (supportedTransforms     unsigned-32)
     (currentTransform        unsigned-32)
     (supportedCompositeAlpha unsigned-32)
     (supportedUsageFlags     unsigned-32)))

  (define-ftype <VkClearColorValue>
    ;; Union of float[4] / int32[4] / uint32[4]; all same size. We only ever
    ;; write float values, so declare as float[4].
    (struct
     (float32 (array 4 float))))

  ;; VkPhysicalDeviceProperties — sizeof 824 on x86_64 (verified via
  ;; sizeof against libvulkan-dev 1.3.275). We only read the first 276
  ;; bytes (through pipelineCacheUUID); the rest is an opaque tail that
  ;; includes 4 bytes of compiler-inserted alignment padding before
  ;; VkPhysicalDeviceLimits. Treating the tail as a single byte array
  ;; makes the struct size match C without hand-aligning limits.
  (define-ftype <VkPhysicalDeviceProperties>
    (struct
     (apiVersion        unsigned-32)          ; 0
     (driverVersion     unsigned-32)          ; 4
     (vendorID          unsigned-32)          ; 8
     (deviceID          unsigned-32)          ; 12
     (deviceType        unsigned-32)          ; 16
     (deviceName        (array 256 unsigned-8))  ; 20..275
     (pipelineCacheUUID (array 16 unsigned-8))   ; 276..291
     (rest              (array 532 unsigned-8)))) ; 292..823 → size 824

  ;; ----------------------------------------------------------------
  ;; CreateInfo structs
  ;; ----------------------------------------------------------------

  (define-ftype <VkApplicationInfo>
    (struct
     (sType              unsigned-32)
     (pNext              uptr)
     (pApplicationName   uptr)
     (applicationVersion unsigned-32)
     (pEngineName        uptr)
     (engineVersion      unsigned-32)
     (apiVersion         unsigned-32)))

  (define-ftype <VkInstanceCreateInfo>
    (struct
     (sType                    unsigned-32)
     (pNext                    uptr)
     (flags                    unsigned-32)
     (pApplicationInfo         uptr)
     (enabledLayerCount        unsigned-32)
     (ppEnabledLayerNames      uptr)
     (enabledExtensionCount    unsigned-32)
     (ppEnabledExtensionNames  uptr)))

  (define-ftype <VkDeviceQueueCreateInfo>
    (struct
     (sType             unsigned-32)
     (pNext             uptr)
     (flags             unsigned-32)
     (queueFamilyIndex  unsigned-32)
     (queueCount        unsigned-32)
     (pQueuePriorities  uptr)))

  (define-ftype <VkDeviceCreateInfo>
    (struct
     (sType                    unsigned-32)
     (pNext                    uptr)
     (flags                    unsigned-32)
     (queueCreateInfoCount     unsigned-32)
     (pQueueCreateInfos        uptr)
     (enabledLayerCount        unsigned-32)
     (ppEnabledLayerNames      uptr)
     (enabledExtensionCount    unsigned-32)
     (ppEnabledExtensionNames  uptr)
     (pEnabledFeatures         uptr)))

  (define-ftype <VkDisplaySurfaceCreateInfoKHR>
    (struct
     (sType             unsigned-32)
     (pNext             uptr)
     (flags             unsigned-32)
     (displayMode       unsigned-64)
     (planeIndex        unsigned-32)
     (planeStackIndex   unsigned-32)
     (transform         unsigned-32)
     (globalAlpha       float)
     (alphaMode         unsigned-32)
     (imageExtent       (struct (width unsigned-32) (height unsigned-32)))))

  (define-ftype <VkSwapchainCreateInfoKHR>
    (struct
     (sType                  unsigned-32)
     (pNext                  uptr)
     (flags                  unsigned-32)
     (surface                unsigned-64)
     (minImageCount          unsigned-32)
     (imageFormat            unsigned-32)
     (imageColorSpace        unsigned-32)
     (imageExtent            (struct (width unsigned-32) (height unsigned-32)))
     (imageArrayLayers       unsigned-32)
     (imageUsage             unsigned-32)
     (imageSharingMode       unsigned-32)
     (queueFamilyIndexCount  unsigned-32)
     (pQueueFamilyIndices    uptr)
     (preTransform           unsigned-32)
     (compositeAlpha         unsigned-32)
     (presentMode            unsigned-32)
     (clipped                unsigned-32)
     (oldSwapchain           unsigned-64)))

  (define-ftype <VkSemaphoreCreateInfo>
    (struct
     (sType unsigned-32)
     (pNext uptr)
     (flags unsigned-32)))

  (define-ftype <VkFenceCreateInfo>
    (struct
     (sType unsigned-32)
     (pNext uptr)
     (flags unsigned-32)))

  (define-ftype <VkCommandPoolCreateInfo>
    (struct
     (sType            unsigned-32)
     (pNext            uptr)
     (flags            unsigned-32)
     (queueFamilyIndex unsigned-32)))

  (define-ftype <VkCommandBufferAllocateInfo>
    (struct
     (sType               unsigned-32)
     (pNext               uptr)
     (commandPool         unsigned-64)
     (level               unsigned-32)
     (commandBufferCount  unsigned-32)))

  (define-ftype <VkCommandBufferBeginInfo>
    (struct
     (sType            unsigned-32)
     (pNext            uptr)
     (flags            unsigned-32)
     (pInheritanceInfo uptr)))

  (define-ftype <VkSubmitInfo>
    (struct
     (sType                  unsigned-32)
     (pNext                  uptr)
     (waitSemaphoreCount     unsigned-32)
     (pWaitSemaphores        uptr)
     (pWaitDstStageMask      uptr)
     (commandBufferCount     unsigned-32)
     (pCommandBuffers        uptr)
     (signalSemaphoreCount   unsigned-32)
     (pSignalSemaphores      uptr)))

  (define-ftype <VkPresentInfoKHR>
    (struct
     (sType              unsigned-32)
     (pNext              uptr)
     (waitSemaphoreCount unsigned-32)
     (pWaitSemaphores    uptr)
     (swapchainCount     unsigned-32)
     (pSwapchains        uptr)
     (pImageIndices      uptr)
     (pResults           uptr)))

  (define-ftype <VkImageMemoryBarrier>
    (struct
     (sType               unsigned-32)
     (pNext               uptr)
     (srcAccessMask       unsigned-32)
     (dstAccessMask       unsigned-32)
     (oldLayout           unsigned-32)
     (newLayout           unsigned-32)
     (srcQueueFamilyIndex unsigned-32)
     (dstQueueFamilyIndex unsigned-32)
     (image               unsigned-64)
     (subresourceRange    (struct
                           (aspectMask     unsigned-32)
                           (baseMipLevel   unsigned-32)
                           (levelCount     unsigned-32)
                           (baseArrayLayer unsigned-32)
                           (layerCount     unsigned-32)))))

  ;; ----------------------------------------------------------------
  ;; Function bindings
  ;; ----------------------------------------------------------------
  ;;
  ;; Every Vulkan handle type larger than void* (i.e., non-dispatchable
  ;; VkDisplayKHR etc.) is uint64_t. Dispatchable handles (VkInstance,
  ;; VkDevice, VkPhysicalDevice, VkQueue, VkCommandBuffer) are pointers,
  ;; carried as uptr.

  (define vkCreateInstance
    (foreign-procedure "vkCreateInstance" (uptr uptr uptr) int))
  (define vkDestroyInstance
    (foreign-procedure "vkDestroyInstance" (uptr uptr) void))
  (define vkEnumeratePhysicalDevices
    (foreign-procedure "vkEnumeratePhysicalDevices" (uptr uptr uptr) int))
  (define vkGetPhysicalDeviceProperties
    (foreign-procedure "vkGetPhysicalDeviceProperties" (uptr uptr) void))
  (define vkGetPhysicalDeviceQueueFamilyProperties
    (foreign-procedure "vkGetPhysicalDeviceQueueFamilyProperties"
                       (uptr uptr uptr) void))

  (define vkCreateDevice
    (foreign-procedure "vkCreateDevice" (uptr uptr uptr uptr) int))
  (define vkDestroyDevice
    (foreign-procedure "vkDestroyDevice" (uptr uptr) void))
  (define vkDeviceWaitIdle
    (foreign-procedure "vkDeviceWaitIdle" (uptr) int))
  (define vkGetDeviceQueue
    (foreign-procedure "vkGetDeviceQueue" (uptr unsigned-32 unsigned-32 uptr) void))

  (define vkGetPhysicalDeviceDisplayPropertiesKHR
    (foreign-procedure "vkGetPhysicalDeviceDisplayPropertiesKHR"
                       (uptr uptr uptr) int))
  (define vkGetDisplayModePropertiesKHR
    (foreign-procedure "vkGetDisplayModePropertiesKHR"
                       (uptr unsigned-64 uptr uptr) int))
  (define vkGetPhysicalDeviceDisplayPlanePropertiesKHR
    (foreign-procedure "vkGetPhysicalDeviceDisplayPlanePropertiesKHR"
                       (uptr uptr uptr) int))
  (define vkCreateDisplayPlaneSurfaceKHR
    (foreign-procedure "vkCreateDisplayPlaneSurfaceKHR"
                       (uptr uptr uptr uptr) int))
  (define vkDestroySurfaceKHR
    (foreign-procedure "vkDestroySurfaceKHR" (uptr unsigned-64 uptr) void))

  (define vkGetPhysicalDeviceSurfaceCapabilitiesKHR
    (foreign-procedure "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"
                       (uptr unsigned-64 uptr) int))
  (define vkGetPhysicalDeviceSurfaceFormatsKHR
    (foreign-procedure "vkGetPhysicalDeviceSurfaceFormatsKHR"
                       (uptr unsigned-64 uptr uptr) int))
  (define vkCreateSwapchainKHR
    (foreign-procedure "vkCreateSwapchainKHR" (uptr uptr uptr uptr) int))
  (define vkDestroySwapchainKHR
    (foreign-procedure "vkDestroySwapchainKHR"
                       (uptr unsigned-64 uptr) void))
  (define vkGetSwapchainImagesKHR
    (foreign-procedure "vkGetSwapchainImagesKHR"
                       (uptr unsigned-64 uptr uptr) int))
  (define vkAcquireNextImageKHR
    (foreign-procedure "vkAcquireNextImageKHR"
                       (uptr unsigned-64 unsigned-64 unsigned-64 unsigned-64 uptr) int))
  (define vkQueuePresentKHR
    (foreign-procedure "vkQueuePresentKHR" (uptr uptr) int))

  (define vkCreateSemaphore
    (foreign-procedure "vkCreateSemaphore" (uptr uptr uptr uptr) int))
  (define vkDestroySemaphore
    (foreign-procedure "vkDestroySemaphore"
                       (uptr unsigned-64 uptr) void))
  (define vkCreateFence
    (foreign-procedure "vkCreateFence" (uptr uptr uptr uptr) int))
  (define vkDestroyFence
    (foreign-procedure "vkDestroyFence"
                       (uptr unsigned-64 uptr) void))
  (define vkWaitForFences
    (foreign-procedure "vkWaitForFences"
                       (uptr unsigned-32 uptr unsigned-32 unsigned-64) int))
  (define vkResetFences
    (foreign-procedure "vkResetFences" (uptr unsigned-32 uptr) int))

  (define vkCreateCommandPool
    (foreign-procedure "vkCreateCommandPool" (uptr uptr uptr uptr) int))
  (define vkDestroyCommandPool
    (foreign-procedure "vkDestroyCommandPool"
                       (uptr unsigned-64 uptr) void))
  (define vkAllocateCommandBuffers
    (foreign-procedure "vkAllocateCommandBuffers" (uptr uptr uptr) int))
  (define vkFreeCommandBuffers
    (foreign-procedure "vkFreeCommandBuffers"
                       (uptr unsigned-64 unsigned-32 uptr) void))
  (define vkBeginCommandBuffer
    (foreign-procedure "vkBeginCommandBuffer" (uptr uptr) int))
  (define vkEndCommandBuffer
    (foreign-procedure "vkEndCommandBuffer" (uptr) int))
  (define vkCmdPipelineBarrier
    (foreign-procedure "vkCmdPipelineBarrier"
                       (uptr unsigned-32 unsigned-32 unsigned-32
                             unsigned-32 uptr
                             unsigned-32 uptr
                             unsigned-32 uptr) void))
  (define vkCmdClearColorImage
    (foreign-procedure "vkCmdClearColorImage"
                       (uptr unsigned-64 unsigned-32 uptr unsigned-32 uptr) void))
  (define vkQueueSubmit
    (foreign-procedure "vkQueueSubmit"
                       (uptr unsigned-32 uptr unsigned-64) int)))
