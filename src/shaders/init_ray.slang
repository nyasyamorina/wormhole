#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> ray_tex;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> ray_plane_y_axis_and_ray_compression_tex;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> _unused_4;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    ray_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float2 uv = getScreenCoordinate(thread_id.xy, extent);
    float3 ray_local_space = uv.x * uniform.camera.u + uv.y * uniform.camera.v + uniform.camera.direction;

    /// light ray has space-time length of 0, and we should send light "back in time" to figure out what we see.
    float4 ray_local = float4(normalize(ray_local_space), -1.0);
    float4 ray = ray_local;//special_relativity::localToGlobal(ray_local, uniform.velocity);

    // convert ray in 3-D Cartesian coordinate to 2-D polar coordinate
    float3 x_axis = normalize(uniform.position.xyz);
    float3 y_axis = normalize(ray.xyz - dot(ray.xyz, x_axis) * x_axis);
    float2 ray_2d = {dot(ray.xyz, x_axis), dot(ray.xyz, y_axis)};
    float2 position_2d = {length(uniform.position.xyz), 0.0};
    float2[2] ray_polar = polar.fromCartesian(position_2d, ray_2d);

    ray_tex.Store(thread_id.xy, float4(ray_polar[0], ray_polar[1]));
    ray_plane_y_axis_and_ray_compression_tex.Store(thread_id.xy, float4(y_axis, -ray.w));
}
