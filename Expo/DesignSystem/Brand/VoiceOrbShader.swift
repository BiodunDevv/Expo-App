// Voice Orb shader: a breathing liquid sphere that responds to voice activity.
// Ported from the WebGL shader of beUI's Voice Orb (MIT License,
// Copyright (c) starc007, https://github.com/starc007/ui-components).
// It is compiled when first used, so building Expo needs no Metal toolchain.
enum VoiceOrbShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms { float2 size; float time; float activity; float4 base; float4 light; float4 dark; };
struct Corner { float4 position [[position]]; };

vertex Corner orbVertex(uint index [[vertex_id]]) {
    // One triangle that covers the whole view.
    float2 points[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    return { float4(points[index], 0, 1) };
}

static float orbHash(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

static float orbNoise(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(orbHash(i), orbHash(i + float3(1, 0, 0)), f.x),
                   mix(orbHash(i + float3(0, 1, 0)), orbHash(i + float3(1, 1, 0)), f.x), f.y),
               mix(mix(orbHash(i + float3(0, 0, 1)), orbHash(i + float3(1, 0, 1)), f.x),
                   mix(orbHash(i + float3(0, 1, 1)), orbHash(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

static float orbFbm(float3 p) {
    return orbNoise(p) * 0.57 + orbNoise(p * 2.03 + 7.2) * 0.28 + orbNoise(p * 4.07 + 3.1) * 0.15;
}

fragment float4 orbFragment(Corner in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 size = u.size;
    float time = u.time;
    float activity = u.activity;
    float2 position = in.position.xy;
    float side = min(size.x, size.y);
    float2 p = (position * 2.0 - size) / side;
    p.y = -p.y;
    float t = time * 0.38;
    float angle = atan2(p.y, p.x);
    float breath = sin(time * 1.4) * 0.008;
    float ripple = sin(angle * 3.0 + t * 2.1) * 0.55
                 + sin(angle * 5.0 - t * 1.7) * 0.30
                 + sin(angle * 2.0 + t) * 0.15;
    p /= 0.91 + breath + activity * 0.025 + ripple * (0.004 + activity * 0.024);
    float r2 = dot(p, p);
    float aa = 3.0 / side;
    float alpha = 1.0 - smoothstep(1.0 - aa, 1.0, r2);
    if (alpha <= 0.0) return float4(0.0);
    float3 normal = float3(p, sqrt(max(0.0, 1.0 - r2)));
    float3 flow = float3(normal.xy * 1.65, normal.z * 1.4);
    flow.xy += float2(sin(normal.y * 2.6 + t), cos(normal.x * 2.3 - t * 0.8)) * (0.25 + activity * 0.22);
    float3 warp = float3(orbNoise(flow + float3(0.0, t, t * 0.3)),
                         orbNoise(flow + float3(4.7, -t * 0.7, t)),
                         orbNoise(flow + float3(t * 0.5, 9.2, -t))) - 0.5;
    float pigment = orbFbm(flow + warp * 1.4 + float3(t * 0.3, -t * 0.2, t * 0.4));
    float fold = normal.x * 0.50 + normal.y * 0.32 + sin(normal.y * 2.6 - t) * 0.30 + (pigment - 0.5) * 0.65;
    float shadow = smoothstep(-0.30, 0.42, fold);
    float3 lightColor = float3(u.light.rgb);
    float3 color = mix(float3(u.dark.rgb), float3(u.base.rgb), shadow);
    color = mix(color, lightColor, smoothstep(0.40, 0.82, pigment) * 0.34);
    float diffuse = max(0.0, dot(normal, normalize(float3(-0.4, 0.65, 1.0))));
    color *= 0.64 + 0.46 * diffuse;
    float shine = exp(-pow((fold + 0.06) * 8.0, 2.0)) * pow(normal.z, 0.65);
    float innerLight = exp(-pow((fold - 0.28) * 4.0, 2.0)) * normal.z;
    color = mix(color, lightColor, innerLight * (0.18 + activity * 0.16));
    color = mix(color, mix(lightColor, float3(1.0), 0.55), shine * 0.78);
    float gleam = pow(max(0.0, dot(normal, normalize(float3(-0.45, 0.55, 1.0)))), 24.0);
    color += gleam * 0.16;
    float rim = pow(1.0 - normal.z, 3.0);
    color = mix(color, lightColor, rim * (0.36 + 0.25 * max(0.0, -normal.x)));
    color += (orbHash(float3(position, 1.0)) - 0.5) * 0.032;
    // The layer expects premultiplied color.
    return float4(clamp(color, 0.0, 1.0) * alpha, alpha);
}
"""#
}
