/********* VideoPlayer.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface VideoPlayer : CDVPlugin {
    AVPlayerViewController *moviePlayer;
    AVPlayer *movie;
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
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];

    movie = [AVPlayer playerWithPlayerItem:item];
    moviePlayer = [[AVPlayerViewController alloc] init];
    moviePlayer.player = movie;
    moviePlayer.showsPlaybackControls = NO;
    moviePlayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    if(@available(iOS 11.0, *)) {
        [moviePlayer setEntersFullScreenWhenPlaybackBegins:YES];
    }

    [self.viewController presentViewController:moviePlayer animated:YES completion:^(void){
        [movie play];
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
