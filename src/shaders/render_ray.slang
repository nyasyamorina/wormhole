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

    float3 color = 0.0;

    // startfield
    float startfield_brightness = startfieldBrightness(ray.direction.xyz);
    float startfield_b_v = startfieldBVIndex(ray.direction.xyz);
    color += startfield_brightness * BVIndexToRgb(startfield_b_v);

    // nebulae
    float nebulae_brightness = nebulaeBrightness(ray.direction.xyz);
    float nebulae_b_v = nebulaeBVIndex(ray.direction.xyz);
    color += nebulae_brightness * BVIndexToRgb(nebulae_b_v);

    // crosshair
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

    float noise = simplexNoise3(direction * scale);
    return noiseToBVIndex(clamp(noise * 0.5 + 0.5, 0.0, 1.0));
}

float nebulaeBrightness(float3 direction) {
    const float scale_1 = 1.0;
    const float amplitude_1 = 0.7;
    const float scale_2 = 5.0;
    const float amplitude_2 = 0.1;
    const float scale_3 = 10.0;
    const float amplitude_3 = 0.08;
    const float scale_4 = 20.0;
    const float amplitude_4 = 0.035;

    float nebulae = amplitude_1 * simplexNoise3(direction * scale_1);
    float milky_way = 0.8 * (1.0 - 3.2 * sqr(direction.z));
    float mix = 0.15 + 5.0 * sqr(direction.z) - (0.07 * direction.x);
    float base = clamp(lerp(milky_way, nebulae, min(1.0, mix)), 0.0, 1.0);

    float noise = amplitude_2 * simplexNoise3(direction * scale_2);
    noise += amplitude_3 * simplexNoise3(direction * scale_3);
    noise += amplitude_4 * simplexNoise3(direction * scale_4);
    float noise_base = noise * 0.6 + 0.95;
    float noise_mix = 0.3 + 3.0 * sqr(direction.z) * (0.5 * direction.x + 0.5);
    noise_base = max(0.0, (0.07 * direction.x) + lerp(1.05, noise_base, min(1.0, noise_mix)));

    return sqr(base * cub(noise_base));
}

float nebulaeBVIndex(float3 direction) {
    const float scale = 2.5;
    const float amplitude = 0.25;
    const float shift = -0.1;

    float noise = shift - amplitude * simplexNoise3(direction * scale);
    return noiseToBVIndex(clamp(noise * 0.5 + 0.5, 0.0, 1.0));
}


/// noise in [0, 1]
float noiseToBVIndex(float noise) {
    const float b_v_min = -0.5;
    const float b_v_max = 1.8;
    const float white_concentration = 0.1;
    const float white_b_v = 0.656;

    float b_v = (b_v_max - b_v_min) * noise + b_v_min;
    return lerp(b_v, white_b_v, white_concentration);
}
