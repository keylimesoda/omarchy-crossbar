/* Firmware-exact PS3 SPU captured cloth vertex shader.
 * Replays 64 seamlessly crossfaded 128x128 keyframes from wave_atlas.png
 * using Catmull-Rom cubic interpolation + static normals from wave_normals.png.
 * Adapted from TheGammaSqueeze/xmb-web (VS_WAVECAP).
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
} pc;

layout(binding = 1) uniform sampler2D atlas;
layout(binding = 2) uniform sampler2D normalMap;

const vec2 MIN_NDC = vec2(-2.572977, -0.762615);
const vec2 RANGE_NDC = vec2(1.877702 - (-2.572977), 0.259765 - (-0.762615));

vec2 sampleFrame(int frameIdx, vec2 gridCoord) {
    float fx = float(frameIdx - (frameIdx / 8) * 8) * 128.0;
    float fy = float(frameIdx / 8) * 128.0;

    vec2 uvHi = vec2((fx + gridCoord.x + 0.5) / 2048.0, (fy + gridCoord.y + 0.5) / 1024.0);
    vec2 uvLo = vec2((1024.0 + fx + gridCoord.x + 0.5) / 2048.0, (fy + gridCoord.y + 0.5) / 1024.0);

    vec2 hi = floor(texture(atlas, uvHi).rg * 255.0 + 0.5);
    vec2 lo = floor(texture(atlas, uvLo).rg * 255.0 + 0.5);
    vec2 norm = (hi * 256.0 + lo) / 65535.0;
    return MIN_NDC + norm * RANGE_NDC;
}

void main() {
    // GridMesh resolution is 127x127 quads = 128x128 vertices -> [0..127]
    vec2 gridCoord = floor(qt_MultiTexCoord0 * 127.0 + 0.5);

    float p = mod(pc.framePhase, 64.0);
    int i0 = int(floor(p));
    int im1 = (i0 + 63) - ((i0 + 63) / 64) * 64;
    int i1 = (i0 + 1) - ((i0 + 1) / 64) * 64;
    int i2 = (i0 + 2) - ((i0 + 2) / 64) * 64;
    float t = fract(p);
    float t2 = t * t;
    float t3 = t2 * t;

    vec2 P0 = sampleFrame(im1, gridCoord);
    vec2 A  = sampleFrame(i0,  gridCoord);
    vec2 B  = sampleFrame(i1,  gridCoord);
    vec2 P3 = sampleFrame(i2,  gridCoord);

    // Catmull-Rom C1-continuous cubic interpolation across keyframes
    vec2 ndc = 0.5 * ((2.0 * A)
                    + (-P0 + B) * t
                    + (2.0 * P0 - 5.0 * A + 4.0 * B - P3) * t2
                    + (-P0 + 3.0 * A - 3.0 * B + P3) * t3);

    ndc.y *= pc.scaleY;

    vec2 nrmUV = (gridCoord + 0.5) / 128.0;
    vNrm = texture(normalMap, nrmUV).rgb * 2.0 - 1.0;
    vUV = qt_MultiTexCoord0;

    vec2 res = max(pc.resolution, vec2(1.0));
    vec2 screenPos = vec2((ndc.x * 0.5 + 0.5) * res.x, (0.5 - ndc.y * 0.5) * res.y);
    gl_Position = pc.qt_Matrix * vec4(screenPos, 0.0, 1.0);
}
