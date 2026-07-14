VARYING vec3 v_tint;
VARYING float v_bright;
VARYING float v_alpha;
VARYING vec2 v_quad;

void MAIN()
{
    vec2 coord = v_quad * 2.0 - 1.0;
    float dist = dot(coord, coord);
    float edge = 1.0 - smoothstep(0.25, 1.0, dist);

    vec3 col = v_tint;
    if (u_hasCover > 0.5)
        col = texture(coverMap, UV0).rgb;
    else
        col = mix(v_tint, vec3(0.55, 0.48, 0.92), 0.35);
    col = mix(col, u_tint.rgb, 0.06);
    col *= v_bright * 1.8;
    col += u_beat * 0.18 * u_tint.rgb;
    col += u_energy * 0.12;
    col = clamp(col, vec3(0.0), vec3(2.8));

    float alpha = edge * v_alpha * u_particleAlpha;
    if (u_hasCover < 0.5)
        alpha = max(alpha, edge * 0.68 * u_particleAlpha);

    BASE_COLOR = vec4(col, alpha);
    EMISSIVE_COLOR = col * edge * 1.6;
    METALNESS = 0.0;
    ROUGHNESS = 1.0;
    SPECULAR_AMOUNT = 0.0;
}
