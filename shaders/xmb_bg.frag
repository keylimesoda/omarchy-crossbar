/* Pure per-pixel PS3 XMB silk wave & sparkle fragment shader (zero mesh aliasing). */

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
    vec2 resolution;
    float time;
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

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 4; ++i) {
        v += a * noise2(p);
        p = rot * p * 2.02 + vec2(13.1, 7.7);
        a *= 0.5;
    }
    return v;
}

float waveCurve(float x, float seed, float t) {
    float s = t * (0.042 + seed * 0.008);
    float y = sin(x * (1.25 + seed * 0.09) + s + seed * 2.7) * 0.085;
    y += sin(x * (2.35 + seed * 0.13) - s * 1.35 + seed * 5.1) * 0.032;
    y += cos(x * (3.60 + seed * 0.17) + s * 0.65 + seed * 1.9) * 0.014;
    return y;
}

float sparkleLayer(vec2 uv, float scale, float speed, float threshold) {
    vec2 p = uv * scale + vec2(pc.time * speed * 0.025, -pc.time * speed * 0.015);
    vec2 cell = floor(p);
    vec2 f = fract(p) - 0.5;
    float id = hash12(cell);
    if (id < threshold) return 0.0;

    vec2 jitter = (vec2(hash12(cell + 3.1), hash12(cell + 9.7)) - 0.5) * 0.60;
    float d = length(f - jitter) / mix(0.035, 0.075, hash12(cell + 17.3));
    if (d > 1.0) return 0.0;

    float d2 = d * d;
    float core = exp(-d2 * 14.0);
    float halo = exp(-d2 * 3.2) * 0.28;
    float twinkle = 0.40 + 0.60 * sin(pc.time * (0.65 + id * 1.4) + id * 19.0);
    return (core + halo) * twinkle * 0.72;
}

void main() {
    vec2 res = max(pc.resolution, vec2(1.0));
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * 2.0 - 1.0;
    p.x *= res.x / res.y;

    // Smooth deep PS3 midnight-blue sky gradient (with subtle fbm dither)
    vec3 topCol = pc.tint.rgb * vec3(0.18, 0.30, 0.54);
    vec3 midCol = pc.tint.rgb * vec3(0.08, 0.16, 0.34);
    vec3 botCol = pc.tint.rgb * vec3(0.02, 0.05, 0.12);
    vec3 col = mix(topCol, midCol, smoothstep(0.0, 0.52, uv.y));
    col = mix(col, botCol, smoothstep(0.48, 1.0, uv.y));

    float t = pc.time;
    float silkTex = fbm(vec2(p.x * 1.4 + t * 0.02, p.y * 3.8 - t * 0.015));

    // 9 overlapping analytical silk strands (zero triangle/mesh aliasing)
    float bodyAccum = 0.0;
    float crestAccum = 0.0;
    for (int i = 0; i < 9; ++i) {
        float fi = float(i);
        float seed = fi * 0.67 + 0.3;
        float yOffset = (fi - 4.0) * 0.014 - 0.04;
        float y = waveCurve(p.x, seed, t) + yOffset;
        float d = p.y - y;

        // Asymmetric silk ribbon: soft body underneath, crisp glowing upper crest
        float width = 0.022 + 0.016 * sin(fi * 1.7 + p.x * 0.8 + t * 0.05);
        float body = exp(-(d * d) / (width * width * 1.8));
        float crest = exp(-abs(d) / (0.0022 + 0.0012 * (1.0 - silkTex)));

        float mod = 0.55 + 0.75 * smoothstep(0.25, 0.78, silkTex + 0.12 * sin(fi + p.x));
        float weight = (0.11 + 0.05 * sin(fi * 2.1)) * mod;
        bodyAccum += body * weight;
        crestAccum += crest * (0.14 + 0.10 * mod);
    }

    vec3 silkTint = mix(vec3(0.45, 0.72, 1.0), vec3(0.86, 0.94, 1.0), 0.45);
    col += silkTint * clamp(bodyAccum, 0.0, 0.85) * 0.42;
    col += vec3(0.88, 0.95, 1.0) * clamp(crestAccum, 0.0, 1.0) * 0.38;

    // Soft pinpoint sparkles
    vec2 dustUv = vec2(uv.x * (res.x / res.y), uv.y);
    float dust = sparkleLayer(dustUv, 14.0, 0.55, 0.970)
               + sparkleLayer(dustUv + vec2(7.3, 4.1), 24.0, 0.35, 0.978) * 0.65;
    col += vec3(0.88, 0.95, 1.0) * clamp(dust, 0.0, 1.0) * 0.65;

    // Subtle film-grain dither to eliminate 8-bit gradient banding
    float dither = (hash12(gl_FragCoord.xy + fract(t) * 100.0) - 0.5) * (1.5 / 255.0);
    col += dither;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * pc.qt_Opacity;
}
