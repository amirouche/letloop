# letloop desktop — milestone 2 plan

A handoff-friendly map of what's done, what's immediately next, and what's beyond. This file is the source of truth — keep it in sync with the code.

## Status

| Milestone   | Description                                                       | State    | Commit    |
|-------------|-------------------------------------------------------------------|----------|-----------|
| M2.0        | Seat acquisition + DRM connector enumeration                      | Done     | 325eb57   |
| M2.1 chunk A | Vulkan FFI bindings + instance/device/display enumeration         | Done     | 8529cb2   |
| M2.1 chunk B | Display-plane enumeration + graphics-queue picker + system deps   | Done     | cb4f78f   |
| M2.1 chunk C | Surface + swapchain + magenta clear loop (the deliverable)        | Done     | cd0b1cf   |
| M2.2 chunk A | FFI for graphics pipeline + descriptors + buffers + memory        | Done     | 0803768   |
| M2.2 chunk B | PSF2 reader with Unicode table                                    | Done     | f1ace5d   |
| M2.2 chunk C-1 | Atlas builder for PSF2 glyphs                                    | Done     | 875998e   |
| M2.2 chunk C-2 | Text pipeline GLSL + embedded SPIR-V                             | Done     | 4959f76   |
| M2.2 chunk D-1 | Bundle FullCyrAsia-DejaVu30x16 PSF2                              | Done     | ab67824   |
| M2.2 chunk D-2 | Render pass replaces clear-image loop                            | Done     | 508345d   |
| M2.2 chunk D-3 | Atlas, descriptor, pipeline construction (llvmpipe-verified)    | Done     | ff3ca29   |
| M2.2 chunk D-4 | window-draw-text! + per-frame draw (llvmpipe-verified)         | Done     | c8a8a62   |
| M2.3 chunk E-1 | evdev input_event parser + sync read wrapper                     | Done     | 2b05e83   |
| M2.3 chunk E-2 | US-QWERTY scancode→char mapping                                  | Done     | afd1a58   |
| M2.3 chunk E-3 | Keyboard event pump (sync, io_uring deferred)                    | Done     | ed182f1   |
| M2.3 chunk E-4 | Line editor + keyboard wiring in window                          | Done     | b42a1ec   |
| M2.4        | Graphical REPL via window line editor (no port redirection yet)    | Done     | a9ab14a   |
| M2.x F-1    | Per-instance color, REPL errors render in red                      | Done     | f3cdcbd   |
| M2.x F-2    | Draw-path llvmpipe smoke harness                                  | Done     | a10eef3   |
| M2.x F-3    | Draw-smoke verifies pixels (vkCmdCopyImageToBuffer + asserts)     | Done     | a2ae365   |
| M2.x F-4    | VT_PROCESS handling refuses Alt+Fn switches                       | Done     | f45fc92   |
| M2.x F-5    | SIGTERM / SIGSEGV trap to release the seat                        | Done     | 07257f8   |
| M2.x F-6    | io_uring single-shot keyboard variant                              | Done     | 48cc612   |
| M2.x F-7    | EVIOCGBIT keyboard classification                                  | Done     | 48cb388   |
| libtls.so   | LibreTLS — handled at the distro level (see CLAUDE.md update)      | Pending  | —         |

## Immediate next: M2.1 chunk C — `desktop/window.scm`

### Deliverable
`letloop desktop` after seat-take should fill the screen with magenta. From a Scheme prompt (once M2.4 lands) `(window-clear-color! w 0.2 0.5 0.9)` reconfigures the color live. Until then a `LETLOOP_DESKTOP_COLOR` env var (or just hardcoded magenta) is fine.

### Files to create
- `src/letloop/desktop/window.scm` — record + render loop.

### Files to modify
- `src/letloop/desktop.scm` — replace `park-forever` after `vulkan-describe` with `call-with-window` + `window-run!`.

### Window record
```scheme
(define-record-type window
  (fields
    (mutable released?)
    instance physical-device queue-family-index
    device queue
    surface swapchain
    format extent-width extent-height
    images           ; list of u64 VkImage
    command-pool command-buffer
    image-available-sem render-finished-sem in-flight-fence
    ;; pre-allocated scratch foreign buffers, freed in window-close
    scratch          ; list of foreign-alloc'd addresses
    (mutable r) (mutable g) (mutable b) (mutable a)))
```

