#include "utils.slang"


struct Uniform {
    /// in local coord
    Camera camera;
    /// in global coord
    float4 position;
    /// in global coord
    float3 velocity;
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

    float2 uv = getScreenCoordinate(thread_id.xy, extent);
    float3 ray_local_space = uv.x * uniform.camera.u + uv.y * uniform.camera.v + uniform.camera.direction;

    /// light ray has space-time length of 0, and we should send light "back in time" to figure out what we see.
    float4 ray_local = float4(normalize(ray_local_space), -1.0);
    float4 ray = special_relativity::localToGlobal(ray_local, uniform.velocity);

    ray_position_tex.Store(thread_id.xy, uniform.position);
    ray_direction_tex.Store(thread_id.xy, ray);
}
