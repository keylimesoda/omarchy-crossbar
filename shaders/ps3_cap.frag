/* Firmware-exact PS3 RSX silk fragment shader (FS_WAVECAP) with:
 *  - Chromatic Fresnel LUT sampling (freslut.png) with firmware R/G/B offsets
 *  - Baked RSX noise texture (noise.png) modulating lacy longitudinal silk strands
 *  - Blinn-Phong key-light specular glint + pure additive blending
 */

#version 440

layout(location = 0) in vec3 vNrm;
layout(location = 1) in vec2 vUV;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
    vec2 resolution;
    float framePhase;
    float alpha;
    float scaleY;
    float waveVelX;
    float waveVelY;
} pc;

layout(binding = 3) uniform sampler2D fresLut;
layout(binding = 4) uniform sampler2D noiseTex;

float strandBand(float phase, float power) {
    float fw = fwidth(phase);
    float aa = 1.0 / (1.0 + fw * 1.4);
    float s = 0.5 + 0.5 * sin(phase);
    return mix(0.35, pow(s, power), aa);
}

void main() {
    vec3 N = normalize(vNrm);

    // View & key light from PS3 firmware constants
    vec3 V  = normalize(vec3(3.12367, -0.0166247, -0.0852542));
    vec3 L0 = normalize(vec3(0.484729, 0.382283, -0.97268));
    vec3 H0 = normalize(L0 + V);

    // Chromatic Fresnel via firmware LUT (subtle prismatic sheen without purple cast)
    float fNdotV = clamp(1.0 + dot(vec3(0.0, 0.0, -1.0), N), 0.0, 1.0);
    vec3 fresLutCol;
    fresLutCol.r = texture(fresLut, vec2(clamp(fNdotV - 0.008, 0.0, 1.0), 0.5)).r;
    fresLutCol.g = texture(fresLut, vec2(clamp(fNdotV,         0.0, 1.0), 0.5)).g;
    fresLutCol.b = texture(fresLut, vec2(clamp(fNdotV + 0.010, 0.0, 1.0), 0.5)).b;
    float lutLuma = dot(fresLutCol, vec3(0.299, 0.587, 0.114));
    fresLutCol = mix(vec3(lutLuma), fresLutCol, 0.35);
    float F = 0.5 * pow(fNdotV, 3.0);
    vec3 chromaticFres = mix(vec3(F), fresLutCol * F * 1.35, 0.35);

    // Tight Blinn-Phong specular glint (exponent 44.8563)
    float spec0 = pow(max(dot(N, H0), 0.0), 44.8563);

    vec3 silkCol = clamp(chromaticFres * 0.667 * 1.8 + vec3(spec0 * 0.34), vec3(0.0), vec3(1.0));
    vec3 litCol = vec3(0.107345) + silkCol;

    // Baked RSX noise.png modulating lacy longitudinal silk filaments
    vec2 nUV1 = fract(vec2(vUV.x * 2.6 + pc.framePhase * 0.008, vUV.y * 4.2));
    vec2 nUV2 = fract(vec2(vUV.x * 5.2 - pc.framePhase * 0.014, vUV.y * 9.5));
    float n1 = texture(noiseTex, nUV1).r;
    float n2 = texture(noiseTex, nUV2).r;

    float warp = (n1 - 0.5) * 3.8;
    float s1 = strandBand(vUV.y * 74.0  + warp * 1.4, 4.5);
    float s2 = strandBand(vUV.y * 160.0 - warp * 2.0 + vUV.x * 2.5, 6.5);
    float s3 = strandBand(vUV.y * 295.0 + warp * 2.6 - vUV.x * 4.0, 8.5);
    float lace = (0.32 + 0.34 * s1 + 0.30 * s2 + 0.24 * s3) * (0.72 + 0.44 * n2);

    float edge = smoothstep(0.0, 0.08, vUV.y) * smoothstep(0.0, 0.08, 1.0 - vUV.y)
               * smoothstep(0.0, 0.04, vUV.x) * smoothstep(0.0, 0.04, 1.0 - vUV.x);
    vec3 rgb = pc.tint.rgb * litCol * (pc.alpha * edge * lace * 1.75);

    // Output at 0.5x HDR scale (pure additive alpha = 0.0) so overlapping folds accumulate into HDR
    fragColor = vec4(clamp(rgb * 0.5, vec3(0.0), vec3(1.0)) * pc.qt_Opacity, 0.0);
}
