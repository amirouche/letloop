#!chezscheme
;; Minimal DRM mode enumeration — just enough to answer "what display is
;; attached and what's its preferred mode?" The M2.0 deliverable.
;;
;; All the interesting DRM ioctls are "two-pass": call once with count
;; fields zeroed and pointer fields NULL; the kernel writes the actual
;; sizes back. Then allocate buffers, stash their addresses in the same
;; struct, and call again — the kernel fills the buffers. We hide this
;; pattern behind drm-get-resources and drm-get-connector.
;;
;; Struct layouts are copied verbatim from include/uapi/drm/drm_mode.h;
;; offsets below are byte-exact on x86_64 / aarch64 (same ABI). If you
;; touch them, cross-check against that header.
(library (letloop desktop drm)
  (export
   ;; resources
   drm-get-resources
   drm-resources?
   drm-resources-connector-ids
   drm-resources-encoder-ids
   drm-resources-crtc-ids
   drm-resources-fb-ids
   drm-resources-min-width
   drm-resources-max-width
   drm-resources-min-height
   drm-resources-max-height

   ;; connector
   drm-get-connector
   drm-connector?
   drm-connector-id
   drm-connector-type
   drm-connector-type-id
   drm-connector-type-name
   drm-connector-name
   drm-connector-connection
   drm-connector-connection-name
   drm-connector-mm-width
   drm-connector-mm-height
   drm-connector-modes
   drm-connector-preferred-mode

   ;; mode
   drm-mode?
   drm-mode-clock
   drm-mode-hdisplay
   drm-mode-vdisplay
   drm-mode-vrefresh
   drm-mode-flags
   drm-mode-type
   drm-mode-name
   drm-mode-preferred?

   ;; high-level formatter
   drm-describe-connectors)
  (import
   (chezscheme)
   (letloop desktop ioctl))

  ;; ---------- ioctl request codes ----------

  (define DRM_IOCTL_MODE_GETRESOURCES (_IOWR #x64 #xA0 64))
  (define DRM_IOCTL_MODE_GETCONNECTOR (_IOWR #x64 #xA7 80))

  ;; ---------- connector type / state lookup ----------

  (define connector-type-names
    '#("Unknown" "VGA" "DVI-I" "DVI-D" "DVI-A" "Composite" "SVIDEO"
       "LVDS" "Component" "9PinDIN" "DP" "HDMI-A" "HDMI-B" "TV"
       "eDP" "Virtual" "DSI" "DPI" "Writeback" "SPI" "USB"))

  (define (drm-connector-type-name conn)
    (let ((type (drm-connector-type conn)))
      (if (< type (vector-length connector-type-names))
          (vector-ref connector-type-names type)
          "Unknown")))

  (define (drm-connector-name conn)
    (format #f "~a-~a"
            (drm-connector-type-name conn)
            (drm-connector-type-id conn)))

  (define (drm-connector-connection-name conn)
    (case (drm-connector-connection conn)
      ((1) "connected")
      ((2) "disconnected")
      (else "unknown")))

  ;; DRM_MODE_TYPE_PREFERRED — see drm_modes.h.
  (define DRM_MODE_TYPE_PREFERRED 8)

  (define (drm-mode-preferred? mode)
    (not (zero? (bitwise-and (drm-mode-type mode) DRM_MODE_TYPE_PREFERRED))))

  ;; ---------- drm-resources record ----------

  (define-record-type drm-resources
    (fields
     (immutable fb-ids)
     (immutable crtc-ids)
     (immutable connector-ids)
     (immutable encoder-ids)
     (immutable min-width)
     (immutable max-width)
     (immutable min-height)
     (immutable max-height)))

  ;; ---------- drm-connector record ----------

  (define-record-type drm-connector
    (fields
     (immutable id)
     (immutable encoder-id)
     (immutable type)
     (immutable type-id)
     (immutable connection)
     (immutable mm-width)
     (immutable mm-height)
     (immutable subpixel)
     (immutable modes)         ; list of drm-mode
     (immutable encoder-ids))) ; list of compatible encoder ids

  ;; ---------- drm-mode record ----------

  (define-record-type drm-mode
    (fields
     (immutable clock)
     (immutable hdisplay)
     (immutable vdisplay)
     (immutable vrefresh)
     (immutable flags)
     (immutable type)
     (immutable name)))

  ;; ---------- drm-get-resources ----------
  ;;
  ;; struct drm_mode_card_res (64 bytes):
  ;;    0 u64 fb_id_ptr
  ;;    8 u64 crtc_id_ptr
  ;;   16 u64 connector_id_ptr
  ;;   24 u64 encoder_id_ptr
  ;;   32 u32 count_fbs
  ;;   36 u32 count_crtcs
  ;;   40 u32 count_connectors
  ;;   44 u32 count_encoders
  ;;   48 u32 min_width
  ;;   52 u32 max_width
  ;;   56 u32 min_height
  ;;   60 u32 max_height
  (define (drm-get-resources drm-fd)

    (define (zero-struct! p)
      (do ((i 0 (+ i 8)))
          ((= i 64))
        (foreign-set! 'unsigned-64 p i 0)))

    (define (call-once p)
      (let-values (((ret errno) (sys-ioctl-ptr drm-fd DRM_IOCTL_MODE_GETRESOURCES p)))
        (errno-check 'drm-get-resources ret errno)))

    (define (read-ids-array base-addr count)
      (let loop ((i 0) (out '()))
        (if (= i count)
            (reverse out)
            (loop (+ i 1)
                  (cons (foreign-ref 'unsigned-32 base-addr (* i 4)) out)))))

    (let ((res (foreign-alloc 64)))
      (dynamic-wind
       void
       (lambda ()
         ;; Pass 1: counts only.
         (zero-struct! res)
         (call-once res)
         (let ((n-fb   (foreign-ref 'unsigned-32 res 32))
               (n-crtc (foreign-ref 'unsigned-32 res 36))
               (n-conn (foreign-ref 'unsigned-32 res 40))
               (n-enc  (foreign-ref 'unsigned-32 res 44)))
           ;; Pass 2: allocate backing storage and refill.
           (let ((fb-buf   (and (positive? n-fb)   (foreign-alloc (* 4 n-fb))))
                 (crtc-buf (and (positive? n-crtc) (foreign-alloc (* 4 n-crtc))))
                 (conn-buf (and (positive? n-conn) (foreign-alloc (* 4 n-conn))))
                 (enc-buf  (and (positive? n-enc)  (foreign-alloc (* 4 n-enc)))))
             (dynamic-wind
              void
              (lambda ()
                (foreign-set! 'unsigned-64 res  0 (or fb-buf   0))
                (foreign-set! 'unsigned-64 res  8 (or crtc-buf 0))
                (foreign-set! 'unsigned-64 res 16 (or conn-buf 0))
                (foreign-set! 'unsigned-64 res 24 (or enc-buf  0))
                (call-once res)
                (make-drm-resources
                 (if fb-buf   (read-ids-array fb-buf   n-fb)   '())
                 (if crtc-buf (read-ids-array crtc-buf n-crtc) '())
                 (if conn-buf (read-ids-array conn-buf n-conn) '())
                 (if enc-buf  (read-ids-array enc-buf  n-enc)  '())
                 (foreign-ref 'unsigned-32 res 48)
                 (foreign-ref 'unsigned-32 res 52)
                 (foreign-ref 'unsigned-32 res 56)
                 (foreign-ref 'unsigned-32 res 60)))
              (lambda ()
                (when fb-buf   (foreign-free fb-buf))
                (when crtc-buf (foreign-free crtc-buf))
                (when conn-buf (foreign-free conn-buf))
                (when enc-buf  (foreign-free enc-buf)))))))
       (lambda () (foreign-free res)))))

  ;; ---------- drm-get-connector ----------
  ;;
  ;; struct drm_mode_get_connector (80 bytes):
  ;;    0 u64 encoders_ptr
  ;;    8 u64 modes_ptr
  ;;   16 u64 props_ptr
  ;;   24 u64 prop_values_ptr
  ;;   32 u32 count_modes
  ;;   36 u32 count_props
  ;;   40 u32 count_encoders
  ;;   44 u32 encoder_id
  ;;   48 u32 connector_id
  ;;   52 u32 connector_type
  ;;   56 u32 connector_type_id
  ;;   60 u32 connection
  ;;   64 u32 mm_width
  ;;   68 u32 mm_height
  ;;   72 u32 subpixel
  ;;   76 u32 pad
  ;;
  ;; struct drm_mode_modeinfo (68 bytes):
  ;;    0 u32 clock
  ;;    4 u16 hdisplay
  ;;    6 u16 hsync_start
  ;;    8 u16 hsync_end
  ;;   10 u16 htotal
  ;;   12 u16 hskew
  ;;   14 u16 vdisplay
  ;;   16 u16 vsync_start
  ;;   18 u16 vsync_end
  ;;   20 u16 vtotal
  ;;   22 u16 vscan
  ;;   24 u32 vrefresh
  ;;   28 u32 flags
  ;;   32 u32 type
  ;;   36 char name[32]
  (define drm-mode-sizeof 68)

  (define (read-mode-at base-addr index)
    (let ((p (+ base-addr (* index drm-mode-sizeof))))
      (make-drm-mode
       (foreign-ref 'unsigned-32 p  0)
       (foreign-ref 'unsigned-16 p  4)
       (foreign-ref 'unsigned-16 p 14)
       (foreign-ref 'unsigned-32 p 24)
       (foreign-ref 'unsigned-32 p 28)
       (foreign-ref 'unsigned-32 p 32)
       (read-cstring-fixed p 36 32))))

  (define (read-cstring-fixed base off max-len)
    (let loop ((i 0) (chars '()))
      (if (= i max-len)
          (list->string (reverse chars))
          (let ((b (foreign-ref 'unsigned-8 base (+ off i))))
            (if (zero? b)
                (list->string (reverse chars))
                (loop (+ i 1) (cons (integer->char b) chars)))))))

  (define (drm-get-connector drm-fd connector-id)

    (define (zero-struct! p)
      (do ((i 0 (+ i 8)))
          ((= i 80))
        (foreign-set! 'unsigned-64 p i 0))
      (foreign-set! 'unsigned-32 p 48 connector-id))

    (define (call-once p)
      (let-values (((ret errno) (sys-ioctl-ptr drm-fd DRM_IOCTL_MODE_GETCONNECTOR p)))
        (errno-check 'drm-get-connector ret errno)))

    (let ((conn (foreign-alloc 80)))
      (dynamic-wind
       void
       (lambda ()
         (zero-struct! conn)
         (call-once conn)
         (let ((n-modes (foreign-ref 'unsigned-32 conn 32))
               (n-enc   (foreign-ref 'unsigned-32 conn 40)))
           (let ((modes-buf (and (positive? n-modes) (foreign-alloc (* drm-mode-sizeof n-modes))))
                 (enc-buf   (and (positive? n-enc)   (foreign-alloc (* 4 n-enc)))))
             (dynamic-wind
              void
              (lambda ()
                ;; Pass 2: keep count_modes and count_encoders as the kernel
                ;; wrote them; fill in the matching pointers. Zero
                ;; count_props because we haven't allocated props_ptr — the
                ;; kernel rejects count_props > 0 with NULL pointers.
                (foreign-set! 'unsigned-64 conn  0 (or enc-buf   0))
                (foreign-set! 'unsigned-64 conn  8 (or modes-buf 0))
                (foreign-set! 'unsigned-32 conn 36 0)
                (call-once conn)
                (make-drm-connector
                 (foreign-ref 'unsigned-32 conn 48)
                 (foreign-ref 'unsigned-32 conn 44)
                 (foreign-ref 'unsigned-32 conn 52)
                 (foreign-ref 'unsigned-32 conn 56)
                 (foreign-ref 'unsigned-32 conn 60)
                 (foreign-ref 'unsigned-32 conn 64)
                 (foreign-ref 'unsigned-32 conn 68)
                 (foreign-ref 'unsigned-32 conn 72)
                 (if modes-buf
                     (let loop ((i 0) (out '()))
                       (if (= i n-modes)
                           (reverse out)
                           (loop (+ i 1) (cons (read-mode-at modes-buf i) out))))
                     '())
                 (if enc-buf
                     (let loop ((i 0) (out '()))
                       (if (= i n-enc)
                           (reverse out)
                           (loop (+ i 1)
                                 (cons (foreign-ref 'unsigned-32 enc-buf (* i 4))
                                       out))))
                     '())))
              (lambda ()
                (when modes-buf (foreign-free modes-buf))
                (when enc-buf   (foreign-free enc-buf)))))))
       (lambda () (foreign-free conn)))))

  (define (drm-connector-preferred-mode conn)
    (let ((modes (drm-connector-modes conn)))
      (or (find drm-mode-preferred? modes)
          (and (pair? modes) (car modes)))))

  ;; ---------- describe ----------

  (define (drm-describe-connectors drm-fd port)
    (let* ((res (drm-get-resources drm-fd))
           (ids (drm-resources-connector-ids res)))
      (format port "display envelope: ~ax~a ... ~ax~a\n"
              (drm-resources-min-width res)
              (drm-resources-min-height res)
              (drm-resources-max-width res)
              (drm-resources-max-height res))
      (format port "connectors: ~a\n" (length ids))
      (for-each
       (lambda (id)
         (let* ((c (drm-get-connector drm-fd id))
                (pref (drm-connector-preferred-mode c)))
           (format port "  ~a: ~a (~amm x ~amm)\n"
                   (drm-connector-name c)
                   (drm-connector-connection-name c)
                   (drm-connector-mm-width c)
                   (drm-connector-mm-height c))
           (when pref
             (format port "    preferred: ~ax~a @ ~aHz  \"~a\"\n"
                     (drm-mode-hdisplay pref)
                     (drm-mode-vdisplay pref)
                     (drm-mode-vrefresh pref)
                     (drm-mode-name pref)))))
       ids))))
