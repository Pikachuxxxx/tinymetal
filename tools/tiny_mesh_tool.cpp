#include <cstdio>
#include <string>
#include <vector>
#include <unordered_map>

#define TINYOBJLOADER_IMPLEMENTATION
#include <tiny_obj_loader.h>

#include <meshoptimizer.h>

#include <glm/glm.hpp>

//******************************************************************************
// TYPE ALIASES & DEFINES
//******************************************************************************
template <typename T>
using vector_t = std::vector<T>;
using string_t = std::string;

#define MESHLETS_OPTIMAL_VERTICES 64
#define MESHLETS_OPTMIAL_PRIMS    124

#define ALIGN(x, a) (((x) + ((a) - 1)) & ~((a) - 1))

// Simple logging macro mimicking NSLog for standard console output
#define NSLog(...) { std::printf(__VA_ARGS__); std::printf("\n"); }

//******************************************************************************
// DUMMY STRUCTS & CONFIGS
//******************************************************************************
struct TMMeshletBounds
{
    glm::vec3 center;
    float radius;
    glm::vec3 cone_apex;
    glm::vec3 cone_axis;
    float cone_cutoff;
};

//******************************************************************************
// Vertex Data
//******************************************************************************
// - [x] Generate VB and IB data properly
// - [x] Process it using meshoptio for reuse/overdraw/fetch and optimize it
//    meshopt_generateVertexRemap
//    meshopt_optimizeVertexCache
//    meshopt_optimizeOverdraw
//    meshopt_optimizeVertexFetch
//    meshopt_buildMeshlets
// - [x] Generate meshlets
// - [x] export all final VB + IB + meshlets to *.bin files
// - [x] Print all stats

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

struct TinyObjData
{
    tinyobj::attrib_t attrib;
    vector_t<tinyobj::shape_t> shapes;
    vector_t<tinyobj::material_t> materials;
};

struct MeshGeometry
{
    vector_t<Vertex> vertices;
    vector_t<uint32_t> indices;
};

struct BoundingSphere
{
    glm::vec3 center;
    float radius;
};

struct MeshletData
{
    vector_t<meshopt_Meshlet> meshlets;
    vector_t<uint32_t> vertex_map;
    vector_t<uint32_t> packed_indices;
    vector_t<BoundingSphere> spheres;
};

// Encapsulates geometry and meshlets together for safe return and saving
struct SaveMeshData
{
    MeshGeometry geometry;
    MeshletData meshlet_data;
};

struct SaveMeshBinFileOpts
{
    string_t filepath;
    const MeshGeometry& geometry;
    const MeshletData& meshlet_data;
};

struct LoadMeshBinFileOpts
{
    MeshGeometry geometry;
    MeshletData meshlet_data;
    bool has_spheres = false;
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
    std::printf("  -p, --patch <path>          Path to the input BIN file to patch with bounding spheres.\n");
    std::printf("  -h, --help                  Show this help menu.\n");
    std::printf("================================================================================\n");
}

//******************************************************************************
// Block Writing Helpers
//******************************************************************************
bool write_vertices(std::FILE* file, const vector_t<Vertex>& vertices)
{
    uint64_t size = vertices.size();
    if (std::fwrite(&size, sizeof(size), 1, file) != 1) return false;
    if (std::fwrite(vertices.data(), sizeof(Vertex), vertices.size(), file) != vertices.size()) return false;
    return true;
}

bool write_meshlets(std::FILE* file, const vector_t<meshopt_Meshlet>& meshlets)
{
    uint64_t size = meshlets.size();
    if (std::fwrite(&size, sizeof(size), 1, file) != 1) return false;
    if (std::fwrite(meshlets.data(), sizeof(meshopt_Meshlet), meshlets.size(), file) != meshlets.size()) return false;
    return true;
}

bool write_vertex_map(std::FILE* file, const vector_t<uint32_t>& meshletVertMap)
{
    uint64_t size = meshletVertMap.size();
    if (std::fwrite(&size, sizeof(size), 1, file) != 1) return false;
    if (std::fwrite(meshletVertMap.data(), sizeof(uint32_t), meshletVertMap.size(), file) != meshletVertMap.size()) return false;
    return true;
}

