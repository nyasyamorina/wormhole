#include <utils.slang>


struct Uniform {
    vector<uint32_t, 2> extent;
};
[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(1, 0)]
StructuredBuffer<Partical> ray_map;

[vk_binding(2, 0)] [format("rgba8")]
RWTexture2D<vector<float, 4>> surface;


[shader("compute")] [numthreads(16, 16, 1)]
void main(vector<uint32_t, 3> thread_id: SV_DispatchThreadID) {
    if (thread_id.x >= uniform.extent.x || thread_id.y >= uniform.extent.y) return;
    uint64_t idx = uint64_t(thread_id.y) * uint64_t(uniform.extent.x) + uint64_t(thread_id.x);

    vector<float, 4> color = vector<float, 4>(
        float(thread_id.x) / float(uniform.extent.x),
        float(thread_id.y) / float(uniform.extent.y),
        0.0,
        0.0,
    );

    surface.Store(thread_id.xy, color);
}
