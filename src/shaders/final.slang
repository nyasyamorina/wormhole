#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> _unused_1;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> _unused_2;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> mipmap_tex;

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
    color = lerp(color, calculateBloom(thread_id.xy, extent), 0.4);

    // auto exposure
    uint2 target_bright_offset = mipmapOffset(extent, uniform.mipmap_levels - 1);
    float target_bright = mipmap_tex.Load(target_bright_offset).y;
    color /= max(1e-7, target_bright);

    color = acesToneMap(color);
    color = clamp(color, 0.0, 1.0);

    // crosshair
    color = lerp(color, 1.0 - color, crosshair(thread_id.xy, extent));

    surface.Store(thread_id.xy, float4(color, 1.0));
}

float3 calculateBloom(uint2 thread_id, uint2 extent) {
    float3 bloom = 0.0;
    float total = 0.0;
    for (uint l = 0; l < bloom_coefs.getCount(); l++) {
        if (l >= uniform.mipmap_levels - 1) break;
        float coef = bloom_coefs[l];
        bloom += coef * getMipmap(thread_id, extent, l);
        total += coef;
    }
    return bloom / total;
}

float3 getMipmap(uint2 thread_id, uint2 extent, uint level) {
    uint2 offset = mipmapOffset(extent, level);
    uint2 mm_extent = mipmapExtent(extent, level);
    float2 sample_pos = float2(thread_id) * float2(mm_extent) / float2(extent) + float2(offset);

    // using the incorrect process to generate mipmaps, see `_recordGenerateMipmapCommands` in `VulkanContext.zig`.
    // shifting samples to the top-left by sqrt(0.5) will result in mipmaps that looks fine.
    //sample_pos -= 0.5;

    uint2 s1 = uint2(floor(sample_pos));
    uint2 s0 = max(1, s1) - 1;
    uint2 s2 = min(extent, s1 + 1);
    uint2 s3 = min(extent, s1 + 2);
    float2 delta = sample_pos - floor(sample_pos);
    float4 cx = cubicInterpolationCoefs(delta.x);
    float4 cy = cubicInterpolationCoefs(delta.y);

    float3 v0 = cx[0] * mipmap_tex.Load(uint2(s0.x, s0.y)).rgb
              + cx[1] * mipmap_tex.Load(uint2(s1.x, s0.y)).rgb
              + cx[2] * mipmap_tex.Load(uint2(s2.x, s0.y)).rgb
              + cx[3] * mipmap_tex.Load(uint2(s3.x, s0.y)).rgb;
    float3 v1 = cx[0] * mipmap_tex.Load(uint2(s0.x, s1.y)).rgb
              + cx[1] * mipmap_tex.Load(uint2(s1.x, s1.y)).rgb
              + cx[2] * mipmap_tex.Load(uint2(s2.x, s1.y)).rgb
              + cx[3] * mipmap_tex.Load(uint2(s3.x, s1.y)).rgb;
    float3 v2 = cx[0] * mipmap_tex.Load(uint2(s0.x, s2.y)).rgb
              + cx[1] * mipmap_tex.Load(uint2(s1.x, s2.y)).rgb
              + cx[2] * mipmap_tex.Load(uint2(s2.x, s2.y)).rgb
              + cx[3] * mipmap_tex.Load(uint2(s3.x, s2.y)).rgb;
    float3 v3 = cx[0] * mipmap_tex.Load(uint2(s0.x, s3.y)).rgb
              + cx[1] * mipmap_tex.Load(uint2(s1.x, s3.y)).rgb
              + cx[2] * mipmap_tex.Load(uint2(s2.x, s3.y)).rgb
              + cx[3] * mipmap_tex.Load(uint2(s3.x, s3.y)).rgb;

    return cy[0] * v0 + cy[1] * v1 + cy[2] * v2 + cy[3] * v3;
}
