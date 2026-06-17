#import "TMMacMetalView.h"
#include <Foundation/Foundation.h>

#import <QuartzCore/CAMetalLayer.h>

#import "TMRenderer.h"

//******************************************************************************
// Private Interface
//******************************************************************************
@interface TMMacMetalView ()

@property (nonatomic, strong) TMRenderer *renderer;
@property (atomic, assign) BOOL running;
@property (atomic, assign) BOOL keyW;
@property (atomic, assign) BOOL keyA;
@property (atomic, assign) BOOL keyS;
@property (atomic, assign) BOOL keyD;
@property (nonatomic, assign) BOOL mouseCaptured;

@end

//******************************************************************************
// Implementation
//******************************************************************************
@implementation TMMacMetalView

//******************************************************************************
// Mouse Capture Helpers
//******************************************************************************
- (void)captureMouse {
    if (!self.mouseCaptured) {
        self.mouseCaptured = YES;
        [NSCursor hide];
        CGAssociateMouseAndMouseCursorPosition(NO);
        if (self.window) {
            NSRect frame = [self.window convertRectToScreen:[self convertRect:self.bounds toView:nil]];
            CGPoint center = CGPointMake(NSMidX(frame), NSMidY(frame));
            NSScreen *primaryScreen = [NSScreen screens].firstObject;
            CGFloat screenHeight = primaryScreen.frame.size.height;
            CGPoint warpPoint = CGPointMake(center.x, screenHeight - center.y);
            CGWarpMouseCursorPosition(warpPoint);
        }
    }
}

- (void)releaseMouse {
    if (self.mouseCaptured) {
        self.mouseCaptured = NO;
        CGAssociateMouseAndMouseCursorPosition(YES);
        [NSCursor unhide];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    [self captureMouse];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [super viewWillMoveToWindow:newWindow];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:self.window];
    }
    if (newWindow) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidResignKey:) name:NSWindowDidResignKeyNotification object:newWindow];
    }
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [self releaseMouse];
}

//******************************************************************************
// Lifecycle
//******************************************************************************
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

    if (@available(macOS 10.13, *)) {
        ((CAMetalLayer *)self.layer).displaySyncEnabled = NO;
    }

    // Start the background rendering loop
    _running = YES;
    [NSThread detachNewThreadSelector:@selector(renderLoop) toTarget:self withObject:nil];

    return self;
}

- (void)dealloc
{
    _running = NO;
    [self releaseMouse];
}

//******************************************************************************
// View Events
//******************************************************************************
- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateDrawableSize];
    if (self.window) {
        self.window.acceptsMouseMovedEvents = YES;
        [self captureMouse];
    }
}

- (void)layout
{
    [super layout];
    [self updateDrawableSize];
}

- (BOOL) acceptsFirstResponder {
    return YES;
}

- (void) keyDown:(NSEvent *)event {
    if (event.keyCode == 53) { // ESC key
        if (self.mouseCaptured) {
            [self releaseMouse];
        } else {
            _running = NO; 
            [NSApp terminate:self];
        }
    } else {
        NSString *chars = event.charactersIgnoringModifiers;
        if (chars.length > 0) {
            unichar code = [chars characterAtIndex:0];
            if (code == 'w' || code == 'W') self.keyW = YES;
            else if (code == 'a' || code == 'A') self.keyA = YES;
            else if (code == 's' || code == 'S') self.keyS = YES;
            else if (code == 'd' || code == 'D') self.keyD = YES;
        }
        [super keyDown:event];
    }
}

- (void) keyUp:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers;
    if (chars.length > 0) {
        unichar code = [chars characterAtIndex:0];
        if (code == 'w' || code == 'W') self.keyW = NO;
        else if (code == 'a' || code == 'A') self.keyA = NO;
        else if (code == 's' || code == 'S') self.keyS = NO;
        else if (code == 'd' || code == 'D') self.keyD = NO;
    }
    [super keyUp:event];
}

- (void) mouseMoved:(NSEvent *)event {
    if (self.mouseCaptured) {
        float sensitivity = 0.0015f;
        float yaw = self.renderer.cameraYaw + event.deltaX * sensitivity;
        float pitch = self.renderer.cameraPitch - event.deltaY * sensitivity;
        
        // Clamp pitch to avoid flipping upside down (-89 to +89 degrees)
        float limit = 89.0f * (M_PI / 180.0f);
        if (pitch > limit) pitch = limit;
        if (pitch < -limit) pitch = -limit;
        
        self.renderer.cameraYaw = yaw;
        self.renderer.cameraPitch = pitch;
    }
}

- (void) mouseDragged:(NSEvent *)event {
    [self mouseMoved:event];
}

//******************************************************************************
// Drawing
//******************************************************************************
- (void)renderLoop
{
    @autoreleasepool {
        NSTimeInterval lastTime = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval lastFrameTime = lastTime;
        NSInteger frameCount = 0;
        
        while (self.running) {
            @autoreleasepool {
                NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
                frameCount++;
                
                double deltaTime = currentTime - lastFrameTime;
                lastFrameTime = currentTime;
                
                if (currentTime - lastTime >= 1.0) {
                    double fps = frameCount / (currentTime - lastTime);
                    frameCount = 0;
                    lastTime = currentTime;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.window) {
                            self.window.title = [NSString stringWithFormat:@"TinyMetal - %.1f FPS", fps];
                        }
                    });
                }
                
                // FPS Camera Movement (WASD)
                float speed = 2.5f; // Units per second
                simd_float3 pos = self.renderer.cameraPosition;
                float yaw = self.renderer.cameraYaw;
                float pitch = self.renderer.cameraPitch;
                
                // Compute movement vectors in 3D space based on yaw and pitch
                simd_float3 forward;
                forward.x = sinf(yaw) * cosf(pitch);
                forward.y = sinf(pitch);
                forward.z = -cosf(yaw) * cosf(pitch);
                if (simd_length(forward) > 0.0f) {
                    forward = simd_normalize(forward);
                }
                
                simd_float3 right;
                right.x = cosf(yaw);
                right.y = 0.0f;
                right.z = sinf(yaw);
                if (simd_length(right) > 0.0f) {
                    right = simd_normalize(right);
                }
                
                simd_float3 moveDir = (simd_float3){0.0f, 0.0f, 0.0f};
                if (self.keyW) moveDir += forward;
                if (self.keyS) moveDir -= forward;
                if (self.keyD) moveDir += right;
                if (self.keyA) moveDir -= right;
                
                if (simd_length(moveDir) > 0.0f) {
                    moveDir = simd_normalize(moveDir);
                    pos += moveDir * speed * (float)deltaTime;
                    self.renderer.cameraPosition = pos;
                }
                
                [self.renderer draw];
            }
        }
    }
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
