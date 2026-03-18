struct Partical {
    float4 position;
    float4 direction;
};

struct Camera {
    /// normalized
    float3 direction;
    float3 u;
    float3 v;
};

static const float pi = 3.14159265358979323846264338327950288419716939937510;


float2 getScreenCoordinate(uint2 thread_id, uint2 extent) {
    float2 uv_01 = float2(thread_id) / float2(extent);
    return {
        2.0 * uv_01.x - 1.0,
        1.0 - 2.0 * uv_01.y,
    };
}


float crosshair(uint2 thread_id, uint2 extent) {
    const float size = 0.007;
    const float threshold = 0.75;

    float2 uv = getScreenCoordinate(thread_id.xy, extent);
    uv.x *= float(extent.x) / float(extent.y);
    if (abs(uv.x) < size && abs(uv.y) < size) {
        float r_sqr = uv.x * uv.x + uv.y * uv.y;
        r_sqr *= 1.0 / (size * size);
        return clamp((r_sqr - 1.0) * (1.0 / (threshold * threshold - 1.0)), 0.0, 1.0);
    }
    return 0.0;
}


/// noise value in [-1, 1]
float simplexNoise3(float3 p) {
    // convert the point into new coord in order to determine which simplex the point lie in.
    // in N-dimension, squeeze a hypercube along its longest diagonal, can form N! regular simplexes.
    const float f = 1.0 / 3.0; // = (sqrt(N + 1) - 1) / N
    float3 p_ = p + f * (p.x + p.y + p.z); // stretch `p` to new coord
    int3 v0_ = int3(p_) - int3(p_ < 0.0); // fast floor, the minimum corner in the hypercube

    // simplex has N+1 vertices, and one of them is the diagonal of `v0_` in the hypercube,
    // determine the rest of the vertices relative to `v0_new` based on the relative coord of `p`
    int3 rel_v_[2];
    float3 d0_ = p_ - float3(v0_);
    if (d0_.x > d0_.y) {
        if (d0_.y > d0_.z) { // x-y-z
            rel_v_ = { {1, 0, 0}, {1, 1, 0} };
        } else if (d0_.x > d0_.z) { // x-z-y
            rel_v_ = { {1, 0, 0}, {1, 0, 1} };
        } else { // z-x-y
            rel_v_ = { {0, 0, 1}, {1, 0, 1} };
        }
    } else {
        if (d0_.x > d0_.z) { // y-x-z
            rel_v_ = { {0, 1, 0}, {1, 1, 0} };
        } else if (d0_.y > d0_.z) { // y-z-x
            rel_v_ = { {0, 1, 0}, {0, 1, 1} };
        } else { // z-y-x
            rel_v_ = { {0, 0, 1}, {0, 1, 1} };
        }
    }

    // squeeze simplex to old coord to become regular
    const float g = 1.0 / 6.0; // = (1 - 1 / sqrt(N + 1)) / N
    float3 v0 = float3(v0_) - g * float(v0_.x + v0_.y + v0_.z);

    // calculate `p` relative to simplex vertices
    float3 d[4];
    d[0] = p - v0;
    d[1] =   d[0] + g       - float3(rel_v_[0]);
    d[2] =   d[0] + g * 2.0 - float3(rel_v_[1]);
    d[3] =   d[0] + g * 3.0 - 1.0;

    // assign a random "unit" direction to aech simplex vertices,
    // and calculate the dot product with relative direction
    float values[4] = {
        dot(d[0], _grad3(v0_)),
        dot(d[1], _grad3(v0_ + rel_v_[0])),
        dot(d[2], _grad3(v0_ + rel_v_[1])),
        dot(d[3], _grad3(v0_ + 1)),
    };

    // interp... no, "sum up the values using kernel function"
    const float normalization = 32.0;
    values[0] *= _simplexNoiseKernel(d[0]);
    values[1] *= _simplexNoiseKernel(d[1]);
    values[2] *= _simplexNoiseKernel(d[2]);
    values[3] *= _simplexNoiseKernel(d[3]);
    return normalization * (values[0] + values[1] + values[2] + values[3]);
}

int3 _grad3(uint3 v) {
    static int3 grads[12] = {
        {-1, -1, 0}, {-1, 1, 0}, {1, -1, 0}, {1, 1, 0},
        {-1, 0, -1}, {-1, 0, 1}, {1, 0, -1}, {1, 0, 1},
        {0, -1, -1}, {0, -1, 1}, {0, 1, -1}, {0, 1, 1},
    };

    uint idx = _hashInt(v.x + _hashInt(v.y + _hashInt(v.z)));
    return grads[idx % 12];
}

