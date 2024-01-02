/********* VideoPlayer.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface VideoPlayer : CDVPlugin {
    AVPlayerViewController *playerViewController;
    AVPlayer *player;
}


- (void)play:(CDVInvokedUrlCommand*)command;
- (void)close:(CDVInvokedUrlCommand*)command;
@end

@implementation VideoPlayer

- (void)play:(CDVInvokedUrlCommand*)command
{
    NSError* error = nil;
    CDVPluginResult* pluginResult = nil;

    NSString *mediaUrl = [command.arguments objectAtIndex:0];
    NSURL *url = [NSURL URLWithString:mediaUrl];
    player = [AVPlayer playerWithURL:url];

    playerViewController = [[AVPlayerViewController alloc] init];
    playerViewController.player = player;
    playerViewController.showsPlaybackControls = NO;
    playerViewController.videoGravity = AVLayerVideoGravityResizeAspectFill;

    if(@available(iOS 11.0, *)) {
        [playerViewController setEntersFullScreenWhenPlaybackBegins:YES];
    }

    [self.viewController presentViewController:playerViewController animated:YES completion:^(void){
        [player play];
    }];

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)close:(CDVInvokedUrlCommand*)command;
{
    NSError* error = nil;
    CDVPluginResult* pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end
