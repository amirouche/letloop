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
   VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
   VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
   VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
   VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
   VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
   VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
   VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
   VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
   VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
   VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
   VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
   VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
   VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
   VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
   VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO

   ;; format / image layout / usage / sharing
   VK_FORMAT_UNDEFINED
   VK_FORMAT_R8_UNORM
   VK_FORMAT_B8G8R8A8_UNORM
   VK_FORMAT_B8G8R8A8_SRGB
   VK_FORMAT_R8G8B8A8_UNORM
   VK_FORMAT_R32G32_SFLOAT
   VK_FORMAT_R32G32B32A32_SFLOAT

   VK_IMAGE_LAYOUT_UNDEFINED
   VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
   VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
   VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
   VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

   VK_IMAGE_USAGE_TRANSFER_SRC_BIT
   VK_IMAGE_USAGE_TRANSFER_DST_BIT
   VK_IMAGE_USAGE_SAMPLED_BIT
   VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT

   VK_IMAGE_TYPE_2D
   VK_IMAGE_VIEW_TYPE_2D
   VK_IMAGE_TILING_OPTIMAL
   VK_IMAGE_TILING_LINEAR

   VK_IMAGE_ASPECT_COLOR_BIT

   VK_SHARING_MODE_EXCLUSIVE
   VK_SAMPLE_COUNT_1_BIT

   ;; access / pipeline stages
   VK_ACCESS_MEMORY_READ_BIT
   VK_ACCESS_TRANSFER_WRITE_BIT
   VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
   VK_ACCESS_SHADER_READ_BIT

   VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT
   VK_PIPELINE_STAGE_TRANSFER_BIT
   VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT
   VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
   VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT

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

   ;; render pass / pipeline / descriptor / shader / blend / sampler
   VK_ATTACHMENT_LOAD_OP_LOAD
   VK_ATTACHMENT_LOAD_OP_CLEAR
   VK_ATTACHMENT_LOAD_OP_DONT_CARE
   VK_ATTACHMENT_STORE_OP_STORE
   VK_ATTACHMENT_STORE_OP_DONT_CARE

   VK_PIPELINE_BIND_POINT_GRAPHICS
   VK_SUBPASS_EXTERNAL
   VK_SUBPASS_CONTENTS_INLINE

   VK_VERTEX_INPUT_RATE_VERTEX
   VK_VERTEX_INPUT_RATE_INSTANCE
   VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
   VK_POLYGON_MODE_FILL
   VK_CULL_MODE_NONE
   VK_FRONT_FACE_COUNTER_CLOCKWISE

   VK_BLEND_FACTOR_ZERO
   VK_BLEND_FACTOR_ONE
   VK_BLEND_FACTOR_SRC_ALPHA
   VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
   VK_BLEND_OP_ADD
   VK_COLOR_COMPONENT_R_BIT
   VK_COLOR_COMPONENT_G_BIT
   VK_COLOR_COMPONENT_B_BIT
   VK_COLOR_COMPONENT_A_BIT

   VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER

   VK_SHADER_STAGE_VERTEX_BIT
   VK_SHADER_STAGE_FRAGMENT_BIT

   VK_FILTER_NEAREST
   VK_FILTER_LINEAR
   VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
   VK_SAMPLER_ADDRESS_MODE_REPEAT
   VK_SAMPLER_MIPMAP_MODE_NEAREST
   VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK

   VK_DYNAMIC_STATE_VIEWPORT
   VK_DYNAMIC_STATE_SCISSOR

   VK_BUFFER_USAGE_TRANSFER_SRC_BIT
   VK_BUFFER_USAGE_TRANSFER_DST_BIT
   VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
   VK_BUFFER_USAGE_INDEX_BUFFER_BIT
   VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT
   VK_BUFFER_USAGE_STORAGE_BUFFER_BIT

   VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
   VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
   VK_MEMORY_PROPERTY_HOST_COHERENT_BIT

   ;; extension name strings
   VK_KHR_SURFACE_EXTENSION_NAME
   VK_KHR_DISPLAY_EXTENSION_NAME
   VK_KHR_SWAPCHAIN_EXTENSION_NAME

   ;; ftypes — small
   <VkExtent2D>
   <VkExtent3D>
   <VkOffset2D>
   <VkOffset3D>
   <VkRect2D>
   <VkViewport>
   <VkComponentMapping>
   <VkImageSubresourceRange>
   <VkImageSubresourceLayers>
   <VkSurfaceFormatKHR>
   <VkDisplayModeParametersKHR>
   <VkDisplayModePropertiesKHR>
   <VkDisplayPropertiesKHR>
   <VkDisplayPlanePropertiesKHR>
   <VkQueueFamilyProperties>
   <VkSurfaceCapabilitiesKHR>
   <VkClearColorValue>
   <VkClearValue>
   <VkBufferImageCopy>
   <VkPushConstantRange>
   <VkMemoryRequirements>
   <VkMemoryType>
   <VkMemoryHeap>
   <VkPhysicalDeviceMemoryProperties>

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
   <VkBufferCreateInfo>
   <VkImageCreateInfo>
   <VkImageViewCreateInfo>
   <VkSamplerCreateInfo>
   <VkShaderModuleCreateInfo>
   <VkMemoryAllocateInfo>
   <VkAttachmentDescription>
   <VkAttachmentReference>
   <VkSubpassDescription>
   <VkSubpassDependency>
   <VkRenderPassCreateInfo>
   <VkRenderPassBeginInfo>
   <VkFramebufferCreateInfo>
   <VkPipelineLayoutCreateInfo>
   <VkPipelineShaderStageCreateInfo>
   <VkVertexInputBindingDescription>
   <VkVertexInputAttributeDescription>
   <VkPipelineVertexInputStateCreateInfo>
   <VkPipelineInputAssemblyStateCreateInfo>
   <VkPipelineViewportStateCreateInfo>
   <VkPipelineRasterizationStateCreateInfo>
   <VkPipelineMultisampleStateCreateInfo>
   <VkPipelineColorBlendAttachmentState>
   <VkPipelineColorBlendStateCreateInfo>
   <VkPipelineDynamicStateCreateInfo>
   <VkGraphicsPipelineCreateInfo>
   <VkDescriptorSetLayoutBinding>
   <VkDescriptorSetLayoutCreateInfo>
   <VkDescriptorPoolSize>
   <VkDescriptorPoolCreateInfo>
   <VkDescriptorSetAllocateInfo>
   <VkDescriptorImageInfo>
   <VkDescriptorBufferInfo>
   <VkWriteDescriptorSet>

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
   vkQueueSubmit

   ;; render pass / framebuffer
   vkCreateRenderPass
   vkDestroyRenderPass
   vkCreateFramebuffer
   vkDestroyFramebuffer

   ;; image / view / sampler
   vkCreateImage
   vkDestroyImage
   vkCreateImageView
   vkDestroyImageView
   vkCreateSampler
   vkDestroySampler
   vkGetImageMemoryRequirements
   vkBindImageMemory

   ;; shader / pipeline
   vkCreateShaderModule
   vkDestroyShaderModule
   vkCreatePipelineLayout
   vkDestroyPipelineLayout
   vkCreateGraphicsPipelines
   vkDestroyPipeline

   ;; descriptors
   vkCreateDescriptorSetLayout
   vkDestroyDescriptorSetLayout
   vkCreateDescriptorPool
   vkDestroyDescriptorPool
   vkAllocateDescriptorSets
   vkUpdateDescriptorSets

   ;; buffers + memory
   vkCreateBuffer
   vkDestroyBuffer
   vkGetBufferMemoryRequirements
   vkBindBufferMemory
   vkAllocateMemory
   vkFreeMemory
   vkMapMemory
   vkUnmapMemory
   vkGetPhysicalDeviceMemoryProperties

   ;; record-time graphics commands
   vkCmdBeginRenderPass
   vkCmdEndRenderPass
   vkCmdBindPipeline
   vkCmdBindVertexBuffers
   vkCmdBindDescriptorSets
   vkCmdDraw
   vkCmdSetViewport
   vkCmdSetScissor
   vkCmdPushConstants
   vkCmdCopyBufferToImage
   vkCmdCopyImageToBuffer)
  (import (chezscheme) (letloop cffi))

  (define-shared-object libvulkan "libvulkan.so.1" "libvulkan.so")

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
  (define VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO                            12)
  (define VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO                             14)
  (define VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO                        15)
  (define VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO                     16)
  (define VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO             18)
  (define VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO       19)
  (define VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO     20)
  (define VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO           22)
  (define VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO      23)
  (define VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO        24)
  (define VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO        26)
  (define VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO            27)
  (define VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO                 28)
  (define VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO                   30)
  (define VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO                           31)
  (define VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO             32)
  (define VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO                   33)
  (define VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO                  34)
  (define VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET                          35)
  (define VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO                       37)
  (define VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO                       38)
  (define VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO                           5)
  (define VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO                        43)

  ;; ----------------------------------------------------------------
  ;; Enums / flags
  ;; ----------------------------------------------------------------
  (define VK_FORMAT_UNDEFINED            0)
  (define VK_FORMAT_R8_UNORM             9)
  (define VK_FORMAT_R8G8B8A8_UNORM      37)
  (define VK_FORMAT_B8G8R8A8_UNORM      44)
  (define VK_FORMAT_B8G8R8A8_SRGB       50)
  (define VK_FORMAT_R32G32_SFLOAT      103)
  (define VK_FORMAT_R32G32B32A32_SFLOAT 109)

  (define VK_IMAGE_LAYOUT_UNDEFINED                0)
  (define VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL 2)
  (define VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL 5)
  (define VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL     6)
  (define VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL     7)
  (define VK_IMAGE_LAYOUT_PRESENT_SRC_KHR          1000001002)

  (define VK_IMAGE_USAGE_TRANSFER_SRC_BIT      #x01)
  (define VK_IMAGE_USAGE_TRANSFER_DST_BIT      #x02)
  (define VK_IMAGE_USAGE_SAMPLED_BIT           #x04)
  (define VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT  #x10)

  (define VK_IMAGE_TYPE_2D                      1)
  (define VK_IMAGE_VIEW_TYPE_2D                 1)
  (define VK_IMAGE_TILING_OPTIMAL               0)
  (define VK_IMAGE_TILING_LINEAR                1)

  (define VK_IMAGE_ASPECT_COLOR_BIT             #x01)

  (define VK_SHARING_MODE_EXCLUSIVE              0)
  (define VK_SAMPLE_COUNT_1_BIT                  1)

  (define VK_ACCESS_MEMORY_READ_BIT             #x00008000)
  (define VK_ACCESS_TRANSFER_WRITE_BIT          #x00001000)
  (define VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT  #x00000100)
  (define VK_ACCESS_SHADER_READ_BIT             #x00000020)

  (define VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT          #x00000001)
  (define VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT      #x00000080)
  (define VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT #x00000400)
  (define VK_PIPELINE_STAGE_TRANSFER_BIT             #x00001000)
  (define VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT       #x00002000)

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
  ;; Render pass / pipeline / descriptor / shader / blend / sampler
  ;; ----------------------------------------------------------------

  (define VK_ATTACHMENT_LOAD_OP_LOAD          0)
  (define VK_ATTACHMENT_LOAD_OP_CLEAR         1)
  (define VK_ATTACHMENT_LOAD_OP_DONT_CARE     2)
  (define VK_ATTACHMENT_STORE_OP_STORE        0)
  (define VK_ATTACHMENT_STORE_OP_DONT_CARE    1)

  (define VK_PIPELINE_BIND_POINT_GRAPHICS     0)
  (define VK_SUBPASS_EXTERNAL                 #xFFFFFFFF)
  (define VK_SUBPASS_CONTENTS_INLINE          0)

  (define VK_VERTEX_INPUT_RATE_VERTEX         0)
  (define VK_VERTEX_INPUT_RATE_INSTANCE       1)
  (define VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST 3)
  (define VK_POLYGON_MODE_FILL                0)
  (define VK_CULL_MODE_NONE                   0)
  (define VK_FRONT_FACE_COUNTER_CLOCKWISE     0)

  (define VK_BLEND_FACTOR_ZERO                0)
  (define VK_BLEND_FACTOR_ONE                 1)
  (define VK_BLEND_FACTOR_SRC_ALPHA           6)
  (define VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA 7)
  (define VK_BLEND_OP_ADD                     0)
  (define VK_COLOR_COMPONENT_R_BIT           #x01)
  (define VK_COLOR_COMPONENT_G_BIT           #x02)
  (define VK_COLOR_COMPONENT_B_BIT           #x04)
  (define VK_COLOR_COMPONENT_A_BIT           #x08)

  (define VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER 1)

  (define VK_SHADER_STAGE_VERTEX_BIT         #x01)
  (define VK_SHADER_STAGE_FRAGMENT_BIT       #x10)

  (define VK_FILTER_NEAREST                   0)
  (define VK_FILTER_LINEAR                    1)
  (define VK_SAMPLER_ADDRESS_MODE_REPEAT          0)
  (define VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE   2)
  (define VK_SAMPLER_MIPMAP_MODE_NEAREST      0)
  (define VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK  3)

  (define VK_DYNAMIC_STATE_VIEWPORT           0)
  (define VK_DYNAMIC_STATE_SCISSOR            1)

  (define VK_BUFFER_USAGE_TRANSFER_SRC_BIT    #x001)
  (define VK_BUFFER_USAGE_TRANSFER_DST_BIT    #x002)
  (define VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT  #x010)
  (define VK_BUFFER_USAGE_STORAGE_BUFFER_BIT  #x020)
  (define VK_BUFFER_USAGE_INDEX_BUFFER_BIT    #x040)
  (define VK_BUFFER_USAGE_VERTEX_BUFFER_BIT   #x080)

  (define VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT     #x01)
  (define VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT     #x02)
  (define VK_MEMORY_PROPERTY_HOST_COHERENT_BIT    #x04)

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

  (define-ftype <VkOffset2D>
    (struct
     (x integer-32)
     (y integer-32)))

  (define-ftype <VkOffset3D>
    (struct
     (x integer-32)
     (y integer-32)
     (z integer-32)))

  (define-ftype <VkRect2D>
    (struct
     (offset (struct (x integer-32) (y integer-32)))
     (extent (struct (width unsigned-32) (height unsigned-32)))))

  (define-ftype <VkViewport>
    (struct
     (x        float)
     (y        float)
     (width    float)
     (height   float)
     (minDepth float)
     (maxDepth float)))

  (define-ftype <VkComponentMapping>
    (struct
     (r unsigned-32)
     (g unsigned-32)
     (b unsigned-32)
     (a unsigned-32)))

  (define-ftype <VkImageSubresourceLayers>
    (struct
     (aspectMask     unsigned-32)
     (mipLevel       unsigned-32)
     (baseArrayLayer unsigned-32)
     (layerCount     unsigned-32)))

  (define-ftype <VkPushConstantRange>
    (struct
     (stageFlags unsigned-32)
     (offset     unsigned-32)
     (size       unsigned-32)))

  (define-ftype <VkBufferImageCopy>
    (struct
     (bufferOffset      unsigned-64)
     (bufferRowLength   unsigned-32)
     (bufferImageHeight unsigned-32)
     (imageSubresource  (struct
                         (aspectMask     unsigned-32)
                         (mipLevel       unsigned-32)
                         (baseArrayLayer unsigned-32)
                         (layerCount     unsigned-32)))
     (imageOffset       (struct (x integer-32) (y integer-32) (z integer-32)))
     (imageExtent       (struct (width unsigned-32) (height unsigned-32) (depth unsigned-32)))))

  (define-ftype <VkMemoryRequirements>
    (struct
     (size           unsigned-64)
     (alignment      unsigned-64)
     (memoryTypeBits unsigned-32)))

  (define-ftype <VkMemoryType>
    (struct
     (propertyFlags unsigned-32)
     (heapIndex     unsigned-32)))

  (define-ftype <VkMemoryHeap>
    (struct
     (size  unsigned-64)
     (flags unsigned-32)))

  ;; VK_MAX_MEMORY_TYPES = 32, VK_MAX_MEMORY_HEAPS = 16
  (define-ftype <VkPhysicalDeviceMemoryProperties>
    (struct
     (memoryTypeCount unsigned-32)
     (memoryTypes     (array 32 (struct
                                 (propertyFlags unsigned-32)
                                 (heapIndex     unsigned-32))))
     (memoryHeapCount unsigned-32)
     (memoryHeaps     (array 16 (struct
                                 (size  unsigned-64)
                                 (flags unsigned-32))))))

  ;; VkClearValue is a union of color (16 bytes) and depthStencil (8 bytes);
  ;; we only ever use it as color.
  (define-ftype <VkClearValue>
    (struct
     (color (struct (float32 (array 4 float))))))

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

  (define-ftype <VkBufferCreateInfo>
    (struct
     (sType                 unsigned-32)
     (pNext                 uptr)
     (flags                 unsigned-32)
     (size                  unsigned-64)
     (usage                 unsigned-32)
     (sharingMode           unsigned-32)
     (queueFamilyIndexCount unsigned-32)
     (pQueueFamilyIndices   uptr)))

  (define-ftype <VkImageCreateInfo>
    (struct
     (sType                 unsigned-32)
     (pNext                 uptr)
     (flags                 unsigned-32)
     (imageType             unsigned-32)
     (format                unsigned-32)
     (extent                (struct (width  unsigned-32)
                                    (height unsigned-32)
                                    (depth  unsigned-32)))
     (mipLevels             unsigned-32)
     (arrayLayers           unsigned-32)
     (samples               unsigned-32)
     (tiling                unsigned-32)
     (usage                 unsigned-32)
     (sharingMode           unsigned-32)
     (queueFamilyIndexCount unsigned-32)
     (pQueueFamilyIndices   uptr)
     (initialLayout         unsigned-32)))

  (define-ftype <VkImageViewCreateInfo>
    (struct
     (sType            unsigned-32)
     (pNext            uptr)
     (flags            unsigned-32)
     (image            unsigned-64)
     (viewType         unsigned-32)
     (format           unsigned-32)
     (components       (struct (r unsigned-32) (g unsigned-32)
                               (b unsigned-32) (a unsigned-32)))
     (subresourceRange (struct
                        (aspectMask     unsigned-32)
                        (baseMipLevel   unsigned-32)
                        (levelCount     unsigned-32)
                        (baseArrayLayer unsigned-32)
                        (layerCount     unsigned-32)))))

  (define-ftype <VkSamplerCreateInfo>
    (struct
     (sType                  unsigned-32)
     (pNext                  uptr)
     (flags                  unsigned-32)
     (magFilter              unsigned-32)
     (minFilter              unsigned-32)
     (mipmapMode             unsigned-32)
     (addressModeU           unsigned-32)
     (addressModeV           unsigned-32)
     (addressModeW           unsigned-32)
     (mipLodBias             float)
     (anisotropyEnable       unsigned-32)
     (maxAnisotropy          float)
     (compareEnable          unsigned-32)
     (compareOp              unsigned-32)
     (minLod                 float)
     (maxLod                 float)
     (borderColor            unsigned-32)
     (unnormalizedCoordinates unsigned-32)))

  (define-ftype <VkShaderModuleCreateInfo>
    (struct
     (sType    unsigned-32)
     (pNext    uptr)
     (flags    unsigned-32)
     (codeSize unsigned-64)            ; size_t — 8 bytes on x86_64
     (pCode    uptr)))

  (define-ftype <VkMemoryAllocateInfo>
    (struct
     (sType           unsigned-32)
     (pNext           uptr)
     (allocationSize  unsigned-64)
     (memoryTypeIndex unsigned-32)))

  (define-ftype <VkAttachmentDescription>
    (struct
     (flags          unsigned-32)
     (format         unsigned-32)
     (samples        unsigned-32)
     (loadOp         unsigned-32)
     (storeOp        unsigned-32)
     (stencilLoadOp  unsigned-32)
     (stencilStoreOp unsigned-32)
     (initialLayout  unsigned-32)
     (finalLayout    unsigned-32)))

  (define-ftype <VkAttachmentReference>
    (struct
     (attachment unsigned-32)
     (layout     unsigned-32)))

  (define-ftype <VkSubpassDescription>
    (struct
     (flags                   unsigned-32)
     (pipelineBindPoint       unsigned-32)
     (inputAttachmentCount    unsigned-32)
     (pInputAttachments       uptr)
     (colorAttachmentCount    unsigned-32)
     (pColorAttachments       uptr)
     (pResolveAttachments     uptr)
     (pDepthStencilAttachment uptr)
     (preserveAttachmentCount unsigned-32)
     (pPreserveAttachments    uptr)))

  (define-ftype <VkSubpassDependency>
    (struct
     (srcSubpass      unsigned-32)
     (dstSubpass      unsigned-32)
     (srcStageMask    unsigned-32)
     (dstStageMask    unsigned-32)
     (srcAccessMask   unsigned-32)
     (dstAccessMask   unsigned-32)
     (dependencyFlags unsigned-32)))

  (define-ftype <VkRenderPassCreateInfo>
    (struct
     (sType           unsigned-32)
     (pNext           uptr)
     (flags           unsigned-32)
     (attachmentCount unsigned-32)
     (pAttachments    uptr)
     (subpassCount    unsigned-32)
     (pSubpasses      uptr)
     (dependencyCount unsigned-32)
     (pDependencies   uptr)))

  (define-ftype <VkRenderPassBeginInfo>
    (struct
     (sType           unsigned-32)
     (pNext           uptr)
     (renderPass      unsigned-64)
     (framebuffer     unsigned-64)
     (renderArea      (struct
                       (offset (struct (x integer-32) (y integer-32)))
                       (extent (struct (width unsigned-32) (height unsigned-32)))))
     (clearValueCount unsigned-32)
     (pClearValues    uptr)))

  (define-ftype <VkFramebufferCreateInfo>
    (struct
     (sType           unsigned-32)
     (pNext           uptr)
     (flags           unsigned-32)
     (renderPass      unsigned-64)
     (attachmentCount unsigned-32)
     (pAttachments    uptr)
     (width           unsigned-32)
     (height          unsigned-32)
     (layers          unsigned-32)))

  (define-ftype <VkPipelineLayoutCreateInfo>
    (struct
     (sType                  unsigned-32)
     (pNext                  uptr)
     (flags                  unsigned-32)
     (setLayoutCount         unsigned-32)
     (pSetLayouts            uptr)
     (pushConstantRangeCount unsigned-32)
     (pPushConstantRanges    uptr)))

  (define-ftype <VkPipelineShaderStageCreateInfo>
    (struct
     (sType               unsigned-32)
     (pNext               uptr)
     (flags               unsigned-32)
     (stage               unsigned-32)
     (module              unsigned-64)
     (pName               uptr)
     (pSpecializationInfo uptr)))

  (define-ftype <VkVertexInputBindingDescription>
    (struct
     (binding   unsigned-32)
     (stride    unsigned-32)
     (inputRate unsigned-32)))

  (define-ftype <VkVertexInputAttributeDescription>
    (struct
     (location unsigned-32)
     (binding  unsigned-32)
     (format   unsigned-32)
     (offset   unsigned-32)))

  (define-ftype <VkPipelineVertexInputStateCreateInfo>
    (struct
     (sType                          unsigned-32)
     (pNext                          uptr)
     (flags                          unsigned-32)
     (vertexBindingDescriptionCount  unsigned-32)
     (pVertexBindingDescriptions     uptr)
     (vertexAttributeDescriptionCount unsigned-32)
     (pVertexAttributeDescriptions   uptr)))

  (define-ftype <VkPipelineInputAssemblyStateCreateInfo>
    (struct
     (sType                  unsigned-32)
     (pNext                  uptr)
     (flags                  unsigned-32)
     (topology               unsigned-32)
     (primitiveRestartEnable unsigned-32)))

  (define-ftype <VkPipelineViewportStateCreateInfo>
    (struct
     (sType         unsigned-32)
     (pNext         uptr)
     (flags         unsigned-32)
     (viewportCount unsigned-32)
     (pViewports    uptr)
     (scissorCount  unsigned-32)
     (pScissors     uptr)))

  (define-ftype <VkPipelineRasterizationStateCreateInfo>
    (struct
     (sType                   unsigned-32)
     (pNext                   uptr)
     (flags                   unsigned-32)
     (depthClampEnable        unsigned-32)
     (rasterizerDiscardEnable unsigned-32)
     (polygonMode             unsigned-32)
     (cullMode                unsigned-32)
     (frontFace               unsigned-32)
     (depthBiasEnable         unsigned-32)
     (depthBiasConstantFactor float)
     (depthBiasClamp          float)
     (depthBiasSlopeFactor    float)
     (lineWidth               float)))

  (define-ftype <VkPipelineMultisampleStateCreateInfo>
    (struct
     (sType                 unsigned-32)
     (pNext                 uptr)
     (flags                 unsigned-32)
     (rasterizationSamples  unsigned-32)
     (sampleShadingEnable   unsigned-32)
     (minSampleShading      float)
     (pSampleMask           uptr)
     (alphaToCoverageEnable unsigned-32)
     (alphaToOneEnable      unsigned-32)))

  (define-ftype <VkPipelineColorBlendAttachmentState>
    (struct
     (blendEnable         unsigned-32)
     (srcColorBlendFactor unsigned-32)
     (dstColorBlendFactor unsigned-32)
     (colorBlendOp        unsigned-32)
     (srcAlphaBlendFactor unsigned-32)
     (dstAlphaBlendFactor unsigned-32)
     (alphaBlendOp        unsigned-32)
     (colorWriteMask      unsigned-32)))

  (define-ftype <VkPipelineColorBlendStateCreateInfo>
    (struct
     (sType           unsigned-32)
     (pNext           uptr)
     (flags           unsigned-32)
     (logicOpEnable   unsigned-32)
     (logicOp         unsigned-32)
     (attachmentCount unsigned-32)
     (pAttachments    uptr)
     (blendConstants  (array 4 float))))

  (define-ftype <VkPipelineDynamicStateCreateInfo>
    (struct
     (sType             unsigned-32)
     (pNext             uptr)
     (flags             unsigned-32)
     (dynamicStateCount unsigned-32)
     (pDynamicStates    uptr)))

  (define-ftype <VkGraphicsPipelineCreateInfo>
    (struct
     (sType               unsigned-32)
     (pNext               uptr)
     (flags               unsigned-32)
     (stageCount          unsigned-32)
     (pStages             uptr)
     (pVertexInputState   uptr)
     (pInputAssemblyState uptr)
     (pTessellationState  uptr)
     (pViewportState      uptr)
     (pRasterizationState uptr)
     (pMultisampleState   uptr)
     (pDepthStencilState  uptr)
     (pColorBlendState    uptr)
     (pDynamicState       uptr)
     (layout              unsigned-64)
     (renderPass          unsigned-64)
     (subpass             unsigned-32)
     (basePipelineHandle  unsigned-64)
     (basePipelineIndex   integer-32)))

  (define-ftype <VkDescriptorSetLayoutBinding>
    (struct
     (binding            unsigned-32)
     (descriptorType     unsigned-32)
     (descriptorCount    unsigned-32)
     (stageFlags         unsigned-32)
     (pImmutableSamplers uptr)))

  (define-ftype <VkDescriptorSetLayoutCreateInfo>
    (struct
     (sType        unsigned-32)
     (pNext        uptr)
     (flags        unsigned-32)
     (bindingCount unsigned-32)
     (pBindings    uptr)))

  (define-ftype <VkDescriptorPoolSize>
    (struct
     (type            unsigned-32)
     (descriptorCount unsigned-32)))

  (define-ftype <VkDescriptorPoolCreateInfo>
    (struct
     (sType         unsigned-32)
     (pNext         uptr)
     (flags         unsigned-32)
     (maxSets       unsigned-32)
     (poolSizeCount unsigned-32)
     (pPoolSizes    uptr)))

  (define-ftype <VkDescriptorSetAllocateInfo>
    (struct
     (sType              unsigned-32)
     (pNext              uptr)
     (descriptorPool     unsigned-64)
     (descriptorSetCount unsigned-32)
     (pSetLayouts        uptr)))

  (define-ftype <VkDescriptorImageInfo>
    (struct
     (sampler     unsigned-64)
     (imageView   unsigned-64)
     (imageLayout unsigned-32)))

  (define-ftype <VkDescriptorBufferInfo>
    (struct
     (buffer unsigned-64)
     (offset unsigned-64)
     (range  unsigned-64)))

  (define-ftype <VkWriteDescriptorSet>
    (struct
     (sType            unsigned-32)
     (pNext            uptr)
     (dstSet           unsigned-64)
     (dstBinding       unsigned-32)
     (dstArrayElement  unsigned-32)
     (descriptorCount  unsigned-32)
     (descriptorType   unsigned-32)
     (pImageInfo       uptr)
     (pBufferInfo      uptr)
     (pTexelBufferView uptr)))

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
    (lazy-foreign-procedure libvulkan "vkCreateInstance" (uptr uptr uptr) int))
  (define vkDestroyInstance
    (lazy-foreign-procedure libvulkan "vkDestroyInstance" (uptr uptr) void))
  (define vkEnumeratePhysicalDevices
    (lazy-foreign-procedure libvulkan "vkEnumeratePhysicalDevices" (uptr uptr uptr) int))
  (define vkGetPhysicalDeviceProperties
    (lazy-foreign-procedure libvulkan "vkGetPhysicalDeviceProperties" (uptr uptr) void))
  (define vkGetPhysicalDeviceQueueFamilyProperties
    (lazy-foreign-procedure libvulkan "vkGetPhysicalDeviceQueueFamilyProperties"
                       (uptr uptr uptr) void))

  (define vkCreateDevice
    (lazy-foreign-procedure libvulkan "vkCreateDevice" (uptr uptr uptr uptr) int))
  (define vkDestroyDevice
    (lazy-foreign-procedure libvulkan "vkDestroyDevice" (uptr uptr) void))
  (define vkDeviceWaitIdle
    (lazy-foreign-procedure libvulkan "vkDeviceWaitIdle" (uptr) int))
  (define vkGetDeviceQueue
    (lazy-foreign-procedure libvulkan "vkGetDeviceQueue" (uptr unsigned-32 unsigned-32 uptr) void))

  (define vkGetPhysicalDeviceDisplayPropertiesKHR
    (lazy-foreign-procedure libvulkan "vkGetPhysicalDeviceDisplayPropertiesKHR"
                       (uptr uptr uptr) int))
  (define vkGetDisplayModePropertiesKHR
    (lazy-foreign-procedure libvulkan "vkGetDisplayModePropertiesKHR"
                       (uptr unsigned-64 uptr uptr) int))
  (define vkGetPhysicalDeviceDisplayPlanePropertiesKHR
    (lazy-foreign-procedure libvulkan "vkGetPhysicalDeviceDisplayPlanePropertiesKHR"
                       (uptr uptr uptr) int))
  (define vkCreateDisplayPlaneSurfaceKHR
    (lazy-foreign-procedure libvulkan "vkCreateDisplayPlaneSurfaceKHR"
                       (uptr uptr uptr uptr) int))
  (define vkDestroySurfaceKHR
    (lazy-foreign-procedure libvulkan "vkDestroySurfaceKHR" (uptr unsigned-64 uptr) void))

  (define vkGetPhysicalDeviceSurfaceCapabilitiesKHR
    (lazy-foreign-procedure libvulkan "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"
                       (uptr unsigned-64 uptr) int))
  (define vkGetPhysicalDeviceSurfaceFormatsKHR
    (lazy-foreign-procedure libvulkan "vkGetPhysicalDeviceSurfaceFormatsKHR"
                       (uptr unsigned-64 uptr uptr) int))
  (define vkCreateSwapchainKHR
    (lazy-foreign-procedure libvulkan "vkCreateSwapchainKHR" (uptr uptr uptr uptr) int))
  (define vkDestroySwapchainKHR
    (lazy-foreign-procedure libvulkan "vkDestroySwapchainKHR"
                       (uptr unsigned-64 uptr) void))
  (define vkGetSwapchainImagesKHR
    (lazy-foreign-procedure libvulkan "vkGetSwapchainImagesKHR"
                       (uptr unsigned-64 uptr uptr) int))
  (define vkAcquireNextImageKHR
    (lazy-foreign-procedure libvulkan "vkAcquireNextImageKHR"
                       (uptr unsigned-64 unsigned-64 unsigned-64 unsigned-64 uptr) int))
  (define vkQueuePresentKHR
    (lazy-foreign-procedure libvulkan "vkQueuePresentKHR" (uptr uptr) int))

  (define vkCreateSemaphore
    (lazy-foreign-procedure libvulkan "vkCreateSemaphore" (uptr uptr uptr uptr) int))
  (define vkDestroySemaphore
    (lazy-foreign-procedure libvulkan "vkDestroySemaphore"
                       (uptr unsigned-64 uptr) void))
  (define vkCreateFence
    (lazy-foreign-procedure libvulkan "vkCreateFence" (uptr uptr uptr uptr) int))
  (define vkDestroyFence
    (lazy-foreign-procedure libvulkan "vkDestroyFence"
                       (uptr unsigned-64 uptr) void))
  (define vkWaitForFences
    (lazy-foreign-procedure libvulkan "vkWaitForFences"
                       (uptr unsigned-32 uptr unsigned-32 unsigned-64) int))
  (define vkResetFences
    (lazy-foreign-procedure libvulkan "vkResetFences" (uptr unsigned-32 uptr) int))

  (define vkCreateCommandPool
    (lazy-foreign-procedure libvulkan "vkCreateCommandPool" (uptr uptr uptr uptr) int))
  (define vkDestroyCommandPool
    (lazy-foreign-procedure libvulkan "vkDestroyCommandPool"
                       (uptr unsigned-64 uptr) void))
  (define vkAllocateCommandBuffers
    (lazy-foreign-procedure libvulkan "vkAllocateCommandBuffers" (uptr uptr uptr) int))
  (define vkFreeCommandBuffers
    (lazy-foreign-procedure libvulkan "vkFreeCommandBuffers"
                       (uptr unsigned-64 unsigned-32 uptr) void))
  (define vkBeginCommandBuffer
    (lazy-foreign-procedure libvulkan "vkBeginCommandBuffer" (uptr uptr) int))
  (define vkEndCommandBuffer
    (lazy-foreign-procedure libvulkan "vkEndCommandBuffer" (uptr) int))
  (define vkCmdPipelineBarrier
    (lazy-foreign-procedure libvulkan "vkCmdPipelineBarrier"
                       (uptr unsigned-32 unsigned-32 unsigned-32
                             unsigned-32 uptr
                             unsigned-32 uptr
                             unsigned-32 uptr) void))
  (define vkCmdClearColorImage
    (lazy-foreign-procedure libvulkan "vkCmdClearColorImage"
                       (uptr unsigned-64 unsigned-32 uptr unsigned-32 uptr) void))
  (define vkQueueSubmit
    (lazy-foreign-procedure libvulkan "vkQueueSubmit"
                       (uptr unsigned-32 uptr unsigned-64) int))

  ;; ----------------------------------------------------------------
  ;; M2.2 — render pass / framebuffer / image / view / sampler /
  ;;         shader / pipeline / descriptors / buffers / memory
  ;; ----------------------------------------------------------------

  (define vkCreateRenderPass
    (lazy-foreign-procedure libvulkan "vkCreateRenderPass" (uptr uptr uptr uptr) int))
  (define vkDestroyRenderPass
    (lazy-foreign-procedure libvulkan "vkDestroyRenderPass"
                       (uptr unsigned-64 uptr) void))

  (define vkCreateFramebuffer
    (lazy-foreign-procedure libvulkan "vkCreateFramebuffer" (uptr uptr uptr uptr) int))
  (define vkDestroyFramebuffer
    (lazy-foreign-procedure libvulkan "vkDestroyFramebuffer"
                       (uptr unsigned-64 uptr) void))

  (define vkCreateImage
    (lazy-foreign-procedure libvulkan "vkCreateImage" (uptr uptr uptr uptr) int))
  (define vkDestroyImage
    (lazy-foreign-procedure libvulkan "vkDestroyImage"
                       (uptr unsigned-64 uptr) void))
  (define vkCreateImageView
    (lazy-foreign-procedure libvulkan "vkCreateImageView" (uptr uptr uptr uptr) int))
  (define vkDestroyImageView
    (lazy-foreign-procedure libvulkan "vkDestroyImageView"
                       (uptr unsigned-64 uptr) void))
  (define vkCreateSampler
    (lazy-foreign-procedure libvulkan "vkCreateSampler" (uptr uptr uptr uptr) int))
  (define vkDestroySampler
    (lazy-foreign-procedure libvulkan "vkDestroySampler"
                       (uptr unsigned-64 uptr) void))
  (define vkGetImageMemoryRequirements
    (lazy-foreign-procedure libvulkan "vkGetImageMemoryRequirements"
                       (uptr unsigned-64 uptr) void))
  (define vkBindImageMemory
    (lazy-foreign-procedure libvulkan "vkBindImageMemory"
                       (uptr unsigned-64 unsigned-64 unsigned-64) int))

  (define vkCreateShaderModule
    (lazy-foreign-procedure libvulkan "vkCreateShaderModule" (uptr uptr uptr uptr) int))
  (define vkDestroyShaderModule
    (lazy-foreign-procedure libvulkan "vkDestroyShaderModule"
                       (uptr unsigned-64 uptr) void))
  (define vkCreatePipelineLayout
    (lazy-foreign-procedure libvulkan "vkCreatePipelineLayout" (uptr uptr uptr uptr) int))
  (define vkDestroyPipelineLayout
    (lazy-foreign-procedure libvulkan "vkDestroyPipelineLayout"
                       (uptr unsigned-64 uptr) void))
  (define vkCreateGraphicsPipelines
    (lazy-foreign-procedure libvulkan "vkCreateGraphicsPipelines"
                       (uptr unsigned-64 unsigned-32 uptr uptr uptr) int))
  (define vkDestroyPipeline
    (lazy-foreign-procedure libvulkan "vkDestroyPipeline"
                       (uptr unsigned-64 uptr) void))

  (define vkCreateDescriptorSetLayout
    (lazy-foreign-procedure libvulkan "vkCreateDescriptorSetLayout"
                       (uptr uptr uptr uptr) int))
  (define vkDestroyDescriptorSetLayout
    (lazy-foreign-procedure libvulkan "vkDestroyDescriptorSetLayout"
                       (uptr unsigned-64 uptr) void))
  (define vkCreateDescriptorPool
    (lazy-foreign-procedure libvulkan "vkCreateDescriptorPool"
                       (uptr uptr uptr uptr) int))
  (define vkDestroyDescriptorPool
    (lazy-foreign-procedure libvulkan "vkDestroyDescriptorPool"
                       (uptr unsigned-64 uptr) void))
  (define vkAllocateDescriptorSets
    (lazy-foreign-procedure libvulkan "vkAllocateDescriptorSets" (uptr uptr uptr) int))
  (define vkUpdateDescriptorSets
    (lazy-foreign-procedure libvulkan "vkUpdateDescriptorSets"
                       (uptr unsigned-32 uptr unsigned-32 uptr) void))

  (define vkCreateBuffer
    (lazy-foreign-procedure libvulkan "vkCreateBuffer" (uptr uptr uptr uptr) int))
  (define vkDestroyBuffer
    (lazy-foreign-procedure libvulkan "vkDestroyBuffer"
                       (uptr unsigned-64 uptr) void))
  (define vkGetBufferMemoryRequirements
    (lazy-foreign-procedure libvulkan "vkGetBufferMemoryRequirements"
                       (uptr unsigned-64 uptr) void))
  (define vkBindBufferMemory
    (lazy-foreign-procedure libvulkan "vkBindBufferMemory"
                       (uptr unsigned-64 unsigned-64 unsigned-64) int))
  (define vkAllocateMemory
    (lazy-foreign-procedure libvulkan "vkAllocateMemory" (uptr uptr uptr uptr) int))
  (define vkFreeMemory
    (lazy-foreign-procedure libvulkan "vkFreeMemory"
                       (uptr unsigned-64 uptr) void))
  (define vkMapMemory
    (lazy-foreign-procedure libvulkan "vkMapMemory"
                       (uptr unsigned-64 unsigned-64 unsigned-64
                             unsigned-32 uptr) int))
  (define vkUnmapMemory
    (lazy-foreign-procedure libvulkan "vkUnmapMemory"
                       (uptr unsigned-64) void))
  (define vkGetPhysicalDeviceMemoryProperties
    (lazy-foreign-procedure libvulkan "vkGetPhysicalDeviceMemoryProperties"
                       (uptr uptr) void))

  (define vkCmdBeginRenderPass
    (lazy-foreign-procedure libvulkan "vkCmdBeginRenderPass"
                       (uptr uptr unsigned-32) void))
  (define vkCmdEndRenderPass
    (lazy-foreign-procedure libvulkan "vkCmdEndRenderPass" (uptr) void))
  (define vkCmdBindPipeline
    (lazy-foreign-procedure libvulkan "vkCmdBindPipeline"
                       (uptr unsigned-32 unsigned-64) void))
  (define vkCmdBindVertexBuffers
    (lazy-foreign-procedure libvulkan "vkCmdBindVertexBuffers"
                       (uptr unsigned-32 unsigned-32 uptr uptr) void))
  (define vkCmdBindDescriptorSets
    (lazy-foreign-procedure libvulkan "vkCmdBindDescriptorSets"
                       (uptr unsigned-32 unsigned-64
                             unsigned-32 unsigned-32 uptr
                             unsigned-32 uptr) void))
  (define vkCmdDraw
    (lazy-foreign-procedure libvulkan "vkCmdDraw"
                       (uptr unsigned-32 unsigned-32
                             unsigned-32 unsigned-32) void))
  (define vkCmdSetViewport
    (lazy-foreign-procedure libvulkan "vkCmdSetViewport"
                       (uptr unsigned-32 unsigned-32 uptr) void))
  (define vkCmdSetScissor
    (lazy-foreign-procedure libvulkan "vkCmdSetScissor"
                       (uptr unsigned-32 unsigned-32 uptr) void))
  (define vkCmdPushConstants
    (lazy-foreign-procedure libvulkan "vkCmdPushConstants"
                       (uptr unsigned-64 unsigned-32
                             unsigned-32 unsigned-32 uptr) void))
  (define vkCmdCopyBufferToImage
    (lazy-foreign-procedure libvulkan "vkCmdCopyBufferToImage"
                       (uptr unsigned-64 unsigned-64
                             unsigned-32 unsigned-32 uptr) void))
  (define vkCmdCopyImageToBuffer
    (lazy-foreign-procedure libvulkan "vkCmdCopyImageToBuffer"
                       (uptr unsigned-64 unsigned-32
                             unsigned-64 unsigned-32 uptr) void)))
