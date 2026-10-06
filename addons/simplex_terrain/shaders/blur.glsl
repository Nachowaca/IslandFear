#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer In {
    float inHeights[];
};

layout(set = 0, binding = 1, std430) buffer Out {
    float outHeights[];
};

layout(set = 0, binding = 2, std430) buffer Params {
    float q;
    float h;
    float width;
    float height;
};

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint z = gl_GlobalInvocationID.y;
    uint w = uint(width);
    uint h_val = uint(height);

    if (x >= w || z >= h_val) return;

    uint idx = z * w + x;

    // Handle border conditions (clamped boundaries)
    if (x == 0 || x == w - 1 || z == 0 || z == h_val - 1) {
        outHeights[idx] = inHeights[idx];
        return;
    }

    // 2D Binomial 3x3 filter (mathematically equivalent to horizontal + vertical 1D binomial passes)
    float center = inHeights[idx];
    float left = inHeights[idx - 1];
    float right = inHeights[idx + 1];
    float top = inHeights[idx - w];
    float bottom = inHeights[idx + w];
    
    float topLeft = inHeights[idx - w - 1];
    float topRight = inHeights[idx - w + 1];
    float bottomLeft = inHeights[idx + w - 1];
    float bottomRight = inHeights[idx + w + 1];

    outHeights[idx] = h * h * center + 
                      q * h * (left + right + top + bottom) + 
                      q * q * (topLeft + topRight + bottomLeft + bottomRight);
}
