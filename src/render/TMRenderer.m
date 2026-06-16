#import "TMRenderer.h"

#import <Metal/Metal.h>
#import <simd/simd.h>

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
} TMUniforms;

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

//******************************************************************************
// Private Interface
//******************************************************************************
@interface TMRenderer ()

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, weak) CAMetalLayer *metalLayer;
@property (nonatomic, assign) float aspect;

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
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"hello_triangle_fragment_main"];

    // Pipeline descriptor setup using Mesh Pipeline State
    MTLMeshRenderPipelineDescriptor *descriptor = [[MTLMeshRenderPipelineDescriptor alloc] init];
    descriptor.meshFunction = meshFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    _pipelineState = [_device newRenderPipelineStateWithMeshDescriptor:descriptor 
                                                               options:MTLPipelineOptionNone 
                                                            reflection:nil 
                                                                 error:error];
    if (!_pipelineState) {
        return nil;
    }

    _metalLayer = metalLayer;
    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;

    // Initialize 3D Camera at position (0, 0, 3) looking forward
    _cameraPosition = (simd_float3){0.0f, 0.0f, 3.0f};
    _cameraYaw = 0.0f;
    _cameraPitch = 0.0f;
    _aspect = 1.5f;

    return self;
}

- (void)drawableSizeWillChange:(CGSize)size
{
    self.metalLayer.drawableSize = size;
    self.aspect = (float)size.width / (float)size.height;
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

    // Build Model, View, and Projection (MVP) matrices
    simd_float3 pos = self.cameraPosition;
    float yaw = self.cameraYaw;
    float pitch = self.cameraPitch;
    
    simd_float4x4 translation = matrix_translation(-pos.x, -pos.y, -pos.z);
    simd_float4x4 rotationY = matrix_rotation_y(-yaw);
    simd_float4x4 rotationX = matrix_rotation_x(-pitch);
    simd_float4x4 viewMatrix = simd_mul(rotationX, simd_mul(rotationY, translation));
    
    float fov = 65.0f * (M_PI / 180.0f); // 65-degree FOV
    simd_float4x4 projectionMatrix = matrix_perspective_fov(fov, self.aspect, 0.1f, 100.0f);
    
    // Model rotation over time to show 3D effect
    static float angle = 0.0f;
    angle += 0.005f;
    simd_float4x4 modelMatrix = matrix_rotation_y(angle);

    TMUniforms uniforms;
    uniforms.modelMatrix = modelMatrix;
    uniforms.viewMatrix = viewMatrix;
    uniforms.projectionMatrix = projectionMatrix;

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setMeshBytes:triangleVertices length:sizeof(triangleVertices) atIndex:0];
    [encoder setMeshBytes:&uniforms length:sizeof(uniforms) atIndex:1];
   
    MTLSize threadGroups = MTLSizeMake(1, 1, 1);
    MTLSize threadsPerMesh = MTLSizeMake(128, 1, 1);

    [encoder drawMeshThreadgroups:threadGroups 
      threadsPerObjectThreadgroup:MTLSizeMake(0, 0, 0) 
        threadsPerMeshThreadgroup:threadsPerMesh];

    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
