#include "utils.slang"


[vk_binding(0, 0)]
ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)]
RWTexture2D<float4, 1> ray_direction_tex;

[vk_binding(1, 1)]
RWTexture2D<float4, 1> brightness_scale_tex;

[vk_binding(2, 1)]
RWTexture2D<float4, 1> _unused_3;

[vk_binding(3, 1)]
RWTexture2D<float4, 1> _unused_4;


[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) {
    uint2 extent;
    ray_direction_tex.GetDimensions(extent.x, extent.y);
    if (thread_id.x >= extent.x || thread_id.y >= extent.y) return;

    float2 uv = getScreenCoordinate(thread_id.xy, extent);
    float3 ray_local_space = uv.x * uniform.camera.u + uv.y * uniform.camera.v + uniform.camera.direction;

    /// light ray has space-time length of 0, and we should send light "back in time" to figure out what we see.
    float4 ray_local = float4(normalize(ray_local_space), -1.0);
    float4 ray = special_relativity::localToGlobal(ray_local, uniform.velocity);

    // the total energy of the light emittef from distant star and received by the "player" is the same,
    // but the rate of time passes is different, resulting in different light flux.
    float V_t = sqrt(1.0 + dot(uniform.velocity, uniform.velocity));
    float brightness_scale = V_t;

    // the front scenery will be shrink, resulting more light in the same solid angle,
    // and the opposite happens at the back side.

    // the brightness factor is equal to the change of the solid angle element `dO'/dO`,
    // where `dO` is the solid angle element in local coordinate, `dO'` is the solid angle element in global coordinate,
    // and `dO = sinZ * dA * dZ`, where `A` is azimuth angle, `Z` is zenith angle.
    // consider a point on pass light cone `(cosA*sinZ, sinA*sinZ, cosZ, -1)`,
    // apply Lorenz transformation `L_{(0,0,z,t)}` on it, where `t = sqrt(1+z*z)`,
    // get `(cosA*sinZ, sinA*sinZ, cosZ*t-z, cozZ*z-t)`, it yields `dA' = dA`, `dZ' = dZ / m` and `sinZ' = sinZ / m`,
    // where `m = t - z*cosZ`, and finally `dO'/dO = 1 / m^2`.
    brightness_scale /= sqr(V_t - dot(normalize(ray_local_space), uniform.velocity));

    ray_direction_tex.Store(thread_id.xy, ray);
    brightness_scale_tex.Store(thread_id.xy, float4(brightness_scale, 0.0, 0.0, 0.0));
}
