/* Firmware-exact PS3 SPU captured cloth vertex shader with:
 *  - Catmull-Rom cubic interpolation across 64 128x128 keyframes (wave_atlas.png)
 *  - Dynamic per-frame normal perturbation from live neighboring cloth vertices
 *  - Navigation impulse swells (waveVelX / waveVelY) matching xmb-web impulseDy()
 */

#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec3 vNrm;
layout(location = 1) out vec2 vUV;

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

layout(binding = 1) uniform sampler2D atlas;
layout(binding = 2) uniform sampler2D normalMap;

const vec2 MIN_NDC = vec2(-2.572977, -0.762615);
const vec2 RANGE_NDC = vec2(1.877702 - (-2.572977), 0.259765 - (-0.762615));

vec2 sampleFrame(int frameIdx, vec2 gridCoord) {
    vec2 gc = clamp(gridCoord, vec2(0.0), vec2(127.0));
    float fx = float(frameIdx - (frameIdx / 8) * 8) * 128.0;
    float fy = float(frameIdx / 8) * 128.0;

    vec2 uvHi = vec2((fx + gc.x + 0.5) / 2048.0, (fy + gc.y + 0.5) / 1024.0);
    vec2 uvLo = vec2((1024.0 + fx + gc.x + 0.5) / 2048.0, (fy + gc.y + 0.5) / 1024.0);

    vec2 hi = floor(texture(atlas, uvHi).rg * 255.0 + 0.5);
    vec2 lo = floor(texture(atlas, uvLo).rg * 255.0 + 0.5);
    vec2 norm = (hi * 256.0 + lo) / 65535.0;
    return MIN_NDC + norm * RANGE_NDC;
}

vec2 sampleCubic(int im1, int i0, int i1, int i2, float t, float t2, float t3, vec2 gc) {
    vec2 P0 = sampleFrame(im1, gc);
    vec2 A  = sampleFrame(i0,  gc);
    vec2 B  = sampleFrame(i1,  gc);
    vec2 P3 = sampleFrame(i2,  gc);
    return 0.5 * ((2.0 * A)
                + (-P0 + B) * t
                + (2.0 * P0 - 5.0 * A + 4.0 * B - P3) * t2
                + (-P0 + 3.0 * A - 3.0 * B + P3) * t3);
}

float impulseDy(float xN) {
    float total = 0.0;
    if (abs(pc.waveVelX) > 0.0001) {
        float cx = clamp(pc.waveVelX * 2.5, -0.25, 0.25);
        float dx = xN - cx;
        total += pc.waveVelX * exp(-(dx * dx) / (0.55 * 0.55));
    }
    if (abs(pc.waveVelY) > 0.0001) {
        float dx = xN + 0.25;
        total += pc.waveVelY * exp(-(dx * dx) / (0.70 * 0.70));
    }
    return total;
}

void main() {
    vec2 gridCoord = floor(qt_MultiTexCoord0 * 127.0 + 0.5);

    float p = mod(pc.framePhase, 64.0);
    int i0 = int(floor(p));
    int im1 = (i0 + 63) - ((i0 + 63) / 64) * 64;
    int i1 = (i0 + 1) - ((i0 + 1) / 64) * 64;
    int i2 = (i0 + 2) - ((i0 + 2) / 64) * 64;
    float t = fract(p);
    float t2 = t * t;
    float t3 = t2 * t;

    vec2 ndc = sampleCubic(im1, i0, i1, i2, t, t2, t3, gridCoord);

    // Smoothly interpolated per-frame normal perturbation (no integer-keyframe pop/blink)
    vec2 ndcRight = mix(sampleFrame(i0, gridCoord + vec2(1.0, 0.0)),
                        sampleFrame(i1, gridCoord + vec2(1.0, 0.0)), t);
    vec2 ndcDown  = mix(sampleFrame(i0, gridCoord + vec2(0.0, 1.0)),
                        sampleFrame(i1, gridCoord + vec2(0.0, 1.0)), t);
    vec2 basePos  = sampleFrame(0,  gridCoord);
    vec2 baseR    = sampleFrame(0,  gridCoord + vec2(1.0, 0.0));
    vec2 baseD    = sampleFrame(0,  gridCoord + vec2(0.0, 1.0));

    vec2 deltaSlope = ((ndcRight - ndc) - (baseR - basePos)) * 18.0
                    + ((ndcDown  - ndc) - (baseD - basePos)) * 18.0;

    vec2 nrmUV = (gridCoord + 0.5) / 128.0;
    vec3 staticNrm = texture(normalMap, nrmUV).rgb * 2.0 - 1.0;
    vNrm = normalize(staticNrm + vec3(-deltaSlope.y, deltaSlope.x, 0.0) * 0.55);

    // Apply smooth 2nd-order navigation swell & subtle horizontal silk glide
    ndc.y += impulseDy(ndc.x) * 0.16;
    ndc.x -= pc.waveVelX * 0.12 * (0.6 + 0.4 * (1.0 - abs(qt_MultiTexCoord0.y * 2.0 - 1.0)));
    ndc.y *= pc.scaleY;
    vUV = qt_MultiTexCoord0;

    vec2 res = max(pc.resolution, vec2(1.0));
    vec2 screenPos = vec2((ndc.x * 0.5 + 0.5) * res.x, (0.5 - ndc.y * 0.5) * res.y);
    gl_Position = pc.qt_Matrix * vec4(screenPos, 0.0, 1.0);
}
