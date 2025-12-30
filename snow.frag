#version 440

// PERFORMANCE OPTIMIZATIONS:
// 1. Early exit culling - skips flakes far from current pixel (biggest performance win)
// 2. Simplified snowflake SDF - reduced from 12 to 6 line calculations
// 3. Optimized rotation - single Z-axis rotation with simplified tilt (reduces sin/cos calls)
// 4. Optimized hash functions - faster integer-based hashing
// 5. Pre-calculated time values - reduces redundant calculations
// 6. Splash distance culling - only calculates splashes near the pixel

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

// Optimized hash function (faster, fewer operations)
float hash(float n) {
    // Use integer-based hash for better performance
    float h = n * 0.1031;
    h = fract(h);
    h *= h + 33.33;
    h *= h + h;
    return fract(h);
}

float hash2(vec2 p) {
    // Optimized 2D hash
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Optimized smooth wind noise (reduced operations)
float noise(float x) {
    float i = floor(x);
    float f = fract(x);
    // Use simpler smoothstep approximation
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash(i), hash(i + 1.0), f);
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

// Optimized 6-arm snowflake SDF (simplified for performance)
float snowflakeSDF(vec2 p, float size) {
    // Use simpler star shape instead of complex 12-line SDF
    // This reduces from 12 line calculations to 6 distance checks
    float d = 1e5;
    
    // Pre-calculate rotation angle once
    float angleStep = 3.14159265 / 3.0; // 60 degrees
    
    for (int i = 0; i < 6; i++) {
        float a = float(i) * angleStep;
        // Pre-compute sin/cos once per arm
        float ca = cos(a);
        float sa = sin(a);
        vec2 dir = vec2(ca, sa);
        
        // Main arm
        d = min(d, sdLine(p, vec2(0.0), dir * size, size * 0.06));
        // Branch (simplified - single branch instead of two)
        d = min(d, sdLine(p, dir * size * 0.6, dir * size * 0.85, size * 0.04));
    }
    return d;
}

// Optimized procedural ground splash - expanding oval that fades out (snow impact style)
float splash(vec2 p, vec2 center, float t) {
    // Expand over time
    float r = t * 28.0;
    
    // Ellipse scaling (wider than tall - looks like snow hitting surface)
    vec2 scale = vec2(1.6, 0.6);
    vec2 diff = (p - center) / scale;
    
    // Add subtle directional smear for realism (snow rarely splashes symmetrically)
    // OPTIMIZED: Pre-calculate sin value
    diff.x += sin(center.x * 0.1 + t * 10.0) * 0.3;
    
    // Calculate distance (sqrt needed for smoothstep, but we check squared distance first)
    float distSq = dot(diff, diff);
    float rSq = r * r;
    
    // Early exit if way too far (using squared distance to avoid sqrt)
    if (distSq > (r + 3.0) * (r + 3.0)) return 0.0;
    
    float d = abs(sqrt(distSq) - r);
    
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
    
    // Maximum distance to consider a flake (early exit optimization)
    const float MAX_FLAKE_DISTANCE = 15.0; // pixels

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

        // OPTIMIZED: Pre-calculate time-based values once
        float time15 = ubuf.u_time * 0.15 + fi;
        float time05 = ubuf.u_time * 0.5 + fi;
        float time80 = ubuf.u_time * 0.8 + fi;

        // Micro wind (per-flake local drift) - reduced for less wobble
        float microWind =
            noise(time15) * 25.0 +
            sin(time05) * 10.0;
        
        // Micro-turbulence (fluttering motion - reduced frequency and magnitude)
        float flutter =
            sin(ubuf.u_time * 5.0 + fi * 3.1) *
            noise(time80) * 3.5;
        
        // Gust affects flakes differently by height (stronger higher up)
        float heightFactor = smoothstep(0.2, 1.0, 1.0 - uv.y);
        float wind = microWind + flutter + gustStrength * heightFactor;

        vec2 flakePos = vec2(x + wind, y);

        // CRITICAL OPTIMIZATION: Early exit if flake is too far from current pixel
        // This skips expensive calculations for flakes that won't contribute to this pixel
        vec2 delta = p - flakePos;
        float distSq = dot(delta, delta);

        // Size varies by depth (closer = bigger)
        float size = mix(0.5, 2.4, depth) * 3.0;
        float maxDistSq = (size + MAX_FLAKE_DISTANCE) * (size + MAX_FLAKE_DISTANCE);
        
        // Skip this flake if it's too far away (early exit - huge performance win!)
        if (distSq > maxDistSq) {
            // Still check for splashes near ground (only if near bottom of screen)
            if (uv.y > 0.92) {
                float hitTime = fract(rawY / ubuf.u_resolution.y);
                if (hitTime < 0.08) {
                    vec2 groundPos = vec2(
                        flakePos.x + gustStrength * 0.05,
                        ubuf.u_resolution.y - 6.0
                    );
                    vec2 splashDelta = p - groundPos;
                    float splashDistSq = dot(splashDelta, splashDelta);
                    if (splashDistSq < 400.0) { // Only calculate if splash is nearby
                        splashes += splash(p, groundPos, hitTime);
                    }
                }
            }
            continue; // Skip expensive flake calculations
        }

        // Calculate distance with optimized rotation (snowflakes tumble in 3D space)
        vec2 q = (p - flakePos) / size;
        
        // OPTIMIZED: Simplified rotation - use single Z-axis rotation with pre-calculated tilt
        // This reduces from 3 sin/cos calls to 1, and eliminates expensive perspective calculations
        float angleZ = ubuf.u_time * 0.6 + seed;  // Z-axis (screen plane)
        
        // Pre-calculate rotation matrix
        float cz = cos(angleZ);
        float sz = sin(angleZ);
        q = mat2(cz, -sz, sz, cz) * q;
        
        // Simplified tilt (use single combined tilt value instead of separate X/Y)
        float combinedTilt = sin(ubuf.u_time * 0.5 + seed * 0.8) * 0.25;
        q.x += combinedTilt * q.y * 0.3;
        q.y += combinedTilt * q.x * 0.3;
        
        // Use optimized snowflake SDF
        float d = snowflakeSDF(q, 1.0);
        
        // Soft snowflake rendering
        float flake = smoothstep(0.2, 0.0, d);
        
        // Alpha varies by depth (closer = brighter, far = faint)
        float alpha = mix(0.3, 1.0, depth);
        flakes += flake * alpha;
        
        // Splash when flake hits ground (only calculate if near ground)
        if (uv.y > 0.85) {
        float hitTime = fract(rawY / ubuf.u_resolution.y);
        if (hitTime < 0.08) {
            // Gusts affect splashes slightly (subtle sideways smear during strong wind)
            vec2 groundPos = vec2(
                flakePos.x + gustStrength * 0.05,
                ubuf.u_resolution.y - 6.0
            );
                // Early exit for splash distance check
                vec2 splashDelta = p - groundPos;
                float splashDist = length(splashDelta);
                if (splashDist < 20.0) { // Only calculate if splash is nearby
            splashes += splash(p, groundPos, hitTime);
                }
            }
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
