#include <utils.slang>


struct Uniform {
    Camera camera;
};
[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> ray_position_tex;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> ray_direction_tex;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> _unused_4;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    ray_position_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    Partical ray;
    ray.position = float4(uniform.camera.position, 1.0);

    float2 uv = getScreenCoordinate(thread_id.xy, extent);
    float3 direction = uv.x * uniform.camera.u + uv.y * uniform.camera.v + uniform.camera.direction;
    ray.direction = float4(direction, 0.0);

    ray_position_tex.Store(thread_id.xy, ray.position);
    ray_direction_tex.Store(thread_id.xy, ray.direction);
}
