#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> ray_tex;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> ray_plane_y_axis_and_ray_scale_tex;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> color_output_tex;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    color_output_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float4 ray = ray_tex.Load(thread_id.xy);
    float2 ray_position = ray.xy;
    float2 ray_direction = ray.zw;
    float4 ray_plane_y_axis_and_ray_scale = ray_plane_y_axis_and_ray_scale_tex.Load(thread_id.xy);
    float3 y_axis = ray_plane_y_axis_and_ray_scale.xyz;
    float ray_scale = ray_plane_y_axis_and_ray_scale.w;

    float wavelength_scale = ray_scale;
    float brightness_scale = sqr(sqr(ray_scale));

    // convert from 2-D Ellis coordinates to 3-D Cartesian coordinates
    float3 x_axis = ball::toCartesianPoint(spacial(uniform.frame.position).yz);
    float3 p_ball =   cos(ray_position[1]) * x_axis + sin(ray_position[1]) * y_axis;
    float3 v_ball = (-sin(ray_position[1]) * x_axis + cos(ray_position[1]) * y_axis) * ray_direction[1];
    float3 ray_direction_spacial = normalize(p_ball * ray_direction[0] + v_ball * ray_position[0]);
    ray_direction_spacial = mul(ray_direction_spacial, uniform.sub_frame.asMatrix());

    float3 color;
    if (ray_position[0] > 0.0) {
        color = renderCelestialSphere(ray_direction_spacial, wavelength_scale);
    } else {
        color = renderExoticCelestialSphere(ray_direction_spacial, wavelength_scale);
    }
    color *= brightness_scale;

    color_output_tex.Store(thread_id.xy, float4(max(0.0, color), 1.0));
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

float nebulaBright(float3 direction) {
    const float scale_1 = 1.0;
    const float amplitude_1 = 0.7;
    const float scale_2 = 5.0;
    const float amplitude_2 = 0.1;
    const float scale_3 = 10.0;
    const float amplitude_3 = 0.08;
    const float scale_4 = 20.0;
    const float amplitude_4 = 0.035;

    float nebula = amplitude_1 * simplexNoise3(direction * scale_1);
    float milky_way = 0.8 * (1.0 - 3.2 * sqr(direction.z));
    float mix = 0.15 + 5.0 * sqr(direction.z) - (0.07 * direction.x);
    float base = clamp(lerp(milky_way, nebula, min(1.0, mix)), 0.0, 1.0);

    float noise = amplitude_2 * simplexNoise3(direction * scale_2);
    noise += amplitude_3 * simplexNoise3(direction * scale_3);
    noise += amplitude_4 * simplexNoise3(direction * scale_4);
    float noise_base = noise * 0.6 + 0.95;
    float noise_mix = 0.3 + 3.0 * sqr(direction.z) * (0.5 * direction.x + 0.5);
    noise_base = max(0.0, (0.1 * direction.x) + lerp(1.05, noise_base, min(1.0, noise_mix)));

    return sqr(base * cub(noise_base));
}

float nebulaTemp(float3 direction) {
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

/// `direction`: normalized
float3 renderCelestialSphere(float3 direction, float wavelength_scale) {
    float3 color = 0.0;

    // starfield
    float starfield_bright = starfieldBright(direction);
    float starfield_temp = starfieldTemp(direction);
    color += renderBlackBody(starfield_bright, starfield_temp, wavelength_scale);

    // nebula
    float nebula_bright = nebulaBright(direction);
    float nebula_temp = nebulaTemp(direction);
    color += 0.3 * renderBlackBody(nebula_bright, nebula_temp, wavelength_scale);

    return color;
}


/// modified from "https://www.shadertoy.com/view/XlfGRj"
/// `direction`: normalized
float3 renderExoticCelestialSphere(float3 direction, float wavelength_scale) {
    const uint iterations = 17;
    const float formuparam = 0.53;
    const uint volsteps = 20;
    const float stepsize = 0.1;
    const float tile = 0.85;
    const float brightness = 5e-7;
    const float distfading = 0.83;
    const float3 from = {1.0, 0.5, 0.0};

    float s = 0.1; float fade = 1.0;
    float3 color = 0.0;
    for (uint r = 0; r < volsteps; r++) {
        float3 p = 0.5 * s * direction + from;
        p = abs(tile - fmod(p, 2.0 * tile));
        float pa = 0.0; float a = 0.0;
        for (uint i = 0; i < iterations; i++) {
            p = abs(p) / dot(p, p) - formuparam;
            a += abs(length(p) - pa);
            pa = length(p);
        }
        a *= a * a;
        color += fade * renderStarNest(0.5 * s, a / (1e-5 * a + 1.0), wavelength_scale);
        fade *= distfading;
        s += stepsize;
    }
    color *= brightness;
    return color * sqrt(color);
}

float3 renderStarNest(float s, float a, float wavelength_scale) {
    float3 color = 0.0;
    float wavelength = cie::table_wave_length_begin;
    for (uint k = 0; k < cie::XYZ_table.getCount(); k++) {
        color += cie::XYZ_table[k] * startNestSpetrum(wavelength * wavelength_scale, s, 0.01 * a);
        wavelength += cie::table_wave_length_step;
    }
    return a * cie::table_wave_length_step * cie::XYZ_to_linear_sRGB(color);
}
float startNestSpetrum(float wavelength, float s, float a) {
    return a / (abs(lerp(cie::table_wave_length_begin, cie::table_wave_length_end + 30.0, s) - wavelength) + a);
}
