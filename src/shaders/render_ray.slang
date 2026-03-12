#include <utils.slang>


struct Uniform {
    vector<uint32_t, 2> extent;
};
[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)] [format("rgba32f")]
RWTexture2D<vector<float, 4>, 1> ray_position;

[vk_binding(1, 1)] [format("rgba32f")]
RWTexture2D<vector<float, 4>, 1> ray_direction;

[vk_binding(2, 1)] [format("rgba32f")]
RWTexture2D<vector<float, 4>, 1> _unused_3;

[vk_binding(3, 1)] [format("rgba32f")]
RWTexture2D<vector<float, 4>, 1> _unused_4;

[vk_binding(0, 2)] [format("bgra8")]
RWTexture2D<vector<float, 4>> surface;


[shader("compute")] [numthreads(16, 16, 1)]
void main(vector<uint, 3> thread_id: SV_DispatchThreadID) {
    vector<uint, 2> extent;
    surface.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    vector<float, 4> color = {
        float(thread_id.x) / float(extent.x),
        float(thread_id.y) / float(extent.y),
        0.0,
        0.0,
    };

    surface.Store(thread_id.xy, color);
}
