/* Two-population PS3 XMB particle system:
 *  1) High-density short-lived micro-glitter: hundreds of crisp 1-2px diamond
 *     specks tightly carpeting the silk ribbon that pop in at random spots,
 *     sparkle brightly for ~0.7-1.8s, and disappear.
 *  2) Long-lived luminous foreground bokeh orbs: 36 3D eye-space RPCS3 orbs
 *     that fade in gently, float slowly for 7-13s, and drift away softly.
 */

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float time;
    float parallaxX;
    float parallaxY;
} pc;

layout(binding = 1) uniform sampler2D cloudTex;

const vec3 MIN_EYE = vec3(-7.7300, -2.5000, -7.2400);
const vec3 RANGE_EYE = vec3(5.5100 - (-7.7300), 1.1200 - (-2.5000), -2.7500 - (-7.2400));
const float PI = 3.14159265;

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 metallicTint(float h, float edgeBoost) {
    float chance = mix(0.84, 0.70, edgeBoost);
    if (h < chance) return vec3(0.94, 0.97, 1.0);
    float pick = fract((h - chance) * 19.7);
    if (pick < 0.36) return vec3(1.00, 0.82, 0.42); // warm gold
    if (pick < 0.70) return vec3(0.88, 0.92, 1.00); // cool silver
    return vec3(1.00, 1.00, 1.00);                  // pure white glint
}

// Population 1: Short-lived popping micro-glitter (spawns at a new random position every lifecycle)
vec3 popGlitterLayer(vec2 aspectUV, vec2 screenUV, float scale, float depthFactor,
                     float densityThreshold, float bandSigma, float sizePx, float pxScale, float seedOff) {
    // Very slow ambient drift + unified navigation parallax
    vec2 drift = vec2(-0.012, -0.004) * pc.time + vec2(pc.parallaxX * 0.14, -pc.parallaxY * 0.08) * depthFactor;
    vec2 p = aspectUV * scale + drift + vec2(seedOff * 19.3, seedOff * 11.7);
    vec2 cell = floor(p);
    vec2 f = fract(p) - 0.5;

    // Each cell has its own short lifecycle (~0.7s - 1.9s); seed changes every cycle
    float baseH = hash12(cell + seedOff * 23.1);
    float lifeDur = 0.70 + baseH * 1.25;
    float phaseOffset = hash12(cell + vec2(9.1, 4.3) + seedOff) * 12.0;
    float tNorm = (pc.time + phaseOffset) / lifeDur;
    float cycle = floor(tNorm);
    float age = fract(tNorm);

    // Pop-in / pop-out envelope: quick crisp flash then vanish
    float lifeEnv = pow(sin(age * PI), 1.8);
    if (lifeEnv < 0.02) return vec3(0.0);

    vec2 cycleSeed = cell + vec2(cycle * 7.13 + seedOff * 31.1, cycle * 3.71 + seedOff * 17.9);
    float spawnId = hash12(cycleSeed);
    if (spawnId < densityThreshold) return vec3(0.0);

    float h0 = hash12(cycleSeed + vec2(17.3, 5.1));
    float h1 = hash12(cycleSeed + vec2(3.7, 29.4));

    // Random spawn position inside the cell + tiny gentle drift during its brief life
    vec2 pos = (vec2(h0, h1) - 0.5) * 0.72 + vec2((age - 0.5) * 0.08, -(age - 0.5) * 0.05);

    // Wave-band vertical envelope hugging the PS3-aligned SPU ribbon contour
    float bandY = 0.485 - 0.048 * sin((screenUV.x - 0.14) * 2.5);
    float dy = screenUV.y - bandY;
    float bandMask = exp(-(dy * dy) / (bandSigma * bandSigma));
    if (bandMask < 0.02) return vec3(0.0);

    float cellPx = (pc.resolution.y / scale);
    float rUV = (sizePx * pxScale * (0.55 + 0.75 * h1)) / max(cellPx, 1.0);
    float d = length(f - pos) / max(rUV, 0.002);
    if (d > 1.0) return vec3(0.0);

    float d2 = d * d;
    float core = exp(-d2 * 8.5) + exp(-d2 * 2.6) * 0.22;
    float edgeBoost = smoothstep(0.55, 0.95, abs(screenUV.x * 2.0 - 1.0));
    float intensity = core * lifeEnv * bandMask * (0.65 + 0.95 * h0);
    return metallicTint(h1, edgeBoost) * intensity;
}

