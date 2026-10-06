#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer InA {
    float inHeightsA[];
};

layout(set = 0, binding = 1, std430) buffer Out {
    float outHeights[];
};

layout(set = 0, binding = 2, std430) buffer Params {
    float globalStrength;
    float blendMode;
    float width;
    float height;
    float hasMask;
};

layout(set = 0, binding = 3, std430) buffer InB {
    float inHeightsB[];
};

layout(set = 0, binding = 4, std430) buffer Mask {
    float maskHeights[];
};

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint z = gl_GlobalInvocationID.y;
    uint w = uint(width);
    uint h = uint(height);

    if (x >= w || z >= h) return;

    uint idx = z * w + x;
    float a = inHeightsA[idx];
    float b = inHeightsB[idx];
    float m = (hasMask > 0.5) ? maskHeights[idx] : 1.0;
    m = clamp(m * globalStrength, 0.0, 1.0);

    float result = a;
    int mode = int(blendMode);

    if (mode == 0) { // Lerp / Override
        result = a + (b - a) * m;
    } else if (mode == 1) { // Add
        result = a + b * m;
    } else if (mode == 2) { // Subtract
        result = a - b * m;
    } else if (mode == 3) { // Multiply
        result = mix(a, a * b, m);
    } else if (mode == 4) { // Max
        result = mix(a, max(a, b), m);
    } else if (mode == 5) { // Min
        result = mix(a, min(a, b), m);
    }

    outHeights[idx] = result;
}
