#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform sampler2D atlas;

layout(push_constant) uniform Push {
    vec2 viewport_size;
    vec2 _pad0;
    vec4 fg_color;
} push;

void main() {
    // Atlas is single-channel R8: 0xFF where the glyph bitmap is set.
    float coverage = texture(atlas, v_uv).r;
    if (coverage < 0.01) discard;
    out_color = vec4(push.fg_color.rgb, push.fg_color.a * coverage);
}
