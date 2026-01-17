#version 450

layout(location = 0) in vec2 vUV;
layout(location = 0) out vec4 fragColor;

layout(binding = 0) uniform sampler2D tex;

void main() {
    // clamp because vUV is intentionally > 1 for the fullscreen triangle trick
    vec2 uv = clamp(vUV, 0.0, 1.0);
    fragColor = texture(tex, uv);
}
