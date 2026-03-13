#include <utils.slang>


struct Uniform {
    float _placeholder;
};
[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4> ray_position_tex;

[vk_binding(1, 1)]
RWTexture2D<float4> ray_direction_tex;

[vk_binding(2, 1)]
RWTexture2D<float4> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4> _unused_4;

[vk_binding(0, 2)] [format("rgba8")]
RWTexture2D<float4> surface;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    surface.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    Partical ray;
    ray.position = ray_position_tex.Load(thread_id.xy);
    ray.direction = ray_direction_tex.Load(thread_id.xy);

    float3 color = {
        (ray.direction.x > 0.0) ? 1.0 : 0.0,
        (ray.direction.y > 0.0) ? 1.0 : 0.0,
        (ray.direction.z > 0.0) ? 1.0 : 0.0,
    };

    // crosshair
    float2 uv = getScreenUV(thread_id.xy, extent);
    uv.x *= float(extent.x) / float(extent.y);
    if (abs(uv.x) < 0.01 && abs(uv.y) < 0.01) {
        if (uv.x * uv.x + uv.y * uv.y < 0.01 * 0.01) {
            color = 1.0 - color;
        }
    }

    surface.Store(thread_id.xy, float4(color, 1.0));
}
