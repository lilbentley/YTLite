#import <Foundation/Foundation.h>

@interface MDXLocalStorage : NSObject
@property(nonatomic) NSInteger localNetworkPermissionsStatus;
@end
@implementation MDXLocalStorage
@end

@interface MDXClientEnvironment : NSObject
@property(nonatomic, strong) MDXLocalStorage *localStorage;
+ (id)sharedInstance;
@end
@implementation MDXClientEnvironment
+ (id)sharedInstance {
    static MDXClientEnvironment *environment;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        environment = [MDXClientEnvironment new];
        environment.localStorage = [MDXLocalStorage new];
        environment.localStorage.localNetworkPermissionsStatus = 2;
    });
    return environment;
}
@end

@interface MDXLocalNetworkPermissions : NSObject
@property(nonatomic) NSUInteger originalChecks;
@property(nonatomic) NSUInteger notifications;
@property(nonatomic) NSInteger notifiedStatus;
- (void)verifyAccessWithCompletion:(void (^)(NSInteger))completion;
- (NSInteger)lastKnownPermissionsStatus;
- (void)notifyStatusChangeObservers:(NSInteger)status;
@end
@implementation MDXLocalNetworkPermissions
- (void)verifyAccessWithCompletion:(void (^)(NSInteger))completion {
    self.originalChecks++;
    if (completion) completion(2);
}
- (NSInteger)lastKnownPermissionsStatus {
    MDXClientEnvironment *environment = [MDXClientEnvironment sharedInstance];
    return environment.localStorage.localNetworkPermissionsStatus;
}
- (void)notifyStatusChangeObservers:(NSInteger)status {
    self.notifications++;
    self.notifiedStatus = status;
}
@end

static BOOL FactoryMulticast, FactoryUnicast;
static id FactoryReachability, FactoryResult;
static double FactoryRescan, FactoryTimeout;
@interface GCKCastDeviceMDNSScanner : NSObject
+ (id)createMDNSServiceBrowserWithCustomMulticastEnabled:(BOOL)multicast
                                    useUnicastQueries:(BOOL)unicast
                                  networkReachability:(id)reachability
                                       rescanInterval:(double)rescan
                                deviceTimeoutInterval:(double)timeout;
@end
@implementation GCKCastDeviceMDNSScanner
+ (id)createMDNSServiceBrowserWithCustomMulticastEnabled:(BOOL)multicast
                                    useUnicastQueries:(BOOL)unicast
                                  networkReachability:(id)reachability
                                       rescanInterval:(double)rescan
                                deviceTimeoutInterval:(double)timeout {
    FactoryMulticast = multicast;
    FactoryUnicast = unicast;
    FactoryReachability = reachability;
    FactoryRescan = rescan;
    FactoryTimeout = timeout;
    return FactoryResult;
}
@end

#define YTLOCALNETWORKFIX_TESTING 1
#import "YTLiteLocalNetworkFix.m"

static void Require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

static NSUInteger ProbeCalls;
static NSInteger FakeStatus;
static char MainQueueKey;
static void FakeProbe(void (^completion)(NSInteger)) {
    ProbeCalls++;
    completion(FakeStatus);
}

static void CheckUnknown(MDXLocalNetworkPermissions *permissions) {
    FakeStatus = YTLNFUnknown;
    [permissions verifyAccessWithCompletion:^(NSInteger result) {
        Require(result == YTLNFDenied, "unknown must preserve cached native result");
        Require(permissions.notifications == 2, "unknown must not emit a false permission change");
        Require(permissions.originalChecks == 0 && ProbeCalls == 3, "every call must use the new probe");
        Require(dispatch_get_specific(&MainQueueKey) == &MainQueueKey, "completion must run on the main queue");
        puts("PASS: casting hooks, argument preservation, cache recovery, denial, unknown and one-shot completion");
        exit(0);
    }];
}

static void CheckDenied(MDXLocalNetworkPermissions *permissions) {
    FakeStatus = YTLNFDenied;
    [permissions verifyAccessWithCompletion:^(NSInteger result) {
        Require(result == YTLNFDenied && [permissions lastKnownPermissionsStatus] == YTLNFDenied,
                "denial must remain denied and replace previously allowed cache");
        Require(permissions.notifications == 1, "hook must leave notifications to the native caller");
        [permissions notifyStatusChangeObservers:result];
        Require(permissions.notifications == 2 && permissions.notifiedStatus == YTLNFDenied,
                "permission revocation must notify native observers");
        CheckUnknown(permissions);
    }];
}

int main(void) {
    @autoreleasepool {
        dispatch_queue_set_specific(dispatch_get_main_queue(), &MainQueueKey, &MainQueueKey, NULL);
        const char *wrongArgs[] = {"@", ":", "q"};
        Require(!HasSignature(class_getInstanceMethod([MDXLocalNetworkPermissions class], @selector(verifyAccessWithCompletion:)),
                              "v", 3, wrongArgs), "incompatible callback ABI must be rejected");
        Require(!HasSignature(NULL, "v", 3, wrongArgs), "missing methods must be rejected");
        Require(InstallCastingFix(), "verified mock ABI must install");
        FactoryResult = [NSObject new];
        id reachability = [NSObject new];
        id browser = [GCKCastDeviceMDNSScanner createMDNSServiceBrowserWithCustomMulticastEnabled:YES
            useUnicastQueries:YES networkReachability:reachability rescanInterval:0.25 deviceTimeoutInterval:42.5];
        Require(!FactoryMulticast && FactoryUnicast && FactoryReachability == reachability,
                "factory must change multicast only");
        Require(FactoryRescan == 0.25 && FactoryTimeout == 42.5 && browser == FactoryResult,
                "factory must preserve floating-point arguments and return identity");

        __block NSUInteger callbacks = 0;
        YTLNFBonjourProbe *probe = [YTLNFBonjourProbe new];
        probe.completion = ^(NSInteger status) {
            callbacks++;
            Require(status == YTLNFAllowed, "first probe outcome must win");
        };
        [probe finishWithStatus:YTLNFAllowed];
        [probe finishWithStatus:YTLNFDenied];
        Require(callbacks == 1, "late cancellation/timeout must not invoke completion twice");

        ProbeRunner = FakeProbe;
        FakeStatus = YTLNFAllowed;
        MDXLocalNetworkPermissions *permissions = [MDXLocalNetworkPermissions new];
        [permissions verifyAccessWithCompletion:^(NSInteger result) {
            Require(result == YTLNFAllowed && [permissions lastKnownPermissionsStatus] == YTLNFAllowed,
                    "successful Bonjour must recover a cached multicast denial");
            Require(permissions.notifications == 0, "hook must not duplicate native caller notifications");
            [permissions notifyStatusChangeObservers:result];
            Require(permissions.notifications == 1 && permissions.notifiedStatus == YTLNFAllowed,
                    "successful recovery must notify native observers");
            CheckDenied(permissions);
        }];
    }
    // Bound the test even if a hook loses its completion callback.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        Require(NO, "completion timed out");
    });
    dispatch_main();
}
