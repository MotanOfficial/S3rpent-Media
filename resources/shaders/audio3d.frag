#version 440

layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;

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

layout(binding = 1) uniform sampler2D u_coverTexture;

#define PI 3.14159265359

float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453123);
}

vec3 mod289v3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289v4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289v4(((x * 34.0) + 1.0) * x); }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod289v3(i);
    vec4 p = permute(permute(permute(
        i.z + vec4(0.0, i1.z, i2.z, 1.0))
        + i.y + vec4(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = inversesqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

vec3 defaultSilkColor(vec2 uv) {
    return mix(
        vec3(0.36, 0.28, 0.72),
        mix(vec3(0.85, 0.55, 0.95), vec3(0.45, 0.78, 0.95), uv.x),
        uv.y
    );
}

vec3 coverColorAt(vec2 uv) {
    vec2 safe = clamp(uv, vec2(0.002), vec2(0.998));
    if (ubuf.u_hasCover > 0.5)
        return textureLod(u_coverTexture, safe, 0.0).rgb;
    return defaultSilkColor(safe);
}

// User orbit / pan / zoom (mouse drag in immersive mode)
vec2 applyCamera(vec2 uv, float aspect) {
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    float zoom = max(0.42, 1.0 + ubuf.u_orbitZoom * 0.72);
    p /= zoom;
    float cy = cos(ubuf.u_orbitYaw);
    float sy = sin(ubuf.u_orbitYaw);
    p = mat2(cy, -sy, sy, cy) * p;
    p.y += ubuf.u_orbitPitch * 0.62;
    p += ubuf.u_pan * vec2(aspect, 1.0);
    return p / vec2(aspect, 1.0) + 0.5;
}

vec2 applyGesture(vec2 p) {
    float cy = cos(ubuf.u_gestureRotY);
    float sy = sin(ubuf.u_gestureRotY);
    p = mat2(cy, -sy, sy, cy) * p;
    float cx = cos(ubuf.u_gestureRotX);
    float sx = sin(ubuf.u_gestureRotX);
    float px = p.x * cx + p.y * sx * 0.35;
    float py = p.y * cx - p.x * sx * 0.35;
    return vec2(px, py);
}

vec3 renderStarfield(vec2 uv, float aspect, float t) {
    vec3 stars = vec3(0.0);
    for (int layer = 0; layer < 3; layer++) {
        float scale = 95.0 + float(layer) * 72.0;
        float depth = 0.45 + float(layer) * 0.28;
        vec2 gv = uv * scale + vec2(float(layer) * 19.7, t * 0.0016 * depth);
        vec2 cell = floor(gv);
        vec2 f = fract(gv) - 0.5;
        float rnd = hash11(cell.x * 127.1 + cell.y * 431.7 + float(layer) * 53.0);
        if (rnd > 0.962) {
            float brightness = (rnd - 0.962) / 0.038;
            float sz = 0.018 + rnd * 0.032;
            float s = exp(-dot(f, f) / (sz * sz));
            float tw = 0.5 + 0.5 * sin(t * (1.2 + rnd * 5.5) + rnd * 41.0);
            vec3 tint = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.94, 0.86), rnd);
            stars += tint * s * tw * brightness * depth * 1.35;
        }
    }
    return stars;
}

float silkHeight(vec2 planeXY, float t, float K, float aRand) {
    float midN = snoise(vec3(planeXY.x * 1.4, planeXY.y * 1.4, t * 0.55)) * 0.6
               + snoise(vec3(planeXY.x * 2.8 + 5.0, planeXY.y * 2.8 - 3.0, t * 0.85)) * 0.4;
    float midMask = 0.55 + 0.45 * snoise(vec3(planeXY.x * 0.4, planeXY.y * 0.4, t * 0.18));
    float midDisp = midN * ubuf.u_mid * 0.55 * midMask * K;
    float trebleJ = snoise(vec3(planeXY.x * 6.5, planeXY.y * 6.5, t * 3.5 + aRand * 4.0)) * ubuf.u_treble * 0.18 * K;
    float bassBreath = snoise(vec3(planeXY.x * 0.35, planeXY.y * 0.35, t * 0.4)) * ubuf.u_bass * 0.42 * K;
    return midDisp + trebleJ + bassBreath;
}

vec3 renderSilk(vec2 uv, float aspect, float t, float K) {
    uv = applyCamera(uv, aspect);
    float yaw = t * 0.10 + ubuf.u_beat * 0.08;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

    // Perspective warp — silk plane fills the view
    float depth = 1.0 + p.y * 0.35;
    vec2 planeUv = vec2(
        p.x / depth + sin(yaw) * 0.12,
        p.y / depth * 0.85 + cos(t * 0.07) * 0.04
    );
    vec2 coverUv = planeUv * 0.48 + 0.5;
    vec2 planeXY = applyGesture(planeUv * 4.0);

    float h = silkHeight(planeXY, t, K, 0.5);
    float eps = 0.028;
    float hL = silkHeight(planeXY + vec2(-eps, 0.0), t, K, 0.5);
    float hR = silkHeight(planeXY + vec2(eps, 0.0), t, K, 0.5);
    float hD = silkHeight(planeXY + vec2(0.0, -eps), t, K, 0.5);
    float hU = silkHeight(planeXY + vec2(0.0, eps), t, K, 0.5);
    vec3 normal = normalize(vec3(hL - hR, hD - hU, eps * 3.2));

    vec3 albedo = coverColorAt(coverUv);
    albedo = mix(albedo, ubuf.u_tint.rgb, 0.08);

    vec3 lightDir = normalize(vec3(0.25, 0.45, 0.95));
    vec3 viewDir = normalize(vec3(-p.x * 0.6, -p.y * 0.6, 1.0));
    float diff = max(dot(normal, lightDir), 0.0);
    vec3 halfDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), 28.0);

    vec3 col = albedo * (0.28 + diff * 1.05);
    col += spec * (0.18 + ubuf.u_treble * 0.35) * vec3(0.9, 0.95, 1.0);
    col += h * vec3(0.14, 0.10, 0.22);
    col *= 0.82 + ubuf.u_energy * 0.42 + ubuf.u_beat * 0.16;

    // Point-cloud cover particles (Mineradio dot field)
    vec2 grid = coverUv * 118.0;
    vec2 f = fract(grid) - 0.5;
    vec2 cellId = floor(grid);
    float rnd = hash11(cellId.x * 17.0 + cellId.y * 31.0);
    float point = exp(-dot(f, f) * 22.0) * (0.65 + rnd * 0.55);
    float pointZ = silkHeight(applyGesture((cellId + 0.5) / 118.0 * 4.0 - 2.0), t, K, rnd);
    point *= smoothstep(-0.45, 0.65, pointZ + 0.18);
    col += albedo * point * (0.38 + ubuf.u_bass * 0.42 + ubuf.u_beat * 0.18 + ubuf.u_energy * 0.12);
    col += point * point * (0.08 + ubuf.u_treble * 0.14) * vec3(0.92, 0.96, 1.0);

    float vig = 1.0 - dot(p, p) * 0.42;
    col *= clamp(vig, 0.25, 1.0);

    return col;
}

