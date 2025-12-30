#version 440

layout(location = 0) out vec4 fragColor;
layout(location = 0) in vec2 vTexCoord;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
} ubuf;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(
        mix(hash(i), hash(i + vec2(1, 0)), f.x),
        mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x),
        f.y
    );
}

// Generate a single layer of procedural snow - static pattern with subtle animation
float snowLayer(vec2 uv, float scale, float speed) {
    float t = ubuf.u_time * speed;
    
    // Create grid cells - static grid, no scrolling
    vec2 grid = floor(uv * scale);
    vec2 cell = fract(uv * scale) - 0.5;
    
    // Random offset per cell (static, based on grid position)
    float n = hash(grid);
    vec2 offset = vec2(
        fract(n * 10.0) - 0.5,
        fract(n * 7.0) - 0.5
    ) * 0.3;
    
    // Add very subtle time-based animation (not scrolling, just gentle movement)
    offset.x += sin(t * 0.02 + grid.y * 0.1) * 0.05;  // Very subtle horizontal drift
    offset.y += cos(t * 0.015 + grid.x * 0.1) * 0.03;  // Very subtle vertical drift
    
    // Distance from cell center with offset
    float dist = length(cell + offset);
    
    // Soft circular snowflake
    float flake = smoothstep(0.35, 0.0, dist);
    
    // Fade based on random value for density variation
    flake *= smoothstep(0.8, 0.2, n);
    
    return flake;
}

void main() {
    vec2 uv = vTexCoord;
    
    // Very subtle background snow - just a hint, not dominant
    // Large, slow flakes (background) - very subtle
    float layer1 = snowLayer(uv, 12.0, 0.01) * 0.1;
    
    // Medium flakes (midground) - very subtle
    float layer2 = snowLayer(uv, 20.0, 0.015) * 0.15;
    
    // Small flakes (foreground) - very subtle
    float layer3 = snowLayer(uv, 35.0, 0.02) * 0.1;
    
    // Combine all layers - much more subtle
    float snow = layer1 + layer2 + layer3;
    
    // Dark background color (not white) - subtle dark gray/blue tint
    vec3 color = vec3(0.15, 0.18, 0.22);  // Dark blue-gray instead of white
    color += vec3(0.05, 0.05, 0.05) * snow;  // Slight brightening from snow
    
    // Very subtle snow alpha - just a hint
    float snowAlpha = clamp(snow * 0.15, 0.0, 1.0);  // Much more subtle
    
    // Output with opacity control - mostly transparent, just a hint of snow
    fragColor = vec4(color, 0.3 + snowAlpha * 0.2) * ubuf.qt_Opacity;  // Mostly transparent background
}

