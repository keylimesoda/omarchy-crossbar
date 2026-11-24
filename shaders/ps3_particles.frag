/* PS3 XMB sparkling fairy-dust particle field:
 *  - 5 multi-speed, wave-hugging micro-glitter layers (hundreds of crisp
 *    twinkling pinpoints densely concentrated along the silk ribbon)
 *  - 48 3D eye-space RPCS3 draw-36 foreground bokeh/glitter orbs (particle_cloud.png)
 *  - Smooth depth-scaled 3D navigation parallax (parallaxX / parallaxY)
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

// One independent layer of crisp, wave-hugging micro-glitter motes
float glitterLayer(vec2 aspectUV, vec2 screenUV, float scale, vec2 vel, float depthFactor,
                   float densityThreshold, float bandSigma, float sizePx, float pxScale, float seedOff) {
    vec2 drift = vel * pc.time + vec2(pc.parallaxX * 0.06, -pc.parallaxY * 0.04) * depthFactor;
    vec2 p = aspectUV * scale + drift + vec2(seedOff * 13.7, seedOff * 7.3);
    vec2 cell = floor(p);
    vec2 f = fract(p) - 0.5;

    float id = hash12(cell + seedOff * 31.1);
    if (id < densityThreshold) return 0.0;

    // Gentle local organic wander inside the cell so particles don't feel locked to a grid
    float h0 = hash12(cell + vec2(17.3, 5.1) + seedOff);
    float h1 = hash12(cell + vec2(3.7, 29.4) + seedOff);
    vec2 jitter = (vec2(h0, h1) - 0.5) * 0.68
                + vec2(sin(pc.time * (0.4 + h0 * 0.5) + id * 20.0),
                       cos(pc.time * (0.35 + h1 * 0.5) + id * 17.0)) * 0.08;

    // Wave-band vertical envelope hugging the SPU ribbon contour
    float bandY = 0.545 - 0.048 * sin((screenUV.x - 0.14) * 2.5);
    float dy = screenUV.y - bandY;
    float bandMask = exp(-(dy * dy) / (bandSigma * bandSigma));
    if (bandMask < 0.02) return 0.0;

    // Pixel-accurate crisp radius (stays razor-sharp at 1080p and 4K)
    float cellPx = (pc.resolution.y / scale);
    float rUV = (sizePx * pxScale * (0.55 + 0.85 * h1)) / max(cellPx, 1.0);
    float d = length(f - jitter) / max(rUV, 0.002);
    if (d > 1.0) return 0.0;

    float d2 = d * d;
    float core = exp(-d2 * 7.5) + exp(-d2 * 2.4) * 0.25;
    // Sharp diamond-dust twinkle (flashes bright white, fades smoothly to zero)
    float twinkle = pow(0.5 + 0.5 * sin(pc.time * (0.7 + h0 * 1.9) + id * 47.0), 2.6);
    return core * (0.15 + 0.85 * twinkle) * bandMask * (0.55 + 0.75 * h0);
}

void main() {
    vec2 res = max(pc.resolution, vec2(1.0));
    vec2 uv = qt_TexCoord0;
    vec2 fragPx = uv * res;
    float aspect = res.x / res.y;
    float pxScale = res.y / 1080.0;
    vec2 aspectUV = vec2(uv.x * aspect, uv.y);
    float t = pc.time;

    float glitter = 0.0;
    // 3 dense micro-glitter layers tightly hugging the silk ribbon
    glitter += glitterLayer(aspectUV, uv, 26.0, vec2(-0.08, -0.025), 0.85, 0.76, 0.085, 1.6, pxScale, 1.0) * 1.15;
    glitter += glitterLayer(aspectUV, uv, 38.0, vec2(-0.13,  0.018), 1.05, 0.78, 0.070, 1.4, pxScale, 2.0) * 1.05;
    glitter += glitterLayer(aspectUV, uv, 52.0, vec2(-0.05, -0.012), 0.65, 0.82, 0.105, 1.2, pxScale, 3.0) * 0.90;
    // 2 sparser floating straggler layers slightly wider above/below the wave
    glitter += glitterLayer(aspectUV, uv, 18.0, vec2(-0.06, -0.030), 1.20, 0.86, 0.200, 2.2, pxScale, 4.0) * 0.85;
    glitter += glitterLayer(aspectUV, uv, 13.0, vec2(-0.10,  0.015), 1.40, 0.91, 0.240, 3.0, pxScale, 5.0) * 0.75;

    vec3 accum = vec3(0.90, 0.96, 1.0) * glitter;

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
        float py = eye.y * 0.65 + wanderY + pc.parallaxY * depthFactor * 0.45;

        vec2 ndc = vec2(px / (depth * 0.58 * aspect), py / (depth * 0.58));
        vec2 centerPx = vec2((ndc.x * 0.5 + 0.5) * res.x, (0.5 - ndc.y * 0.5) * res.y);

        // Occasional larger soft bokeh orbs (like the glowing edge specks in PS3 XMB)
        float radiusPx = max(1.8, (2.0 + pow(h1, 3.0) * 4.8) * depthFactor * pxScale);
        vec2 coord = (fragPx - centerPx) / radiusPx;
        float d2 = dot(coord, coord);
        if (d2 < 1.0) {
            float twinkle = pow(0.5 + 0.5 * sin(t * (0.55 + h0 * 1.2) + fi * 4.3), 2.0);
            float orb = exp(-d2 * 5.5) + exp(-d2 * 1.9) * 0.32;
            float brightness = orb * (0.20 + 0.80 * twinkle) * (0.45 + 0.65 * h0);
            vec3 pCol = mix(vec3(0.84, 0.93, 1.0), vec3(1.0), clamp(brightness, 0.0, 1.0));
            accum += pCol * brightness;
        }
    }

    // Output at 0.5x HDR scale (pure additive alpha = 0.0) so bright glints catch the HDR bloom
    fragColor = vec4(clamp(accum * 0.5, vec3(0.0), vec3(1.0)) * pc.qt_Opacity, 0.0);
}
