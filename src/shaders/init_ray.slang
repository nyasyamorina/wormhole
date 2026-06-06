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
RWTexture2D<float4, 1> _unused_4;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    ray_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float2 uv = getScreenCoordinate(thread_id.xy, extent);
    float2 xz = uv * uniform.screen_scale;
    float4 ray_local = spacetime(normalize(float3(xz[0], 1.0, xz[1])), -1.0);
    float4 ray_global = mul(ray_local, uniform.frame.asMatrix());
    float ray_scale = -1.0 / temporal(ray_global);
    ray_global *= ray_scale;

    // convert from 3-D Ellis coordinates to 2-D Ellis coordinates
    float3 v_ball = ball::toCartesianVector(spacial(uniform.frame.position).yz, spacial(ray_global).yz);
    float3 y_axis = normalize(v_ball);
    float2 ray_position = {spacial(uniform.frame.position)[0], 0.0};
    float2 ray_direction = {spacial(ray_global)[0], length(v_ball)};

    ray_tex.Store(thread_id.xy, float4(ray_position, ray_direction));
    ray_plane_y_axis_and_ray_scale_tex.Store(thread_id.xy, float4(y_axis, ray_scale));
}
