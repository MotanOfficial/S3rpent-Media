VARYING vec3 v_tint;
VARYING float v_bright;
VARYING float v_alpha;
VARYING vec2 v_quad;

#define PI 3.14159265359

float hash21(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 silkPosition(vec2 planeXY, float aRand, float t, float K)
{
    float midN = sin(planeXY.x * 1.4 + t * 0.55) * 0.6
               + sin(planeXY.x * 2.8 + planeXY.y * 2.8 + t * 0.85) * 0.4;
    float midMask = 0.55 + 0.45 * sin(planeXY.x * 0.4 + planeXY.y * 0.4 + t * 0.18);
    float midDisp = midN * u_mid * 0.55 * midMask * K;
    float trebleJ = sin(planeXY.x * 6.5 + planeXY.y * 6.5 + t * 3.5 + aRand * 4.0) * u_treble * 0.18 * K;
    float bassBreath = sin(planeXY.x * 0.35 + planeXY.y * 0.35 + t * 0.4) * u_bass * 0.42 * K;
    return vec3(planeXY.x, planeXY.y, midDisp + trebleJ + bassBreath);
}

vec3 tunnelPosition(vec2 coverUv, float t, float K)
{
    float spin = t * 0.12;
    float angle = coverUv.x * 2.0 * PI + spin;
    float flow = fract(coverUv.y - t * 0.08 * (1.0 + u_bass * 0.55));
    float zPos = (flow - 0.5) * 9.0;
    float baseR = 2.0 - u_bass * 0.28 * K;
    float ripG = sin(angle * 5.0 + zPos * 1.4 + t * 2.2) * 0.10 * (u_mid + u_treble) * K;
    float r = baseR + ripG;
    return vec3(cos(angle) * r, sin(angle) * r, zPos);
}

vec3 orbitPosition(vec2 coverUv, float aRand, float t, float K)
{
    float theta = coverUv.x * 2.0 * PI;
    float phi = (coverUv.y - 0.5) * PI;
    float baseR = 2.2;
    float trebFlare = sin(theta * 1.5 + phi * 1.5 + t * 0.7) * u_treble * 0.85 * K;
    float bassExpand = u_bass * 0.35 * K;
    float r = baseR * (1.0 + bassExpand) + trebFlare;
    vec3 pos;
    pos.x = r * cos(phi) * cos(theta);
    pos.y = r * sin(phi);
    pos.z = r * cos(phi) * sin(theta);
    float yaw = t * 0.18;
    float cy = cos(yaw);
    float sy = sin(yaw);
    pos.xz = mat2(cy, -sy, sy, cy) * pos.xz;
    return pos;
}

void MAIN()
{
    vec2 coverUv = UV0;
    vec2 quadUv = UV1;
    v_quad = quadUv;

    float aRand = hash21(coverUv);
    float t = u_time;
    float K = u_intensity * 1.6;
    float preset = u_preset;
    vec2 planeXY = (coverUv - vec2(0.5)) * u_planeSize;
    v_alpha = 1.0;

    vec3 centerPos;
    if (preset < 0.5)
        centerPos = silkPosition(planeXY, aRand, t, K);
    else if (preset < 1.5) {
        centerPos = tunnelPosition(coverUv, t, K);
        v_alpha = smoothstep(-4.5, 4.5, centerPos.z) * 0.55 + 0.45;
    } else {
        centerPos = orbitPosition(coverUv, aRand, t, K);
    }

    vec3 localOff = VERTEX - vec3(planeXY.x, planeXY.y, 0.0);
    vec3 camRight = vec3(VIEW_MATRIX[0][0], VIEW_MATRIX[1][0], VIEW_MATRIX[2][0]);
    vec3 camUp = vec3(VIEW_MATRIX[0][1], VIEW_MATRIX[1][1], VIEW_MATRIX[2][1]);
    vec3 billboardPos = centerPos + camRight * localOff.x + camUp * localOff.y;

    v_tint = mix(vec3(0.42, 0.34, 0.78), u_tint.rgb, 0.18);
    v_bright = 1.15 + u_energy * 0.85 + u_beat * 0.45 + u_bass * 0.22;

    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(billboardPos, 1.0);
}