uint _hashInt(uint x) {
    const uint m = 0x45D9F3B;
    x = ((x >> 16) ^ x) * m;
    x = ((x >> 16) ^ x) * m;
    return (x >> 16) ^ x;
}

float _simplexNoiseKernel(float3 d) {
    const float kernel_size_sqr = 0.6; // 0.5 ensures no discontinuities, 0.6 may increase visual quality
    return sqr(sqr(max(0.0, kernel_size_sqr - dot(d, d))));
}


float sqr(float x) {
    return x * x;
}
float cub(float x) {
    return x * x * x;
}


/// https://sotrh.github.io/learn-wgpu/intermediate/tutorial13-hdr/#tonemapping
float3 acesToneMap(float3 color) {
    const float3x3 m1 = {
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777,
    };
    const float3x3 m2 = {
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602,
    };

    float3 v = mul(color, m1);
    float3 a = (v + 0.0245786) * v - 0.000090537;
    float3 b = (0.983729 * v + 0.4329510) * v + 0.238081;
    return mul(a / b, m2);
}


namespace special_relativity {
    /// consider the camera 4-velocity `V` in space-time, it is also the time axis of the tangent space-time of the camera,
    /// so `V` has space-time length of 1, so the time component of `V` is `V.t = sqrt(1 + dot(V.xyz, V.xyz))`.
    ///
    /// consider a Lorenz transformation `L` that transform the global time axis `{1,0,0,0}` into `V`,
    /// `L` can also transform vector in tangent space-time to global space-time.
    ///
    /// the camera speed for the "global observer" is `v = length(V.xyz) / V.t`,
    /// so the Lorenz factor of `L` is `γ = 1 / sqrt(1 - β * β)`, where `β = v/c` and `c` is the speed of light, we set `c = 1` here.
    /// then yields `γ = V.t`.
    ///
    /// consider a Lorenz transformation in 1-d space `l`, and `l` has the same Lorenz factor as `L`,
    /// then `l` can transform `{1,0}` into `{V.t,length(V.xyz)}`.
    /// consider a space rotation `R` that transform `V.xyz` into `{length(V.xyz),0,0}`,
    /// then the full `L` is construct as `L = inv(R) * l * R`.
    ///
    /// fortunately, there is no need to calculate `R`, because the net effect of `L` in space is expanding or shrinking along `V.xyz`,
    /// marked `L` applies to arbitrary space-time vector `A` gets `B`, and assume `B.xyz = A.xyz + k * normalize(V.xyz)`,
    /// consider `l` applies to `{t₀,x₀}` gets `{t₁,x₁} = {γ * (t₀ + β * x₀), γ * (β * t₀ + x₀)}`, then `x₁ = x₀ + k`,
    /// yields `B.xyz = A.xyz + (A.t + dot(A.xyz, V.xyz) / (V.t + 1)) * V.xyz` and `B.t = A.t * V.t + dot(A.xyz, V.xyz)`.
    float4 localToGlobal(float4 A, float3 V_xyz) {
        float V_t = sqrt(1 + dot(V_xyz, V_xyz));
        float scale = A.w + dot(A.xyz, V_xyz) / (V_t + 1);
        float3 space_comp = A.xyz + scale * V_xyz;
        float time_comp = dot(A, float4(V_xyz, V_t));
        return float4(space_comp, time_comp);
    }
}


/// fited in temperature range [2, 30]*1000
namespace black_body {
    float3 relColor(float T) {
        return {relR(T), relG(T), relB(T)};
    }
    /// max rel error ~1.3%
    float relR(float T) {
        return 3.561 * exp(-0.389 * T) + 0.745;
    }
    /// max rel error ~4%
    float relG(float T) {
        return -3.4 * exp(-0.49 * T) / sqr(T) + 0.00154 * T + 0.956;
    }
    /// max rel error ~4%
    float relB(float T) {
        float t = exp(-0.13 * T);
        return (-0.89 * sqr(t) - 1.7) * t + 0.013 * T + 1.704;
    }

    /// max rel error ~5%
    float luminance(float T) {
        return (50.0 * T) / (5.33 * exp(22.1 / T) + 9.7);
    }
}
