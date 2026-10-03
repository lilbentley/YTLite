#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

// Included by YouPiP's Tweak.x and the macOS regression tests. Every call to a
// private method is checked against the inspected native ABI before dispatch.
static BOOL YPCClassSignature(Class cls, NSString *name, const char *result, unsigned args) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method || method_getNumberOfArguments(method) != args) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strcmp(type, result) == 0;
    free(type);
    return valid;
}
static BOOL YPCSignature(id object, NSString *name, const char *result, unsigned args) {
    return YPCClassSignature(object_getClass(object), name, result, args);
}

static id YPCRead(id object, NSString *key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; }
    @catch (NSException *exception) { return nil; }
}

static BOOL YPCBool(id object, NSString *selector) {
    if (!YPCSignature(object, selector, "B", 2)) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selector));
}

static void YPCVoid(id object, NSString *selector) {
    if (YPCSignature(object, selector, "v", 2))
        ((void (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selector));
}

typedef void (^YPCFailure)(NSString *reason);
static char YPCPendingKey;

@interface YPCAttempt : NSObject
@property(nonatomic, strong) id controller;
@property(nonatomic, strong) id video;
@property(nonatomic, copy) YPCFailure failure;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic) BOOL finished;
- (void)step;
@end

@implementation YPCAttempt
- (void)finish {
    self.finished = YES;
    self.failure = nil;
    if (objc_getAssociatedObject(self.controller, &YPCPendingKey) == self)
        objc_setAssociatedObject(self.controller, &YPCPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)fail:(NSString *)reason {
    if (self.finished) return;
    YPCFailure failure = self.failure;
    [self finish];
    if (failure) failure(reason);
}
- (void)step {
    if (self.finished) return;
    if (NSProcessInfo.processInfo.systemUptime >= self.deadline) {
        [self fail:@"iOS did not make the video renderer ready for PiP within two seconds."];
        return;
    }
    if (YPCRead(self.controller, @"_singleVideo") != self.video) {
        [self fail:@"The playing video changed before PiP was ready."];
        return;
    }
    id policy = YPCRead(self.controller, @"_backgroundabilityPolicy");
    if (!YPCBool(policy, @"isPlayableInPictureInPictureByUserSettings")) {
        [self fail:@"YouTube's background playback setting is blocking PiP."];
        return;
    }
    // Preserve the complete native gate: external playback, embargo, disabled
    // player traits, renderer compatibility and media playability all remain.
    if (!YPCBool(self.controller, @"canEnablePictureInPicture")) {
        NSString *reason = @"YouTube's native player rejected PiP for this video.";
        id nativePiP = YPCRead(self.controller, @"_pipController");
        if (YPCBool(self.video, @"isExternalPlaybackActive"))
            reason = @"YouTube still reports TV or AirPlay playback as active.";
        else if (YPCBool(self.controller, @"isPictureInPictureForceDisabled"))
            reason = @"YouTube disabled PiP support for the current player.";
        else if ([YPCRead(self.controller, @"_embargoActive") boolValue])
            reason = @"YouTube is blocking PiP during an ad or playback restriction.";
        else if (YPCBool(YPCRead(self.video, @"videoData"), @"needsGLRendering"))
            reason = @"This video uses a renderer that YouTube cannot put in PiP.";
        else if (YPCSignature(nativePiP, @"pictureInPictureSupported", "B", 2) &&
                 !YPCBool(nativePiP, @"pictureInPictureSupported"))
            reason = @"iOS reports that PiP is unsupported on this device.";
        [self fail:reason];
        return;
    }
    id pip = YPCRead(self.controller, @"_pipController");
    if (!pip || !YPCSignature(pip, @"activatePiPController", "v", 2)) {
        [self fail:@"The native PiP controller is unavailable."];
        return;
    }
    YPCVoid(pip, @"activatePiPController");
    id avpip = YPCRead(pip, @"_pictureInPictureController");
    if (YPCBool(avpip, @"isPictureInPictureActive")) {
        [self finish];
        return;
    }
    if (YPCBool(avpip, @"isPictureInPicturePossible") &&
        YPCSignature(avpip, @"startPictureInPicture", "v", 2)) {
        // Mark finished before starting: AVKit can synchronously call delegates.
        [self finish];
        YPCVoid(avpip, @"startPictureInPicture");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ [self step]; });
}
@end

static void YPCRequest(id controller, YPCFailure failure) {
    if (!controller) {
        if (failure) failure(@"The current player has no PiP controller.");
        return;
    }
    if (objc_getAssociatedObject(controller, &YPCPendingKey)) return;
    YPCAttempt *attempt = [YPCAttempt new];
    attempt.controller = controller;
    attempt.video = YPCRead(controller, @"_singleVideo");
    attempt.failure = failure;
    attempt.deadline = NSProcessInfo.processInfo.systemUptime + 2.0;
    objc_setAssociatedObject(controller, &YPCPendingKey, attempt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [attempt step];
}

static BOOL (*YPCOriginalDefaultOff)(id, SEL);
static BOOL (*YPCEnabled)(void);
static BOOL YPCDefaultOff(id self, SEL cmd) {
    // Select the original method's user-settings branch, not an unconditional
    // canEnable=YES. Disabling YouPiP restores the original experiment value.
    return YPCEnabled && YPCEnabled() ? NO : YPCOriginalDefaultOff(self, cmd);
}

static BOOL YPCInstallDefaultOff(Class hotConfig, BOOL (*enabled)(void)) {
    if (!hotConfig || YPCOriginalDefaultOff) return NO;
    Method method = class_getInstanceMethod(hotConfig,
        NSSelectorFromString(@"iosPlayerClientSharedConfigDefaultOffPremiumPip"));
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strcmp(type, "B") == 0;
    free(type);
    if (!valid) return NO;
    YPCEnabled = enabled;
    YPCOriginalDefaultOff = (BOOL (*)(id, SEL))method_setImplementation(method, (IMP)YPCDefaultOff);
    return YES;
}
