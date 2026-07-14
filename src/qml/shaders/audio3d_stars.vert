VARYING float v_phase;

void MAIN()
{
    v_phase = UV0.x;
    vec2 quadUv = UV0;
    float h = u_starHalf;
    vec3 localOff = vec3((quadUv.x - 0.5) * 2.0 * h, (quadUv.y - 0.5) * 2.0 * h, 0.0);
    vec3 starCenter = VERTEX - localOff;

    vec3 camRight = vec3(VIEW_MATRIX[0][0], VIEW_MATRIX[1][0], VIEW_MATRIX[2][0]);
    vec3 camUp = vec3(VIEW_MATRIX[0][1], VIEW_MATRIX[1][1], VIEW_MATRIX[2][1]);
    vec3 billboardPos = starCenter + camRight * localOff.x + camUp * localOff.y;

    float tw = 0.55 + 0.45 * sin(u_time * (1.4 + v_phase * 5.0) + v_phase * 40.0);
    billboardPos += camRight * (tw - 1.0) * h * 0.15;

    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(billboardPos, 1.0);
}