vec3 renderTunnel(vec2 uv, float aspect, float t, float K) {
    uv = applyCamera(uv, aspect);
    vec2 p = applyGesture((uv - 0.5) * vec2(aspect, 1.0) * 3.0) / 3.0;
    float radius = length(p);
    float angle = atan(p.y, p.x);
    float spin = t * 0.12;
    float flow = fract((uv.y - 0.08) - t * 0.08 * (1.0 + ubuf.u_bass * 0.55));
    float tunnelR = 0.38 + sin(angle * 5.0 + flow * 14.0 + t * 2.2) * 0.04 * (ubuf.u_mid + ubuf.u_treble) * K;

    float wall = smoothstep(tunnelR + 0.08, tunnelR - 0.02, radius);
    float core = smoothstep(0.02, 0.12, radius);
    float mask = wall * core;

    vec2 sampleUv = vec2(angle / (2.0 * PI) + 0.5 + spin * 0.05, flow);
    vec3 col = coverColorAt(sampleUv);
    col = mix(col, ubuf.u_tint.rgb, 0.08);

    float depthFade = smoothstep(0.0, 0.55, radius / max(tunnelR, 0.01));
    col *= 0.35 + depthFade * 0.75;
    col *= 0.85 + ubuf.u_beat * 0.18;

    vec3 bg = vec3(0.01, 0.01, 0.03);
    return mix(bg, col, mask);
}

vec3 renderOrbit(vec2 uv, float aspect, float t, float K) {
    uv = applyCamera(uv, aspect);
    vec2 p = applyGesture((uv - 0.5) * vec2(aspect, 1.0) * 2.8) / 2.8;
    float len = length(p);
    float baseR = 0.36 * (1.0 + ubuf.u_bass * 0.22 * K);
    float trebFlare = snoise(vec3(p * 4.0, t * 0.7)) * ubuf.u_treble * 0.12 * K;
    float sphereR = baseR + trebFlare;

    float d = len - sphereR;
    float sphereMask = 1.0 - smoothstep(-0.01, 0.02, d);

    float theta = atan(p.y, p.x) + t * 0.18;
    float phi = (len / max(sphereR, 0.001)) * 1.2;
    vec2 sampleUv = vec2(theta / (2.0 * PI) + 0.5, phi * 0.5 + 0.25);

    vec3 col = coverColorAt(sampleUv);
    col = mix(col, ubuf.u_tint.rgb, 0.08);

    vec3 lightDir = normalize(vec3(-0.3, 0.5, 1.0));
  vec3 normal = normalize(vec3(p / max(sphereR, 0.001), 0.65));
    float diff = max(dot(normal, lightDir), 0.0);
    col *= 0.3 + diff * 1.1;
    col += trebFlare * 0.5 * vec3(0.7, 0.85, 1.0);
    col *= 0.88 + ubuf.u_beat * 0.14;

    float rim = smoothstep(sphereR - 0.02, sphereR + 0.06, len)
              * (1.0 - smoothstep(sphereR + 0.06, sphereR + 0.18, len));
    col += rim * 0.25 * ubuf.u_tint.rgb;

    vec3 bg = vec3(0.02, 0.02, 0.05);
    return mix(bg, col, sphereMask);
}

void main() {
    vec2 uv = vTexCoord;
    float aspect = ubuf.u_resolution.x / max(ubuf.u_resolution.y, 1.0);
    float t = ubuf.u_time;
    float K = ubuf.u_intensity * 1.6;
    float preset = ubuf.u_preset;

    vec3 starBg = renderStarfield(uv, aspect, t);

    vec3 col;
    if (preset < 0.5)
        col = renderSilk(uv, aspect, t, K);
    else if (preset < 1.5)
        col = renderTunnel(uv, aspect, t, K);
    else
        col = renderOrbit(uv, aspect, t, K);

    float sceneLum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(starBg, col + starBg * 0.35, clamp(sceneLum * 1.35, 0.0, 1.0));

    col += ubuf.u_beat * 0.035 * ubuf.u_tint.rgb;
    fragColor = vec4(col, ubuf.qt_Opacity);
}
