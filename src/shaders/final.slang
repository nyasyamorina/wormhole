#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> _unused_1;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> _unused_2;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> color_tex;

[vk_binding(0, 2)] [format("rgba8")]
RWTexture2D<float4> surface;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    surface.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float3 color = color_tex.Load(thread_id.xy).rgb;
    //color = acesToneMap(color);

    // crosshair
    //color = lerp(color, 1.0 - color, crosshair(thread_id.xy, extent));

    surface.Store(thread_id.xy, float4(color, 1.0));
}
