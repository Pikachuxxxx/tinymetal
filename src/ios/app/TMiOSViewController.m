#import "TMiOSViewController.h"

#import "TMiOSMetalView.h"

@implementation TMiOSViewController

- (void)loadView
{
    self.view = [[TMiOSMetalView alloc] initWithFrame:(CGRect){0}];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"FPS TRAVEL" forState:UIControlStateNormal];
    
    // Premium styling
    button.backgroundColor = [UIColor colorWithRed:0.2f green:0.4f blue:0.8f alpha:0.9f];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16.0f];
    button.layer.cornerRadius = 8.0f;
    
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:button];
    
    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [button.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-40.0f],
        [button.widthAnchor constraintEqualToConstant:160.0f],
        [button.heightAnchor constraintEqualToConstant:50.0f]
    ]];
    
    [button addTarget:self action:@selector(fpsTravelPressed:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)fpsTravelPressed:(UIButton *)sender
{
    NSLog(@"[UIKit] FPS TRAVEL button pressed!");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"FPS Travel"
                                                                   message:@"Initiating travel sequence..."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

@end
