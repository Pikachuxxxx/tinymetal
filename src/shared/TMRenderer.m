#import "TMRenderer.h"

#import <Metal/Metal.h>
#import <simd/simd.h>

typedef struct
{
    vector_float2 position;
    vector_float4 color;
} TMVertex;

static NSString * const TMRendererErrorDomain = @"com.example.tinymetal.renderer";

@interface TMRenderer ()

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, weak) CAMetalLayer *metalLayer;

@end

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

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    _pipelineState = [_device newRenderPipelineStateWithDescriptor:descriptor error:error];
    if (!_pipelineState) {
        return nil;
    }

    _metalLayer = metalLayer;
    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;

    return self;
}

- (void)drawableSizeWillChange:(CGSize)size
{
    self.metalLayer.drawableSize = size;
}

- (void)draw
{
    id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
    if (!drawable) {
        return;
    }

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

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBytes:triangleVertices length:sizeof(triangleVertices) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
