/* Firmware-exact PS3 RSX silk fragment shader (FS_WAVECAP) with fine lacy
 * longitudinal silk-fiber filaments along the SPU cloth parameterization.
 * Adapted from TheGammaSqueeze/xmb-web.
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
} pc;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
        mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

// Anti-aliased sinusoidal silk filament band
float strandBand(float phase, float power) {
    float fw = fwidth(phase);
    float aa = 1.0 / (1.0 + fw * 1.4);
    float s = 0.5 + 0.5 * sin(phase);
    return mix(0.35, pow(s, power), aa);
}

void main() {
    vec3 N = normalize(vNrm);

    // Asymmetric Fresnel rim (brightest where silk grazes view, faint face-on)
    float F = 0.5 * pow(max(1.0 + dot(vec3(0.0, 0.0, -1.0), N), 0.0), 3.0);

    // PS3 firmware key light Blinn-Phong specular glint
    vec3 V  = normalize(vec3(3.12367, -0.0166247, -0.0852542));
    vec3 L0 = normalize(vec3(0.484729, 0.382283, -0.97268));
    vec3 H0 = normalize(L0 + V);
    float spec0 = pow(max(dot(N, H0), 0.0), 44.8563);

    float silk = clamp(F * 0.667 * 1.7 + spec0 * 0.30, 0.0, 0.95);
    float lit = 0.107345 + silk;

    // Fine lacy/feathery longitudinal silk threads running ALONG the ribbon (vUV.x)
    // and arrayed across the cloth width (vUV.y)
    float warp = noise2(vec2(vUV.x * 3.5 + pc.framePhase * 0.03, vUV.y * 7.0)) * 2.2;
    float s1 = strandBand(vUV.y * 72.0  + warp * 1.6, 5.0);
    float s2 = strandBand(vUV.y * 155.0 - warp * 2.2 + vUV.x * 2.5, 7.0);
    float s3 = strandBand(vUV.y * 290.0 + warp * 2.8 - vUV.x * 4.0, 9.0);
    float shimmer = 0.72 + 0.28 * noise2(vec2(vUV.x * 6.0 - pc.framePhase * 0.06, vUV.y * 18.0));
    float lace = (0.20 + 0.44 * s1 + 0.38 * s2 + 0.32 * s3) * shimmer;

    // Soft feathering at the top/bottom edges of the cloth
    float edge = smoothstep(0.0, 0.08, vUV.y) * smoothstep(0.0, 0.08, 1.0 - vUV.y)
               * smoothstep(0.0, 0.04, vUV.x) * smoothstep(0.0, 0.04, 1.0 - vUV.x);
    float a = clamp(pc.alpha * edge * lit * lace * 1.65, 0.0, 1.0);

    // Pure additive blending in Qt6 premultiplied alpha (ONE, ONE_MINUS_SRC_ALPHA)
    fragColor = vec4(pc.tint.rgb * a * pc.qt_Opacity, 0.0);
}
