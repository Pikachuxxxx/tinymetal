#import <AppKit/AppKit.h>

#import "TMMacAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printf("================================================================================\n");
                printf("  TinyMetal Renderer Options\n");
                printf("================================================================================\n");
                printf("Usage: TinyMetal [options]\n\n");
                printf("Available Options:\n");
                printf("  -m, --model, -i, --input <path>   Path to the input optimized binary mesh file (.bin).\n");
                printf("  -h, --help                        Show this help menu.\n");
                printf("================================================================================\n");
                return 0;
            }
        }
        NSApplication *application = [NSApplication sharedApplication];
        TMMacAppDelegate *delegate = [[TMMacAppDelegate alloc] init];
        application.delegate = delegate;
        return NSApplicationMain(argc, argv);
    }
}
