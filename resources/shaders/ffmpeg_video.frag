#version 450
layout(binding = 0) uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;
void main() {
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    fragColor = texture(tex, uv);
}
