#import "LandscapeAVPlayerViewController.h"

@implementation LandscapeAVPlayerViewController

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight; // or LandscapeLeft
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}
@end
