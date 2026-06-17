#import "TMiOSViewController.h"
#import "TMiOSMetalView.h"
#import "TMRenderer.h"

@interface TMiOSViewController ()

@property (nonatomic, strong) TMiOSMetalView *metalView;
@property (nonatomic, strong) UIVisualEffectView *controlPanel;

@end

@implementation TMiOSViewController

- (void)loadView
{
    self.metalView = [[TMiOSMetalView alloc] initWithFrame:(CGRect){0}];
    self.view = self.metalView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Create Glassmorphic Blur panel
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    self.controlPanel = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlPanel.clipsToBounds = YES;
    self.controlPanel.layer.cornerRadius = 14.0f;
    self.controlPanel.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.15f].CGColor;
    self.controlPanel.layer.borderWidth = 1.0f;
    
    [self.view addSubview:self.controlPanel];
    
    // UI elements inside the panel's contentView
    UIView *contentView = self.controlPanel.contentView;
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"RENDER SETTINGS";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:11.0f];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:titleLabel];
    
    // Segmented control for rendering modes
    UISegmentedControl *modeSegments = [[UISegmentedControl alloc] initWithItems:@[@"Shade", @"Mesh", @"UV", @"Norm", @"Pos"]];
    modeSegments.selectedSegmentIndex = 0;
    modeSegments.translatesAutoresizingMaskIntoConstraints = NO;
    modeSegments.backgroundColor = [UIColor colorWithWhite:0.1f alpha:0.4f];
    modeSegments.selectedSegmentTintColor = [UIColor colorWithRed:0.2f green:0.4f blue:0.8f alpha:0.9f];
    
    NSDictionary *textAttrs = @{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:10.0f weight:UIFontWeightMedium]};
    [modeSegments setTitleTextAttributes:textAttrs forState:UIControlStateNormal];
    [modeSegments setTitleTextAttributes:textAttrs forState:UIControlStateSelected];
    
    [modeSegments addTarget:self action:@selector(renderModeChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:modeSegments];
    
    UILabel *colorLabel = [[UILabel alloc] init];
    colorLabel.text = @"Diffuse Color";
    colorLabel.textColor = [UIColor whiteColor];
    colorLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightMedium];
    colorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:colorLabel];
    
    // UIKit native Color Well (iOS 14+)
    UIColorWell *colorWell = [[UIColorWell alloc] init];
    colorWell.selectedColor = [UIColor whiteColor];
    colorWell.translatesAutoresizingMaskIntoConstraints = NO;
    [colorWell addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:colorWell];
    
    // Keep old FPS Travel button, but place it inside the floating card to keep UI clean and compact
    UIButton *travelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [travelButton setTitle:@"FPS TRAVEL" forState:UIControlStateNormal];
    travelButton.backgroundColor = [UIColor colorWithRed:0.2f green:0.4f blue:0.8f alpha:0.9f];
    [travelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    travelButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0f];
    travelButton.layer.cornerRadius = 8.0f;
    travelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [travelButton addTarget:self action:@selector(fpsTravelPressed:) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:travelButton];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Float panel in top-right of Safe Area
        [self.controlPanel.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16.0f],
        [self.controlPanel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16.0f],
        [self.controlPanel.widthAnchor constraintEqualToConstant:220.0f],
        [self.controlPanel.heightAnchor constraintEqualToConstant:210.0f],
        
        // Title Label
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:14.0f],
        [titleLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        
        // Mode segments
        [modeSegments.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0f],
        [modeSegments.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12.0f],
        [modeSegments.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12.0f],
        [modeSegments.heightAnchor constraintEqualToConstant:32.0f],
        
        // Color label
        [colorLabel.topAnchor constraintEqualToAnchor:modeSegments.bottomAnchor constant:16.0f],
        [colorLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16.0f],
        
        // Color well
        [colorWell.centerYAnchor constraintEqualToAnchor:colorLabel.centerYAnchor],
        [colorWell.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-16.0f],
        
        // Travel button
        [travelButton.topAnchor constraintEqualToAnchor:colorWell.bottomAnchor constant:16.0f],
        [travelButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12.0f],
        [travelButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12.0f],
        [travelButton.heightAnchor constraintEqualToConstant:36.0f]
    ]];
}

- (void)renderModeChanged:(UISegmentedControl *)sender
{
    self.metalView.renderer.renderMode = (uint32_t)sender.selectedSegmentIndex;
}

- (void)colorChanged:(UIColorWell *)sender
{
    UIColor *uiColor = sender.selectedColor;
    CGFloat r, g, b, a;
    [uiColor getRed:&r green:&g blue:&b alpha:&a];
    self.metalView.renderer.diffuseColor = (simd_float4){(float)r, (float)g, (float)b, (float)a};
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
