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

struct TMMeshVertex
{
    float3 position;
    float2 uv;
    float3 normal;
};

static_assert(sizeof(TMMeshVertex) == 48, "GPU TMMeshVertex size must be 48 bytes");

struct TMMeshlet
{
    uint vertex_offset;
    uint triangle_offset;
    uint vertex_count;
    uint triangle_count;
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
    uint renderMode;
    float4 diffuseColor;
};

//******************************************************************************
// Mesh Shader
//******************************************************************************
[[mesh]] void hello_triangle_mesh_main(
    mesh<VertexOut, void, 3, 1, topology::triangle> outputMesh,
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

[[mesh]] void hello_mesh_main(
    mesh<VertexOut, void, 64, 128, topology::triangle> outputMesh,
    device const TMMeshVertex* vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]],
    device const TMMeshlet* meshlets [[buffer(2)]],
    device const uint* meshletVertsMap [[buffer(3)]],
    device const uint* meshletIndices [[buffer(4)]],
    uint gtid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
    )
{
    device const TMMeshlet& m = meshlets[gid];
    outputMesh.set_primitive_count(m.triangle_count);

    // set meshletIndices 
    if (gtid < m.triangle_count)
    {
        uint packed = meshletIndices[m.triangle_offset + gtid];
        uint vIdx0  = (packed >>  0) & 0xFF;
        uint vIdx1  = (packed >>  8) & 0xFF;
        uint vIdx2  = (packed >> 16) & 0xFF;
        
        // set the local primitive indices so we use gtid, of not we can use global thread id in grid instead.
        uint triIdx = 3 * gtid;
        outputMesh.set_index(triIdx + 0, vIdx0);
        outputMesh.set_index(triIdx + 1, vIdx1);
        outputMesh.set_index(triIdx + 2, vIdx2);
    }

    // output the vertices now    
    if (gtid < m.vertex_count) 
    {
        uint vertIdx = meshletVertsMap[m.vertex_offset + gtid];
        TMMeshVertex meshVertex = vertices[vertIdx];

        VertexOut outVertex;
        // Transform the 3D vertex position to 3D clip space:
        float4 localPosition = float4(meshVertex.position, 1.0);
        
        // Transform: Projection * View * Model * Position
        outVertex.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * localPosition;

        if (uniforms.renderMode == 1) // Meshlets
        {

            uint h = gid * 0xF56A72FBu + 1013904223u;

            float3 color = float3(
                (h & 255) / 255.0f,
                ((h >> 8) & 255) / 255.0f,
                ((h >> 16) & 255) / 255.0f);

            outVertex.color = float4(color, 1.0f);
        }
        else if (uniforms.renderMode == 2) // UV Coordinates
        {
            outVertex.color = float4(meshVertex.uv, 0.0f, 1.0f);
        }
        else if (uniforms.renderMode == 3) // Normals
        {
            outVertex.color = float4(meshVertex.normal * 0.5f + 0.5f, 1.0f);
        }
        else if (uniforms.renderMode == 4) // Positions
        {
            outVertex.color = float4(meshVertex.position * 0.5f + 0.5f, 1.0f);
        }
        else // Default Shaded (Diffuse Lighting)
        {
            float3 lightDir = normalize(float3(0.5f, 1.0f, 0.5f));
            float diffuse = max(dot(meshVertex.normal, lightDir), 0.15f);
            outVertex.color = uniforms.diffuseColor * diffuse;
        }
        
        outputMesh.set_vertex(gtid, outVertex);
    }
}

//******************************************************************************
// Fragment Shader
//******************************************************************************
fragment float4 hello_triangle_fragment_main(VertexOut inVertex [[stage_in]])
{
    return inVertex.color;
}
