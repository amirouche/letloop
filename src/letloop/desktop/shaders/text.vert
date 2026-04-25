#version 450

// Per-instance attributes — one quad per glyph instance.
//   in_xywh   = (x, y, width, height) in pixel coords, top-left origin.
//   in_uv_rect = (u, v, uw, uh) in atlas UV space, [0,1].
layout(location = 0) in vec4 in_xywh;
layout(location = 1) in vec4 in_uv_rect;

layout(push_constant) uniform Push {
    vec2 viewport_size;   // pixels — matches the swapchain extent
    vec2 _pad0;
    vec4 fg_color;        // unused here, but the block is shared with the
                          // fragment stage so the layout must agree.
} push;

layout(location = 0) out vec2 v_uv;

// 6 vertices per quad, two CCW triangles in pixel-coord space:
//  (0,0)  (0,1)  (1,1)  (0,0)  (1,1)  (1,0)
const vec2 corners[6] = vec2[](
    vec2(0.0, 0.0),
    vec2(0.0, 1.0),
    vec2(1.0, 1.0),
    vec2(0.0, 0.0),
    vec2(1.0, 1.0),
    vec2(1.0, 0.0)
);

void main() {
    vec2 corner = corners[gl_VertexIndex];
    vec2 pixel  = in_xywh.xy + corner * in_xywh.zw;

    // Pixel coords (top-left origin) → Vulkan NDC (top-left = (-1,-1)).
    vec2 ndc = pixel / push.viewport_size * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);

    v_uv = in_uv_rect.xy + corner * in_uv_rect.zw;
}
