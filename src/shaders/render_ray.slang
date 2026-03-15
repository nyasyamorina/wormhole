#include <utils.slang>


struct Uniform {
    float _placeholder;
};
[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4> ray_position_tex;

[vk_binding(1, 1)]
RWTexture2D<float4> ray_direction_tex;

[vk_binding(2, 1)]
RWTexture2D<float4> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4> _unused_4;

[vk_binding(0, 2)] [format("rgba8")]
RWTexture2D<float4> surface;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    surface.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    Partical ray;
    ray.position = ray_position_tex.Load(thread_id.xy);
    ray.direction = ray_direction_tex.Load(thread_id.xy);
    ray.direction.xyz = normalize(ray.direction.xyz);

    //float3 color = float3(ray.direction.xyz > 0.0);
    float brightness = startfieldBrightness(ray.direction.xyz);
    float b_v = startfieldBVIndex(ray.direction.xyz);
    float3 color = brightness * BVIndexToRgb(b_v);

    color = lerp(color, 1.0 - color, crosshair(thread_id.xy, extent));

    surface.Store(thread_id.xy, float4(color, 1.0));
}


float startfieldBrightness(float3 direction) {
    const float scale = 200.0;

    float noise = simplexNoise3(direction * scale);
    float base = clamp(noise * 0.5 + 0.5, 0.0, 1.0);
    return sqr(cub(cub(base)));
}

float startfieldBVIndex(float3 direction) {
    const float scale = 30.0;
    const float b_v_min = -0.5;
    const float b_v_max = 1.8;
    const float white_concentration = 0.1;
    const float white_b_v = 0.656;

    float noise = simplexNoise3(direction * scale);
    float base = clamp(noise * 0.5 + 0.5, 0.0, 1.0);
    float b_v = (b_v_max - b_v_min) * base + b_v_min;

    return lerp(b_v, white_b_v, white_concentration);
}

/// from "https://stackoverflow.com/a/22630970"
/// `b_v` in [-0.4, 2.0]
float3 BVIndexToRgb(float b_v) {
    float t;
    float3 color;

    if (b_v < 0.0) {
        t = (b_v - -0.4) / (0.0 - -0.4);
        color.r = (0.1 * t + 0.11) * t + 0.61;
    } else if (b_v < 0.4) {
        t = (b_v - 0.0) / (0.4 - 0.0);
        color.r = 0.18 * t + 0.82; // original: 0.17 * t + 0.83
    } else {
        color.r = 1.0;
    }

    if (b_v < 0.0) {
        t = (b_v - -0.4) / (0.0 - -0.4);
        color.g = (0.1 * t + 0.07) * t + 0.7;
    } else if (b_v < 0.4) {
        t = (b_v - 0.0) / (0.4 - 0.0);
        color.g = 0.11 * t + 0.87;
    } else if (b_v < 1.6) {
        t = (b_v - 0.4) / (1.6 - 0.4);
        color.g = -0.16 * t + 0.98;
    } else {
        t = (b_v - 1.6) / (2.0 - 1.6);
        color.g = -0.5 * t * t + 0.82;
    }

    if (b_v < 0.4) {
        color.b = 1.0;
    } else if (b_v < 1.5) {
        t = (b_v - 0.4) / (1.5 - 0.4);
        color.b = (0.1 * t - 0.47) * t + 1.0;
    } else {
        t = (b_v - 1.5) / (1.94 - 1.5);
        color.b = max(0.0, -0.6 * t * t + 0.63);
    }

    return color;
}
