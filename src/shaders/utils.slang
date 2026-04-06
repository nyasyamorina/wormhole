struct Camera {
    /// normalized
    float3 direction;
    float3 u;
    float3 v;
};

struct Uniform {
    /// in global coord
    float4 position;
    /// in global coord
    float3 velocity;

    Camera camera;

    uint iter_per_call;
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
    /// `V` has space-time length of 1, so the time component of `V` is `V.t = sqrt(1 + dot(V.xyz, V.xyz))`.
    ///
    /// consider a Lorenz transformation `L` that transform the global time axis `{1,0,0,0}` into `V`,
    /// and `L` can also transform vector in tangent space-time to global space-time.
    ///
    /// the speed of the camera for "global observers" is `v = length(V.xyz) / V.t`,
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


/// temperature range [2, 30]*1000 K
namespace black_body {
    float relRadiance(float wave_length, float temp) {
        float t = wave_length * 0.001;
        return 1.0 / (t * sqr(sqr(t)) * (exp(14.387768775039339 / (t * temp)) - 1.0));
    }

    float luminance(float temp) {
        float t = 0.0;
        float wave_length = cie::table_wave_length_begin;
        for (uint table_index = 0; table_index <= 33; table_index += 1) {
            t += relRadiance(wave_length, temp) * cie::XYZ_table[table_index].y;
            wave_length += cie::table_wave_length_step;
        }
        return cie::table_wave_length_step * t;
    }

    float3 color(float temp) {
        float3 t = float3(0.0);
        float wave_length = cie::table_wave_length_begin;
        for (uint table_index = 0; table_index <= 33; table_index += 1) {
            t += relRadiance(wave_length, temp) * cie::XYZ_table[table_index];
            wave_length += cie::table_wave_length_step;
        }
        return cie::table_wave_length_step * cie::XYZ_to_linear_sRGB(t);
    }
}


namespace cie {
    float3 XYZ_to_linear_sRGB(float3 xyz) {
        const float3x3 m = {
            3.2406255, -1.5372080, -0.4986286,
            -0.9689307, 1.8757561, 0.0415175,
            0.0557101, -0.2040211, 1.0569959,
        };
        return mul(m, xyz);
    }

    static const float3 XYZ_table[33] = {
        {0.001368, 0.000039, 0.006450001},
        {0.004243, 0.00012, 0.02005001},
        {0.01431, 0.000396, 0.06785001},
        {0.04351, 0.00121, 0.2074},
        {0.13438, 0.004, 0.6456},
        {0.2839, 0.0116, 1.3856},
        {0.34828, 0.023, 1.74706},
        {0.3362, 0.038, 1.77211},
        {0.2908, 0.06, 1.6692},
        {0.19536, 0.09098, 1.28764},
        {0.09564, 0.13902, 0.8129501},
        {0.03201, 0.20802, 0.46518},
        {0.0049, 0.323, 0.272},
        {0.0093, 0.503, 0.1582},
        {0.06327, 0.71, 0.07824999},
        {0.1655, 0.862, 0.04216},
        {0.2904, 0.954, 0.0203},
        {0.4334499, 0.9949501, 0.008749999},
        {0.5945, 0.995, 0.0039},
        {0.7621, 0.952, 0.0021},
        {0.9163, 0.87, 0.001650001},
        {1.0263, 0.757, 0.0011},
        {1.0622, 0.631, 0.0008},
        {1.0026, 0.503, 0.00034},
        {0.8544499, 0.381, 0.00019},
        {0.6424, 0.265, 0.00004999999},
        {0.4479, 0.175, 0.00002},
        {0.2835, 0.107, 0.0},
        {0.1649, 0.061, 0.0},
        {0.0874, 0.032, 0.0},
        {0.04677, 0.017, 0.0},
        {0.0227, 0.00821, 0.0},
        {0.01135916, 0.004102, 0.0},
    };
    static const float table_wave_length_begin = 380.0;
    static const float table_wave_length_end = 710.0;
    static const float table_wave_length_step = 10.0;
}


/// 2-D polar coordinate
namespace polar {
    float2 fromCartesian(float2 p) {
        return {length(p), atan2(p.y, p.x)};
    }
    float2[2] fromCartesian(float2 p, float2 d) {
        float2 pp = fromCartesian(p);
        float dr = dot(d, p) / pp[0];
        float da = dot(d, float2(-p.y, p.x)) / sqr(pp[0]);
        return {pp, {dr, da}};
    }

    float2 toCartesian(float2 p) {
        return p[0] * float2(cos(p[1]), sin(p[1]));
    }
    float2[2] toCartesian(float2 p, float2 d) {
        float2 pc = toCartesian(p);
        float dx = dot(d, float2(cos(p[1]), -pc.y));
        float dy = dot(d, float2(sin(p[1]),  pc.x));
        return {pc, {dx, dy}};
    }
}
