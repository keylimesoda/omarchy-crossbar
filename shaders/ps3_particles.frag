/* PS3 XMB sparkling fairy-dust particle field:
 *  - 5 wave-hugging micro-glitter layers with organic hover-around-home motion
 *    and unified depth-scaled 3D navigation parallax
 *  - 48 3D eye-space RPCS3 draw-36 foreground bokeh/glitter orbs (particle_cloud.png)
 *  - Metallic gold / silver / white glitter tinting (from xmb-web spawnParticle)
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
    // ~15% of bright/edge glints get warm gold or cool silver metallic reflection
    float chance = mix(0.86, 0.72, edgeBoost);
    if (h < chance) return vec3(0.92, 0.96, 1.0);
    float pick = fract((h - chance) * 19.7);
    if (pick < 0.36) return vec3(1.00, 0.80, 0.38); // warm gold
    if (pick < 0.70) return vec3(0.86, 0.89, 1.00); // cool silver
    return vec3(1.00, 1.00, 1.00);                  // pure white glint
}

// One independent layer of crisp, wave-hugging micro-glitter motes
vec3 glitterLayer(vec2 aspectUV, vec2 screenUV, float scale, vec2 vel, float depthFactor,
                  float densityThreshold, float bandSigma, float sizePx, float pxScale, float seedOff) {
    // Unified gentle drift + depth-scaled navigation parallax matching the 3D orbs
    vec2 drift = vel * pc.time + vec2(pc.parallaxX * 0.14, -pc.parallaxY * 0.08) * depthFactor;
    vec2 p = aspectUV * scale + drift + vec2(seedOff * 13.7, seedOff * 7.3);
    vec2 cell = floor(p);
    vec2 f = fract(p) - 0.5;

    float id = hash12(cell + seedOff * 31.1);
    if (id < densityThreshold) return vec3(0.0);

    // Organic Lissajous hover around each mote's home position
    float h0 = hash12(cell + vec2(17.3, 5.1) + seedOff);
    float h1 = hash12(cell + vec2(3.7, 29.4) + seedOff);
    vec2 jitter = (vec2(h0, h1) - 0.5) * 0.58
                + vec2(sin(pc.time * (0.28 + h0 * 0.35) + id * 20.0),
                       cos(pc.time * (0.24 + h1 * 0.35) + id * 17.0)) * 0.14;

    // Wave-band vertical envelope hugging the PS3-aligned SPU ribbon contour
    float bandY = 0.485 - 0.048 * sin((screenUV.x - 0.14) * 2.5);
    float dy = screenUV.y - bandY;
    float bandMask = exp(-(dy * dy) / (bandSigma * bandSigma));
    if (bandMask < 0.02) return vec3(0.0);

    float cellPx = (pc.resolution.y / scale);
    float rUV = (sizePx * pxScale * (0.55 + 0.85 * h1)) / max(cellPx, 1.0);
    float d = length(f - jitter) / max(rUV, 0.002);
    if (d > 1.0) return vec3(0.0);

    float d2 = d * d;
    float core = exp(-d2 * 9.0) + exp(-d2 * 2.8) * 0.20;
    // Dual-frequency sharp glittery scintillation (brief crisp diamond-dust flashes)
    float s1 = 0.5 + 0.5 * sin(pc.time * (1.1 + h0 * 2.4) + id * 47.0);
    float s2 = 0.5 + 0.5 * cos(pc.time * (0.65 + h1 * 1.8) - id * 31.0);
    float glint = pow(s1 * s2, 3.2);
    float edgeBoost = smoothstep(0.55, 0.95, abs(screenUV.x * 2.0 - 1.0));
    float intensity = core * (0.08 + 1.35 * glint) * bandMask * (0.55 + 0.75 * h0);
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
    // 3 dense micro-glitter layers tightly hugging the silk ribbon (subtle drift + organic hover)
    accum += glitterLayer(aspectUV, uv, 26.0, vec2(-0.016, -0.006), 0.85, 0.76, 0.085, 1.6, pxScale, 1.0) * 1.15;
    accum += glitterLayer(aspectUV, uv, 38.0, vec2(-0.024,  0.004), 1.05, 0.78, 0.070, 1.4, pxScale, 2.0) * 1.05;
    accum += glitterLayer(aspectUV, uv, 52.0, vec2(-0.010, -0.003), 0.65, 0.82, 0.105, 1.2, pxScale, 3.0) * 0.90;
    // 2 sparser floating straggler layers slightly wider above/below the wave
    accum += glitterLayer(aspectUV, uv, 18.0, vec2(-0.012, -0.008), 1.20, 0.86, 0.200, 2.2, pxScale, 4.0) * 0.85;
    accum += glitterLayer(aspectUV, uv, 13.0, vec2(-0.018,  0.004), 1.40, 0.91, 0.240, 3.0, pxScale, 5.0) * 0.75;

    // 48 true 3D RPCS3 foreground bokeh/glitter orbs (particle_cloud.png)
    for (int i = 0; i < 48; ++i) {
        float fi = float(i) * 4.0;
        vec3 raw = texture(cloudTex, vec2((fi + 0.5) / 192.0, 0.5)).rgb;
        vec3 eye = MIN_EYE + raw * RANGE_EYE;

        float h0 = hash11(fi * 1.37 + 11.0);
        float h1 = hash11(fi * 2.91 + 37.0);
        float depth = max(2.4, -eye.z);
        float depthFactor = clamp(4.8 / depth, 0.70, 1.45);

        float wanderX = sin(t * (0.14 + h0 * 0.16) + fi * 2.3) * 0.30;
        float wanderY = sin(t * (0.18 + h1 * 0.20) + fi * 1.7) * 0.12;
        float px = mod(eye.x + wanderX - pc.parallaxX * depthFactor + 7.73, 13.24) - 7.73;
        float py = eye.y * 0.65 + 0.12 + wanderY + pc.parallaxY * depthFactor * 0.45;

        vec2 ndc = vec2(px / (depth * 0.58 * aspect), py / (depth * 0.58));
        vec2 centerPx = vec2((ndc.x * 0.5 + 0.5) * res.x, (0.5 - ndc.y * 0.5) * res.y);

        float radiusPx = max(2.0, (2.4 + pow(h1, 2.8) * 5.6) * depthFactor * pxScale);
        vec2 coord = (fragPx - centerPx) / radiusPx;
        float d2 = dot(coord, coord);
        if (d2 < 1.0) {
            float d = sqrt(d2);
            // True lens bokeh disc (flat soft circle + subtle bright aperture rim, not a pointy Gaussian)
            float disc = smoothstep(1.0, 0.68, d);
            float rim  = smoothstep(0.50, 0.84, d) * smoothstep(1.0, 0.82, d) * 0.42;
            float orb  = disc * 0.52 + rim;
            // Sharp dual-frequency glitter scintillation
            float s1 = 0.5 + 0.5 * sin(t * (0.95 + h0 * 2.1) + fi * 4.3);
            float s2 = 0.5 + 0.5 * cos(t * (0.55 + h1 * 1.5) - fi * 2.9);
            float glint = pow(s1 * s2, 2.6);
            float brightness = orb * (0.12 + 1.15 * glint) * (0.45 + 0.65 * h0);
            float edgeBoost = smoothstep(0.55, 0.95, abs(ndc.x));
            vec3 pCol = mix(metallicTint(h1, edgeBoost), vec3(1.0), clamp(brightness * 0.45, 0.0, 1.0));
            accum += pCol * brightness;
        }
    }

    // Output at 0.5x HDR scale (pure additive alpha = 0.0) so bright glints catch the HDR bloom
    fragColor = vec4(clamp(accum * 0.5, vec3(0.0), vec3(1.0)) * pc.qt_Opacity, 0.0);
}
