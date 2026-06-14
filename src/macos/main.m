#import <AppKit/AppKit.h>

#import "TMMacAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        TMMacAppDelegate *delegate = [[TMMacAppDelegate alloc] init];
        application.delegate = delegate;
        return NSApplicationMain(argc, argv);
    }
}
