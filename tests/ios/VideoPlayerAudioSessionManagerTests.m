#import <Foundation/Foundation.h>
#import "VideoPlayerAudioSessionManager.h"

@interface FakeAudioSession : NSObject <VideoPlayerAudioSessionState>
@property(nonatomic, copy) NSString *category;
@property(nonatomic, copy) NSString *mode;
@property(nonatomic) NSUInteger options;
@property(nonatomic) NSUInteger policy;
@property(nonatomic) BOOL restoreSucceeds;
@property(nonatomic) NSUInteger restoreCalls;
@end

@implementation FakeAudioSession

- (NSString *)videoPlayerCategory { return self.category; }
- (NSString *)videoPlayerMode { return self.mode; }
- (NSUInteger)videoPlayerCategoryOptions { return self.options; }
- (NSUInteger)videoPlayerRouteSharingPolicy { return self.policy; }

- (BOOL)videoPlayerRestoreCategory:(NSString *)category
                              mode:(NSString *)mode
                           options:(NSUInteger)options
                routeSharingPolicy:(NSUInteger)routeSharingPolicy
       capturesRouteSharingPolicy:(BOOL)capturesRouteSharingPolicy
                             error:(NSError **)error
{
    self.restoreCalls += 1;
    if (!self.restoreSucceeds) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"VideoPlayerAudioSessionTests"
                                         code:1
                                     userInfo:nil];
        }
        return NO;
    }

    self.category = category;
    self.mode = mode;
    self.options = options;
    if (capturesRouteSharingPolicy) {
        self.policy = routeSharingPolicy;
    }
    return YES;
}

@end

static FakeAudioSession *Session(NSString *category, NSString *mode,
                                 NSUInteger options, NSUInteger policy)
{
    FakeAudioSession *session = [[FakeAudioSession alloc] init];
    session.category = category;
    session.mode = mode;
    session.options = options;
    session.policy = policy;
    session.restoreSucceeds = YES;
    return session;
}

static void TestRestoresEveryCapturedField(void)
{
    NSArray<NSString *> *categories = @[@"Playback", @"Ambient", @"PlayAndRecord"];
    for (NSUInteger index = 0; index < categories.count; index += 1) {
        FakeAudioSession *session = Session(categories[index], @"OriginalMode",
                                            3 + index, 7 + index);
        VideoPlayerAudioSessionManager *manager =
            [[VideoPlayerAudioSessionManager alloc] initWithCapturesRouteSharingPolicy:YES];
        [manager captureBeforePlayback:session];

        session.category = @"PluginPlayback";
        session.mode = @"PluginMode";
        session.options = 0;
        session.policy = 1;
        [manager capturePlaybackConfiguration:session];

        NSError *error = nil;
        NSCAssert([manager restoreSessionIfNeeded:session error:&error], @"restore failed");
        NSCAssert(error == nil, @"unexpected restore error");
        NSCAssert([session.category isEqualToString:categories[index]], @"category mismatch");
        NSCAssert([session.mode isEqualToString:@"OriginalMode"], @"mode mismatch");
        NSCAssert(session.options == 3 + index, @"options mismatch");
        NSCAssert(session.policy == 7 + index, @"policy mismatch");
        NSCAssert(session.restoreCalls == 1, @"restore call mismatch");
        NSCAssert(!manager.hasSnapshot, @"snapshot was not discarded");
    }
}

static void TestPreservesExternalChanges(void)
{
    FakeAudioSession *session = Session(@"Host", @"HostMode", 3, 4);
    VideoPlayerAudioSessionManager *manager =
        [[VideoPlayerAudioSessionManager alloc] initWithCapturesRouteSharingPolicy:YES];
    [manager captureBeforePlayback:session];
    session.category = @"Plugin";
    session.mode = @"PluginMode";
    session.options = 0;
    session.policy = 1;
    [manager capturePlaybackConfiguration:session];

    session.category = @"External";
    NSError *error = nil;
    NSCAssert([manager restoreSessionIfNeeded:session error:&error], @"skip failed");
    NSCAssert([session.category isEqualToString:@"External"], @"external change overwritten");
    NSCAssert(session.restoreCalls == 0, @"restore should have been skipped");
}

static void TestFailedRestoreIsReportedAndDiscarded(void)
{
    FakeAudioSession *session = Session(@"Host", @"HostMode", 3, 4);
    VideoPlayerAudioSessionManager *manager =
        [[VideoPlayerAudioSessionManager alloc] initWithCapturesRouteSharingPolicy:YES];
    [manager captureBeforePlayback:session];
    session.category = @"Plugin";
    [manager capturePlaybackConfiguration:session];
    session.restoreSucceeds = NO;

    NSError *error = nil;
    NSCAssert(![manager restoreSessionIfNeeded:session error:&error], @"failure was hidden");
    NSCAssert(error != nil, @"restore error missing");
    NSCAssert(!manager.hasSnapshot, @"deferred retry belongs to the on-hold follow-up");
}

static void TestRecapturesAfterExternalChangeBeforeNextPlayback(void)
{
    FakeAudioSession *session = Session(@"FirstHost", @"FirstMode", 1, 2);
    VideoPlayerAudioSessionManager *manager =
        [[VideoPlayerAudioSessionManager alloc] initWithCapturesRouteSharingPolicy:YES];
    [manager captureBeforePlayback:session];
    session.category = @"FirstPlugin";
    [manager capturePlaybackConfiguration:session];

    session.category = @"LatestHost";
    session.mode = @"LatestMode";
    session.options = 5;
    session.policy = 6;
    [manager captureBeforePlayback:session];
    session.category = @"SecondPlugin";
    [manager capturePlaybackConfiguration:session];

    NSError *error = nil;
    NSCAssert([manager restoreSessionIfNeeded:session error:&error], @"restore failed");
    NSCAssert([session.category isEqualToString:@"LatestHost"], @"latest category not restored");
    NSCAssert([session.mode isEqualToString:@"LatestMode"], @"latest mode not restored");
    NSCAssert(session.options == 5, @"latest options not restored");
    NSCAssert(session.policy == 6, @"latest policy not restored");
}

int main(void)
{
    @autoreleasepool {
        TestRestoresEveryCapturedField();
        TestPreservesExternalChanges();
        TestFailedRestoreIsReportedAndDiscarded();
        TestRecapturesAfterExternalChangeBeforeNextPlayback();
        NSLog(@"VideoPlayerAudioSessionManager tests passed");
    }
    return 0;
}
