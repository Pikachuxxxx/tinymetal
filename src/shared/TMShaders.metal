#include <metal_stdlib>

using namespace metal;

struct VertexIn
{
    float2 position;
    float4 color;
};

struct VertexOut
{
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant VertexIn *vertices [[buffer(0)]])
{
    VertexOut outVertex;
    outVertex.position = float4(vertices[vertexID].position, 0.0, 1.0);
    outVertex.color = vertices[vertexID].color;
    return outVertex;
}

fragment float4 fragment_main(VertexOut inVertex [[stage_in]])
{
    return inVertex.color;
}
