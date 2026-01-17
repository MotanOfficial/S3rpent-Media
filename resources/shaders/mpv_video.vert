#version 450

layout(location = 0) out vec2 vUV;

void main() {
    // Fullscreen triangle using gl_VertexIndex / gl_VertexID (Qt’s qsb maps this)
    vec2 pos;
    if (gl_VertexIndex == 0) {
        pos = vec2(-1.0, -1.0);
        vUV = vec2(0.0, 0.0);
    } else if (gl_VertexIndex == 1) {
        pos = vec2( 3.0, -1.0);
        vUV = vec2(2.0, 0.0);
    } else {
        pos = vec2(-1.0,  3.0);
        vUV = vec2(0.0, 2.0);
    }

    gl_Position = vec4(pos, 0.0, 1.0);
}
