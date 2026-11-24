/* Firmware-accurate PS3 particles.elf shader (ported from xmb-web buildParticleData):
 *  - Physical camera Depth of Field (FOCUS_Z = 5.8):
 *      * In-focus motes  -> tiny, razor-sharp, blazing bright pinpoints
 *      * Out-of-focus    -> larger, softer, dimmer bokeh circles (energy-conserving)
 *  - Spinning 3D facet normal (sx0, sx1) reflecting Sony's spot light (4.16, 2.63, -7.6)
 *    for authentic tumbling-glitter specular flashes
 *  - Smooth lifetime turnover (12% fade-in, 63% hold, 25% fade-out)
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
const vec3 SPOT_L = normalize(vec3(4.16, 2.63, -7.6));
const float FOCUS_Z = 5.8;

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

// Physical spinning-normal specular flash against PS3 firmware spotlight
float facetReflectance(vec3 eyePos, float t, float h0, float h1, float id) {
    vec3 V = normalize(-eyePos);
    vec3 H = normalize(SPOT_L + V);

    float sx0 = id * 6.28318 + t * (0.45 + h0 * 1.15);
    float sx1 = h1 * 6.28318 + t * (0.35 + h1 * 0.95);
    float s0 = sin(sx0);
    vec3 N = vec3(s0 * cos(sx1), s0 * sin(sx1), cos(sx0));

    float ndh = max(dot(N, H), 0.0);
    float ndv = max(dot(N, V), 0.0);
    float spec = pow(ndh, 28.0) * 2.8;
    float fres = pow(1.0 - ndv, 3.0) * 0.18;
    return 0.10 + spec + fres;
}

// Dense tumbling-flake micro-glitter layer at a given focal depth
vec3 flakeLayer(vec2 aspectUV, vec2 screenUV, float scale, float layerDepth,
                float densityThreshold, float bandSigma, float pxScale, float seedOff) {
    float depthFactor = clamp(FOCUS_Z / layerDepth, 0.70, 1.40);
    vec2 drift = vec2(-0.010, -0.003) * pc.time + vec2(pc.parallaxX * 0.14, -pc.parallaxY * 0.08) * depthFactor;
    vec2 p = aspectUV * scale + drift + vec2(seedOff * 19.3, seedOff * 11.7);
    vec2 cell = floor(p);
    vec2 f = fract(p) - 0.5;

    // Smooth lifetime turnover (12% fade-in, 63% hold, 25% fade-out) with respawn per cycle
    float baseH = hash12(cell + seedOff * 23.1);
    float lifeDur = 2.4 + baseH * 3.6;
    float tNorm = (pc.time + hash12(cell + vec2(9.1, 4.3) + seedOff) * 20.0) / lifeDur;
    float cycle = floor(tNorm);
    float age = fract(tNorm);
    float ageF = (age < 0.12) ? (age / 0.12) : ((age > 0.75) ? ((1.0 - age) / 0.25) : 1.0);
    if (ageF < 0.01) return vec3(0.0);

    vec2 cycleSeed = cell + vec2(cycle * 7.13 + seedOff * 31.1, cycle * 3.71 + seedOff * 17.9);
    float spawnId = hash12(cycleSeed);
    if (spawnId < densityThreshold) return vec3(0.0);

    float h0 = hash12(cycleSeed + vec2(17.3, 5.1));
    float h1 = hash12(cycleSeed + vec2(3.7, 29.4));

    // Gentle Brownian-like hover inside the cell
    vec2 pos = (vec2(h0, h1) - 0.5) * 0.68
             + vec2(sin(pc.time * (0.25 + h0 * 0.35) + spawnId * 25.0),
                    cos(pc.time * (0.22 + h1 * 0.30) + spawnId * 19.0)) * 0.10;

    float bandY = 0.485 - 0.048 * sin((screenUV.x - 0.14) * 2.5);
    float dy = screenUV.y - bandY;
    float bandMask = exp(-(dy * dy) / (bandSigma * bandSigma));
    if (bandMask < 0.02) return vec3(0.0);

    // Physical Depth of Field: defocus enlarges radius AND dims intensity (energy conservation)
    float defocus = abs(layerDepth - FOCUS_Z) / 2.2;
    float radiusPx = (1.15 + defocus * 3.6) * pxScale * (0.75 + 0.50 * h1);
    float dofDim = 1.0 / (1.0 + defocus * defocus * 2.6);

    float cellPx = pc.resolution.y / scale;
    float d = length(f - pos) / max(radiusPx / max(cellPx, 1.0), 0.002);
    if (d > 1.0) return vec3(0.0);

    float d2 = d * d;
    // In-focus = sharp specular pinpoint; out-of-focus = soft bokeh circle
    float sharp = exp(-d2 * 9.0) + exp(-d2 * 2.8) * 0.18;
    float softBokeh = smoothstep(1.0, 0.35, d) * 0.75;
    float shape = mix(sharp, softBokeh, clamp(defocus * 0.85, 0.0, 1.0));

    vec3 eyePos = vec3((screenUV.x * 2.0 - 1.0) * 5.0, (0.5 - screenUV.y) * 2.5, -layerDepth);
    float refl = facetReflectance(eyePos, pc.time, h0, h1, spawnId);

    float edgeBoost = smoothstep(0.55, 0.95, abs(screenUV.x * 2.0 - 1.0));
    float intensity = shape * refl * ageF * bandMask * dofDim;
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

    // 4 in-focus crisp tumbling-flake layers tightly carpeting the ribbon (depth ~5.5-6.1)
    accum += flakeLayer(aspectUV, uv, 34.0, 5.80, 0.42, 0.085, pxScale, 1.0);
    accum += flakeLayer(aspectUV, uv, 48.0, 5.65, 0.46, 0.070, pxScale, 2.0);
    accum += flakeLayer(aspectUV, uv, 64.0, 5.95, 0.50, 0.065, pxScale, 3.0);
    accum += flakeLayer(aspectUV, uv, 82.0, 5.75, 0.54, 0.095, pxScale, 4.0);
    // 2 slightly defocused mid-depth layers (softer, wider stragglers around the wave)
    accum += flakeLayer(aspectUV, uv, 24.0, 4.70, 0.68, 0.180, pxScale, 5.0);
    accum += flakeLayer(aspectUV, uv, 19.0, 7.10, 0.72, 0.220, pxScale, 6.0);

    // 40 3D RPCS3 draw-36 particles with exact DoF (near/far = soft dim bokeh, mid = sharp glint)
    for (int i = 0; i < 40; ++i) {
        float fi = float(i) * 4.5;
        vec3 raw = texture(cloudTex, vec2((fi + 0.5) / 192.0, 0.5)).rgb;
        vec3 eye = MIN_EYE + raw * RANGE_EYE;

        float h0 = hash11(fi * 1.37 + 11.0);
        float h1 = hash11(fi * 2.91 + 37.0);
        float depth = max(2.6, -eye.z);
        float depthFactor = clamp(FOCUS_Z / depth, 0.75, 1.45);

        float orbLife = 6.5 + h0 * 6.5;
        float age = fract((t + h1 * 24.0) / orbLife);
        float ageF = (age < 0.12) ? (age / 0.12) : ((age > 0.75) ? ((1.0 - age) / 0.25) : 1.0);
        if (ageF < 0.01) continue;

        float wanderX = sin(t * (0.12 + h0 * 0.14) + fi * 2.3) * 0.40 + (age - 0.5) * 0.28;
        float wanderY = sin(t * (0.15 + h1 * 0.16) + fi * 1.7) * 0.16 - (age - 0.5) * 0.10;
        float px = mod(eye.x + wanderX - pc.parallaxX * depthFactor + 7.73, 13.24) - 7.73;
        float py = eye.y * 0.60 + 0.12 + wanderY + pc.parallaxY * depthFactor * 0.45;

        vec2 ndc = vec2(px / (depth * 0.58 * aspect), py / (depth * 0.58));
        vec2 centerPx = vec2((ndc.x * 0.5 + 0.5) * res.x, (0.5 - ndc.y * 0.5) * res.y);

        // Energy-conserving Depth of Field from FOCUS_Z = 5.8
        float defocus = abs(depth - FOCUS_Z) / 1.65;
        float radiusPx = max(1.6, (1.6 + defocus * 5.2) * pxScale);
        float dofDim = 1.0 / (1.0 + defocus * defocus * 2.4);

        vec2 coord = (fragPx - centerPx) / radiusPx;
        float d2 = dot(coord, coord);
        if (d2 < 1.0) {
            float d = sqrt(d2);
            float sharp = exp(-d2 * 8.0) + exp(-d2 * 2.5) * 0.22;
            float softBokeh = smoothstep(1.0, 0.40, d) * 0.62
                            + smoothstep(0.55, 0.85, d) * smoothstep(1.0, 0.80, d) * 0.22;
            float shape = mix(sharp, softBokeh, clamp(defocus * 0.85, 0.0, 1.0));

            float refl = facetReflectance(vec3(px, py, -depth), t, h0, h1, fi * 0.13);
            float brightness = shape * refl * ageF * dofDim * 0.95;
            float edgeBoost = smoothstep(0.55, 0.95, abs(ndc.x));
            vec3 pCol = mix(metallicTint(h1, edgeBoost), vec3(1.0), clamp(brightness * 0.4, 0.0, 1.0));
            accum += pCol * brightness;
        }
    }

    // Output at 0.5x HDR scale (pure additive alpha = 0.0) so specular flashes catch HDR bloom
    fragColor = vec4(clamp(accum * 0.5, vec3(0.0), vec3(1.0)) * pc.qt_Opacity, 0.0);
}
