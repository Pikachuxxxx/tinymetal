#import "TMRenderer.h"

#import <Metal/Metal.h>
#import <simd/simd.h>

//******************************************************************************
// TODO:
//******************************************************************************
// - [ ] Cruse mesh shaders loading using custom *.bin file
// - [ ] Cleanup UI code and make it pretty alteast for mac, easy to program
//     - [ ] add some label on how to navigate etc using esc twice etc.
// - [ ] improve UI for iOS as well and add radio button for wireframe etc.
// - [ ] Add support for GPU frustum culling, write the instance buffer to be read by actual mesh shaders using GPU driven setup
// - [ ] continue with tutorial ==> LODs and selection etc.
// - [ ] Add support for bindless textures and load materials

//******************************************************************************
// Logging Utility
//******************************************************************************
static NSString* GetProjectRootDir() {
    static NSString *projectRoot = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleDir = [[NSBundle mainBundle] bundlePath];
        NSString *currentSearchDir = bundleDir;
        for (int i = 0; i < 10; i++) {
            // Scan for a marker that represents the project root (e.g. CMakeLists.txt)
            NSString *checkPath = [currentSearchDir stringByAppendingPathComponent:@"CMakeLists.txt"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:checkPath]) {
                projectRoot = currentSearchDir;
                break;
            }
            currentSearchDir = [currentSearchDir stringByDeletingLastPathComponent];
            if ([currentSearchDir isEqualToString:@"/"] || currentSearchDir.length == 0) {
                break;
            }
        }
        if (!projectRoot) {
            projectRoot = [[NSFileManager defaultManager] currentDirectoryPath];
        }
    });
    return projectRoot;
}

static void TMLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // Print to system console
    NSLog(@"%@", message);
    
    // Write to render_log.txt in the project root
    NSString *logPath = [GetProjectRootDir() stringByAppendingPathComponent:@"render_log.txt"];
    NSString *logLine = [NSString stringWithFormat:@"%@\n", message];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [logLine writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

//******************************************************************************
// Defines
//******************************************************************************

#define TM_MAX_MESHLET_VERTS 64
#define TM_MAX_MESHLET_TRIS  124

//******************************************************************************
// Types
//******************************************************************************
typedef struct
{
    vector_float2 position;
    vector_float4 color;
} TMVertex;

typedef struct {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
    uint32_t renderMode;
    uint32_t pad[3]; // 16-byte alignment padding
    simd_float4 diffuseColor;
} TMUniforms;

typedef struct {
    simd_float3 position;
    simd_float2 uv;
    simd_float3 normal;
} TMMeshVertex;

typedef struct {
    uint32_t vertexOffset;
    uint32_t triangleOffset;
    uint32_t vertexCount;
    uint32_t triangleCount;
} TMMeshlet;

//******************************************************************************
// Constants
//******************************************************************************
static NSString * const TMRendererErrorDomain = @"com.example.tinymetal.renderer";

//******************************************************************************
// Math Helpers
//******************************************************************************
static inline simd_float4x4 matrix_translation(float x, float y, float z) {
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[3] = (simd_float4){ x, y, z, 1.0f };
    return m;
}

static inline simd_float4x4 matrix_rotation_x(float radians) {
    float cosAngle = cosf(radians);
    float sinAngle = sinf(radians);
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[1] = (simd_float4){ 0.0f, cosAngle, sinAngle, 0.0f };
    m.columns[2] = (simd_float4){ 0.0f, -sinAngle, cosAngle, 0.0f };
    return m;
}

static inline simd_float4x4 matrix_rotation_y(float radians) {
    float cosAngle = cosf(radians);
    float sinAngle = sinf(radians);
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0] = (simd_float4){ cosAngle, 0.0f, -sinAngle, 0.0f };
    m.columns[2] = (simd_float4){ sinAngle, 0.0f, cosAngle, 0.0f };
    return m;
}

