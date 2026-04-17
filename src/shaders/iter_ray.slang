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

    RayTag ray_tag = bit_cast<RayTag>(ray_tag_tex.Load(thread_id.xy)[0]);
    if (ray_tag != RayTag::None) return;

    float4 ray = ray_tex.Load(thread_id.xy);
    float2 ray_position = ray.xy;
    float3 ray_direction = float3(ray.zw, -1.0);

    float4 ray_plane_y_axis_and_ray_compression = ray_plane_y_axis_and_ray_compression_tex.Load(thread_id.xy);
    float ray_compression = ray_plane_y_axis_and_ray_compression.w;

    //bool prev_ray_outside = ray_position[0] > schwarzschild::radius;
    for (uint l = 0; l < uniform.iter_per_call; l += 1) {

        // check validity
        //bool ray_outside = ray_position[0] > schwarzschild::radius;
        //if (prev_ray_outside && !ray_outside) {
        //    ray_tag = RayTag::Invalid;
        //    break;
        //}
        //prev_ray_outside = ray_outside;

        if (ray_position[0] > 100.0 * schwarzschild::radius && ray_direction[0] > 0.0) {
            ray_tag = RayTag::Escaped;
            break;
        }

        if (ray_position[0] <= 1.5 * schwarzschild::radius && ray_direction[0] < 0.0) {
            ray_tag = RayTag::Catptured;
            break;
        }


        float step_size = max(0.05 * ray_position[0] / schwarzschild::radius, 0.1 * (ray_position[0] / schwarzschild::radius - 1.0));
        solveStep(step_size, ray_position, ray_direction);

        // normalize by time to keep stability as long as possible
        float scale = -1.0 / ray_direction[2];
        ray_direction *= scale;
        ray_compression *= scale;
    }

    ray_tex.Store(thread_id.xy, float4(ray_position, ray_direction.xy));
    ray_plane_y_axis_and_ray_compression_tex.Store(thread_id.xy, float4(ray_plane_y_axis_and_ray_compression.xyz, ray_compression));
    ray_tag_tex.Store(thread_id.xy, float4(bit_cast<float>(ray_tag), 0.0, 0.0, 0.0));
}


void solveStep(float step_size, in out float2 position, in out float3 direction) {
    float2 p1 = position;
    float3 v1 = direction;
    float3 a1 = schwarzschild::deltaParallelTransport(p1[0], v1, v1);

    float2 p2 = p1 + step_size * (2.0/3.0) * v1.xy;
    float3 v2 = v1 + step_size * (2.0/3.0) * a1;
    float3 a2 = schwarzschild::deltaParallelTransport(p2[0], v2, v2);

    position  += step_size * lerp(v1.xy, v2.xy, 0.75);
    direction += step_size * lerp(a1,    a2,    0.75);
}
