#include <cstdio>
#include <string>
#include <vector>
#include <unordered_map>

#define TINYOBJLOADER_IMPLEMENTATION
#include <tiny_obj_loader.h>

#include <meshoptimizer.h>

#include <glm/glm.hpp>
//******************************************************************************
// DEFINES
//******************************************************************************
#define MESHLETS_OPTIMAL_VERTICES 64
#define MESHLETS_OPTMIAL_PRIMS    124

#define ALIGN(x, a) (((x) + ((a) - 1)) & ~((a) - 1))

//******************************************************************************
// Vertex Data
//******************************************************************************
// - [x] Generate VB and IB data properly
// - [ ] Process it using meshoptio for reuse/overdraw/fetch and optimize it
//    meshopt_generateVertexRemap
//    meshopt_optimizeVertexCache
//    meshopt_optimizeOverdraw
//    meshopt_optimizeVertexFetch
//    meshopt_buildMeshlets
// - [ ] Generate meshles 
// - [ ] export all final VB + IB + meshlets to *.bin files
// - [ ] Print all stats

struct Vertex 
{
    glm::vec3 pos;
    float pad1 = 0.0f;
    glm::vec2 uv;
    float pad2[2] = { 0.0f, 0.0f };
    glm::vec3 normal;
    float pad3 = 0.0f;
};

struct VertexKey
{
    int32_t pos;
    int32_t uv;
    int32_t normal;

    bool operator==(const VertexKey& other) const
    {
        return pos == other.pos && uv == other.uv && normal == other.normal;
    }
};

struct VertexKeyHash
{
    size_t operator()(const VertexKey& key) const 
    {
        size_t h = std::hash<int>{}(key.pos);
        h ^= std::hash<int>{}(key.uv)     + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>{}(key.normal) + 0x9e3779b9 + (h << 6) + (h >> 2);
        return h;
    }
};

//******************************************************************************
// Help Menu
//******************************************************************************
void print_usage(const char* program_name)
{
    std::printf("================================================================================\n");
    std::printf("  TinyMeshTool Options\n");
    std::printf("================================================================================\n");
    std::printf("Usage: %s [options]\n\n", program_name);
    std::printf("Available Options:\n");
    std::printf("  -i, --input, --obj <path>   Path to the input Wavefront OBJ file.\n");
    std::printf("  -h, --help                  Show this help menu.\n");
    std::printf("================================================================================\n");
}

//******************************************************************************
// Export Data
//******************************************************************************
bool export_mesh_data(const std::string& filepath,
                      const std::vector<Vertex>& vertices,
                      const std::vector<meshopt_Meshlet>& meshlets,
                      const std::vector<uint32_t>& meshletVertMap,
                      const std::vector<uint32_t>& meshletIndices)
{
    std::FILE* file = std::fopen(filepath.c_str(), "wb");
    if (!file) {
        std::fprintf(stderr, "Error: Failed to open output file '%s'\n", filepath.c_str());
        return false;
    }

    uint64_t vertices_size = vertices.size();
    std::fwrite(&vertices_size, sizeof(vertices_size), 1, file);
    std::fwrite(vertices.data(), sizeof(Vertex), vertices.size(), file);

    uint64_t meshlets_size = meshlets.size();
    std::fwrite(&meshlets_size, sizeof(meshlets_size), 1, file);
    std::fwrite(meshlets.data(), sizeof(meshopt_Meshlet), meshlets.size(), file);

    uint64_t vertmap_size = meshletVertMap.size();
    std::fwrite(&vertmap_size, sizeof(vertmap_size), 1, file);
    std::fwrite(meshletVertMap.data(), sizeof(uint32_t), meshletVertMap.size(), file);

    uint64_t indices_size = meshletIndices.size();
    std::fwrite(&indices_size, sizeof(indices_size), 1, file);
    std::fwrite(meshletIndices.data(), sizeof(uint32_t), meshletIndices.size(), file);

    std::fclose(file);
    return true;
}

