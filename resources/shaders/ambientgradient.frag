#version 440

// Fragment output
layout(location = 0) out vec4 fragColor;

// Fragment input - comes from vertex shader
layout(location = 0) in vec2 vTexCoord;

// ALL uniforms in ONE block (Qt 6 rule) - must match vertex shader
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_distortion;
    vec4 color1;
    vec4 color2;
    vec4 color3;
    vec4 color4;
    vec4 color5;
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

void main() {
    // Use vTexCoord from vertex shader (normalized 0-1)
    vec2 uv = vTexCoord;
    
    // Generate random positions for each spot using noise seeded by time
    // Each spot gets a unique seed based on its index
    float seed1 = ubuf.u_time * 0.01 + 1.0;
    float seed2 = ubuf.u_time * 0.01 + 2.5;
    float seed3 = ubuf.u_time * 0.01 + 4.2;
    float seed4 = ubuf.u_time * 0.01 + 6.7;
    float seed5 = ubuf.u_time * 0.01 + 8.9;
    
    // Use noise to generate random X and Y positions for each spot
    // Keep them within bounds (0.15 to 0.85) to avoid edges
    vec2 spot1_center = vec2(
        0.15 + noise(vec2(seed1, seed1 + 1.0)) * 0.7,
        0.15 + noise(vec2(seed1 + 2.0, seed1 + 3.0)) * 0.7
    );
    vec2 spot2_center = vec2(
        0.15 + noise(vec2(seed2, seed2 + 1.0)) * 0.7,
        0.15 + noise(vec2(seed2 + 2.0, seed2 + 3.0)) * 0.7
    );
    vec2 spot3_center = vec2(
        0.15 + noise(vec2(seed3, seed3 + 1.0)) * 0.7,
        0.15 + noise(vec2(seed3 + 2.0, seed3 + 3.0)) * 0.7
    );
    vec2 spot4_center = vec2(
        0.15 + noise(vec2(seed4, seed4 + 1.0)) * 0.7,
        0.15 + noise(vec2(seed4 + 2.0, seed4 + 3.0)) * 0.7
    );
    vec2 spot5_center = vec2(
        0.15 + noise(vec2(seed5, seed5 + 1.0)) * 0.7,
        0.15 + noise(vec2(seed5 + 2.0, seed5 + 3.0)) * 0.7
    );
    
    // Calculate distances to each spot center
    float d1 = length(uv - spot1_center);
    float d2 = length(uv - spot2_center);
    float d3 = length(uv - spot3_center);
    float d4 = length(uv - spot4_center);
    float d5 = length(uv - spot5_center);
    
    // Create circular spots with very smooth, soft falloff for seamless blending
    // Use exponential falloff for ultra-smooth blending
    float spotRadius = 0.5;  // Base radius
    
    // Exponential falloff: exp(-distance^2 / (2 * sigma^2))
    // This creates a Gaussian-like falloff that's much smoother than smoothstep
    float sigma = 0.25;  // Controls falloff width (larger = wider, softer)
    
    float w1 = exp(-(d1 * d1) / (2.0 * sigma * sigma));  // Gaussian falloff for color1
    float w2 = exp(-(d2 * d2) / (2.0 * sigma * sigma));  // Gaussian falloff for color2
    float w3 = exp(-(d3 * d3) / (2.0 * sigma * sigma));  // Gaussian falloff for color3
    float w4 = exp(-(d4 * d4) / (2.0 * sigma * sigma));  // Gaussian falloff for color4
    float w5 = exp(-(d5 * d5) / (2.0 * sigma * sigma));  // Gaussian falloff for color5

    // Normalize weights to prevent over-brightening
    float sum = w1 + w2 + w3 + w4 + w5;
    vec4 col = sum > 0.001 ? 
        (ubuf.color1 * w1 + ubuf.color2 * w2 + ubuf.color3 * w3 + ubuf.color4 * w4 + ubuf.color5 * w5) / sum :
        ubuf.color1;

    // Very subtle vignette - just a gentle edge darkening
    vec2 p = uv - vec2(0.5);
    float r = length(p);
    float vignette = smoothstep(0.9, 0.5, r);
    vignette = mix(1.0, vignette, 0.2);  // Only 20% vignette influence

    fragColor = col * vignette * ubuf.qt_Opacity;
}
