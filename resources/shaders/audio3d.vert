#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec2 vTexCoord;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    vec2 u_resolution;
    float u_bass;
    float u_mid;
    float u_treble;
    float u_beat;
    float u_energy;
    float u_preset;
    float u_intensity;
    float u_hasCover;
    vec4 u_tint;
    float u_orbitYaw;
    float u_orbitPitch;
    float u_orbitZoom;
    vec2 u_pan;
    float u_gestureRotX;
    float u_gestureRotY;
} ubuf;

void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = ubuf.qt_Matrix * qt_Vertex;
}
