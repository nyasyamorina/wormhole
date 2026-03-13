struct Partical {
    float4 position;
    float4 direction;
};

struct Camera {
    float3 position;
    /// normalized
    float3 direction;
    float3 u;
    float3 v;
};

static const float pi = 3.14159265358979323846264338327950288419716939937510;

float2 getScreenUV(uint2 thread_id, uint2 extent) {
    float2 uv_01 = float2(thread_id) / float2(extent);
    return {
        2.0 * uv_01.x - 1.0,
        1.0 - 2.0 * uv_01.y,
    };
}