static inline simd_float4x4 matrix_perspective_fov(float fovRadians, float aspect, float nearZ, float farZ) {
    float ys = 1.0f / tanf(fovRadians * 0.5f);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    
    simd_float4x4 m;
    m.columns[0] = (simd_float4){ xs, 0.0f, 0.0f, 0.0f };
    m.columns[1] = (simd_float4){ 0.0f, ys, 0.0f, 0.0f };
    m.columns[2] = (simd_float4){ 0.0f, 0.0f, zs, -1.0f };
    m.columns[3] = (simd_float4){ 0.0f, 0.0f, zs * nearZ, 0.0f };
    return m;
}

static inline simd_float4x4 matrix_scale(float sx, float sy, float sz) {
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0].x = sx;
    m.columns[1].y = sy;
    m.columns[2].z = sz;
    return m;
}

//******************************************************************************
// Private Interface
//******************************************************************************
@interface TMRenderer ()

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLDepthStencilState> depthStencilState;
@property (nonatomic, strong) id<MTLTexture> depthTexture;
@property (nonatomic, weak) CAMetalLayer *metalLayer;
@property (nonatomic, assign) float aspect;

// Mesh resources loaded from binary file
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> meshletBuffer;
@property (nonatomic, strong) id<MTLBuffer> vertMapBuffer;
@property (nonatomic, strong) id<MTLBuffer> indicesBuffer;
@property (nonatomic, assign) uint64_t verticesCount;
@property (nonatomic, assign) uint64_t meshletsCount;
@property (nonatomic, assign) BOOL hasMesh;

// Auto-centering and scaling properties
@property (nonatomic, assign) simd_float3 meshCenter;
@property (nonatomic, assign) float meshScale;

@end

//******************************************************************************
// Implementation
//******************************************************************************
@implementation TMRenderer

