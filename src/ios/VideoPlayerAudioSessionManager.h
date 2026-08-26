#import <Foundation/Foundation.h>

@protocol VideoPlayerAudioSessionState <NSObject>
@property(nonatomic, readonly) NSString *videoPlayerCategory;
@property(nonatomic, readonly) NSString *videoPlayerMode;
@property(nonatomic, readonly) NSUInteger videoPlayerCategoryOptions;
@property(nonatomic, readonly) NSUInteger videoPlayerRouteSharingPolicy;

- (BOOL)videoPlayerRestoreCategory:(NSString *)category
                              mode:(NSString *)mode
                           options:(NSUInteger)options
                routeSharingPolicy:(NSUInteger)routeSharingPolicy
       capturesRouteSharingPolicy:(BOOL)capturesRouteSharingPolicy
                             error:(NSError **)error;
@end

@interface VideoPlayerAudioSessionManager : NSObject
@property(nonatomic, readonly) BOOL hasSnapshot;

- (instancetype)initWithCapturesRouteSharingPolicy:(BOOL)capturesRouteSharingPolicy;
- (void)captureBeforePlayback:(id<VideoPlayerAudioSessionState>)audioSession;
- (void)capturePlaybackConfiguration:(id<VideoPlayerAudioSessionState>)audioSession;
- (BOOL)restoreSessionIfNeeded:(id<VideoPlayerAudioSessionState>)audioSession
                         error:(NSError **)error;
- (void)discardSnapshot;
@end
