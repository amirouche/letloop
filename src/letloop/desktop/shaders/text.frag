#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform sampler2D atlas;

void main() {
    // Atlas is single-channel R8: 0xFF where the glyph bitmap is set.
    float coverage = texture(atlas, v_uv).r;
    if (coverage < 0.01) discard;
    out_color = vec4(v_color.rgb, v_color.a * coverage);
}
