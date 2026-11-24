/* PS3 XMB deep sky backdrop (OpenXMB monthly_background.frag value/chroma envelope). */

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 topColor;
    vec4 bottomColor;
    vec2 resolution;
    float time;
} pc;

void main() {
    float screenY = clamp(qt_TexCoord0.y, 0.0, 1.0);

    float bottomMix = smoothstep(0.65, 1.0, screenY);
    vec3 col = mix(pc.topColor.rgb, pc.bottomColor.rgb, bottomMix);

    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = max(vec3(luma) + (col - vec3(luma)) * 1.22, vec3(0.0));

    float dip = exp(-pow((screenY - 0.66) / 0.16, 2.0));
    float envelope = (1.04 - 0.22 * dip) * (1.0 + 0.06 * smoothstep(0.30, 0.0, screenY));
    col *= envelope;

    // Output at 0.5x HDR scale so xmbRawScene holds up to 2.0 linear HDR without 8-bit clipping
    fragColor = vec4(clamp(col * 0.5, 0.0, 1.0), 1.0) * pc.qt_Opacity;
}
