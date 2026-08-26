#import "VideoPlayerAudioSessionManager.h"

@interface VideoPlayerAudioSessionManager () {
    NSString *categoryBeforePlayback;
    NSString *modeBeforePlayback;
    NSUInteger optionsBeforePlayback;
    NSUInteger routeSharingPolicyBeforePlayback;
    NSString *categoryForPlayback;
    NSString *modeForPlayback;
    NSUInteger optionsForPlayback;
    NSUInteger routeSharingPolicyForPlayback;
    BOOL capturesRouteSharingPolicy;
}
@end

@implementation VideoPlayerAudioSessionManager

- (instancetype)initWithCapturesRouteSharingPolicy:(BOOL)shouldCaptureRouteSharingPolicy
{
    self = [super init];
    if (self) {
        capturesRouteSharingPolicy = shouldCaptureRouteSharingPolicy;
    }
    return self;
}

- (BOOL)hasSnapshot
{
    return categoryBeforePlayback != nil;
}

- (void)captureBeforePlayback:(id<VideoPlayerAudioSessionState>)audioSession
{
    if (self.hasSnapshot) {
        if ([self audioSessionMatchesPlaybackConfiguration:audioSession]) {
            return;
        }
        [self discardSnapshot];
    }

    categoryBeforePlayback = audioSession.videoPlayerCategory;
    modeBeforePlayback = audioSession.videoPlayerMode;
    optionsBeforePlayback = audioSession.videoPlayerCategoryOptions;
    if (capturesRouteSharingPolicy) {
        routeSharingPolicyBeforePlayback = audioSession.videoPlayerRouteSharingPolicy;
    }
}

- (void)capturePlaybackConfiguration:(id<VideoPlayerAudioSessionState>)audioSession
{
    categoryForPlayback = audioSession.videoPlayerCategory;
    modeForPlayback = audioSession.videoPlayerMode;
    optionsForPlayback = audioSession.videoPlayerCategoryOptions;
    if (capturesRouteSharingPolicy) {
        routeSharingPolicyForPlayback = audioSession.videoPlayerRouteSharingPolicy;
    }
}

- (BOOL)restoreSessionIfNeeded:(id<VideoPlayerAudioSessionState>)audioSession
                         error:(NSError **)error
{
    if (!self.hasSnapshot) {
        return YES;
    }

    if (![self audioSessionMatchesPlaybackConfiguration:audioSession]) {
        [self discardSnapshot];
        return YES;
    }

    BOOL success = [audioSession videoPlayerRestoreCategory:categoryBeforePlayback
                                                       mode:modeBeforePlayback
                                                    options:optionsBeforePlayback
                                         routeSharingPolicy:routeSharingPolicyBeforePlayback
                                capturesRouteSharingPolicy:capturesRouteSharingPolicy
                                                      error:error];
    [self discardSnapshot];
    return success;
}

- (void)discardSnapshot
{
    categoryBeforePlayback = nil;
    modeBeforePlayback = nil;
    optionsBeforePlayback = 0;
    routeSharingPolicyBeforePlayback = 0;
    categoryForPlayback = nil;
    modeForPlayback = nil;
    optionsForPlayback = 0;
    routeSharingPolicyForPlayback = 0;
}

- (BOOL)audioSessionMatchesPlaybackConfiguration:(id<VideoPlayerAudioSessionState>)audioSession
{
    if (![audioSession.videoPlayerCategory isEqualToString:categoryForPlayback]
        || ![audioSession.videoPlayerMode isEqualToString:modeForPlayback]
        || audioSession.videoPlayerCategoryOptions != optionsForPlayback) {
        return NO;
    }

    return !capturesRouteSharingPolicy
        || audioSession.videoPlayerRouteSharingPolicy == routeSharingPolicyForPlayback;
}

@end
