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
    CDVPluginResult* pluginResult = nil;

    /**
     오디오 세션 설정은 AVPlayer 객체를 생성하고 사용하기 전에 별도로 이루어집니다.
     AVAudioSession 설정은 앱의 오디오 동작을 정의하는 것으로, 실제 플레이어 객체와 직접 연결되지 않아도 동작합니다.

     AVAudioSession은 애플리케이션 전체에서 오디오 동작을 관리하는 싱글톤 객체입니다.
     이 설정은 앱이 오디오를 재생하거나 녹음하는 방식에 대한 전반적인 맥락을 제공하며, 오디오 하드웨어의 사용법을 결정합니다.
     따라서 오디오 세션을 설정하는 것은 AVPlayer가 오디오를 재생할 때 올바른 오디오 컨텍스트가 설정되었는지를 보장하는 일반적인 단계입니다.
     */
    NSError *sessionError = nil;
    BOOL success = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
    if (!success) {
        NSString *errorMessage = [NSString stringWithFormat:@"AVAudioSession setCategory error: %@", sessionError.localizedDescription];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    success = [[AVAudioSession sharedInstance] setActive:YES error:&sessionError];
    if (!success) {
        NSString *errorMessage = [NSString stringWithFormat:@"AVAudioSession setActive error: %@", sessionError.localizedDescription];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSString *mediaUrl = [command.arguments objectAtIndex:0];
    if (mediaUrl == nil || [mediaUrl length] == 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Media URL was not provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSURL *url = [NSURL URLWithString:mediaUrl];
    if (url == nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid media URL"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

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

    // 탭 제스처 인식기를 playerViewController의 뷰에 추가
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleVideoTap:)];
    [playerViewController.view addGestureRecognizer:tapGestureRecognizer];

    [self.viewController presentViewController:playerViewController animated:NO completion:^(void){
        [player play];
    }];

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)close:(CDVInvokedUrlCommand*)command;
{
    if (player) {
        [player pause];
        player = nil;
    }

    if (playerViewController.presentingViewController) {
        [playerViewController dismissViewControllerAnimated:YES completion:^{
            playerViewController = nil;

            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    } else {
        CDVPluginResult* pluginResult = nil;

        if (playerViewController == nil) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Video player was not initialized"];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Video player is not currently presented"];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

// 영상 재생이 끝난 후에 호출될 메서드
- (void)playerDidFinishPlaying:(NSNotification *)notification
{
    // 옵저버 제거
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];

    // 영상 재생이 완료되면 playerViewController를 닫음
    [playerViewController dismissViewControllerAnimated:NO completion:^{
        playerViewController = nil;
        player = nil;
    }];
}

// 영상 탭 시 호출될 메서드
- (void)handleVideoTap:(UITapGestureRecognizer *)recognizer {
    // 재생을 멈추고
    [player pause];

    // 옵저버를 제거
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem];

    // 화면을 닫고
    if (playerViewController.presentingViewController) {
        [playerViewController dismissViewControllerAnimated:NO completion:^{
            playerViewController = nil;
            player = nil;
        }];
    }
}

@end
