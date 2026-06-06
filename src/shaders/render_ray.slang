#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4> ray_direction_tex;

[vk_binding(1, 1)]
RWTexture2D<float4> _unused_2;

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

    float4 ray = ray_direction_tex.Load(thread_id.xy);
    float scale = -1.0 / ray.w;
    ray *= scale;
    float wavelength_scale = scale;
    float brightness_scale = sqr(sqr(scale));

    float3 color = 0.0;

    // starfield
    float starfield_bright = starfieldBright(ray.xyz);
    float starfield_temp = starfieldTemp(ray.xyz);
    color += renderBlackBody(starfield_bright, starfield_temp, wavelength_scale);

    // nebulae
    float nebulae_bright = nebulaeBright(ray.xyz);
    float nebulae_temp = nebulaeTemp(ray.xyz);
    color += renderBlackBody(nebulae_bright, nebulae_temp, wavelength_scale);

    color *= brightness_scale;

    // tone mapping
    color = acesToneMap(color);
    color = clamp(color, 0.0, 1.0);

    // crosshair
    color = lerp(color, 1.0 - color, crosshair(thread_id.xy, extent));

    surface.Store(thread_id.xy, float4(color, 1.0));
}


float starfieldBright(float3 direction) {
    const float scale1 = 200.0;
    const float amplitude_1 = 0.45;
    const float scale2 = 150.0;
    const float amplitude_2 = 0.45;
    const float scale3 = 100.0;
    const float amplitude_3 = 0.3;

    float noise = amplitude_1 * simplexNoise3(direction * scale1);
    noise += amplitude_2 * simplexNoise3(direction * scale2);
    noise += amplitude_3 * simplexNoise3(direction * scale3);
    float base = max(0.0, noise * 0.5 + 0.5);
    return 1.2 * cub(cub(base));
}

float starfieldTemp(float3 direction) {
    const float scale = 30.0;

    float noise = simplexNoise3(direction * scale);
    return noiseToTemp(clamp(noise * 0.3 + 0.5, 0.0, 1.0));
}

float nebulaeBright(float3 direction) {
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
    noise_base = max(0.0, (0.1 * direction.x) + lerp(1.05, noise_base, min(1.0, noise_mix)));

    return sqr(base * cub(noise_base));
}

float nebulaeTemp(float3 direction) {
    const float scale = 2.5;
    const float amplitude = 0.25;
    const float shift = -0.1;

    float noise = shift - amplitude * simplexNoise3(direction * scale + 2.0);
    return noiseToTemp(clamp(noise * 0.5 + 0.5, 0.0, 1.0));
}


/// noise in [0, 1]
float noiseToTemp(float noise) {
    const float temp_min = 3.0; // 1000K
    const float temp_max = 30.0; // 1000K
    const float white_concentration = 0.2;
    const float white_temp = 6.5;

    const float mired_min = 1.0 / temp_max;
    const float mired_max = 1.0 / temp_min;
    const float white_mired = 1.0 / white_temp;

    float mired = (mired_max - mired_min) * noise + mired_min;
    mired = lerp(mired, white_mired, white_concentration);

    return 1.0 / mired;
}

float3 renderBlackBody(float bright, float temp, float wavelength_scale) {
    // normalize the black body radiation to target brightness
    bright /= black_body::luminance(temp);

    // in black body radiation, wavelength scaling can be calculated by scaling temperature and brightness instead.
    // `B(sλ,T) = B(λ,sT)/s^5`
    float bright_scale = sqr(sqr(wavelength_scale)) * wavelength_scale;
    return bright / bright_scale * black_body::color(temp * wavelength_scale);
}