- (nullable instancetype)initWithMetalLayer:(CAMetalLayer *)metalLayer error:(NSError * _Nullable __autoreleasing *)error
{
    self = [super init];
    if (!self) {
        return nil;
    }

    // Reset/clear render_log.txt on renderer initialization
    NSString *logPath = [GetProjectRootDir() stringByAppendingPathComponent:@"render_log.txt"];
    [[NSData data] writeToFile:logPath atomically:YES];

    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        if (error) {
            *error = [NSError errorWithDomain:TMRendererErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Metal is not available on this device."}];
        }
        return nil;
    }

    _commandQueue = [_device newCommandQueue];
    if (!_commandQueue) {
        if (error) {
            *error = [NSError errorWithDomain:TMRendererErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create a Metal command queue."}];
        }
        return nil;
    }

    NSURL *libraryURL = [[NSBundle mainBundle] URLForResource:@"default" withExtension:@"metallib"];
    if (!libraryURL) {
        if (error) {
            *error = [NSError errorWithDomain:TMRendererErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not find default.metallib in the app bundle."}];
        }
        return nil;
    }

    id<MTLLibrary> library = [_device newLibraryWithURL:libraryURL error:error];
    if (!library) {
        return nil;
    }

    // Load mesh and fragment shader functions
    id<MTLFunction> meshFunction = [library newFunctionWithName:@"hello_triangle_mesh_main"];
    id<MTLFunction> meshMainFunction = [library newFunctionWithName:@"hello_mesh_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"hello_triangle_fragment_main"];

    // Pipeline descriptor setup using Mesh Pipeline State
    MTLMeshRenderPipelineDescriptor *descriptor = [[MTLMeshRenderPipelineDescriptor alloc] init];
    descriptor.meshFunction = meshMainFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    _pipelineState = [_device newRenderPipelineStateWithMeshDescriptor:descriptor 
                                                               options:MTLPipelineOptionNone 
                                                            reflection:nil 
                                                                 error:error];
    if (!_pipelineState) {
        if (error && *error) {
            TMLog(@"[Renderer] Error: Failed to create Mesh Render Pipeline State: %@", (*error).localizedDescription);
        } else {
            TMLog(@"[Renderer] Error: Failed to create Mesh Render Pipeline State.");
        }
        return nil;
    }
    
    MTLDepthStencilDescriptor* dsDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    dsDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    dsDescriptor.depthWriteEnabled = YES;
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:dsDescriptor];


    TMLog(@"[Renderer] Successfully created Mesh Render Pipeline State.");
    TMLog(@"[Renderer] TMMeshVertex size: %zu", sizeof(TMMeshVertex));
    TMLog(@"[Renderer]   position offset: %zu", offsetof(TMMeshVertex, position));
    TMLog(@"[Renderer]   uv offset: %zu", offsetof(TMMeshVertex, uv));
    TMLog(@"[Renderer]   normal offset: %zu", offsetof(TMMeshVertex, normal));

    _metalLayer = metalLayer;
    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;

    // Initialize 3D Camera at position (0, 0, 3) looking forward
    _cameraPosition = (simd_float3){0.0f, 0.0f, 3.0f};
    _cameraYaw = 0.0f;
    _cameraPitch = 0.0f;
    _aspect = 1.5f;
    _renderMode = 0; // Default shaded
    _diffuseColor = (simd_float4){1.0f, 1.0f, 1.0f, 1.0f}; // Default white

    // Parse command line arguments for a custom model path
    NSString *modelPath = @"./data/bunny.bin"; // Default
    NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
    for (NSUInteger i = 0; i < arguments.count; i++) {
        if ([arguments[i] isEqualToString:@"--model"] || [arguments[i] isEqualToString:@"-m"] || [arguments[i] isEqualToString:@"--input"] || [arguments[i] isEqualToString:@"-i"]) {
            if (i + 1 < arguments.count) {
                modelPath = arguments[i + 1];
                break;
            }
        }
    }

    // load the 3D model now
    NSError* meshloadError = nil;
    BOOL loaded = [self loadMeshFromBinaryFile:modelPath error:&meshloadError];
    if (loaded) {
        TMLog(@"[Renderer] Mesh loaded successfully on init. Model: %@", modelPath);
    } else {
        TMLog(@"[Renderer] Error: Failed to load mesh on init. Model: %@, Error: %@", modelPath, meshloadError.localizedDescription);
    }

    return self;
}

- (void)drawableSizeWillChange:(CGSize)size
{
    self.metalLayer.drawableSize = size;
    self.aspect = (float)size.width / (float)size.height;

    // recreate the depth whenever window size changes
    MTLTextureDescriptor* depthTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                width:size.width
                                                height:size.height
                                                mipmapped:NO];
    depthTexDesc.storageMode = MTLStorageModePrivate;
    depthTexDesc.usage = MTLTextureUsageRenderTarget;
    self.depthTexture = [self.device newTextureWithDescriptor:depthTexDesc];
}

- (void)draw
{
    id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
    if (!drawable) {
        return;
    }

    // Original 2D triangle positions (Z is set to 0.0 inside the shader)
    static const TMVertex triangleVertices[] = {
        { {  0.0f,  0.7f }, { 1.0f, 0.2f, 0.2f, 1.0f } },
        { { -0.7f, -0.7f }, { 0.2f, 1.0f, 0.2f, 1.0f } },
        { {  0.7f, -0.7f }, { 0.2f, 0.4f, 1.0f, 1.0f } },
    };

    MTLRenderPassDescriptor *renderPass = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPass.colorAttachments[0].texture = drawable.texture;
    renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0.08, 0.09, 0.12, 1.0);
    renderPass.depthAttachment.texture = self.depthTexture;
    renderPass.depthAttachment.clearDepth = 1.0f;
    renderPass.depthAttachment.loadAction = MTLLoadActionClear;
    renderPass.depthAttachment.storeAction = MTLStoreActionStore;

    // Build Model, View, and Projection (MVP) matrices
    simd_float3 pos = self.cameraPosition;
    float yaw = self.cameraYaw;
    float pitch = self.cameraPitch;
    
    simd_float4x4 translation = matrix_translation(-pos.x, -pos.y, -pos.z);
    simd_float4x4 rotationY = matrix_rotation_y(yaw);
    simd_float4x4 rotationX = matrix_rotation_x(-pitch);
    simd_float4x4 viewMatrix = simd_mul(rotationX, simd_mul(rotationY, translation));
    
    float fov = 65.0f * (M_PI / 180.0f); // 65-degree FOV
    simd_float4x4 projectionMatrix = matrix_perspective_fov(fov, self.aspect, 0.1f, 100.0f);
    
    // Keep model stationary at the origin
    simd_float4x4 modelMatrix;
    if (self.hasMesh) {
        simd_float4x4 scaleMatrix = matrix_scale(self.meshScale, self.meshScale, self.meshScale);
        simd_float4x4 translateMatrix = matrix_translation(-self.meshCenter.x, -self.meshCenter.y, -self.meshCenter.z);
        modelMatrix = simd_mul(scaleMatrix, translateMatrix);
    } else {
        modelMatrix = matrix_identity_float4x4;
    }

    static BOOL loggedFirstDraw = NO;
    if (self.hasMesh && !loggedFirstDraw) {
        loggedFirstDraw = YES;
        TMLog(@"[Renderer] First draw call with mesh: %llu meshlets, %llu vertices.", self.meshletsCount, self.verticesCount);
        TMLog(@"[Renderer] Center applied: (%f, %f, %f), Scale applied: %f", self.meshCenter.x, self.meshCenter.y, self.meshCenter.z, self.meshScale);
    }

    TMUniforms uniforms;
    uniforms.modelMatrix = modelMatrix;
    uniforms.viewMatrix = viewMatrix;
    uniforms.projectionMatrix = projectionMatrix;
    uniforms.renderMode = self.renderMode;
    uniforms.diffuseColor = self.diffuseColor;

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setDepthStencilState:self.depthStencilState];
    [encoder setCullMode:MTLCullModeBack];
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [encoder setMeshBytes:&uniforms length:sizeof(uniforms) atIndex:1];
   
    if (self.hasMesh) {
        [encoder setMeshBuffer:self.vertexBuffer offset:0 atIndex:0];
        [encoder setMeshBuffer:self.meshletBuffer offset:0 atIndex:2];
        [encoder setMeshBuffer:self.vertMapBuffer offset:0 atIndex:3];
        [encoder setMeshBuffer:self.indicesBuffer offset:0 atIndex:4];

        MTLSize threadGroups = MTLSizeMake(self.meshletsCount, 1, 1);
        MTLSize threadsPerMesh = MTLSizeMake(128, 1, 1);

        [encoder drawMeshThreadgroups:threadGroups 
            threadsPerObjectThreadgroup:MTLSizeMake(0, 0, 0) 
            threadsPerMeshThreadgroup:threadsPerMesh];
    }

    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

