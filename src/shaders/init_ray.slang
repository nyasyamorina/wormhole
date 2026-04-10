#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> ray_tex;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> ray_plane_y_axis_and_ray_compression_tex;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> ray_tag_tex;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> _unused_4;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    ray_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float2 uv = getScreenCoordinate(thread_id.xy, extent);
    float4 ray_position = uniform.frame.position;
    float4 ray_direction = uniform.frame.rayDirection(uv * uniform.screen_scale);

    // scale ray direction so that its tempolar component is equal to -1
    float ray_compression = -1.0 / temporal(ray_direction);
    ray_direction *= ray_compression;

    // convert ray in 3-D Cartesian coordinate to 2-D Cartesian coordinate
    float3 x_axis = normalize(spacial(uniform.frame.position));
    float3 y_axis = normalize(spacial(ray_direction) - dot(spacial(ray_direction), x_axis) * x_axis);
    float2 ray_p_2d = {length(spacial(ray_position)), 0.0};
    float2 ray_d_2d = {dot(spacial(ray_direction), x_axis), dot(spacial(ray_direction), y_axis)};

    // convert ray in 2-D Cartesian coordinate to 2-D polar coordinate
    float2[2] ray_polar = polar.fromCartesian(ray_p_2d, ray_d_2d);

    RayTag tag = RayTag::None;

    ray_tex.Store(thread_id.xy, float4(ray_polar[0], ray_polar[1]));
    ray_plane_y_axis_and_ray_compression_tex.Store(thread_id.xy, float4(y_axis, ray_compression));
    ray_tag_tex.Store(thread_id.xy, float4(bit_cast<float>(tag), 0.0, 0.0, 0.0));
}
