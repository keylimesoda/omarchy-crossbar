/* Firmware-extracted 3D eye-space PS3 dust motes (RPCS3 draw 36).
 * Projects 192 3D points from particle_cloud.png as tiny, crisp, slowly
 * drifting round PS3 sparkles (no artificial crosses or oversized bokeh).
 */

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float time;
    float waveVelX;
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

void main() {
    vec2 res = max(pc.resolution, vec2(1.0));
    vec2 fragPx = qt_TexCoord0 * res;
    float aspect = res.x / res.y;
    float pxScale = res.y / 1080.0;
    float t = pc.time;

    vec3 accum = vec3(0.0);

    for (int i = 0; i < 192; ++i) {
        float fi = float(i);
        vec3 raw = texture(cloudTex, vec2((fi + 0.5) / 192.0, 0.5)).rgb;
        vec3 eye = MIN_EYE + raw * RANGE_EYE;

        float h0 = hash11(fi * 1.37 + 11.0);
        float h1 = hash11(fi * 2.91 + 37.0);

        // Slow, hypnotic, independent 3D drift (no keypress snap)
        float driftX = mod(eye.x + t * (0.018 + h0 * 0.024) + 7.73, 13.24) - 7.73;
        float driftY = eye.y + sin(t * (0.18 + h1 * 0.22) + fi * 1.7) * 0.08;
        float depth = max(2.4, -eye.z);

        // Perspective projection matching PS3 camera FOV
        vec2 ndc = vec2(driftX / (depth * 0.58 * aspect), driftY / (depth * 0.58));
        vec2 centerPx = vec2((ndc.x * 0.5 + 0.5) * res.x, (0.5 - ndc.y * 0.5) * res.y);

        // Tiny, crisp PS3 dust motes (~1.2px to 3.0px at 1080p, scaled gently by depth)
        float depthFactor = clamp(4.8 / depth, 0.65, 1.35);
        float radiusPx = max(1.1, (1.1 + pow(h1, 3.0) * 2.0) * depthFactor * pxScale);

        vec2 coord = (fragPx - centerPx) / radiusPx;
        float d2 = dot(coord, coord);
        if (d2 < 1.0) {
            float twinkle = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * (0.55 + h0 * 1.1) + fi * 4.3));
            float mote = exp(-d2 * 6.5) + exp(-d2 * 2.2) * 0.22;
            float brightness = mote * twinkle * (0.28 + 0.55 * h0);
            vec3 pCol = mix(vec3(0.84, 0.92, 1.0), vec3(1.0), clamp(brightness, 0.0, 1.0));
            accum += pCol * brightness;
        }
    }

    // Output at 0.5x HDR scale (pure additive alpha = 0.0)
    fragColor = vec4(clamp(accum * 0.5, vec3(0.0), vec3(1.0)) * pc.qt_Opacity, 0.0);
}
