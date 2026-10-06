#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer Out {
    float heights[];
};

layout(set = 0, binding = 1, std430) buffer Params {
    float frequency;
    float seed;
    float originX;
    float originZ;
    float step;
    float padding;
    float outMin;
    float outMax;
    float width;
    float height;
    float octaves;
    float persistence;
    float lacunarity;
};

float quintic(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float hash(vec2 p, float s) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33 + s);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p, float s) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = vec2(quintic(f.x), quintic(f.y));
    return mix(mix(hash(i, s), hash(i + vec2(1, 0), s), u.x),
               mix(hash(i + vec2(0, 1), s), hash(i + vec2(1, 1), s), u.x), u.y);
}

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint z = gl_GlobalInvocationID.y;
    uint w = uint(width);
    uint h = uint(height);

    if (x >= w || z >= h) return;

    float worldX = originX + (float(x) - padding) * step;
    float worldZ = originZ + (float(z) - padding) * step;

    int numOctaves = int(octaves);
    float rAcc = 0.0;
    float curAmp = 1.0;
    float totalAmp = 0.0;
    float freqVal = frequency;

    for (int i = 0; i < numOctaves; i++) {
        float vOct = noise(vec2(worldX * freqVal, worldZ * freqVal), seed + float(i));
        rAcc += vOct * curAmp;
        totalAmp += curAmp;
        freqVal *= lacunarity;
        curAmp *= persistence;
    }

    float normFactor = totalAmp > 0.0 ? 1.0 / totalAmp : 1.0;
    float rOut = rAcc * normFactor;
    float clamped = max(rOut, 0.0);
    
    heights[z * w + x] = outMin + clamped * (outMax - outMin);
}
