#import "Compatibility.h"
#include <assert.h>

@interface WrongHotConfig : NSObject
- (int)iosPlayerClientSharedConfigDefaultOffPremiumPip;
@end
@implementation WrongHotConfig
- (int)iosPlayerClientSharedConfigDefaultOffPremiumPip { return 1; }
@end

@interface TestHotConfig : NSObject
- (bool)iosPlayerClientSharedConfigDefaultOffPremiumPip;
@end
@implementation TestHotConfig
- (bool)iosPlayerClientSharedConfigDefaultOffPremiumPip { return true; }
@end

@interface TestPolicy : NSObject
@property bool allowed;
- (bool)isPlayableInPictureInPictureByUserSettings;
@end
@implementation TestPolicy
- (bool)isPlayableInPictureInPictureByUserSettings { return self.allowed; }
@end

@interface TestVideo : NSObject
@property bool external;
- (bool)isExternalPlaybackActive;
@end
@implementation TestVideo
- (bool)isExternalPlaybackActive { return self.external; }
@end

@interface TestAVPiP : NSObject
@property bool possible;
@property bool active;
@property NSUInteger starts;
- (bool)isPictureInPictureActive;
- (bool)isPictureInPicturePossible;
- (void)startPictureInPicture;
@end
@implementation TestAVPiP
- (bool)isPictureInPictureActive { return self.active; }
- (bool)isPictureInPicturePossible { return self.possible; }
- (void)startPictureInPicture { self.starts++; self.active = true; }
@end

@interface TestPiP : NSObject
@property(nonatomic, strong) TestAVPiP *pictureInPictureController;
@property NSUInteger prepares;
@property NSUInteger readyAfter;
- (void)activatePiPController;
@end
@implementation TestPiP
- (void)activatePiPController {
    self.prepares++;
    if (self.readyAfter && self.prepares >= self.readyAfter)
        self.pictureInPictureController.possible = true;
}
@end

@interface TestController : NSObject
@property(nonatomic, strong) TestPolicy *backgroundabilityPolicy;
@property(nonatomic, strong) TestPiP *pipController;
@property(nonatomic, strong) TestVideo *singleVideo;
@property(nonatomic, strong) TestHotConfig *hotConfig;
@property bool supported;
@property bool forceDisabled;
@property bool embargo;
@property bool glRenderer;
@property bool playable;
- (bool)canEnablePictureInPicture;
@end
@implementation TestController
- (bool)canEnablePictureInPicture {
    // Model the branches recovered from 21.12.4, including the existing gates.
    if (!self.supported || self.forceDisabled || self.embargo ||
        self.singleVideo.external || self.glRenderer || !self.playable) return false;
    if ([self.hotConfig iosPlayerClientSharedConfigDefaultOffPremiumPip]) return false;
    return self.backgroundabilityPolicy.allowed;
}
@end

static BOOL Enabled = YES;
static BOOL IsEnabled(void) { return Enabled; }
static TestController *Controller(void) {
    TestController *c = [TestController new];
    c.hotConfig = [TestHotConfig new];
    c.backgroundabilityPolicy = [TestPolicy new];
    c.backgroundabilityPolicy.allowed = true;
    c.pipController = [TestPiP new];
    c.pipController.pictureInPictureController = [TestAVPiP new];
    c.pipController.readyAfter = 1;
    c.singleVideo = [TestVideo new];
    c.supported = true;
    c.playable = true;
    return c;
}
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
int main(void) {
    @autoreleasepool {
        assert(!YPCInstallDefaultOff(WrongHotConfig.class, IsEnabled));
        TestController *baseline = Controller();
        assert(![baseline canEnablePictureInPicture]);
        assert(YPCInstallDefaultOff(TestHotConfig.class, IsEnabled));
        assert([baseline canEnablePictureInPicture]);
        Enabled = NO;
        assert([baseline.hotConfig iosPlayerClientSharedConfigDefaultOffPremiumPip]);
        Enabled = YES;

        YPCRequest(baseline, ^(NSString *reason) { assert(!reason); });
        assert(baseline.pipController.pictureInPictureController.starts == 1);
        assert(!objc_getAssociatedObject(baseline, &YPCPendingKey));
        // An already active controller does not start again.
        YPCRequest(baseline, ^(NSString *reason) { assert(!reason); });
        assert(baseline.pipController.pictureInPictureController.starts == 1);

        for (NSString *key in @[@"forceDisabled", @"embargo", @"glRenderer"] ) {
            TestController *c = Controller();
            [c setValue:@YES forKey:key];
            __block NSUInteger failures = 0;
            YPCRequest(c, ^(NSString *reason) { assert(reason.length); failures++; });
            assert(failures == 1 && c.pipController.pictureInPictureController.starts == 0);
        }
        for (NSString *key in @[@"supported", @"playable"] ) {
            TestController *c = Controller();
            [c setValue:@NO forKey:key];
            __block NSUInteger failures = 0;
            YPCRequest(c, ^(NSString *reason) { assert(reason.length); failures++; });
            assert(failures == 1 && c.pipController.pictureInPictureController.starts == 0);
        }
        TestController *denied = Controller();
        denied.backgroundabilityPolicy.allowed = false;
        __block NSString *failure = nil;
        YPCRequest(denied, ^(NSString *reason) { failure = reason; });
        assert([failure containsString:@"background"] && denied.pipController.prepares == 0);

        // Readiness may be asynchronous. Repeated button presses share one attempt.
        TestController *delayed = Controller();
        delayed.pipController.readyAfter = 3;
        YPCRequest(delayed, ^(NSString *reason) { assert(!reason); });
        YPCRequest(delayed, ^(NSString *reason) { assert(!reason); });
        Pump(0.35);
        assert(delayed.pipController.pictureInPictureController.starts == 1);

        // Casting becoming active while waiting cancels without forcing PiP.
        TestController *casting = Controller();
        casting.pipController.readyAfter = 3;
        failure = nil;
        YPCRequest(casting, ^(NSString *reason) { failure = reason; });
        casting.singleVideo.external = true;
        Pump(0.15);
        assert([failure containsString:@"TV or AirPlay"]);
        assert(casting.pipController.pictureInPictureController.starts == 0);

        // Don't launch the old video's PiP after navigating to another video.
        TestController *changed = Controller();
        changed.pipController.readyAfter = 3;
        failure = nil;
        YPCRequest(changed, ^(NSString *reason) { failure = reason; });
        changed.singleVideo = [TestVideo new];
        Pump(0.15);
        assert([failure containsString:@"changed"]);
        assert(changed.pipController.pictureInPictureController.starts == 0);

        TestController *timeout = Controller();
        timeout.pipController.readyAfter = 0;
        __block NSUInteger failures = 0;
        YPCRequest(timeout, ^(NSString *reason) { assert([reason containsString:@"two seconds"]); failures++; });
        Pump(2.3);
        assert(failures == 1 && !objc_getAssociatedObject(timeout, &YPCPendingKey));
        timeout.pipController = nil;
        failure = nil;
        YPCRequest(timeout, ^(NSString *reason) { failure = reason; });
        assert([failure containsString:@"unavailable"]);
        NSLog(@"PiP compatibility regression tests passed");
    }
    return 0;
}