### `window-open instance` — sequence
1. Pick first physical device from `vulkan-physical-devices`.
2. `vulkan-pick-graphics-queue-family` — bail with informative error if `#f`.
3. `vulkan-display-properties` — bail if empty (likely missing DRM master).
4. First mode from `vulkan-display-modes`.
5. `vulkan-display-plane-properties` — pick plane index 0 (always valid for primary display).
6. `vkCreateDisplayPlaneSurfaceKHR` with `VkDisplaySurfaceCreateInfoKHR`:
   - `displayMode` = mode handle
   - `planeIndex` = 0, `planeStackIndex` = 0
   - `transform` = `VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR`
   - `globalAlpha` = 1.0, `alphaMode` = `VK_DISPLAY_PLANE_ALPHA_OPAQUE_BIT_KHR`
   - `imageExtent` = mode width/height
7. `vkCreateDevice`:
   - `VkDeviceQueueCreateInfo`: queueCount=1, pQueuePriorities=[1.0]
   - `VkDeviceCreateInfo`: enabled extension = `VK_KHR_swapchain`
8. `vkGetDeviceQueue` — store queue.
9. `vkGetPhysicalDeviceSurfaceCapabilitiesKHR` → caps.
10. `vkGetPhysicalDeviceSurfaceFormatsKHR` → first format.
11. `vkCreateSwapchainKHR`:
    - `minImageCount` = `caps.minImageCount` (clamp to `caps.maxImageCount` if non-zero)
    - `imageFormat` / `imageColorSpace` from format
    - `imageExtent` = `caps.currentExtent` (or mode size if currentExtent.width == 0xFFFFFFFF)
    - `imageArrayLayers` = 1
    - `imageUsage` = `VK_IMAGE_USAGE_TRANSFER_DST_BIT`
    - `imageSharingMode` = `VK_SHARING_MODE_EXCLUSIVE`
    - `preTransform` = `caps.currentTransform`
    - `compositeAlpha` = `VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR`
    - `presentMode` = `VK_PRESENT_MODE_FIFO_KHR`
    - `clipped` = 1, `oldSwapchain` = 0
12. `vkGetSwapchainImagesKHR` → list of `VkImage`.
13. `vkCreateCommandPool` with `VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT` + queue family.
14. `vkAllocateCommandBuffers` — one primary buffer (re-recorded each frame).
15. `vkCreateSemaphore` × 2 (default flags).
16. `vkCreateFence` with `VK_FENCE_CREATE_SIGNALED_BIT` (so first-frame `vkWaitForFences` returns immediately).

If any step raises, `window-open` rolls back what's been built so far before re-raising.

### `window-render-frame!` — per frame
1. `vkWaitForFences(in-flight-fence, timeout=UINT64_MAX)`.
2. `vkResetFences(in-flight-fence)`.
3. `vkAcquireNextImageKHR(swapchain, timeout=UINT64_MAX, image-available-sem, fence=0, &image-index)`.
4. Reset+rerecord command buffer for `images[image-index]`:
   - `vkBeginCommandBuffer` with `VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT`
   - barrier `UNDEFINED` → `TRANSFER_DST_OPTIMAL` (src=0, dst=`TRANSFER_WRITE`, srcStage=`TOP_OF_PIPE`, dstStage=`TRANSFER`)
   - `vkCmdClearColorImage` with `VkClearColorValue.float32 = (r,g,b,a)`, range = full image (color aspect, single mip, single layer)
   - barrier `TRANSFER_DST_OPTIMAL` → `PRESENT_SRC_KHR` (src=`TRANSFER_WRITE`, dst=`MEMORY_READ`, srcStage=`TRANSFER`, dstStage=`BOTTOM_OF_PIPE`)
   - `vkEndCommandBuffer`
5. `vkQueueSubmit`:
   - `pWaitSemaphores=[image-available-sem]`, `pWaitDstStageMask=[TRANSFER_BIT]`
   - `pCommandBuffers=[command-buffer]`
   - `pSignalSemaphores=[render-finished-sem]`
   - `fence=in-flight-fence`
