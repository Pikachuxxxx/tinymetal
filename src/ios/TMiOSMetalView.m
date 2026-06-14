#import "TMiOSMetalView.h"

#import <QuartzCore/CAMetalLayer.h>

#import "TMRenderer.h"

@interface TMiOSMetalView ()

@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) TMRenderer *renderer;

@end

@implementation TMiOSMetalView

+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }

    self.backgroundColor = UIColor.blackColor;
    self.contentScaleFactor = self.traitCollection.displayScale > 0.0 ? self.traitCollection.displayScale : 2.0;

    NSError *error = nil;
    _renderer = [[TMRenderer alloc] initWithMetalLayer:(CAMetalLayer *)self.layer error:&error];
    if (!_renderer) {
        NSLog(@"Renderer setup failed: %@", error.localizedDescription);
        return nil;
    }

    [self updateDrawableSize];

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(drawFrame)];
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self updateDrawableSize];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    CGFloat scale = self.window.screen.scale;
    if (scale <= 0.0) {
        scale = self.traitCollection.displayScale > 0.0 ? self.traitCollection.displayScale : 2.0;
    }
    self.contentScaleFactor = scale;
    [self updateDrawableSize];
}

- (void)drawFrame
{
    [self.renderer draw];
}

- (void)updateDrawableSize
{
    CGSize size = CGSizeMake(CGRectGetWidth(self.bounds) * self.contentScaleFactor,
                             CGRectGetHeight(self.bounds) * self.contentScaleFactor);
    [self.renderer drawableSizeWillChange:size];
}

@end
