#version 440
// Per-widget shade. Hue turns in YIQ space, a linear map that leaves greys,
// white and black exactly where they are, so anti-aliased edges (text over a
// coloured fill) blend just like the colours they mix: no fringes, no
// thresholds. Lightness moves luma in proportion to how colourful a pixel
// is, so neutral text and backgrounds stay put.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float hueShift;
    float lightShift;
    float texelX;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 px = texture(source, qt_TexCoord0);
    if (px.a <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    // Premultiplied rgb works as is: every step below is linear in it,
    // except the lightness weight, which reads the straight colour.
    vec3 c = px.rgb;
    float y = dot(c, vec3(0.299, 0.587, 0.114));
    float i = dot(c, vec3(0.596, -0.274, -0.322));
    float q = dot(c, vec3(0.211, -0.523, 0.312));

    float ang = -hueShift * 6.28318530718;
    float ca = cos(ang), sa = sin(ang);
    float i2 = i * ca - q * sa;
    float q2 = i * sa + q * ca;

    float chroma = length(vec2(i, q)) / px.a;
    float w = smoothstep(0.02, 0.15, chroma);
    y += lightShift * w * px.a;

    vec3 rgb = vec3(y + 0.956 * i2 + 0.621 * q2,
                    y - 0.272 * i2 - 0.647 * q2,
                    y - 1.106 * i2 + 1.703 * q2);
    rgb = clamp(rgb, vec3(0.0), vec3(px.a));
    fragColor = vec4(rgb, px.a) * qt_Opacity;
}
