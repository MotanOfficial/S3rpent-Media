void MAIN()
{
    vec4 tex0 = texture(baseColorVariant0, UV0);
    vec4 tex1 = texture(baseColorVariant1, UV0);
    BASE_COLOR = mix(tex0, tex1, u_colorMix);
    ROUGHNESS = u_roughness;
}
