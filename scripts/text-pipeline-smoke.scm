;; Exercise build-text-pipeline against llvmpipe (no swapchain). The
;; idea: borrow the helper procedures from window.scm but skip the
;; surface/swapchain steps. We need a device, queue, command pool, and
;; a render pass that matches what window.scm uses (so the pipeline
;; verifies for the real format).

(import (chezscheme)
        (letloop desktop vulkan)
        (letloop desktop vulkan low)
        (letloop desktop text-pipeline))

(define (foreign-alloc/zero n)
  (let ((p (foreign-alloc n)))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i 0))
    p))

(define (vk-check who r)
  (unless (= r VK_SUCCESS) (error who (vk-result-name r) r)))

(call-with-vulkan-instance "smoke"
  (lambda (instance)
    (let ((pds (vulkan-physical-devices instance)))
      (when (null? pds) (error 'smoke "no Vulkan devices"))
      (let* ((pd  (car pds))
             (qfi (vulkan-pick-graphics-queue-family pd)))
        (display (list 'pd pd 'qfi qfi)) (newline)
        ;; Build a minimal device with one graphics queue.
        (let* ((priorities (foreign-alloc/zero 4))
               (qci (foreign-alloc/zero (ftype-sizeof <VkDeviceQueueCreateInfo>)))
               (dci (foreign-alloc/zero (ftype-sizeof <VkDeviceCreateInfo>)))
               (qfp (make-ftype-pointer <VkDeviceQueueCreateInfo> qci))
               (dfp (make-ftype-pointer <VkDeviceCreateInfo> dci))
               (out (foreign-alloc/zero 8)))
          (foreign-set! 'float priorities 0 1.0)
          (ftype-set! <VkDeviceQueueCreateInfo> (sType) qfp
                      VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO)
          (ftype-set! <VkDeviceQueueCreateInfo> (queueFamilyIndex) qfp qfi)
          (ftype-set! <VkDeviceQueueCreateInfo> (queueCount) qfp 1)
          (ftype-set! <VkDeviceQueueCreateInfo> (pQueuePriorities) qfp priorities)
          (ftype-set! <VkDeviceCreateInfo> (sType) dfp VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO)
          (ftype-set! <VkDeviceCreateInfo> (queueCreateInfoCount) dfp 1)
          (ftype-set! <VkDeviceCreateInfo> (pQueueCreateInfos) dfp qci)
          (vk-check 'vkCreateDevice (vkCreateDevice pd dci 0 out))
          (let ((device (foreign-ref 'uptr out 0)))
            (display (list 'device device)) (newline)
            ;; Queue
            (let ((qout (foreign-alloc/zero 8)))
              (vkGetDeviceQueue device qfi 0 qout)
              (let ((queue (foreign-ref 'uptr qout 0)))
                (display (list 'queue queue)) (newline)
                ;; Command pool
                (let* ((cpi (foreign-alloc/zero (ftype-sizeof <VkCommandPoolCreateInfo>)))
                       (cfp (make-ftype-pointer <VkCommandPoolCreateInfo> cpi))
                       (cpout (foreign-alloc/zero 8)))
                  (ftype-set! <VkCommandPoolCreateInfo> (sType) cfp
                              VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO)
                  (ftype-set! <VkCommandPoolCreateInfo> (flags) cfp
                              VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT)
                  (ftype-set! <VkCommandPoolCreateInfo> (queueFamilyIndex) cfp qfi)
                  (vk-check 'vkCreateCommandPool
                            (vkCreateCommandPool device cpi 0 cpout))
                  (let ((cp (foreign-ref 'unsigned-64 cpout 0)))
                    (display (list 'command-pool cp)) (newline)
                    ;; Render pass — use window.scm's color format default
                    ;; (B8G8R8A8_UNORM is the typical swapchain format).
                    (let* ((att (foreign-alloc/zero (ftype-sizeof <VkAttachmentDescription>)))
                           (ref (foreign-alloc/zero (ftype-sizeof <VkAttachmentReference>)))
                           (sub (foreign-alloc/zero (ftype-sizeof <VkSubpassDescription>)))
                           (rci (foreign-alloc/zero (ftype-sizeof <VkRenderPassCreateInfo>)))
                           (afp (make-ftype-pointer <VkAttachmentDescription> att))
                           (rfp (make-ftype-pointer <VkAttachmentReference> ref))
                           (sfp (make-ftype-pointer <VkSubpassDescription> sub))
                           (rfp2 (make-ftype-pointer <VkRenderPassCreateInfo> rci))
                           (rpout (foreign-alloc/zero 8)))
                      (ftype-set! <VkAttachmentDescription> (format) afp VK_FORMAT_B8G8R8A8_UNORM)
                      (ftype-set! <VkAttachmentDescription> (samples) afp VK_SAMPLE_COUNT_1_BIT)
                      (ftype-set! <VkAttachmentDescription> (loadOp) afp VK_ATTACHMENT_LOAD_OP_CLEAR)
                      (ftype-set! <VkAttachmentDescription> (storeOp) afp VK_ATTACHMENT_STORE_OP_STORE)
                      (ftype-set! <VkAttachmentDescription> (initialLayout) afp VK_IMAGE_LAYOUT_UNDEFINED)
                      (ftype-set! <VkAttachmentDescription> (finalLayout) afp VK_IMAGE_LAYOUT_PRESENT_SRC_KHR)
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
                      (vk-check 'vkCreateRenderPass
                                (vkCreateRenderPass device rci 0 rpout))
                      (let ((rp (foreign-ref 'unsigned-64 rpout 0)))
                        (display (list 'render-pass rp)) (newline)
                        ;; Now exercise build-text-pipeline.
                        (let ((tp (build-text-pipeline device pd rp queue cp)))
                          (display "build-text-pipeline OK") (newline)
                          (display (list 'pipeline (text-pipeline-pipeline tp)
                                         'descriptor-set (text-pipeline-descriptor-set tp)
                                         'instance-buffer (text-pipeline-instance-buffer tp)
                                         'mapped (text-pipeline-instance-mapped tp)))
                          (newline)
                          (destroy-text-pipeline! device tp)
                          (display "destroy-text-pipeline! OK") (newline))
                        (vkDestroyRenderPass device rp 0))
                      (vkDestroyCommandPool device cp 0))))
                (vkDestroyDevice device 0)))))))))
