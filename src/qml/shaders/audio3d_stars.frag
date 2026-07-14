VARYING float v_phase;

void MAIN()
{
    vec2 coord = UV0 * 2.0 - 1.0;
    float edge = exp(-dot(coord, coord) * 3.2);

    vec3 col = mix(vec3(0.84, 0.92, 1.0), vec3(1.0, 0.97, 0.92), v_phase);
    col *= edge * 2.8;

    BASE_COLOR = vec4(col, edge);
    EMISSIVE_COLOR = col * 2.2;
    METALNESS = 0.0;
    ROUGHNESS = 1.0;
    SPECULAR_AMOUNT = 0.0;
}
