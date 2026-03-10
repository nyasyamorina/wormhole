struct InitRayUniform {
    vector<uint32_t, 2> extent;
};
ConstantBuffer<InitRayUniform> init_ray_uniform;

[Shader("compute")] [NumThreads(16, 16, 1)]
void initRay(uint3 thread_id: SV_DispatchThreadID) {
    if (thread_id.x >= init_ray_uniform.extent.x || thread_id.y >= init_ray_uniform.extent.y) return;


}

struct Partical {
    vector<double, 4> position;
    vector<double, 4> direction;
};
RWStructuredBuffer<Partical> ray_map;

[Shader("compute")] [NumThreads(16, 16, 1)]
void renderRay(uint3 thread_id: SV_DispatchThreadID) {}

[format("rgba8_snorm")]
RWTexture2D<vector<uint8_t, 4>, 1> surface;
