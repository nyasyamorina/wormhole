#include <utils.slang>


struct Uniform {
    vector<uint32_t, 2> extent;
};
[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(1, 0)]
RWStructuredBuffer<Partical> ray_map;


[shader("compute")] [numthreads(16, 16, 1)]
void main(vector<uint32_t, 3> thread_id: SV_DispatchThreadID) {
    if (thread_id.x >= uniform.extent.x || thread_id.y >= uniform.extent.y) return;
    uint64_t idx = uint64_t(thread_id.y) * uint64_t(uniform.extent.y) + uint64_t(thread_id.x);


}
