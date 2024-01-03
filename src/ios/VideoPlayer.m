/********* VideoPlayer.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import "PortraitAVPlayerViewController.h"

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

    playerViewController = [[PortraitAVPlayerViewController alloc] init];
    playerViewController.player = player;
    playerViewController.showsPlaybackControls = NO;
    playerViewController.videoGravity = AVLayerVideoGravityResizeAspectFill;

    if(@available(iOS 11.0, *)) {
        [playerViewController setEntersFullScreenWhenPlaybackBegins:YES];
    }
    // 영상 재생이 끝났을 때 알림을 받을 수 있도록 옵저버 추가
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerDidFinishPlaying:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:player.currentItem];

    [self.viewController presentViewController:playerViewController animated:NO completion:^(void){
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

// 영상 재생이 끝난 후에 호출될 메서드
- (void)playerDidFinishPlaying:(NSNotification *)notification
{
    // 옵저버 제거
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];

    // 영상 재생이 완료되면 playerViewController를 닫음
    [playerViewController dismissViewControllerAnimated:NO completion:nil];
}

@end
