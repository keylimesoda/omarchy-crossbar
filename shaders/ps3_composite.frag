/* PS3 XMB HDR Glare Composite & Filmic Tone-Map (xmb-web FS_COMPOSITE).
 * Combines the rendered scene + blurred glare layer and applies the firmware
 * exposure curve: 1 - exp(-scene * exposure / whiteLevel) + anti-banding dither.
 */

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float bloomStrength;
    float time;
} pc;

layout(binding = 1) uniform sampler2D sceneTex;
layout(binding = 2) uniform sampler2D bloomTex;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    // Unpack 0.5x HDR-scaled scene & glare bloom back into [0.0 .. 2.0] linear HDR
    vec3 scene = texture(sceneTex, qt_TexCoord0).rgb * 2.0;
    vec3 bloom = texture(bloomTex, qt_TexCoord0).rgb * 2.0;

    // Extract true HDR highlights from blurred glare pass so dark sky stays deep
    vec3 glare = max(bloom - vec3(0.16, 0.22, 0.34), vec3(0.0)) * pc.bloomStrength;
    vec3 hdr = scene + glare;

    // xmb-web FS_COMPOSITE steady filmic curve: 1 - exp(-hdr * EXPOSURE / WHITE)
    const float exposure = 1.05;
    const float whiteLevel = 0.899181;
    vec3 mapped = vec3(1.0) - exp(-max(hdr, vec3(0.0)) * (exposure / whiteLevel));

    // Preserve deep midnight-blue shadows while letting HDR crests roll off filmically
    vec3 col = mix(hdr, mapped, 0.72);

    // Subtle film-grain dither to eliminate 8-bit banding
    col += (hash12(gl_FragCoord.xy + fract(pc.time) * 100.0) - 0.5) * (1.5 / 255.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * pc.qt_Opacity;
}