bool write_indices(std::FILE* file, const vector_t<uint32_t>& meshletIndices)
{
    uint64_t size = meshletIndices.size();
    if (std::fwrite(&size, sizeof(size), 1, file) != 1) return false;
    if (std::fwrite(meshletIndices.data(), sizeof(uint32_t), meshletIndices.size(), file) != meshletIndices.size()) return false;
    return true;
}

bool write_bounding_spheres(std::FILE* file, const vector_t<BoundingSphere>& spheres)
{
    uint64_t size = spheres.size();
    if (std::fwrite(&size, sizeof(size), 1, file) != 1) return false;
    if (std::fwrite(spheres.data(), sizeof(BoundingSphere), spheres.size(), file) != spheres.size()) return false;
    return true;
}

//******************************************************************************
// Block Reading Helpers
//******************************************************************************
bool read_vertices(std::FILE* file, vector_t<Vertex>& vertices)
{
    uint64_t size = 0;
    if (std::fread(&size, sizeof(size), 1, file) != 1) return false;
    vertices.resize(size);
    if (std::fread(vertices.data(), sizeof(Vertex), size, file) != size) return false;
    return true;
}

bool read_meshlets(std::FILE* file, vector_t<meshopt_Meshlet>& meshlets)
{
    uint64_t size = 0;
    if (std::fread(&size, sizeof(size), 1, file) != 1) return false;
    meshlets.resize(size);
    if (std::fread(meshlets.data(), sizeof(meshopt_Meshlet), size, file) != size) return false;
    return true;
}

bool read_vertex_map(std::FILE* file, vector_t<uint32_t>& meshletVertMap)
{
    uint64_t size = 0;
    if (std::fread(&size, sizeof(size), 1, file) != 1) return false;
    meshletVertMap.resize(size);
    if (std::fread(meshletVertMap.data(), sizeof(uint32_t), size, file) != size) return false;
    return true;
}

bool read_indices(std::FILE* file, vector_t<uint32_t>& meshletIndices)
{
    uint64_t size = 0;
    if (std::fread(&size, sizeof(size), 1, file) != 1) return false;
    meshletIndices.resize(size);
    if (std::fread(meshletIndices.data(), sizeof(uint32_t), size, file) != size) return false;
    return true;
}

bool read_bounding_spheres(std::FILE* file, vector_t<BoundingSphere>& spheres)
{
    uint64_t size = 0;
    if (std::fread(&size, sizeof(size), 1, file) != 1) return false;
    spheres.resize(size);
    if (std::fread(spheres.data(), sizeof(BoundingSphere), size, file) != size) return false;
    return true;
}

//******************************************************************************
// Main Save/Load Functions
//******************************************************************************
bool save_mesh_bin(const SaveMeshBinFileOpts& opts)
{
    std::FILE* file = std::fopen(opts.filepath.c_str(), "wb");
    if (!file) {
        std::fprintf(stderr, "Error: Failed to open output file '%s'\n", opts.filepath.c_str());
        return false;
    }

    bool ok = write_vertices(file, opts.geometry.vertices) &&
              write_meshlets(file, opts.meshlet_data.meshlets) &&
              write_vertex_map(file, opts.meshlet_data.vertex_map) &&
              write_indices(file, opts.meshlet_data.packed_indices) &&
              write_bounding_spheres(file, opts.meshlet_data.spheres);

    std::fclose(file);
    return ok;
}

bool load_mesh_bin(const string_t& filepath, LoadMeshBinFileOpts& output)
{
    std::FILE* file = std::fopen(filepath.c_str(), "rb");
    if (!file) {
        std::fprintf(stderr, "Error: Failed to open input file '%s'\n", filepath.c_str());
        return false;
    }

    output.has_spheres = false;
    bool ok = read_vertices(file, output.geometry.vertices) &&
              read_meshlets(file, output.meshlet_data.meshlets) &&
              read_vertex_map(file, output.meshlet_data.vertex_map) &&
              read_indices(file, output.meshlet_data.packed_indices);

    if (ok) {
        if (read_bounding_spheres(file, output.meshlet_data.spheres)) {
            output.has_spheres = true;
        } else {
            output.meshlet_data.spheres.clear();
        }
    }

    std::fclose(file);
    return ok;
}

