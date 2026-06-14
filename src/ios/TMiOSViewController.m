#import "TMiOSViewController.h"

#import "TMiOSMetalView.h"

@implementation TMiOSViewController

- (void)loadView
{
    self.view = [[TMiOSMetalView alloc] initWithFrame:CGRectZero];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

@end
