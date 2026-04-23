(library (letloop desktop vulkan)
  (export
   ;; instance lifecycle
   vulkan-create-instance
   vulkan-destroy-instance
   call-with-vulkan-instance

   ;; enumeration
   vulkan-physical-devices
   vulkan-physical-device-name
   vulkan-physical-device-properties
   vulkan-device-info?
   vulkan-device-info-api-version
   vulkan-device-info-driver-version
   vulkan-device-info-vendor-id
   vulkan-device-info-device-id
   vulkan-device-info-device-type
   vulkan-device-info-device-name
   vulkan-queue-family-indices
   vulkan-display-properties
   vulkan-display-modes

   ;; high-level
   vulkan-describe)
  (import
   (chezscheme)
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

  (define (c-string-alloc s)
    ;; allocates a null-terminated UTF-8 byte sequence; caller owns.
    (let* ((bv  (string->utf8 s))
           (len (bytevector-length bv))
           (p   (foreign-alloc (+ len 1))))
      (do ((i 0 (+ i 1))) ((= i len))
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)))
      (foreign-set! 'unsigned-8 p len 0)
      p))

  (define (with-cstring-array strings proc)
    ;; calls proc with (array-ptr count); frees everything on exit.
    (let* ((n       (length strings))
           (bufs    (map c-string-alloc strings))
           (arr     (foreign-alloc (* (max 1 n) 8))))
      (do ((i 0 (+ i 1)) (bs bufs (cdr bs)))
          ((null? bs))
        (foreign-set! 'uptr arr (* i 8) (car bs)))
      (dynamic-wind
       void
       (lambda () (proc arr n))
       (lambda ()
         (foreign-free arr)
         (for-each foreign-free bufs)))))

  (define (ptr->cstring ptr)
    ;; reads a null-terminated UTF-8 byte sequence at ptr, returns string.
    ;; Safe for ICD-provided strings (VkDisplayPropertiesKHR.displayName).
    (if (zero? ptr)
        ""
        (let loop ((i 0) (bs '()))
          (let ((b (foreign-ref 'unsigned-8 ptr i)))
            (if (zero? b)
                (utf8->string (u8-list->bytevector (reverse bs)))
                (loop (+ i 1) (cons b bs)))))))

  (define (read-cstring-field/n base-addr len)
    ;; Reads up to len bytes starting at base-addr, stopping at first NUL.
    ;; Used for inline char arrays like VkPhysicalDeviceProperties.deviceName.
    (let loop ((i 0) (bs '()))
      (if (= i len)
          (utf8->string (u8-list->bytevector (reverse bs)))
          (let ((b (foreign-ref 'unsigned-8 base-addr i)))
            (if (zero? b)
                (utf8->string (u8-list->bytevector (reverse bs)))
                (loop (+ i 1) (cons b bs)))))))

  ;; ----------------------------------------------------------------
  ;; Instance
  ;; ----------------------------------------------------------------

  (define DEFAULT_INSTANCE_EXTENSIONS
    (list VK_KHR_SURFACE_EXTENSION_NAME
          VK_KHR_DISPLAY_EXTENSION_NAME))

  ;; Vulkan API version helper: uint32 packed as (major<<22)|(minor<<12)|patch
  (define (make-api-version major minor patch)
    (bitwise-ior
     (bitwise-arithmetic-shift-left major 22)
     (bitwise-arithmetic-shift-left minor 12)
     patch))

  (define (vulkan-create-instance application-name)
    (define app-info   (foreign-alloc/zero (ftype-sizeof <VkApplicationInfo>)))
    (define info       (foreign-alloc/zero (ftype-sizeof <VkInstanceCreateInfo>)))
    (define out-handle (foreign-alloc/zero 8))
    (define app-name-p (c-string-alloc application-name))
    (define engine-p   (c-string-alloc "letloop"))
    (define app-info-ptr   (make-ftype-pointer <VkApplicationInfo> app-info))
    (define info-ptr       (make-ftype-pointer <VkInstanceCreateInfo> info))
    (dynamic-wind
     void
     (lambda ()
       (ftype-set! <VkApplicationInfo> (sType)              app-info-ptr
                   VK_STRUCTURE_TYPE_APPLICATION_INFO)
       (ftype-set! <VkApplicationInfo> (pApplicationName)   app-info-ptr app-name-p)
       (ftype-set! <VkApplicationInfo> (applicationVersion) app-info-ptr
                   (make-api-version 0 1 0))
       (ftype-set! <VkApplicationInfo> (pEngineName)        app-info-ptr engine-p)
       (ftype-set! <VkApplicationInfo> (engineVersion)      app-info-ptr
                   (make-api-version 0 1 0))
       (ftype-set! <VkApplicationInfo> (apiVersion)         app-info-ptr
                   (make-api-version 1 0 0))

       (with-cstring-array DEFAULT_INSTANCE_EXTENSIONS
         (lambda (exts-arr count)
           (ftype-set! <VkInstanceCreateInfo> (sType)             info-ptr
                       VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO)
           (ftype-set! <VkInstanceCreateInfo> (pApplicationInfo)  info-ptr app-info)
           (ftype-set! <VkInstanceCreateInfo> (enabledExtensionCount)   info-ptr count)
           (ftype-set! <VkInstanceCreateInfo> (ppEnabledExtensionNames) info-ptr exts-arr)
           (vk-check 'vulkan-create-instance
                     (vkCreateInstance info 0 out-handle))))
       (pk 'vulkan-create-instance 'handle (foreign-ref 'uptr out-handle 0))
       (foreign-ref 'uptr out-handle 0))
     (lambda ()
       (foreign-free out-handle)
       (foreign-free info)
       (foreign-free app-info)
       (foreign-free app-name-p)
       (foreign-free engine-p))))

  (define (vulkan-destroy-instance instance)
    (vkDestroyInstance instance 0))

  (define (call-with-vulkan-instance application-name proc)
    (let ((instance (vulkan-create-instance application-name)))
      (dynamic-wind
       void
       (lambda () (proc instance))
       (lambda () (vulkan-destroy-instance instance)))))

  ;; ----------------------------------------------------------------
  ;; Physical device enumeration
  ;; ----------------------------------------------------------------

  (define (vulkan-physical-devices instance)
    (let ((count-p (foreign-alloc/zero 4)))
      (dynamic-wind
       void
       (lambda ()
         (vk-check 'vulkan-physical-devices/count
                   (vkEnumeratePhysicalDevices instance count-p 0))
         (let ((n (foreign-ref 'unsigned-32 count-p 0)))
           (if (zero? n)
               '()
               (let ((arr (foreign-alloc (* n 8))))
                 (dynamic-wind
                  void
                  (lambda ()
                    (vk-check 'vulkan-physical-devices/fill
                              (vkEnumeratePhysicalDevices instance count-p arr))
                    (let loop ((i 0) (out '()))
                      (if (= i n)
                          (reverse out)
                          (loop (+ i 1)
                                (cons (foreign-ref 'uptr arr (* i 8)) out)))))
                  (lambda () (foreign-free arr)))))))
       (lambda () (foreign-free count-p)))))

  ;; A Scheme-side mirror of VkPhysicalDeviceProperties with the fields we
  ;; actually care about.
  (define-record-type vulkan-device-info
    (fields
     (immutable api-version)
     (immutable driver-version)
     (immutable vendor-id)
     (immutable device-id)
     (immutable device-type)
     (immutable device-name)))

  (define (device-type-name t)
    (case t
      ((0) "other")
      ((1) "integrated-gpu")
      ((2) "discrete-gpu")
      ((3) "virtual-gpu")
      ((4) "cpu")
      (else "unknown")))

  (define (vulkan-physical-device-name pd)
    (vulkan-device-info-device-name
     (vulkan-physical-device-properties pd)))

  (define (vulkan-physical-device-properties pd)
    (let* ((p   (foreign-alloc/zero (ftype-sizeof <VkPhysicalDeviceProperties>)))
           (ptr (make-ftype-pointer <VkPhysicalDeviceProperties> p)))
      (dynamic-wind
       void
       (lambda ()
         (vkGetPhysicalDeviceProperties pd p)
         ;; deviceName is a 256-byte inline char[] at offset 20.
         (make-vulkan-device-info
          (ftype-ref <VkPhysicalDeviceProperties> (apiVersion)    ptr)
          (ftype-ref <VkPhysicalDeviceProperties> (driverVersion) ptr)
          (ftype-ref <VkPhysicalDeviceProperties> (vendorID)      ptr)
          (ftype-ref <VkPhysicalDeviceProperties> (deviceID)      ptr)
          (device-type-name
           (ftype-ref <VkPhysicalDeviceProperties> (deviceType)   ptr))
          (read-cstring-field/n (+ p 20) 256)))
       (lambda () (foreign-free p)))))

  ;; ----------------------------------------------------------------
  ;; Queue family query
  ;; ----------------------------------------------------------------

  (define (vulkan-queue-family-indices pd)
    (let ((count-p (foreign-alloc/zero 4)))
      (dynamic-wind
       void
       (lambda ()
         (vkGetPhysicalDeviceQueueFamilyProperties pd count-p 0)
         (let ((n (foreign-ref 'unsigned-32 count-p 0)))
           (if (zero? n)
               '()
               (let* ((sz  (ftype-sizeof <VkQueueFamilyProperties>))
                      (arr (foreign-alloc/zero (* n sz))))
                 (dynamic-wind
                  void
                  (lambda ()
                    (vkGetPhysicalDeviceQueueFamilyProperties pd count-p arr)
                    (let loop ((i 0) (out '()))
                      (if (= i n)
                          (reverse out)
                          (let* ((base (+ arr (* i sz)))
                                 (fp   (make-ftype-pointer
                                        <VkQueueFamilyProperties> base))
                                 (flags (ftype-ref <VkQueueFamilyProperties>
                                                   (queueFlags) fp))
                                 (cnt   (ftype-ref <VkQueueFamilyProperties>
                                                   (queueCount) fp)))
                            (loop (+ i 1)
                                  (cons (list i flags cnt) out))))))
                  (lambda () (foreign-free arr)))))))
       (lambda () (foreign-free count-p)))))

  ;; ----------------------------------------------------------------
  ;; Display + mode enumeration (VK_KHR_display)
  ;; ----------------------------------------------------------------

  (define-record-type vulkan-display
    (fields
     (immutable handle)            ; VkDisplayKHR (uint64)
     (immutable name)              ; string
     (immutable physical-width-mm)
     (immutable physical-height-mm)
     (immutable width-px)
     (immutable height-px)))

  (define-record-type vulkan-display-mode
    (fields
     (immutable handle)    ; VkDisplayModeKHR (uint64)
     (immutable width)
     (immutable height)
     (immutable refresh-rate-millihz)))

  (define (vulkan-display-properties pd)
    (let ((count-p (foreign-alloc/zero 4)))
      (dynamic-wind
       void
       (lambda ()
         (vk-check 'vulkan-display-properties/count
                   (vkGetPhysicalDeviceDisplayPropertiesKHR pd count-p 0))
         (let ((n (foreign-ref 'unsigned-32 count-p 0)))
           (if (zero? n)
               '()
               (let* ((sz  (ftype-sizeof <VkDisplayPropertiesKHR>))
                      (arr (foreign-alloc/zero (* n sz))))
                 (dynamic-wind
                  void
                  (lambda ()
                    (vk-check 'vulkan-display-properties/fill
                              (vkGetPhysicalDeviceDisplayPropertiesKHR pd count-p arr))
                    (let loop ((i 0) (out '()))
                      (if (= i n)
                          (reverse out)
                          (let* ((base (+ arr (* i sz)))
                                 (fp   (make-ftype-pointer
                                        <VkDisplayPropertiesKHR> base))
                                 (handle  (ftype-ref <VkDisplayPropertiesKHR>
                                                     (display) fp))
                                 (name-p  (ftype-ref <VkDisplayPropertiesKHR>
                                                     (displayName) fp))
                                 (dim-w   (ftype-ref <VkDisplayPropertiesKHR>
                                                     (physicalDimensions width) fp))
                                 (dim-h   (ftype-ref <VkDisplayPropertiesKHR>
                                                     (physicalDimensions height) fp))
                                 (res-w   (ftype-ref <VkDisplayPropertiesKHR>
                                                     (physicalResolution width) fp))
                                 (res-h   (ftype-ref <VkDisplayPropertiesKHR>
                                                     (physicalResolution height) fp)))
                            (loop (+ i 1)
                                  (cons (make-vulkan-display
                                         handle
                                         (ptr->cstring name-p)
                                         dim-w dim-h res-w res-h)
                                        out))))))
                  (lambda () (foreign-free arr)))))))
       (lambda () (foreign-free count-p)))))

  (define (vulkan-display-modes pd display-handle)
    (let ((count-p (foreign-alloc/zero 4)))
      (dynamic-wind
       void
       (lambda ()
         (vk-check 'vulkan-display-modes/count
                   (vkGetDisplayModePropertiesKHR pd display-handle count-p 0))
         (let ((n (foreign-ref 'unsigned-32 count-p 0)))
           (if (zero? n)
               '()
               (let* ((sz  (ftype-sizeof <VkDisplayModePropertiesKHR>))
                      (arr (foreign-alloc/zero (* n sz))))
                 (dynamic-wind
                  void
                  (lambda ()
                    (vk-check 'vulkan-display-modes/fill
                              (vkGetDisplayModePropertiesKHR pd display-handle count-p arr))
                    (let loop ((i 0) (out '()))
                      (if (= i n)
                          (reverse out)
                          (let* ((base (+ arr (* i sz)))
                                 (fp   (make-ftype-pointer
                                        <VkDisplayModePropertiesKHR> base))
                                 (handle (ftype-ref <VkDisplayModePropertiesKHR>
                                                    (displayMode) fp))
                                 (w (ftype-ref <VkDisplayModePropertiesKHR>
                                               (parameters visibleRegion width) fp))
                                 (h (ftype-ref <VkDisplayModePropertiesKHR>
                                               (parameters visibleRegion height) fp))
                                 (r (ftype-ref <VkDisplayModePropertiesKHR>
                                               (parameters refreshRate) fp)))
                            (loop (+ i 1)
                                  (cons (make-vulkan-display-mode handle w h r)
                                        out))))))
                  (lambda () (foreign-free arr)))))))
       (lambda () (foreign-free count-p)))))

  ;; ----------------------------------------------------------------
  ;; vulkan-describe — high-level dump, used by M2.1 deliverable.
  ;; ----------------------------------------------------------------

  (define (vulkan-describe port)
    (call-with-vulkan-instance "letloop-desktop"
     (lambda (instance)
       (let ((pds (vulkan-physical-devices instance)))
         (format port "vulkan: ~a physical device(s)\n" (length pds))
         (for-each
          (lambda (pd)
            (let ((props (vulkan-physical-device-properties pd))
                  (qfs   (vulkan-queue-family-indices pd)))
              (format port "  device: ~a (~a, vendor=~a:~a, driver=~a, api=~a)\n"
                      (vulkan-device-info-device-name    props)
                      (vulkan-device-info-device-type    props)
                      (vulkan-device-info-vendor-id      props)
                      (vulkan-device-info-device-id      props)
                      (vulkan-device-info-driver-version props)
                      (vulkan-device-info-api-version    props))
              (for-each
               (lambda (qf)
                 (let ((idx (car qf)) (flags (cadr qf)) (cnt (caddr qf)))
                   (format port "    queue family ~a: flags=#x~x count=~a~a\n"
                           idx flags cnt
                           (if (not (zero? (bitwise-and flags VK_QUEUE_GRAPHICS_BIT)))
                               " (graphics)" ""))))
               qfs)
              (let ((disps (vulkan-display-properties pd)))
                (format port "    displays: ~a\n" (length disps))
                (for-each
                 (lambda (d)
                   (format port "      ~a: ~ax~a px (~amm x ~amm)\n"
                           (vulkan-display-name d)
                           (vulkan-display-width-px d)
                           (vulkan-display-height-px d)
                           (vulkan-display-physical-width-mm d)
                           (vulkan-display-physical-height-mm d))
                   (let ((modes (vulkan-display-modes pd (vulkan-display-handle d))))
                     (for-each
                      (lambda (m)
                        (format port "         mode: ~ax~a @ ~a.~a Hz\n"
                                (vulkan-display-mode-width m)
                                (vulkan-display-mode-height m)
                                (quotient  (vulkan-display-mode-refresh-rate-millihz m) 1000)
                                (remainder (vulkan-display-mode-refresh-rate-millihz m) 1000)))
                      modes)))
                 disps))))
          pds))))))