//******************************************************************************
// Pipeline Processing Functions
//******************************************************************************
bool load_obj_file(const string_t& filepath, TinyObjData& out_data)
{
    std::string err;
    bool ret = tinyobj::LoadObj(&out_data.attrib, &out_data.shapes, &out_data.materials, &err, filepath.c_str());
    if (!err.empty()) {
        std::printf("Load Message: %s\n", err.c_str());
    }
    return ret;
}

MeshGeometry build_vb_ib(const TinyObjData& input)
{
    MeshGeometry geom;
    std::unordered_map<VertexKey, uint32_t, VertexKeyHash> vertexIdxMap;

    for (size_t s = 0; s < input.shapes.size(); ++s) {
        const auto& shape = input.shapes[s];
        for (size_t i = 0; i < shape.mesh.indices.size(); ++i) {
            const tinyobj::index_t attrib_idx = shape.mesh.indices[i];
            VertexKey key = { attrib_idx.vertex_index, attrib_idx.texcoord_index, attrib_idx.normal_index };

            auto it = vertexIdxMap.find(key);
            if (it == vertexIdxMap.end()) {
                Vertex v;
                if (attrib_idx.vertex_index >= 0) {
                    v.pos.x = input.attrib.vertices[3 * attrib_idx.vertex_index + 0];
                    v.pos.y = input.attrib.vertices[3 * attrib_idx.vertex_index + 1];
                    v.pos.z = input.attrib.vertices[3 * attrib_idx.vertex_index + 2];
                } else {
                    v.pos = glm::vec3(0.0f);
                }

                if (attrib_idx.texcoord_index >= 0) {
                    v.uv.x = input.attrib.texcoords[2 * attrib_idx.texcoord_index + 0];
                    v.uv.y = input.attrib.texcoords[2 * attrib_idx.texcoord_index + 1];
                } else {
                    v.uv = glm::vec2(0.0f);
                }

                if (attrib_idx.normal_index >= 0) {
                    v.normal.x = input.attrib.normals[3 * attrib_idx.normal_index + 0];
                    v.normal.y = input.attrib.normals[3 * attrib_idx.normal_index + 1];
                    v.normal.z = input.attrib.normals[3 * attrib_idx.normal_index + 2];
                } else {
                    v.normal = glm::vec3(0.0f, 0.0f, 1.0f);
                }

                uint32_t newIdx = static_cast<uint32_t>(geom.vertices.size());
                vertexIdxMap[key] = newIdx;
                geom.vertices.push_back(v);
                geom.indices.push_back(newIdx);
            } else {
                geom.indices.push_back(it->second);
            }
        }
    }
    return geom;
}

MeshGeometry optimize_mesh(const MeshGeometry& input)
{
    MeshGeometry opt = input;

    // 1. Remap vertices
    {
        vector_t<uint32_t> remappedVerticesTable(opt.vertices.size());
        size_t vertexCount = meshopt_generateVertexRemap(
            remappedVerticesTable.data(), 
            opt.indices.data(), 
            opt.indices.size(), 
            opt.vertices.data(), 
            opt.vertices.size(), 
            sizeof(Vertex)
        );

        vector_t<Vertex> remappedVertices(vertexCount);
        meshopt_remapVertexBuffer(remappedVertices.data(), opt.vertices.data(), opt.vertices.size(), sizeof(Vertex), remappedVerticesTable.data());

        vector_t<uint32_t> remappedIndices(opt.indices.size());
        meshopt_remapIndexBuffer(remappedIndices.data(), opt.indices.data(), opt.indices.size(), remappedVerticesTable.data());

        opt.vertices = remappedVertices;
        opt.indices = remappedIndices;
    }

    // 2. Optimize vertex cache
    {
        vector_t<uint32_t> optimalIndices(opt.indices.size());
        meshopt_optimizeVertexCache(optimalIndices.data(), opt.indices.data(), opt.indices.size(), opt.vertices.size());
        opt.indices = optimalIndices;
    }

    // 3. Optimize overdraw
    {
        vector_t<uint32_t> optimalIndices(opt.indices.size());
        meshopt_optimizeOverdraw(optimalIndices.data(), opt.indices.data(), opt.indices.size(), opt.vertices.empty() ? NULL : &opt.vertices[0].pos.x, opt.vertices.size(), sizeof(Vertex), 1.15f);
        opt.indices = optimalIndices;
    }

    // 4. Optimize vertex fetch
    {
        vector_t<Vertex> optimalVertices(opt.vertices.size());
        size_t uniqueVertices = meshopt_optimizeVertexFetch(optimalVertices.data(), opt.indices.data(), opt.indices.size(), opt.vertices.data(), opt.vertices.size(), sizeof(Vertex));
        optimalVertices.resize(uniqueVertices);
        opt.vertices = optimalVertices;
    }

    return opt;
}

