#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> _unused_1;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> _unused_2;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> color_output_tex;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> color_input_tex;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    color_output_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float4 color = color_input_tex.Load(thread_id.xy);

    color_output_tex.Store(thread_id.xy, color);
}
