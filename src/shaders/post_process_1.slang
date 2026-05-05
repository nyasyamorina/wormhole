#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> _unused_1;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> h_blur_tex;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> mipmap_tex;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> render_tex;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    render_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float3 color = gaussian_blur_coefs[0] * mipmap_tex.Load(thread_id.xy).rgb;
    for (uint idx = 1; idx < gaussian_blur_coefs.getCount(); idx++) {
        color += gaussian_blur_coefs[idx] * (
            mipmap_tex.Load(uint2(min(extent.x, thread_id.x + idx), thread_id.y)).rgb +
            mipmap_tex.Load(uint2(max(idx, thread_id.x) - idx,      thread_id.y)).rgb
        );
    }

    h_blur_tex.Store(thread_id.xy, float4(color * gaussian_blur_norm, 1.0));
}
