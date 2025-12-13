#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_intensity;
    vec2  u_resolution;
    vec4  u_color;
} ubuf;

// Hash without grid repetition
float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth wind noise
float noise(float x) {
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(hash(i), hash(i + 1.0), u);
}

// Slow global gusts (very low frequency, coherent across screen)
float gust(float t) {
    return noise(t * 0.05) * 2.0 - 1.0; // -1 .. 1
}

// Signed distance field for a line segment
float sdLine(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Procedural 6-arm snowflake SDF
float snowflakeSDF(vec2 p, float size) {
    float d = 1e5;
    
    for (int i = 0; i < 6; i++) {
        float a = float(i) * 3.14159265 / 3.0;
        vec2 dir = vec2(cos(a), sin(a));
        d = min(d, sdLine(p, vec2(0.0), dir * size, size * 0.06));
        d = min(d, sdLine(p, dir * size * 0.5, dir * size * 0.8, size * 0.04));
    }
    return d;
}

// Procedural ground splash - expanding oval that fades out (snow impact style)
float splash(vec2 p, vec2 center, float t) {
    // Expand over time
    float r = t * 28.0;
    
    // Ellipse scaling (wider than tall - looks like snow hitting surface)
    vec2 scale = vec2(1.6, 0.6);
    vec2 diff = (p - center) / scale;
    
    // Add subtle directional smear for realism (snow rarely splashes symmetrically)
    diff.x += sin(center.x * 0.1 + t * 10.0) * 0.3;
    
    float d = abs(length(diff) - r);
    return smoothstep(3.0, 0.0, d) * exp(-t * 3.5);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * ubuf.u_resolution;

    // Global wind gust (computed once per frame)
    float gustStrength = gust(ubuf.u_time) * 120.0;
    // Gust ramps in/out (not constant force - feels natural)
    float gustFade = smoothstep(0.2, 0.6, fract(ubuf.u_time * 0.03));
    gustStrength *= gustFade;

    // Track flakes and splashes separately
    float flakes = 0.0;
    float splashes = 0.0;

    // Number of virtual flakes (higher = denser)
    const int FLAKES = 90;

    for (int i = 0; i < FLAKES; i++) {
        float fi = float(i);

        // Unique seed per flake
        float seed = fi * 17.13;

        // Depth layer (0 = far, 1 = close) - creates parallax and 3D feel
        float depth = hash(seed + 9.0);

        // Random horizontal position
        float x = hash(seed) * ubuf.u_resolution.x;

        // Fall speed varies by depth (closer = faster)
        float speed = mix(30.0, 160.0, depth);

        // Vertical position (track rawY before mod for splash detection)
        float rawY = hash(seed + 2.0) * ubuf.u_resolution.y + ubuf.u_time * speed;
        float y = mod(rawY, ubuf.u_resolution.y);

        // Micro wind (per-flake local drift) - reduced for less wobble
        float microWind =
            noise(ubuf.u_time * 0.15 + fi) * 25.0 +
            sin(ubuf.u_time * 0.5 + fi) * 10.0;
        
        // Micro-turbulence (fluttering motion - reduced frequency and magnitude)
        float flutter =
            sin(ubuf.u_time * 5.0 + fi * 3.1) *
            noise(ubuf.u_time * 0.8 + fi) * 3.5;
        
        // Gust affects flakes differently by height (stronger higher up)
        float heightFactor = smoothstep(0.2, 1.0, 1.0 - uv.y);
        float wind = microWind + flutter + gustStrength * heightFactor;

        vec2 flakePos = vec2(x + wind, y);

        // Size varies by depth (closer = bigger)
        float size = mix(0.5, 2.4, depth) * 3.0;

        // Calculate distance with 3D rotation (snowflakes tumble in 3D space)
        vec2 q = (p - flakePos) / size;
        
        // 3D rotation: rotate around X, Y, and Z axes for realistic tumbling
        // Each axis has different rotation speeds for organic motion
        float angleZ = ubuf.u_time * 0.6 + seed;  // Z-axis (screen plane)
        float angleX = ubuf.u_time * 0.4 + seed * 1.3;  // X-axis (pitch)
        float angleY = ubuf.u_time * 0.5 + seed * 0.7;  // Y-axis (yaw)
        
        // Rotation around Z-axis (existing 2D rotation)
        float cz = cos(angleZ);
        float sz = sin(angleZ);
        q = mat2(cz, -sz, sz, cz) * q;
        
        // Simulate 3D rotation around X and Y axes using perspective distortion
        // This makes flakes appear to tilt forward/backward and left/right
        float tiltX = cos(angleX) * 0.3;  // Forward/backward tilt
        float tiltY = sin(angleY) * 0.3;  // Left/right tilt
        
        // Apply perspective distortion based on tilt
        q.x += tiltY * q.y * 0.5;  // Y-axis rotation effect
        q.y += tiltX * q.x * 0.5;  // X-axis rotation effect
        
        // Scale based on tilt to simulate depth (tilted flakes appear smaller)
        float depthScale = 1.0 - abs(tiltX) * 0.2 - abs(tiltY) * 0.2;
        q /= depthScale;
        
        // Use real 6-arm snowflake SDF instead of circles
        float d = snowflakeSDF(q, 1.0);
        
        // Soft snowflake rendering
        float flake = smoothstep(0.2, 0.0, d);
        
        // Alpha varies by depth (closer = brighter, far = faint)
        float alpha = mix(0.3, 1.0, depth);
        flakes += flake * alpha;
        
        // Splash when flake hits ground (procedural, no particles needed)
        float hitTime = fract(rawY / ubuf.u_resolution.y);
        if (hitTime < 0.08) {
            // Gusts affect splashes slightly (subtle sideways smear during strong wind)
            vec2 groundPos = vec2(
                flakePos.x + gustStrength * 0.05,
                ubuf.u_resolution.y - 6.0
            );
            splashes += splash(p, groundPos, hitTime);
        }
    }

    // Apply fade-in from top ONLY to flakes (snow appears gradually from top)
    // After ~20% down, flakes are fully visible
    flakes *= smoothstep(0.0, 0.2, uv.y);
    
    // Make splashes slightly brighter for better visibility
    splashes *= 1.4;

    // Combine flakes and splashes
    float snow = flakes + splashes;
    
    snow *= ubuf.u_intensity;
    snow = clamp(snow, 0.0, 1.0);

    // Premultiplied alpha
    vec3 rgb = ubuf.u_color.rgb * snow;
    fragColor = vec4(rgb, snow) * ubuf.qt_Opacity;
}
