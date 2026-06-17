#import <UIKit/UIKit.h>

@class TMRenderer;

@interface TMiOSMetalView : UIView

@property (nonatomic, readonly) TMRenderer *renderer;

@end
