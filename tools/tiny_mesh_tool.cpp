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

//******************************************************************************
// Vertex Data
//******************************************************************************
// - [ ] Generate VB and IB data properly
// - [ ] Process it using meshoptio for reuse/overdraw/fetch and optimize int
// - [ ] Generate meshles (VB + IB + meshlets) 
// - [ ] export all final VB + IB + meshlets to *.bin files

struct Vertex 
{
    glm::vec3 pos;
    glm::vec2 uv;
    glm::vec3 normal;

};

struct VertexKey
{
    int32_t pos;
    int32_t uv;
    int32_t normal;

    // bool operator==(const VertexKey& other) const = default;
};

struct VertexKeyHash
{
    size_t operator()(const VertexKey& key) const 
    {
        size_t h = std::hash<int>{}(k.pos);
        h ^= std::hash<int>{}(k.uv)     + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>{}(k.normal) + 0x9e3779b9 + (h << 6) + (h >> 2);
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

                VertexKey key(attrib_idx.pos, attrib_idx.normal, attrib_idx.uv);

                if (vertexIdxMap.find(key) == vertexIdxMap.end()) 
                {
                    // new entry add to cache and extract data
                    Vertex v;
                    v.pos    = attrib.vertices[attrib_idx.pos];
                    v.normal = attrib.normals[attrib_idx.normal];
                    v.uv     = attrib.texcoords[attrib_idx.texcoord];

                    uint32_t newIdx = vertexData.size();
                    vertexIdxMap[newIdx] = key;

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
    }

    return 0;
}