MeshletData build_meshlets(const MeshGeometry& input)
{
    MeshletData data;

    size_t maxMeshlets = meshopt_buildMeshletsBound(input.indices.size(), MESHLETS_OPTIMAL_VERTICES, MESHLETS_OPTMIAL_PRIMS);
    vector_t<meshopt_Meshlet> meshlets(maxMeshlets);
    vector_t<uint32_t> meshletVertMap(maxMeshlets * MESHLETS_OPTIMAL_VERTICES);
    vector_t<uint8_t> meshletIndices(maxMeshlets * MESHLETS_OPTMIAL_PRIMS * 3);

    const float coneWeight = 0.0f;
    size_t meshletCount = meshopt_buildMeshlets(
        meshlets.data(),
        meshletVertMap.data(),
        meshletIndices.data(),
        input.indices.data(),
        input.indices.size(),
        input.vertices.empty() ? NULL : &input.vertices[0].pos.x,
        input.vertices.size(),
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

    data.meshlets = meshlets;
    data.vertex_map = meshletVertMap;

    // Pack indices into uint32_t
    {
        for (uint32_t m = 0; m < meshlets.size(); ++m) {
            size_t indexOffset = data.packed_indices.size();
            meshopt_Meshlet& meshlet = data.meshlets[m];

            for (uint32_t t = 0; t < meshlet.triangle_count; ++t) {
                uint32_t t0 = t * 3 + 0 + meshlet.triangle_offset;
                uint32_t t1 = t * 3 + 1 + meshlet.triangle_offset;
                uint32_t t2 = t * 3 + 2 + meshlet.triangle_offset;

                uint8_t idx0 = meshletIndices[t0];
                uint8_t idx1 = meshletIndices[t1];
                switch (t % 1) { // unused, just keep compiler happy
                    default: break;
                }
                uint8_t idx2 = meshletIndices[t2];

                uint32_t packedIdx = ((idx0 & 0xFF) << 0) |
                                     ((idx1 & 0xFF) << 8) |
                                     ((idx2 & 0xFF) << 16);

                data.packed_indices.push_back(packedIdx);
            }

            meshlet.triangle_offset = static_cast<uint32_t>(indexOffset);
        }
    }

    return data;
}

vector_t<BoundingSphere> compute_bounding_spheres(const MeshGeometry& geometry, const MeshletData& meshlet_data)
{
    vector_t<BoundingSphere> spheres(meshlet_data.meshlets.size());

    for (size_t i = 0; i < meshlet_data.meshlets.size(); ++i) {
        const auto& meshlet = meshlet_data.meshlets[i];
        if (meshlet.vertex_count == 0) {
            spheres[i] = { glm::vec3(0.0f), 0.0f };
            continue;
        }

        glm::vec3 min_pos = geometry.vertices[meshlet_data.vertex_map[meshlet.vertex_offset]].pos;
        glm::vec3 max_pos = min_pos;
        for (uint32_t j = 1; j < meshlet.vertex_count; ++j) {
            uint32_t v_idx = meshlet_data.vertex_map[meshlet.vertex_offset + j];
            glm::vec3 p = geometry.vertices[v_idx].pos;
            min_pos = glm::min(min_pos, p);
            max_pos = glm::max(max_pos, p);
        }

        glm::vec3 center = (min_pos + max_pos) * 0.5f;

        float radius = 0.0f;
        for (uint32_t j = 0; j < meshlet.vertex_count; ++j) {
            uint32_t v_idx = meshlet_data.vertex_map[meshlet.vertex_offset + j];
            glm::vec3 p = geometry.vertices[v_idx].pos;
            radius = glm::max(radius, glm::distance(center, p));
        }

        spheres[i] = { center, radius };
    }

    return spheres;
}

SaveMeshData build_export_geom(const TinyObjData& obj_data, const MeshletData& loaded_meshlets)
{
    SaveMeshData result;
    result.geometry = optimize_mesh(build_vb_ib(obj_data));
    if (loaded_meshlets.meshlets.empty()) {
        result.meshlet_data = build_meshlets(result.geometry);
    } else {
        result.meshlet_data = loaded_meshlets;
    }
    result.meshlet_data.spheres = compute_bounding_spheres(result.geometry, result.meshlet_data);
    return result;
}

//******************************************************************************
// Entry Point
//******************************************************************************
int main(int argc, char* argv[])
{
    string_t input_path = "";
    string_t input_bin_to_patch = "";

    for (int i = 1; i < argc; ++i) {
        string_t arg = argv[i];
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
        } else if (arg == "-p" || arg == "--patch") {
            if (i + 1 < argc) {
                input_bin_to_patch = argv[++i]; 
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

    if (input_path.empty() && input_bin_to_patch.empty()) {
        print_usage(argv[0]);
        return 1;
    }

    string_t obj_path = "";
    string_t bin_path = "";

    LoadMeshBinFileOpts loaded;
    SaveMeshData mesh_data;

    if (!input_path.empty()) {
        // -------------------------------------------------------------
        // Export Path (OBJ to BIN)
        // -------------------------------------------------------------
        obj_path = input_path;
        bin_path = obj_path.substr(0, obj_path.size() - 4) + ".bin";

        NSLog("Loading OBJ: %s", obj_path.c_str());
        TinyObjData obj_data;
        if (!load_obj_file(obj_path, obj_data)) return 1;

        // Chained invocation returning SaveMeshData by value safely
        mesh_data = build_export_geom(obj_data, MeshletData());

        goto stage_save;
    } 
    else if (!input_bin_to_patch.empty()) {
        // -------------------------------------------------------------
        // Patch Path (BIN to Patched BIN)
        // -------------------------------------------------------------
        bin_path = input_bin_to_patch;
        if (!load_mesh_bin(bin_path, loaded)) {
            std::fprintf(stderr, "Error: Failed to load BIN file '%s' for patching.\n", bin_path.c_str());
            return 1;
        }

        if (loaded.has_spheres) {
            NSLog("BIN file already has bounding spheres. No patching needed.");
            return 0;
        }

        // Reconstruct matching OBJ path
        obj_path = bin_path.substr(0, bin_path.size() - 4) + ".obj";

        NSLog("Loading matching OBJ: %s", obj_path.c_str());
        TinyObjData obj_data;
        if (!load_obj_file(obj_path, obj_data)) {
            NSLog("\n================================================================================");
            NSLog("Error: Could not load matching OBJ file '%s'.", obj_path.c_str());
            NSLog("The original OBJ geometry is required to calculate bounding spheres for patching.");
            NSLog("================================================================================\n");
            return 1;
        }

        // Call build_export_geom using loaded meshlets
        mesh_data = build_export_geom(obj_data, loaded.meshlet_data);

        goto stage_save;
    }

stage_save:
    NSLog("Saving binary to '%s'...", bin_path.c_str());
    SaveMeshBinFileOpts save_opts = {
        .filepath = bin_path,
        .geometry = mesh_data.geometry,
        .meshlet_data = mesh_data.meshlet_data
    };

    if (save_mesh_bin(save_opts)) {
        NSLog("Done!");
        return 0;
    } else {
        std::fprintf(stderr, "Error: Failed to save mesh bin.\n");
        return 1;
    }

    return 0;
}
