#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> ray_tex;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> ray_plane_y_axis_and_ray_compression_tex;

[vk_binding(2, 1)]
RWTexture2D<float4> ray_tag_tex;

[vk_binding(3, 1)]
RWTexture2D<float4> _unused_4;

[vk_binding(0, 2)] [format("rgba8")]
RWTexture2D<float4> surface;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    surface.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    RayTag ray_tag = bit_cast<RayTag>(ray_tag_tex.Load(thread_id.xy)[0]);

    float4 ray_polar = ray_tex.Load(thread_id.xy);
    float4 ray_plane_y_axis_and_ray_compression = ray_plane_y_axis_and_ray_compression_tex.Load(thread_id.xy);

    // convert ray from 2-D polar coordinate to 2-D Cartesian coordinate
    float2[2] ray_2d = polar.toCartesian(ray_polar.xy, ray_polar.zw);
    float2 ray_p_2d = ray_2d[0];
    float2 ray_d_2d = ray_2d[1];

    // convert ray from 2-D Cartesian coordinate to 3-D Cartesian coordinate
    float3 x_axis = normalize(spacial(uniform.frame.position));
    float3 y_axis = ray_plane_y_axis_and_ray_compression.xyz;
    float3 ray_position  = ray_p_2d.x * x_axis + ray_p_2d.y * y_axis;
    float3 ray_direction = ray_d_2d.x * x_axis + ray_d_2d.y * y_axis;

    // note that the Doppler effect in relativity is purely cause by coordinate transformation,
    // because `ray` has 0 space-time length, `k * ray` also has 0 space-time length, where `k` is any real number,
    // although `k * any` is a valid ray, and has the same direction as `ray`, but its time component is changed,
    // and that is what cause the wavelength of light changed.
    // because we are sending light "back in time", the time component is negative.
    float freq_scale = ray_plane_y_axis_and_ray_compression.w;
    freq_scale *= 1.0 - schwarzschild::radius / ray_polar[0]; // correction for the finite simulation

    float3 color;

    if (ray_tag == RayTag::NotExist || ray_tag == RayTag::Catptured) {
        color = 0.0;
    } else if (ray_tag == RayTag::Invalid) {
        color = {1.0, 0.0, 0.0};
    } else if (ray_polar.x <= 10.0 * schwarzschild::radius) {
        color = {0.0, 0.0, 0.5};
    } else {
        color = renderCelestialSphere(normalize(ray_direction), freq_scale);
    }

    // crosshair
    color = lerp(color, 1.0 - color, crosshair(thread_id.xy, extent));

    surface.Store(thread_id.xy, float4(color, 1.0));
}


float starfieldBright(float3 direction) {
    const float scale = 200.0;

    float noise = simplexNoise3(direction * scale);
    float base = clamp(noise * 0.5 + 0.5, 0.0, 1.0);
    return 1.2 * sqr(cub(cub(base)));
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

float3 renderBlackBody(float bright, float temp, float freq_scale) {
    // normalize the black body radiation to target brightness
    float bright_norm = 1.0 / black_body::luminance(temp);

    // in black body radiation, wavelength scaling can be calculated by scaling temperature and brightness instead.
    // `B(λ,T) dλ -> B(sλ,T) d(sλ) = B(λ,sT)/s^4 dλ`
    bright *= sqr(sqr(freq_scale));
    temp *= freq_scale;

    //float bb_bright = black_body::luminance(temp);
    //float3 bb_color = black_body::relColor(temp);
    float3 bb_color = black_body::color(temp);

    //float abs_bright = bright_norm * bb_bright * bright;
    float abs_bright = bright_norm * bright;
    return abs_bright * bb_color;
}

/// `direction`: normalized
float3 renderCelestialSphere(float3 direction, float freq_scale) {
    float3 color = 0.0;

    // starfield
    float starfield_bright = starfieldBright(direction);
    float starfield_temp = starfieldTemp(direction);
    color += renderBlackBody(starfield_bright, starfield_temp, freq_scale);

    // nebulae
    float nebulae_bright = nebulaeBright(direction);
    float nebulae_temp = nebulaeTemp(direction);
    color += renderBlackBody(nebulae_bright, nebulae_temp, freq_scale);

    // tone mapping
    return acesToneMap(color);
}
