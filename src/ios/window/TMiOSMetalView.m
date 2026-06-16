#import "TMiOSMetalView.h"

#import <QuartzCore/CAMetalLayer.h>

#import "TMRenderer.h"

//******************************************************************************
// Private Interface
//******************************************************************************
@interface TMiOSMetalView ()

@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) TMRenderer *renderer;

@end

//******************************************************************************
// Implementation
//******************************************************************************
@implementation TMiOSMetalView

//******************************************************************************
// UIView Overrides
//******************************************************************************
+ (Class)layerClass
{
    return [CAMetalLayer class];
}

//******************************************************************************
// Lifecycle
//******************************************************************************
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

//******************************************************************************
// View Events
//******************************************************************************
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

//******************************************************************************
// Drawing
//******************************************************************************
- (void)drawFrame
{
    [self.renderer draw];
}

- (void)updateDrawableSize
{
    CGSize boundsSize = self.bounds.size;
    CGSize size = CGSizeMake(boundsSize.width * self.contentScaleFactor,
                             boundsSize.height * self.contentScaleFactor);
    [self.renderer drawableSizeWillChange:size];
}

@end
