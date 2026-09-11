#include <metal_stdlib>
using namespace metal;

struct VertexOut { float4 position [[position]]; float2 uv; };
struct Uniforms { float progress; float projection; float blur; float darkness; };

vertex VertexOut foldVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
}

fragment float4 foldFragment(VertexOut in [[stage_in]],
    constant Uniforms &u [[buffer(0)]],
    texture2d<float> sharp [[texture(0)]], texture2d<float> soft [[texture(1)]],
    texture2d<float> medium [[texture(2)]], texture2d<float> broad [[texture(3)]],
    texture2d<float> frost [[texture(4)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    if (u.progress < 0.00001) return float4(sharp.sample(s, in.uv).rgb, 1);
    float height = 1.0 - in.uv.y;
    float2 uv = float2(in.uv.x, 1.0 - height * u.projection);
    // A broad frost front advances from the free edge towards the hinge.
    // The image below it stays sharp until the front reaches that part of the panel.
    float frostAmount = smoothstep(0.0, 0.90, u.progress * 1.90 - in.uv.y);
    float radius = pow(frostAmount, 1.25) * u.blur;
    float3 color;
    if (radius < 6.0) color = mix(sharp.sample(s, uv).rgb, soft.sample(s, uv).rgb, radius / 6.0);
    else if (radius < 18.0) color = mix(soft.sample(s, uv).rgb, medium.sample(s, uv).rgb, (radius - 6.0) / 12.0);
    else if (radius < 42.0) color = mix(medium.sample(s, uv).rgb, broad.sample(s, uv).rgb, (radius - 18.0) / 24.0);
    else color = mix(broad.sample(s, uv).rgb, frost.sample(s, uv).rgb, clamp((radius - 42.0) / 54.0, 0.0, 1.0));
    // Darkness follows the frost across the surface, leaving the hinge lit last.
    // Both endpoints are exact; no separate whole-screen fade is needed.
    float shadeProgress = pow(u.progress, 1.0 / u.darkness);
    float shade = smoothstep(0.0, 0.65, shadeProgress * 1.65 - in.uv.y);
    color *= 1.0 - shade;
    return float4(color, 1);
}
