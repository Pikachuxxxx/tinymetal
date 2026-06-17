#import <AppKit/AppKit.h>

@class TMRenderer;

@interface TMMacMetalView : NSView

@property (nonatomic, readonly) TMRenderer *renderer;

@end
