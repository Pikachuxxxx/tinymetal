#import "TMMacMetalView.h"

#import <QuartzCore/CAMetalLayer.h>

#import "TMRenderer.h"

@interface TMMacMetalView ()

@property (nonatomic, strong) TMRenderer *renderer;
@property (nonatomic, strong) NSTimer *timer;

@end

@implementation TMMacMetalView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) {
        return nil;
    }

    self.wantsLayer = YES;
    self.layer = [CAMetalLayer layer];

    CGFloat scale = self.window.screen.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
    if (scale <= 0.0) {
        scale = 2.0;
    }
    self.layer.contentsScale = scale;

    NSError *error = nil;
    _renderer = [[TMRenderer alloc] initWithMetalLayer:(CAMetalLayer *)self.layer error:&error];
    if (!_renderer) {
        NSLog(@"Renderer setup failed: %@", error.localizedDescription);
        return nil;
    }

    [self updateDrawableSize];
    _timer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                              target:self
                                            selector:@selector(drawFrame)
                                            userInfo:nil
                                             repeats:YES];

    return self;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateDrawableSize];
}

- (void)layout
{
    [super layout];
    [self updateDrawableSize];
}

- (void)drawFrame
{
    [self.renderer draw];
}

- (void)updateDrawableSize
{
    CGFloat scale = self.window.screen.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
    if (scale <= 0.0) {
        scale = 2.0;
    }

    self.layer.contentsScale = scale;
    CGSize drawableSize = CGSizeMake(NSWidth(self.bounds) * scale, NSHeight(self.bounds) * scale);
    [self.renderer drawableSizeWillChange:drawableSize];
}

@end
