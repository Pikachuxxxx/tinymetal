#import "TMMacAppDelegate.h"

#import "TMMacMetalView.h"

@interface TMMacAppDelegate ()

@property (nonatomic, strong) NSWindow *window;

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
    self.window.contentView = [[TMMacMetalView alloc] initWithFrame:frame];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

@end
