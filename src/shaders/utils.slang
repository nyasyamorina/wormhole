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


float2 getScreenCoordinate(uint2 thread_id, uint2 extent) {
    float2 uv_01 = float2(thread_id) / float2(extent);
    return {
        2.0 * uv_01.x - 1.0,
        1.0 - 2.0 * uv_01.y,
    };
}


float crosshair(uint2 thread_id, uint2 extent) {
    const float size = 0.01;
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


/// from "https://stackoverflow.com/a/22630970"
/// `b_v` in [-0.4, 2.0]
float3 BVIndexToRgb(float b_v) {
    float t;
    float3 color;

    if (b_v < 0.0) {
        t = (b_v - -0.4) / (0.0 - -0.4);
        color.r = (0.1 * t + 0.11) * t + 0.61;
    } else if (b_v < 0.4) {
        t = (b_v - 0.0) / (0.4 - 0.0);
        color.r = 0.18 * t + 0.82; // original: 0.17 * t + 0.83
    } else {
        color.r = 1.0;
    }

    if (b_v < 0.0) {
        t = (b_v - -0.4) / (0.0 - -0.4);
        color.g = (0.1 * t + 0.07) * t + 0.7;
    } else if (b_v < 0.4) {
        t = (b_v - 0.0) / (0.4 - 0.0);
        color.g = 0.11 * t + 0.87;
    } else if (b_v < 1.6) {
        t = (b_v - 0.4) / (1.6 - 0.4);
        color.g = -0.16 * t + 0.98;
    } else {
        t = (b_v - 1.6) / (2.0 - 1.6);
        color.g = -0.5 * t * t + 0.82;
    }

    if (b_v < 0.4) {
        color.b = 1.0;
    } else if (b_v < 1.5) {
        t = (b_v - 0.4) / (1.5 - 0.4);
        color.b = (0.1 * t - 0.47) * t + 1.0;
    } else {
        t = (b_v - 1.5) / (1.94 - 1.5);
        color.b = max(0.0, -0.6 * t * t + 0.63);
    }

    return color;
}

