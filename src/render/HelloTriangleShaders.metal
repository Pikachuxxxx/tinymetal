#include <metal_stdlib>

using namespace metal;

//******************************************************************************
// Shader Types
//******************************************************************************
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

struct Uniforms
{
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

//******************************************************************************
// Mesh Shader
//******************************************************************************
[[mesh]] void hello_triangle_mesh_main(
    mesh<VertexOut, void, 64, 124, topology::triangle> outputMesh,
    constant VertexIn *vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]],
    uint threadIndex [[thread_index_in_threadgroup]])
{
    if (threadIndex == 0) {
        outputMesh.set_primitive_count(1);
        outputMesh.set_index(0, 0);
        outputMesh.set_index(1, 1);
        outputMesh.set_index(2, 2);
    }
    
    if (threadIndex < 3) {
        VertexOut outVertex;
        // Transform the 2D vertex position to 3D clip space:
        // Position on CPU has float2. We lift it to float4(pos.x, pos.y, 0.0, 1.0).
        float4 localPosition = float4(vertices[threadIndex].position, 0.0, 1.0);
        
        // Transform: Projection * View * Model * Position
        outVertex.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * localPosition;
        outVertex.color = vertices[threadIndex].color;
        
        outputMesh.set_vertex(threadIndex, outVertex);
    }
}

//******************************************************************************
// Fragment Shader
//******************************************************************************
fragment float4 hello_triangle_fragment_main(VertexOut inVertex [[stage_in]])
{
    return inVertex.color;
}
