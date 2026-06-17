#import "TMMacAppDelegate.h"
#import "TMMacMetalView.h"
#import "TMRenderer.h"

@interface TMMacAppDelegate ()

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) TMMacMetalView *metalView;

@end

@implementation TMMacAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;

    NSRect frame = NSMakeRect(0.0, 0.0, 960.0, 640.0);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"TinyMetal";
    
    // Create base container view
    NSView *container = [[NSView alloc] initWithFrame:frame];
    self.window.contentView = container;
    
    // Add Metal View
    self.metalView = [[TMMacMetalView alloc] initWithFrame:frame];
    self.metalView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.metalView];
    
    // Create Glassmorphic HUD overlay view
    NSVisualEffectView *overlay = [[NSVisualEffectView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.wantsLayer = YES;
    overlay.layer.cornerRadius = 12.0f;
    overlay.layer.borderColor = [NSColor colorWithWhite:1.0f alpha:0.15f].CGColor;
    overlay.layer.borderWidth = 1.0f;
    
    // Translucency configuration
    overlay.material = NSVisualEffectMaterialHUDWindow;
    overlay.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    overlay.state = NSVisualEffectStateActive;
    [container addSubview:overlay];
    
    // Setup Controls inside Overlay
    NSTextField *modeLabel = [NSTextField labelWithString:@"Render Mode:"];
    modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    modeLabel.textColor = [NSColor whiteColor];
    modeLabel.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
    [overlay addSubview:modeLabel];
    
    NSPopUpButton *modePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [modePopUp addItemsWithTitles:@[@"Default Shaded", @"Meshlet IDs", @"UV Coordinates", @"Normals", @"Local Positions"]];
    modePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    [modePopUp setTarget:self];
    [modePopUp setAction:@selector(renderModeChanged:)];
    [overlay addSubview:modePopUp];
    
    NSTextField *colorLabel = [NSTextField labelWithString:@"Diffuse Color:"];
    colorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    colorLabel.textColor = [NSColor whiteColor];
    colorLabel.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
    [overlay addSubview:colorLabel];
    
    NSColorWell *colorWell = [[NSColorWell alloc] init];
    colorWell.translatesAutoresizingMaskIntoConstraints = NO;
    colorWell.color = [NSColor whiteColor];
    [colorWell setTarget:self];
    [colorWell setAction:@selector(colorChanged:)];
    [overlay addSubview:colorWell];
    
    // Auto-layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Metal view takes full window space
        [self.metalView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.metalView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.metalView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.metalView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        
        // Floating HUD Overlay panel (top-right overlay)
        [overlay.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20.0f],
        [overlay.topAnchor constraintEqualToAnchor:container.topAnchor constant:20.0f],
        [overlay.widthAnchor constraintEqualToConstant:220.0f],
        [overlay.heightAnchor constraintEqualToConstant:120.0f],
        
        // Controls inside overlay
        [modeLabel.topAnchor constraintEqualToAnchor:overlay.topAnchor constant:16.0f],
        [modeLabel.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:16.0f],
        
        [modePopUp.topAnchor constraintEqualToAnchor:modeLabel.bottomAnchor constant:6.0f],
        [modePopUp.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:16.0f],
        [modePopUp.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-16.0f],
        
        [colorLabel.topAnchor constraintEqualToAnchor:modePopUp.bottomAnchor constant:14.0f],
        [colorLabel.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:16.0f],
        
        [colorWell.centerYAnchor constraintEqualToAnchor:colorLabel.centerYAnchor],
        [colorWell.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-16.0f],
        [colorWell.widthAnchor constraintEqualToConstant:48.0f],
        [colorWell.heightAnchor constraintEqualToConstant:24.0f]
    ]];
    
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)renderModeChanged:(NSPopUpButton *)sender
{
    self.metalView.renderer.renderMode = (uint32_t)sender.indexOfSelectedItem;
}

- (void)colorChanged:(NSColorWell *)sender
{
    NSColor *color = [sender.color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    self.metalView.renderer.diffuseColor = (simd_float4){
        (float)color.redComponent,
        (float)color.greenComponent,
        (float)color.blueComponent,
        (float)color.alphaComponent
    };
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

@end
