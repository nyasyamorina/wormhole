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
    return;

    float4 ray = ray_tex.Load(thread_id.xy);
    float2 ray_position = ray.xy;
    float3 ray_direction = float3(ray.zw, -1.0);

    float4 ray_plane_y_axis_and_ray_scale = ray_plane_y_axis_and_ray_scale_tex.Load(thread_id.xy);
    float ray_scale = ray_plane_y_axis_and_ray_scale.w;

    for (uint l = 0; l < uniform.iter_per_call; l += 1) {
        float step_size = max(0.05 * ray_position[0] / ellis::radius, 0.1 * (ray_position[0] / ellis::radius - 1.0));
        solveStep(step_size, ray_position, ray_direction);

        // normalize by time to keep stability as long as possible
        float scale = -1.0 / ray_direction[2];
        ray_direction *= scale;
        ray_scale *= scale;
    }

    ray_tex.Store(thread_id.xy, float4(ray_position, ray_direction.xy));
    ray_plane_y_axis_and_ray_scale_tex.Store(thread_id.xy, float4(ray_plane_y_axis_and_ray_scale.xyz, ray_scale));
}


void solveStep(float step_size, in out float2 position, in out float3 direction) {
    float2 p1 = position;
    float3 v1 = direction;
    float3 a1 = ellis::deltaParallelTransport(p1[0], v1, v1);

    float2 p2 = p1 + step_size * (2.0/3.0) * v1.xy;
    float3 v2 = v1 + step_size * (2.0/3.0) * a1;
    float3 a2 = ellis::deltaParallelTransport(p2[0], v2, v2);

    position  += step_size * lerp(v1.xy, v2.xy, 0.75);
    direction += step_size * lerp(a1,    a2,    0.75);
}
