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
    // Frost travels from the free edge towards the hinge, like the moving Duo panel.
    float local = u.progress * (0.22 + 0.78 * pow(height, 0.72));
    float radius = pow(local, 0.72) * u.blur;
    float3 color;
    if (radius < 6.0) color = mix(sharp.sample(s, uv).rgb, soft.sample(s, uv).rgb, radius / 6.0);
    else if (radius < 18.0) color = mix(soft.sample(s, uv).rgb, medium.sample(s, uv).rgb, (radius - 6.0) / 12.0);
    else if (radius < 42.0) color = mix(medium.sample(s, uv).rgb, broad.sample(s, uv).rgb, (radius - 18.0) / 24.0);
    else color = mix(broad.sample(s, uv).rgb, frost.sample(s, uv).rgb, clamp((radius - 42.0) / 54.0, 0.0, 1.0));
    // Separate opacity from frost: the first degrees should turn the screen into
    // glass without abruptly dimming the whole desktop. No late threshold switch.
    float dark = pow(u.progress, 1.8) * (0.16 + 0.84 * pow(height, 0.8));
    float dim = clamp(dark * u.darkness, 0.0, 0.98);
    float close = smoothstep(0.0, 1.0, pow(u.progress, 3.0));
    color *= (1.0 - dim) * (1.0 - close);
    return float4(color, 1);
}