//******************************************************************************
// Entry Point
//******************************************************************************
int main(int argc, char* argv[])
{
    std::string input_path = "";

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            print_usage(argv[0]);
            return 0;
        } else if (arg == "-i" || arg == "--input" || arg == "--obj") {
            if (i + 1 < argc) {
                input_path = argv[++i];
            } else {
                std::fprintf(stderr, "Error: %s option requires a path argument.\n", arg.c_str());
                return 1;
            }
        } else {
            std::fprintf(stderr, "Error: Unknown argument '%s'\n", arg.c_str());
            print_usage(argv[0]);
            return 1;
        }
    }

    if (!input_path.empty()) {
        std::printf("tiny-mesh-tool\n");
        std::printf("Loading OBJ file: %s\n", input_path.c_str());

        tinyobj::attrib_t attrib;
        std::vector<tinyobj::shape_t> shapes;
        std::vector<tinyobj::material_t> materials;
        std::string err;

        bool ret = tinyobj::LoadObj(&attrib, &shapes, &materials, &err, input_path.c_str());

        if (!err.empty()) {
            std::printf("Load Message: %s\n", err.c_str());
        }

        if (!ret) {
            std::fprintf(stderr, "Failed to load/parse OBJ file.\n");
            return 1;
        }

        size_t num_vertices = attrib.vertices.size() / 3;
        size_t num_normals = attrib.normals.size() / 3;
        size_t num_texcoords = attrib.texcoords.size() / 2;

        std::printf("\n--- Global Statistics ---\n");
        std::printf("Vertices:            %zu\n", num_vertices);
        std::printf("Normals:             %zu (attributes %s)\n", num_normals, num_normals > 0 ? "PRESENT" : "ABSENT");
        std::printf("Texture Coordinates: %zu (attributes %s)\n", num_texcoords, num_texcoords > 0 ? "PRESENT" : "ABSENT");
        std::printf("Shapes Count:        %zu\n", shapes.size());
        std::printf("Materials Count:     %zu\n", materials.size());

        std::unordered_map<VertexKey, uint32_t, VertexKeyHash> vertexIdxMap;
        std::vector<uint32_t> indexData;
        std::vector<Vertex> vertexData;

        std::printf("\n--- Shapes Details ---\n");
        size_t total_indices = 0;
        for (size_t s = 0; s < shapes.size(); ++s) {
            const auto& shape = shapes[s];
            size_t indices_count = shape.mesh.indices.size();
            size_t face_count = shape.mesh.num_face_vertices.size();
            total_indices += indices_count;
            std::printf("  Shape[%zu]: '%s'\n", s, shape.name.c_str());
            std::printf("    Indices:   %zu\n", indices_count);
            std::printf("    Faces:     %zu (triangulated)\n", face_count);


            for (size_t i = 0; i < shape.mesh.indices.size(); ++i) {
                const tinyobj::index_t attrib_idx = shape.mesh.indices[i];

                VertexKey key = { attrib_idx.vertex_index, attrib_idx.texcoord_index, attrib_idx.normal_index };

                auto it = vertexIdxMap.find(key);
                if (it == vertexIdxMap.end()) 
                {
                    // new entry add to cache and extract data
                    Vertex v;
                    if (attrib_idx.vertex_index >= 0) {
                        v.pos.x = attrib.vertices[3 * attrib_idx.vertex_index + 0];
                        v.pos.y = attrib.vertices[3 * attrib_idx.vertex_index + 1];
                        v.pos.z = attrib.vertices[3 * attrib_idx.vertex_index + 2];
                    } else {
                        v.pos = glm::vec3(0.0f);
                    }

                    if (attrib_idx.texcoord_index >= 0) {
                        v.uv.x = attrib.texcoords[2 * attrib_idx.texcoord_index + 0];
                        v.uv.y = attrib.texcoords[2 * attrib_idx.texcoord_index + 1];
                    } else {
                        v.uv = glm::vec2(0.0f);
                    }

                    if (attrib_idx.normal_index >= 0) {
                        v.normal.x = attrib.normals[3 * attrib_idx.normal_index + 0];
                        v.normal.y = attrib.normals[3 * attrib_idx.normal_index + 1];
                        v.normal.z = attrib.normals[3 * attrib_idx.normal_index + 2];
                    } else {
                        v.normal = glm::vec3(0.0f, 0.0f, 1.0f);
                    }

                    uint32_t newIdx = static_cast<uint32_t>(vertexData.size());
                    vertexIdxMap[key] = newIdx;

                    vertexData.push_back(v);
                    indexData.push_back(newIdx);
                } 
                else 
                {
                    // vertex already exists push back the index into the IB list
                    indexData.push_back(it->second);
                }
            }
        }

        std::printf("\nTotal Indices across all shapes: %zu\n", total_indices);
        std::printf("Deduplicated Vertex Count:       %zu\n", vertexData.size());
        std::printf("Generated Index Count:           %zu\n", indexData.size());

        // MESHLET processing
        std::printf("\n--- Begin Meshopt optimization---\n");
        // Apply some meshopt optimization passes before generating meshlets
        // vertex remapping
        {
            std::vector<uint32_t> remappedVerticesTable(vertexData.size());
            size_t vertexCount = meshopt_generateVertexRemap(remappedVerticesTable.data(), indexData.data(), indexData.size(), vertexData.data(), vertexData.size(), sizeof(Vertex));
            std::printf("[meshopt] Remapped vertices count after remapping: %zu\n", vertexCount);
            std::printf("[meshopt] delta                                  : %zu\n", vertexData.size() - vertexCount);

            // this will remove the duplicate vertices, we can use this map to build a new vertex buffer by taking stuff from the remappedVertices table
            // we don't have to do this manually we can use the meshopt_remapVertexBuffer/remapIndexBuffer API to pass this and build new buffers
            std::vector<Vertex> remappedVertices(vertexCount);
            meshopt_remapVertexBuffer(remappedVertices.data(), vertexData.data(), vertexData.size(), sizeof(Vertex), remappedVerticesTable.data());

            // now regenrate the index buffer as well
            std::vector<uint32_t> remappedIndices(indexData.size());
            meshopt_remapIndexBuffer(remappedIndices.data(), indexData.data(), indexData.size(), remappedVerticesTable.data());
            
            vertexData = std::move(remappedVertices);
            indexData = std::move(remappedIndices);
        }
        std::printf("[meshopt] Meshopt Deduplicated Vertex Count      : %zu\n", vertexData.size());
    
        // optimize vertex cache
        {
            std::vector<uint32_t> optimalIndices(indexData.size());
            meshopt_optimizeVertexCache(optimalIndices.data(), indexData.data(), indexData.size(), vertexData.size());

            indexData = std::move(optimalIndices);
        }

        // optimize overdraw
        {
            std::vector<uint32_t> optimalIndices(indexData.size());
            meshopt_optimizeOverdraw(optimalIndices.data(), indexData.data(), indexData.size(), vertexData.empty() ? NULL: &vertexData[0].pos.x, vertexData.size(), sizeof(Vertex), 1.15f);

            indexData = std::move(optimalIndices);
        }

        // optimize vertex fetch
        {
            std::vector<Vertex> optimalVertices(vertexData.size());
            size_t uniqueVertices = meshopt_optimizeVertexFetch(optimalVertices.data(), indexData.data(), indexData.size(), vertexData.data(), vertexData.size(), sizeof(Vertex));

            optimalVertices.resize(uniqueVertices);

            vertexData = std::move(optimalVertices);
        }
        std::printf("[meshopt] Optimized Vertex Count                 : %zu\n", vertexData.size());
        std::printf("[meshopt] Optimized Optimized Index Count        : %zu\n", indexData.size());
        
        std::printf("\n--- Begin Meshlet generation---\n");
        size_t maxMeshlets = meshopt_buildMeshletsBound(indexData.size(), MESHLETS_OPTIMAL_VERTICES, MESHLETS_OPTMIAL_PRIMS);
        std::vector<meshopt_Meshlet> meshlets(maxMeshlets);
        std::vector<uint32_t> meshletVertMap(maxMeshlets * MESHLETS_OPTIMAL_VERTICES);
        std::vector<uint8_t> meshletIndices(maxMeshlets * MESHLETS_OPTMIAL_PRIMS * 3);
        std::printf("Max meshlets that can be generated       : %zu\n", maxMeshlets);
        
        const float coneWeight = 0.0f;

        size_t meshletCount = meshopt_buildMeshlets(
                meshlets.data(), 
                meshletVertMap.data(),
                meshletIndices.data(),
                indexData.data(),
                indexData.size(),
                vertexData.empty() ? NULL: &vertexData[0].pos.x,
                vertexData.size(),
                sizeof(Vertex),
                MESHLETS_OPTIMAL_VERTICES,
                MESHLETS_OPTMIAL_PRIMS,
                coneWeight
                );

        if (meshletCount > 0) {
            meshopt_Meshlet lastMeshlet = meshlets[meshletCount - 1];
            meshlets.resize(meshletCount);
            meshletVertMap.resize(lastMeshlet.vertex_offset + lastMeshlet.vertex_count);
            meshletIndices.resize(lastMeshlet.triangle_offset + (ALIGN(lastMeshlet.triangle_count * 3, 4)));
        } else {
            meshlets.clear();
            meshletVertMap.clear();
            meshletIndices.clear();
        }
        std::printf("[meshopt] Final meshlets generated: %zu\n", meshlets.size());

        // repack indices into pack into uint32_t
        std::vector<uint32_t> meshletIndexDataU32;
        {
            for (uint32_t m = 0; m < meshlets.size(); ++m) {
                size_t indexOffset = meshletIndexDataU32.size();

                meshopt_Meshlet& meshlet = meshlets[m];

                for (uint32_t t = 0; t < meshlet.triangle_count; ++t) 
                {
                    uint32_t t0 = t * 3 + 0 + meshlet.triangle_offset;
                    uint32_t t1 = t * 3 + 1 + meshlet.triangle_offset;
                    uint32_t t2 = t * 3 + 2 + meshlet.triangle_offset;

                    uint8_t idx0 = meshletIndices[t0];
                    uint8_t idx1 = meshletIndices[t1];
                    uint8_t idx2 = meshletIndices[t2];

                    uint32_t packedIdx = ((idx0 & 0xFF) << 0) |
                                         ((idx1 & 0xFF) << 8) |
                                         ((idx2 & 0xFF) << 16);

                    meshletIndexDataU32.push_back(packedIdx);
                }

                // update the new triangle offset for reading packed meshlet local indices
                meshlet.triangle_offset = static_cast<uint32_t>(indexOffset);
            }
        }

        std::printf("\n--- Exporting data ---\n");
        std::string output_path = input_path;
        size_t dot_pos = output_path.find_last_of('.');
        if (dot_pos != std::string::npos) {
            output_path = output_path.substr(0, dot_pos) + ".bin";
        } else {
            output_path += ".bin";
        }

        std::printf("Export path: %s\n", output_path.c_str());
        if (export_mesh_data(output_path, vertexData, meshlets, meshletVertMap, meshletIndexDataU32)) {
            std::printf("[export] Exported %zu vertices (%zu bytes)\n", vertexData.size(), vertexData.size() * sizeof(Vertex));
            std::printf("[export] Exported %zu meshlets (%zu bytes)\n", meshlets.size(), meshlets.size() * sizeof(meshopt_Meshlet));
            std::printf("[export] Exported %zu vertex map entries (%zu bytes)\n", meshletVertMap.size(), meshletVertMap.size() * sizeof(uint32_t));
            std::printf("[export] Exported %zu packed index entries (%zu bytes)\n", meshletIndexDataU32.size(), meshletIndexDataU32.size() * sizeof(uint32_t));
            std::printf("Export completed successfully!\n");
        } else {
            std::printf("Export failed!\n");
        }
    }
    return 0;
}
