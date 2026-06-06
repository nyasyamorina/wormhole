#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> ray_tex;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> _unused_2;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> _unused_4;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    ray_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float4 ray = ray_tex.Load(thread_id.xy);
    float2 ray_position = ray.xy;
    float2 ray_direction = ray.zw;

    for (uint l = 0; l < uniform.iter_per_call; l += 1) {
        float step_size = 0.1 * max(2.0, ray_position[0] / ellis::radius);
        solveStep(step_size, ray_position, ray_direction);
        if (abs(ray_position[0]) > 100.0 * ellis::radius && sign(ray_direction[0]) == sign(ray_position[0])) break;
    }

    ray_tex.Store(thread_id.xy, float4(ray_position, ray_direction.xy));
}


void solveStep(float step_size, in out float2 position, in out float2 direction) {
    float2 p1 = position;
    float2 v1 = direction;
    float2 a1 = ellis::deltaParallelTransport(p1[0], v1, v1);

    float2 p2 = p1 + step_size * (2.0/3.0) * v1;
    float2 v2 = v1 + step_size * (2.0/3.0) * a1;
    float2 a2 = ellis::deltaParallelTransport(p2[0], v2, v2);

    position  += step_size * lerp(v1, v2, 0.75);
    direction += step_size * lerp(a1, a2, 0.75);
}
