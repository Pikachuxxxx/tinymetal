#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMRenderer : NSObject

- (nullable instancetype)initWithMetalLayer:(CAMetalLayer *)metalLayer error:(NSError * _Nullable * _Nullable)error;
- (void)drawableSizeWillChange:(CGSize)size;
- (void)draw;

@end

NS_ASSUME_NONNULL_END