6. `vkQueuePresentKHR`:
   - `pWaitSemaphores=[render-finished-sem]`
   - `pSwapchains=[swapchain]`, `pImageIndices=[image-index]`

### `window-run! window`
Tight loop calling `window-render-frame!`. SIGINT is already trapped by `call-with-seat`, which installs a `keyboard-interrupt-handler` that calls `seat-release` and `(exit 0)`. `(exit 0)` unwinds dynamic-wind and runs `window-close` → `vkDeviceWaitIdle` → tears down everything in reverse.

### `window-close` — teardown order
1. `vkDeviceWaitIdle` (so we don't free in-use objects)
2. Destroy fence, semaphores
3. Free command buffers, destroy command pool
4. Destroy swapchain
5. Destroy device
6. Destroy surface
7. Free all scratch foreign buffers

### Constants needed (already exported)
- `VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT` — pool flags
- `VK_FENCE_CREATE_SIGNALED_BIT` — fence flags
- `VK_IMAGE_LAYOUT_*`, `VK_ACCESS_*`, `VK_PIPELINE_STAGE_*` — barriers
- `VK_QUEUE_FAMILY_IGNORED` — non-transfer barriers

### Smoke test
- Sandbox: `vkCreateDisplayPlaneSurfaceKHR` will fail with `VK_ERROR_OUT_OF_HOST_MEMORY` or similar because `vulkan-display-properties` returns 0 displays (no GPU). Confirm `window-open` raises a clean Scheme error; the seat rollback should restore TTY state.
- Real hardware: `letloop desktop` paints the screen magenta; Ctrl-C drops back to text TTY cleanly.

## M2.2 — glyphs

### Deliverable
`(window-draw-text! w "ⵉⵎⵓⵍⴰ" 40 40)` renders the string at (40, 40) px.

### Files
- `src/letloop/desktop/psf2.scm` — load PSF2 glyph bitmaps from a bytevector.
- `src/letloop/desktop/font.scm` — atlas builder, glyph-to-uv mapping.
- `src/letloop/desktop/shader.scm` — embedded SPIR-V bytevectors (vertex + fragment).
- Extend `desktop/window.scm` — graphics pipeline, instanced quad VBO, descriptor set for atlas sampler.

### Approach
- Bundle Unifont PSF2 (covers Tifinagh U+2D30–U+2D7F + Arabic U+0600–U+06FF). Reference at the project root or fetch via Make target.
- One atlas texture (R8 single-channel, 256×N).
- Vertex shader takes a per-instance `vec4 xywh` + `vec4 uv-rect` from a single SSBO; emits a quad.
- Fragment shader samples the atlas, modulates by a foreground color uniform, alpha-tests.
- `window-draw-text!` builds a list of (glyph-id, x, y) triples, looks up the atlas UV, appends to a CPU-side buffer, uploads, draws.

### Half-baked notes
- Codepoint→glyph mapping in PSF2 is via the Unicode table appended to the file. Parse it once on load.
- For RTL Arabic shaping we'll cheat in M2.2: render glyphs in logical order. Real shaping waits for after M2.4.

### Constants/structs to add to FFI
- `VkRenderPass*`, `VkFramebuffer*`, `VkPipeline*`, `VkPipelineLayout*` — full graphics pipeline
- `VkBuffer*`, `VkDeviceMemory*`, `vkAllocateMemory`, `vkBindBufferMemory`, `vkMapMemory`
- `VkDescriptorSet*`, `VkDescriptorPool*`, `VkSampler*`, `VkImageView*`
- `VkShaderModuleCreateInfo`, `vkCreateShaderModule`

This is a substantial expansion of the FFI. About 30 new functions and 20 new ftypes.

## M2.3 — input

### Deliverable
Type in the desktop window, characters appear in a line buffer; Enter fires a callback.

### Files
- `src/letloop/desktop/evdev.scm` — open `/dev/input/event*`, classify devices via `EVIOCGBIT`, find a keyboard.
- `src/letloop/desktop/keymap.scm` — scancode → keysym table (US QWERTY first; structure for swap).
- `src/letloop/desktop/input.scm` — io_uring read loop yielding events to a Scheme channel.
- Extend `desktop/window.scm` — overlay a line buffer and prompt glyph stream.

### Approach
- Reuse `(letloop liburing low)` for the read submission.
- Each event is `struct input_event { struct timeval time; __u16 type; __u16 code; __s32 value; }` — 24 bytes on x86_64 with 64-bit time_t.
- Key event = type EV_KEY (1), value = 0 (release) | 1 (press) | 2 (repeat).
- Yield `(press CODE)` and `(release CODE)` on a Scheme channel.

### Half-baked notes
- VT switching (Alt+F1..F6) and KDSKBMODE: today the kernel will send the keystroke *and* switch VTs. We probably want `KDSKBMODE K_OFF` so the kernel ignores keys entirely while in graphics mode.
- That should land alongside seat handling — promote it back into M2.0 once we're sure it doesn't break the rollback path.

## M2.4 — eval

### Deliverable
`(+ 1 2)` typed in the graphical REPL prints `3` in the graphical REPL. Errors render in red. Process still exits cleanly on Ctrl-C.

### Files
- `src/letloop/desktop/repl.scm` — port redirection + minimal line editor.

### Approach
- Build custom input/output ports backed by the window's line buffer / glyph stream.
- `(parameterize ((current-input-port  graphical-input)
                  (current-output-port graphical-output))
    (let loop ()
      (display "ⵉⵎⵓⵍⴰ> ")
      (let ((datum (read)))
        (unless (eof-object? datum)
          (write (eval datum (interaction-environment)))
          (newline)
          (loop)))))`
- Line editor: handle backspace (delete last char from line buffer + redraw), enter (append `\n`, signal read).

### Half-baked notes
- `read` blocks on `(get-char port)` — the port impl must integrate with the render loop. Either:
  - Run the REPL and the renderer as cooperating Chez engines (the existing letloop runtime), the renderer yields between frames, the REPL yields when reading.
  - Or: render ALWAYS; the line buffer gets re-rendered when it changes (dirty-flag).
- Lean toward option 2 first — simpler. Engines can come later when there's a second window.

## Open questions / risks

- **VT_PROCESS mode**: not handled in M2.0. Without it, Alt+F1 pulls the user away while we still hold DRM master and the screen freezes for whoever lands on tty1. Promote back into seat handling sooner rather than later.
- **SIGTERM / SIGSEGV**: still untrapped. KD_GRAPHICS leaks if killed with -9 or on a segfault. Best fix is a self-pipe trick + a foreign-callable-light handler that issues `ioctl(fd, KDSETMODE, KD_TEXT)` and `_exit(1)`.
- **Single render thread**: the Chez engine scheduler is cooperative. With one window we yield between frames and the REPL stays responsive. With two windows we'll need a dedicated render thread consuming damage commands over a channel — out of scope for M2.x.
- **No Scheme→SPIR-V compiler**: shaders stay handwritten GLSL → SPIR-V (offline). Embedded as bytevectors. M2.2 will introduce two; future milestones will accumulate more, which raises the question of an in-tree shader build step.
- **libtls.so dependency**: pre-existing, unrelated to desktop. Documented in `CLAUDE.md` with a stub-build snippet. Worth fixing upstream eventually with a `make tls` target.

## Further work — what an HTML render engine (no animation) would need

The current framework is a textured-quad text renderer, not a 2D
rendering engine. Mapping HTML-without-animation onto what's there
turns up a substantial gap list. Captured here so future contributors
inherit the analysis instead of redoing it.

### Reusable from M2.x
- Instanced-quad pipeline + per-instance color (extends naturally to
  more attributes: clip rect, texture index, corner radius).
- Atlas + sampler infra (becomes the glyph-atlas case of a more
  general texture cache).
- HTML parsing (`htmlprag` → SXML), HTTP, TLS, SXPath, JSON.
- Window + line editor + REPL (natural debug shell: load URL, print
  computed-style tree, sample boxes).

### Engine layer — none of this exists yet
- **CSS parser + selector matching + cascade.** Tokenizer, selector
  matcher, specificity, computed-style resolution, inheritance.
  ~1500 LOC of pure Scheme.
- **Box / layout tree.** Block layout (margins, padding, borders,
  widths/heights, margin-collapse), inline layout (line boxes,
  baselines, word wrap), float positioning, `position:
  relative/absolute/fixed`. Flex/grid pushed to v2. ~2000 LOC.
- **Unicode line breaking (UAX #14)** for word wrap, **bidi (UAX #9)**
  for RTL, **basic shaping** (kerning, ligatures — HarfBuzz typical).
  Without these, only ASCII LTR ever looks right.

### Text — PSF2 isn't enough
- **TrueType / OpenType outline rasterization.** PSF2 is a fixed-cell
  bitmap; CSS needs `font-family`, `font-size` (per pixel),
  `font-weight`, `font-style`. FreeType FFI is the cheapest route.
  Each (face, size, weight) feeds a separate atlas — or one SDF
  atlas for fast resize.
- **Multi-font / atlas management.** Today's atlas is one font, sized
  once at startup. Need an atlas allocator that grows or evicts.
- **Subpixel-accurate quad positioning.** Vertex shader takes floats
  already; the layout engine has to *produce* those floats with
  correct advance / kerning.

### Vector / 2D primitives — only axis-aligned quads today
- **Filled rectangles** for backgrounds — already trivially
  expressible through the existing instanced-quad pipeline (treat
  atlas alpha as 1).
- **Borders + border-radius.** Stroke + rounded corners. Either an
  SDF-per-quad shader or analytical rounded-rect coverage. Out of the
  box: nothing.
- **Lines / arbitrary paths** for `<hr>`, `text-decoration:
  underline`, etc. Thin-quad emitters or a real path tessellator
  (Lyon-style).
- **Images.** No PNG/JPEG decoder, no general RGBA texture pipeline.
  stb_image FFI is the small option. Per-image VkImage upload + a
  way to bind multiple textures per draw (descriptor-array,
  bindless, or draw-per-image).

### GPU plumbing — single-purpose right now
- **Multiple textures.** Descriptor pool sized for 1 set; no
  per-image descriptor allocation machinery.
- **Off-screen render targets.** Needed for stacking contexts,
  opacity layers, `overflow:hidden` antialiasing, `box-shadow` blur.
- **Clipping.** No scissor stack. `overflow:hidden` either needs
  `vkCmdSetScissor` per node or fragment-shader rect clipping.
- **Z-order / paint order.** Pure paint-order is fine for static
  HTML, but the renderer must walk the box tree in the right order.
  Currently we flatten everything into one instance buffer in
  arbitrary order.
- **Multiple draw calls / state changes per frame.** One `vkCmdDraw`
  per frame today. HTML wants distinct draws per (texture, clip,
  blend) combination. The frame-record path needs to take a list of
  "draw items" and bake bind/scissor changes between them.
- **Resize handling.** Swapchain isn't recreated when the surface
  size changes. Static page reflow on resize won't work.

### Resource & I/O
- **Async fetch + caching** for `<img>`, `<link rel=stylesheet>`,
  web fonts. We have sync `(letloop www)`; "render the document I
  have so far while images stream in" doesn't exist.
- **URL resolver** with relative-path resolution + redirects.

### Minimum-viable static HTML renderer — dependency order
1. **stb_image FFI + RGBA image upload** (~200 LOC + FFI) — unblocks
   `<img>` and CSS background-image.
2. **Multi-texture binding** (descriptor-array OR bindless OR
   draw-per-texture) — unblocks anything beyond the single atlas.
3. **FreeType FFI + scalable glyph atlas** (~500 LOC + FFI) —
   replaces PSF2, unblocks variable fonts.
4. **CSS parser + cascade** (~1500 LOC of pure Scheme).
5. **Box tree + block / inline layout** (~2000 LOC).
6. **Frame-record API** that emits a list of draw items (rect,
   glyph-run, image, clip-rect, color) — unifies the rendering
   surface so the layout engine doesn't poke Vulkan.
7. **Rounded-rect / border / clipping shader** (one new pipeline +
   fragment shader).
8. **Resize-on-extent-change** in `window-render-frame!`.

Roughly: ~5–8k LOC of new code, two new shader pipelines, three FFI
libraries (FreeType, stb_image, optionally HarfBuzz), and a frame-
graph rewrite of `record-text-draws!`. Achievable, but multi-month,
not an M2.x sprint.