- (BOOL)loadMeshFromBinaryFile:(NSString *)filepath error:(NSError * _Nullable * _Nullable)error
{
    TMLog(@"[Renderer] Attempting to load mesh from binary file: %@", filepath);
    TMLog(@"[Renderer] Current working directory: %@", [NSFileManager defaultManager].currentDirectoryPath);

    const char *path = [filepath UTF8String];
    FILE *file = NULL;
    NSString *resolvedPath = filepath;

    // 1. Try directly (works if we run from terminal in project directory)
    file = fopen(path, "rb");

    // 2. Try walking up from bundle directory to find the file in project directory or build folders
    if (!file) {
        NSString *bundleDir = [[NSBundle mainBundle] bundlePath];
        NSString *currentSearchDir = bundleDir;
        for (int i = 0; i < 10; i++) {
            NSString *checkPath = [currentSearchDir stringByAppendingPathComponent:filepath];
            if ([[NSFileManager defaultManager] fileExistsAtPath:checkPath]) {
                resolvedPath = checkPath;
                file = fopen([resolvedPath UTF8String], "rb");
                if (file) {
                    TMLog(@"[Renderer] Found mesh file via directory walk at: %@", resolvedPath);
                    break;
                }
            }
            currentSearchDir = [currentSearchDir stringByDeletingLastPathComponent];
            if ([currentSearchDir isEqualToString:@"/"] || currentSearchDir.length == 0) {
                break;
            }
        }
    }

    // 3. Try resource bundle (if copied as app resource)
    if (!file) {
        NSString *filename = [filepath lastPathComponent];
        NSString *nameOnly = [filename stringByDeletingPathExtension];
        NSString *ext = [filename pathExtension];
        NSString *resourcePath = [[NSBundle mainBundle] pathForResource:nameOnly ofType:ext];
        if (resourcePath) {
            resolvedPath = resourcePath;
            TMLog(@"[Renderer] Trying bundle resource path: %@", resolvedPath);
            file = fopen([resolvedPath UTF8String], "rb");
        }
    }

    if (!file) {
        TMLog(@"[Renderer] Error: Failed to open binary file '%@' at any path.", filepath);
        if (error) {
            *error = [NSError errorWithDomain:@"com.example.tinymetal"
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open file: %@", filepath]}];
        }
        return NO;
    }
    TMLog(@"[Renderer] Successfully opened binary file at path: %@", resolvedPath);

    // 1. Read vertices size/count
    uint64_t verticesCount = 0;
    if (fread(&verticesCount, sizeof(verticesCount), 1, file) != 1) {
        TMLog(@"[Renderer] Error: Failed to read vertices count.");
        fclose(file);
        return NO;
    }
    TMLog(@"[Renderer] Reading %llu vertices...", verticesCount);
    
    // Allocate GPU buffer for vertices
    size_t vertexBufferSize = verticesCount * sizeof(TMMeshVertex);
    self.vertexBuffer = [self.device newBufferWithLength:vertexBufferSize options:MTLResourceStorageModeShared];
    if (fread(self.vertexBuffer.contents, sizeof(TMMeshVertex), verticesCount, file) != verticesCount) {
        TMLog(@"[Renderer] Error: Failed to read vertex data.");
        fclose(file);
        return NO;
    }
    // Update the global vertex count
    self.verticesCount = verticesCount;

    // Log the first 5 vertices as a sanity check
    TMMeshVertex *vertsTemp = (TMMeshVertex *)self.vertexBuffer.contents;
    for (int i = 0; i < 5 && i < verticesCount; ++i) {
        TMLog(@"[Renderer] Vertex[%d]: pos=(%f, %f, %f), uv=(%f, %f), normal=(%f, %f, %f)",
              i, vertsTemp[i].position.x, vertsTemp[i].position.y, vertsTemp[i].position.z,
              vertsTemp[i].uv.x, vertsTemp[i].uv.y,
              vertsTemp[i].normal.x, vertsTemp[i].normal.y, vertsTemp[i].normal.z);
    }

    // 2. Read meshlets size/count
    uint64_t meshletCount = 0;
    if (fread(&meshletCount, sizeof(meshletCount), 1, file) != 1) {
        TMLog(@"[Renderer] Error: Failed to read meshlet count.");
        fclose(file);
        return NO;
    }
    TMLog(@"[Renderer] Reading %llu meshlets...", meshletCount);

    size_t meshletBufferSize = meshletCount * sizeof(TMMeshlet);
    self.meshletBuffer = [self.device newBufferWithLength:meshletBufferSize options:MTLResourceStorageModeShared];
    if (fread(self.meshletBuffer.contents, sizeof(TMMeshlet), meshletCount, file) != meshletCount) {
        TMLog(@"[Renderer] Error: Failed to read meshlet data.");
        fclose(file);
        return NO;
    }
    
    // Update the global meshlets count
    self.meshletsCount = meshletCount;

    // 3. Read vertex map size/count
    uint64_t vertMapCount = 0;
    if (fread(&vertMapCount, sizeof(vertMapCount), 1, file) != 1) {
        TMLog(@"[Renderer] Error: Failed to read vertex map count.");
        fclose(file);
        return NO;
    }
    TMLog(@"[Renderer] Reading %llu vertex map entries...", vertMapCount);

    size_t vertMapBufferSize = vertMapCount * sizeof(uint32_t);
    self.vertMapBuffer = [self.device newBufferWithLength:vertMapBufferSize options:MTLResourceStorageModeShared];
    if (fread(self.vertMapBuffer.contents, sizeof(uint32_t), vertMapCount, file) != vertMapCount) {
        TMLog(@"[Renderer] Error: Failed to read vertex map data.");
        fclose(file);
        return NO;
    }

    // 4. Read local indices size/count
    uint64_t indicesCount = 0;
    if (fread(&indicesCount, sizeof(indicesCount), 1, file) != 1) {
        TMLog(@"[Renderer] Error: Failed to read local indices count.");
        fclose(file);
        return NO;
    }
    TMLog(@"[Renderer] Reading %llu local indices...", indicesCount);

    size_t indicesBufferSize = indicesCount * sizeof(uint32_t);
    self.indicesBuffer = [self.device newBufferWithLength:indicesBufferSize options:MTLResourceStorageModeShared];
    if (fread(self.indicesBuffer.contents, sizeof(uint32_t), indicesCount, file) != indicesCount) {
        TMLog(@"[Renderer] Error: Failed to read local index data.");
        fclose(file);
        return NO;
    }

    fclose(file);
    self.hasMesh = YES;

    // Compute bounding box and scaling/centering factors
    simd_float3 minBounds = (simd_float3){INFINITY, INFINITY, INFINITY};
    simd_float3 maxBounds = (simd_float3){-INFINITY, -INFINITY, -INFINITY};
    TMMeshVertex *verts = (TMMeshVertex *)self.vertexBuffer.contents;
    for (uint64_t i = 0; i < verticesCount; ++i) {
        simd_float3 p = verts[i].position;
        minBounds = simd_min(minBounds, p);
        maxBounds = simd_max(maxBounds, p);
    }
    self.meshCenter = (minBounds + maxBounds) * 0.5f;
    
    float maxDim = maxBounds.x - minBounds.x;
    if (maxBounds.y - minBounds.y > maxDim) maxDim = maxBounds.y - minBounds.y;
    if (maxBounds.z - minBounds.z > maxDim) maxDim = maxBounds.z - minBounds.z;
    
    if (maxDim > 0.0001f) {
        self.meshScale = 2.0f / maxDim; // Normalize largest dimension to 2.0 units
    } else {
        self.meshScale = 1.0f;
    }

    TMLog(@"[Renderer] Mesh loaded successfully:");
    TMLog(@"[Renderer]   Vertices: %llu", verticesCount);
    TMLog(@"[Renderer]   Meshlets: %llu", self.meshletsCount);
    TMLog(@"[Renderer]   Min Bounds: (%f, %f, %f)", minBounds.x, minBounds.y, minBounds.z);
    TMLog(@"[Renderer]   Max Bounds: (%f, %f, %f)", maxBounds.x, maxBounds.y, maxBounds.z);
    TMLog(@"[Renderer]   Center: (%f, %f, %f)", self.meshCenter.x, self.meshCenter.y, self.meshCenter.z);
    TMLog(@"[Renderer]   Scale Factor applied: %f (Bunny normalized to 2.0 units)", self.meshScale);
    return YES;
}

@end
