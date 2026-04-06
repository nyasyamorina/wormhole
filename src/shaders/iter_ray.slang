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
        break;
    }

    ray_tex.Store(thread_id.xy, float4(ray_position, ray_direction));
}
