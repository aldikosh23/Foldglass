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
    // Keep the image aligned with the physical hinge as the lid closes.
    float2 uv = float2(in.uv.x, 1.0 - height * u.projection);
    // Defocus grows continuously with the fold and the distance from the hinge.
    float frostAmount = smoothstep(0.0, 1.0, u.progress);
    float radius = u.blur * frostAmount * mix(0.025, 1.0, pow(height, 1.3));
    float3 color;
    if (radius < 6.0) color = mix(sharp.sample(s, uv).rgb, soft.sample(s, uv).rgb, radius / 6.0);
    else if (radius < 18.0) color = mix(soft.sample(s, uv).rgb, medium.sample(s, uv).rgb, (radius - 6.0) / 12.0);
    else if (radius < 42.0) color = mix(medium.sample(s, uv).rgb, broad.sample(s, uv).rgb, (radius - 18.0) / 24.0);
    else color = mix(broad.sample(s, uv).rgb, frost.sample(s, uv).rgb, clamp((radius - 42.0) / 54.0, 0.0, 1.0));
    // Keep the image visible through the middle of the fold. The free edge
    // shades first; the final part of closing eases the whole panel to black.
    float shadeProgress = pow(u.progress, 1.0 / u.darkness);
    float shade = 0.78 * smoothstep(0.0, 1.0, shadeProgress) * pow(height, 1.25);
    float closing = smoothstep(0.72, 1.0, shadeProgress);
    color *= (1.0 - shade) * (1.0 - closing);
    return float4(color, 1);
}
