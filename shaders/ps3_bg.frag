/* PS3 XMB deep sky backdrop + independent wave-hugging particles.
 * Ported from OpenXMB (shaders/monthly_background.frag & procedural_wave.vert, GPL-3.0).
 */

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

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float seedHash(float n) {
    float p = fract(n * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float waveCenterY(float x, float t) {
    float flow = t * 0.18;
    float u = clamp(x * 0.5 + 0.5, 0.0, 1.0);
    float disp = mix(
        sin(u * 6.2831853 * 0.65 - flow * 0.25) * 0.00168 + sin(u * 6.2831853 * 1.4 + flow * 0.15) * 0.008,
        sin(flow * 0.25 + u * 2.0) * 0.200 + cos(u * 4.8 + flow * 0.09) * 0.025,
        0.45);
    float y = disp + sin(x * 1.5 + t * 0.18) * 0.06;
    float base = cos(x - t * 0.5) * 0.09 - 0.1 + 0.12 * sin(x * 0.306001 + t * 0.045);
    y -= 0.22 * tanh(base * (0.5 / 0.22));
    return y * 1.9 - 0.20 + x * 0.10;
}

void main() {
    vec2 res = max(pc.resolution, vec2(1.0));
    vec2 uv = qt_TexCoord0;
    float screenY = clamp(uv.y, 0.0, 1.0);

    // OpenXMB monthly_background.frag sky gradient & envelope
    float bottomMix = smoothstep(0.65, 1.0, screenY);
    vec3 col = mix(pc.topColor.rgb, pc.bottomColor.rgb, bottomMix);
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = max(vec3(luma) + (col - vec3(luma)) * 1.22, vec3(0.0));
    float dip = exp(-pow((screenY - 0.66) / 0.16, 2.0));
    float envelope = (1.04 - 0.22 * dip) * (1.0 + 0.06 * smoothstep(0.30, 0.0, screenY));
    col *= envelope;

    // Independent floating PS3 particles (exact OpenXMB procedural_wave.vert equations)
    float tSec = pc.time + 100.0;
    float pTime = tSec * 0.18;
    float aspect = res.x / res.y;
    float ratio = clamp(aspect, 1.0, 2.0) * 0.375;
    vec2 fragPx = uv * res;
    float pxScale = res.y / 1080.0;

    float particleAccum = 0.0;
    for (int id = 0; id < 120; ++id) {
        float fid = float(id);
        vec3 r = vec3(
            seedHash(fid * 3.0 + 1337.0),
            seedHash(fid * 3.0 + 1338.0),
            pow(seedHash(fid * 3.0 + 1339.0), 8.0) + 0.1
        );
        float pxNdc = fract(pTime * (r.x - 0.5) / 15.0 + r.y * 50.0) * 2.0 - 1.0;
        float pyWave = sin(pTime * (r.y + 1.5) / 4.0 + r.x * 100.0) / ((6.0 - r.x * 4.0 * r.y) / ratio);
        float pyNdc = waveCenterY(pxNdc, tSec) + pyWave * 1.1 + 0.1;

        vec2 centerPx = vec2((pxNdc * 0.5 + 0.5) * res.x, (0.5 - pyNdc * 0.5) * res.y);
        float radiusPx = max(1.4, (r.z * 5.2 + 2.4) * pxScale);
        vec2 diff = (fragPx - centerPx) / radiusPx;
        float d2 = dot(diff, diff);
        if (d2 < 1.0) {
            float op = mix(sin(pTime * (r.x + 0.5) * 12.0 + r.y * 10.0),
                           sin(pTime * (r.y + 1.5) * 6.0 + r.x * 4.0),
                           pyWave * 0.5 + 0.5) * r.x + r.y;
            float pAlpha = op * op * (1.0 - fract(r.x + pTime * 0.00285));
            float glow = (1.0 - d2) * (1.0 - d2);
            particleAccum += clamp(pAlpha * glow * 0.55, 0.0, 0.90);
        }
    }

    col += vec3(0.88, 0.95, 1.0) * clamp(particleAccum, 0.0, 1.0);
    col += (hash12(gl_FragCoord.xy + fract(pc.time) * 100.0) - 0.5) * (1.5 / 255.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * pc.qt_Opacity;
}
