#include <cstdio>
#include <string>
#include <vector>

#define TINYOBJLOADER_IMPLEMENTATION
#include <tiny_obj_loader.h>

#include <meshoptimizer.h>

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
    std::printf("  -i, --input <path>    Path to the input Wavefront OBJ file.\n");
    std::printf("  -h, --help            Show this help menu.\n");
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
        } else if (arg == "-i" || arg == "--input") {
            if (i + 1 < argc) {
                input_path = argv[++i];
            } else {
                std::fprintf(stderr, "Error: --input option requires a path argument.\n");
                return 1;
            }
        } else {
            std::fprintf(stderr, "Error: Unknown argument '%s'\n", arg.c_str());
            print_usage(argv[0]);
            return 1;
        }
    }

    if (input_path.empty()) {
        std::printf("No input OBJ file specified. Running default diagnostic...\n\n");
        
        const float vertices[] = {
            0.0f, 0.7f, 0.0f,
           -0.7f, -0.7f, 0.0f,
            0.7f, -0.7f, 0.0f,
        };
        const unsigned int indices[] = { 0, 1, 2 };
        const unsigned int vertexCount = 3;
        const unsigned int indexCount = 3;
        const unsigned int vertexSize = sizeof(float) * 3;
        unsigned int remap[vertexCount];

        const size_t uniqueVertexCount =
            meshopt_generateVertexRemap(remap, indices, indexCount, vertices, vertexCount, vertexSize);

        std::printf("tiny-mesh-tool\n");
        std::printf("meshoptimizer ready\n");
        std::printf("vertex_count=%u\n", vertexCount);
        std::printf("index_count=%u\n", indexCount);
        std::printf("vertex_stride=%u\n", vertexSize);
        std::printf("unique_vertex_count=%zu\n", uniqueVertexCount);
        std::printf("remap=[%u, %u, %u]\n", remap[0], remap[1], remap[2]);
    } else {
        std::printf("tiny-mesh-tool\n");
        std::printf("tinyobjloader ready\n");
        std::printf("Input OBJ path: %s\n", input_path.c_str());
        std::printf("OBJ file path accepted successfully!\n");
    }

    return 0;
}