void main() {
    vec2 res = max(pc.resolution, vec2(1.0));
    vec2 uv = qt_TexCoord0;
    vec2 fragPx = uv * res;
    float aspect = res.x / res.y;
    float pxScale = res.y / 1080.0;
    vec2 aspectUV = vec2(uv.x * aspect, uv.y);
    float t = pc.time;

    vec3 accum = vec3(0.0);

    // Population 1: High-density popping micro-glitter (6 layers tightly carpeting the ribbon)
    accum += popGlitterLayer(aspectUV, uv, 30.0, 0.85, 0.42, 0.085, 1.5, pxScale, 1.0) * 1.15;
    accum += popGlitterLayer(aspectUV, uv, 42.0, 1.00, 0.45, 0.072, 1.3, pxScale, 2.0) * 1.10;
    accum += popGlitterLayer(aspectUV, uv, 56.0, 0.75, 0.48, 0.065, 1.1, pxScale, 3.0) * 1.00;
    accum += popGlitterLayer(aspectUV, uv, 72.0, 0.90, 0.54, 0.095, 1.0, pxScale, 4.0) * 0.95;
    // Slightly wider straggler micro-sparkles drifting above/below the silk
    accum += popGlitterLayer(aspectUV, uv, 24.0, 1.15, 0.68, 0.185, 1.8, pxScale, 5.0) * 0.85;
    accum += popGlitterLayer(aspectUV, uv, 18.0, 1.30, 0.76, 0.230, 2.2, pxScale, 6.0) * 0.75;

    // Population 2: Long-lived luminous foreground bokeh orbs (float gently for 7-13s)
    for (int i = 0; i < 36; ++i) {
        float fi = float(i) * 5.0;
        vec3 raw = texture(cloudTex, vec2((fi + 0.5) / 192.0, 0.5)).rgb;
        vec3 eye = MIN_EYE + raw * RANGE_EYE;

        float h0 = hash11(fi * 1.37 + 11.0);
        float h1 = hash11(fi * 2.91 + 37.0);
        float depth = max(2.4, -eye.z);
        float depthFactor = clamp(4.8 / depth, 0.75, 1.45);

        // Slow 7-13 second lifecycle: smooth fade-in, steady zen float, gentle fade-out
        float orbLife = 7.0 + h0 * 6.0;
        float orbAge = fract((t + h1 * 20.0) / orbLife);
        float orbEnv = smoothstep(0.0, 0.22, orbAge) * smoothstep(1.0, 0.78, orbAge);
        if (orbEnv < 0.01) continue;

        float wanderX = sin(t * (0.12 + h0 * 0.14) + fi * 2.3) * 0.45 + (orbAge - 0.5) * 0.35;
        float wanderY = sin(t * (0.15 + h1 * 0.16) + fi * 1.7) * 0.18 - (orbAge - 0.5) * 0.12;
        float px = mod(eye.x + wanderX - pc.parallaxX * depthFactor + 7.73, 13.24) - 7.73;
        float py = eye.y * 0.62 + 0.12 + wanderY + pc.parallaxY * depthFactor * 0.45;

        vec2 ndc = vec2(px / (depth * 0.58 * aspect), py / (depth * 0.58));
        vec2 centerPx = vec2((ndc.x * 0.5 + 0.5) * res.x, (0.5 - ndc.y * 0.5) * res.y);

        float radiusPx = max(2.8, (3.2 + pow(h1, 2.2) * 5.8) * depthFactor * pxScale);
        vec2 coord = (fragPx - centerPx) / radiusPx;
        float d2 = dot(coord, coord);
        if (d2 < 1.0) {
            float d = sqrt(d2);
            // Luminous out-of-focus camera bokeh (soft glowing disc + subtle bright rim + warm center)
            float disc = smoothstep(1.0, 0.52, d);
            float rim  = smoothstep(0.50, 0.84, d) * smoothstep(1.0, 0.80, d) * 0.35;
            float core = exp(-d2 * 3.8) * 0.45;
            float orb  = disc * 0.55 + rim + core;

            float shimmer = 0.75 + 0.25 * sin(t * (0.6 + h0 * 0.8) + fi * 3.1);
            float brightness = orb * orbEnv * shimmer * (0.55 + 0.55 * h0);
            float edgeBoost = smoothstep(0.55, 0.95, abs(ndc.x));
            vec3 pCol = mix(metallicTint(h1, edgeBoost), vec3(1.0), 0.45);
            accum += pCol * brightness;
        }
    }

    // Output at 0.5x HDR scale (pure additive alpha = 0.0) so bright glints catch the HDR bloom
    fragColor = vec4(clamp(accum * 0.5, vec3(0.0), vec3(1.0)) * pc.qt_Opacity, 0.0);
}
