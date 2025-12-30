#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_frameIndex;  // Current frame index (0-6571 for Bad Apple)
    vec2  u_resolution;
    vec4  u_color;
    bool u_useFrameTexture;  // Whether texture is available
} ubuf;

// Texture sampler - Qt ShaderEffect creates this automatically from ShaderEffectSource property
// When property name is u_frameTexture, Qt creates uniform sampler2D u_frameTexture
// GLSL 440 requires binding, but Qt handles this automatically at runtime
// We declare it here for compilation, Qt will bind it when ShaderEffectSource is provided
layout(binding = 1) uniform sampler2D u_frameTexture;

// Bad Apple frame texture (all frames packed horizontally)
// Texture width: 64 * 6572 = 420608 pixels
// Texture height: 48 pixels
// Texture is passed via ShaderEffectSource for Vulkan compatibility

// Hash function for procedural fallback
float hash(float n) {
    float h = n * 0.1031;
    h = fract(h);
    h *= h + 33.33;
    h *= h + h;
    return fract(h);
}

// Sample Bad Apple frame at pixel position (x, y) for frame index
// Returns 1.0 for white (silhouette), 0.0 for black (background)
float sampleBadAppleFrame(int frameIndex, int pixelX, int pixelY) {
    // Bad Apple is 64x48 pixels
    const int FRAME_WIDTH = 64;
    const int FRAME_HEIGHT = 48;
    
    // Clamp pixel coordinates
    if (pixelX < 0 || pixelX >= FRAME_WIDTH || pixelY < 0 || pixelY >= FRAME_HEIGHT) {
        return 0.0;
    }
    
    // Use texture if available (passed via ShaderEffectSource)
    if (ubuf.u_useFrameTexture) {
        // Pre-calculate constants (optimization: calculate once per frame, not per pixel)
        const float framesPerRow = 256.0;
        const float textureWidth = 16384.0;  // 256 * 64
        const float textureHeight = 1248.0;  // 26 * 48
        
        // Calculate grid position of the frame
        float frameRow = floor(float(frameIndex) / framesPerRow);
        float frameCol = float(frameIndex) - frameRow * framesPerRow;
        
        // Calculate pixel position within the texture (optimized: fewer operations)
        float frameStartX = frameCol * 64.0;  // FRAME_WIDTH
        float frameStartY = frameRow * 48.0;  // FRAME_HEIGHT
        
        // Convert to normalized texture coordinates (0-1) - optimized calculation
        vec2 texCoord = vec2(
            (frameStartX + float(pixelX) + 0.5) / textureWidth,
            (frameStartY + float(pixelY) + 0.5) / textureHeight
        );
        
        // Sample the texture (monochrome, so we use red channel)
        // Use textureLod for better performance (no mipmap lookup needed)
        float value = textureLod(u_frameTexture, texCoord, 0.0).r;
        return value;
    }
    
    // Fallback: procedural generation
    float seed = float(frameIndex * 1000 + pixelY * FRAME_WIDTH + pixelX);
    float value = hash(seed);
    
    // Create a simple silhouette pattern
    vec2 center = vec2(FRAME_WIDTH / 2.0, FRAME_HEIGHT / 2.0);
    vec2 pos = vec2(float(pixelX), float(pixelY));
    float dist = length(pos - center);
    
    // Animated circle that moves (placeholder for actual Bad Apple)
    float timeOffset = float(frameIndex) * 0.1;
    float radius = 15.0 + sin(timeOffset) * 5.0;
    float circle = smoothstep(radius + 2.0, radius - 2.0, dist);
    
    // Add some procedural detail
    float detail = sin(float(pixelX) * 0.3 + timeOffset) * sin(float(pixelY) * 0.3 + timeOffset);
    detail = detail * 0.3 + 0.7;
    
    return circle * detail;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * ubuf.u_resolution;
    
    // Bad Apple frame dimensions
    const int FRAME_WIDTH = 64;
    const int FRAME_HEIGHT = 48;
    
    // Calculate pixel coordinates in the frame
    int pixelX = int((uv.x * float(FRAME_WIDTH)));
    int pixelY = int((uv.y * float(FRAME_HEIGHT)));
    
    // Get current frame index
    int frameIndex = int(ubuf.u_frameIndex);
    
    // Sample the Bad Apple frame
    float pixelValue = sampleBadAppleFrame(frameIndex, pixelX, pixelY);
    
    // Scale up pixels with smooth edges (pixel art style)
    vec2 pixelUV = fract(uv * vec2(float(FRAME_WIDTH), float(FRAME_HEIGHT)));
    float edgeFade = smoothstep(0.1, 0.3, min(pixelUV.x, 1.0 - pixelUV.x)) *
                     smoothstep(0.1, 0.3, min(pixelUV.y, 1.0 - pixelUV.y));
    
    // Apply pixel value with edge smoothing
    float alpha = pixelValue * edgeFade;
    
    // White silhouette on black background
    vec3 color = ubuf.u_color.rgb * alpha;
    fragColor = vec4(color, alpha) * ubuf.qt_Opacity;
}

