#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMRenderer : NSObject

@property (nonatomic, assign) simd_float3 cameraPosition;
@property (nonatomic, assign) float cameraYaw;
@property (nonatomic, assign) float cameraPitch;

- (nullable instancetype)initWithMetalLayer:(CAMetalLayer *)metalLayer error:(NSError * _Nullable * _Nullable)error;
- (void)drawableSizeWillChange:(CGSize)size;
- (void)draw;

@end

NS_ASSUME_NONNULL_END
