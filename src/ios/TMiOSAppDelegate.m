#import "TMiOSAppDelegate.h"

@implementation TMiOSAppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                               options:(UISceneConnectionOptions *)options
{
    (void)application;
    (void)connectingSceneSession;
    (void)options;

    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                                          sessionRole:UIWindowSceneSessionRoleApplication];
    configuration.delegateClass = NSClassFromString(@"TMiOSSceneDelegate");
    return configuration;
}

@end
