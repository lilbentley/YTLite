#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dns_sd.h>
#include <string.h>

@protocol YTLNFNativeSelectors
+ (id)sharedInstance;
- (id)localStorage;
- (NSInteger)localNetworkPermissionsStatus;
- (void)setLocalNetworkPermissionsStatus:(NSInteger)status;
- (NSInteger)lastKnownPermissionsStatus;
- (void)notifyStatusChangeObservers:(NSInteger)status;
- (void)verifyAccessWithCompletion:(void (^)(NSInteger))completion;
@end

// These values and method signatures were verified in YouTube 21.12.4.
// Its original probe sends UDP to 239.255.255.250; failed multicast is not
// sufficient evidence that the user denied Local Network access.
typedef NS_ENUM(NSInteger, YTLNFStatus) {
    YTLNFAllowed = 1,
    YTLNFDenied = 2,
    YTLNFUnknown = 3,
};

static NSMutableSet *ActiveProbes(void) {
    static NSMutableSet *probes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ probes = [NSMutableSet new]; });
    return probes;
}

@interface YTLNFBonjourProbe : NSObject
@property(nonatomic, strong) nw_browser_t browser;
@property(nonatomic, copy) void (^completion)(NSInteger);
@property(nonatomic) BOOL finished;
- (void)start;
- (void)finishWithStatus:(NSInteger)status;
@end

@implementation YTLNFBonjourProbe
- (void)finishWithStatus:(NSInteger)status {
    // All state changes run on the main queue. Cancellation and timeout may
    // arrive after readiness; deliver exactly one result.
    if (self.finished) return;
    self.finished = YES;
    void (^completion)(NSInteger) = self.completion;
    self.completion = nil;
    if (self.browser) nw_browser_cancel(self.browser);
    self.browser = nil;
    NSLog(@"[YTLiteLocalNetworkFix] Bonjour permission result: %ld", (long)status);
    if (completion) completion(status);
    [ActiveProbes() removeObject:self];
}

- (void)start {
    [ActiveProbes() addObject:self];
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    // Browse a declared service type through the system Bonjour stack.
    // No raw multicast socket, arbitrary service browsing, or fake allow flag.
    nw_browse_descriptor_t descriptor = nw_browse_descriptor_create_bonjour_service(
        "_googlecast._tcp", "local.");
    self.browser = nw_browser_create(descriptor, parameters);
    if (!self.browser) {
        [self finishWithStatus:YTLNFUnknown];
        return;
    }
    nw_browser_set_queue(self.browser, dispatch_get_main_queue());
    __weak YTLNFBonjourProbe *weakSelf = self;
    nw_browser_set_state_changed_handler(self.browser, ^(nw_browser_state_t state, nw_error_t error) {
        YTLNFBonjourProbe *probe = weakSelf;
        if (!probe || probe.finished) return;
        if (error && nw_error_get_error_domain(error) == nw_error_domain_dns &&
            nw_error_get_error_code(error) == kDNSServiceErr_PolicyDenied) {
            [probe finishWithStatus:YTLNFDenied];
        } else if (state == nw_browser_state_ready) {
            // Readiness means the browse is running; a TV need not advertise
            // a service for this permission check to complete successfully.
            [probe finishWithStatus:YTLNFAllowed];
        } else if (state == nw_browser_state_failed || state == nw_browser_state_cancelled) {
            [probe finishWithStatus:YTLNFUnknown];
        }
    });
    nw_browser_start(self.browser);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [weakSelf finishWithStatus:YTLNFUnknown];
    });
}
@end

static void StartBonjourProbe(void (^completion)(NSInteger)) {
    YTLNFBonjourProbe *probe = [YTLNFBonjourProbe new];
    probe.completion = completion;
    [probe start];
}

// A separate runner lets the host tests exercise the real hook and native
// cache/observer integration with deterministic allowed/denied/error results.
static void (*ProbeRunner)(void (^)(NSInteger)) = StartBonjourProbe;

static void VerifyAccess(id owner, SEL command, void (^completion)(NSInteger)) {
    (void)command;
    // Recheck even when YouTube previously cached a failed multicast probe.
    dispatch_async(dispatch_get_main_queue(), ^{
        ProbeRunner(^(NSInteger status) {
            if (status != YTLNFUnknown) {
                Class environment = objc_getClass("MDXClientEnvironment");
                id instance = ((id (*)(id, SEL))objc_msgSend)(environment, @selector(sharedInstance));
                id storage = ((id (*)(id, SEL))objc_msgSend)(instance, @selector(localStorage));
                if ([storage respondsToSelector:@selector(setLocalNetworkPermissionsStatus:)]) {
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(storage, @selector(setLocalNetworkPermissionsStatus:), status);
                }
            }
            // Native callers (including verifyPermissionsIfPreviouslyAsked)
            // notify their observers from this completion. Do not notify here
            // as well, which would duplicate the original callback's effect.
            // Unknown preserves the native cache, as the original wrapper did.
            NSInteger result = status == YTLNFUnknown
                ? ((NSInteger (*)(id, SEL))objc_msgSend)(owner, @selector(lastKnownPermissionsStatus))
                : status;
            if (completion) completion(result);
        });
    });
}

typedef id (*BrowserFactoryIMP)(id, SEL, BOOL, BOOL, id, double, double);
static BrowserFactoryIMP OriginalBrowserFactory;

static id CreateBonjourBrowser(id owner, SEL command, BOOL customMulticast,
                               BOOL unicastQueries, id reachability,
                               double rescanInterval, double deviceTimeoutInterval) {
    (void)customMulticast;
    // In 21.12.4 the NO branch constructs GCKBonjourServiceBrowser; YES
    // constructs GCKMDNSServiceBrowser, which uses its own multicast stack.
    id browser = OriginalBrowserFactory(owner, command, NO, unicastQueries,
                                        reachability, rescanInterval, deviceTimeoutInterval);
    NSLog(@"[YTLiteLocalNetworkFix] Cast discovery browser: %@", NSStringFromClass([browser class]));
    return browser;
}

static BOOL HasSignature(Method method, const char *result, unsigned int count,
                         const char *const *arguments) {
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char *type = method_copyReturnType(method);
    BOOL matches = type && strcmp(type, result) == 0;
    free(type);
    for (unsigned int i = 0; matches && i < count; i++) {
        type = method_copyArgumentType(method, i);
        matches = type && strcmp(type, arguments[i]) == 0;
        free(type);
    }
    return matches;
}

static BOOL InstallCastingFix(void) {
    Class permissions = objc_getClass("MDXLocalNetworkPermissions");
    Class environment = objc_getClass("MDXClientEnvironment");
    Class storage = objc_getClass("MDXLocalStorage");
    Class scanner = objc_getClass("GCKCastDeviceMDNSScanner");
    SEL verifySelector = @selector(verifyAccessWithCompletion:);
    SEL factorySelector = NSSelectorFromString(@"createMDNSServiceBrowserWithCustomMulticastEnabled:useUnicastQueries:networkReachability:rescanInterval:deviceTimeoutInterval:");
    Method verify = class_getInstanceMethod(permissions, verifySelector);
    Method factory = class_getClassMethod(scanner, factorySelector);
    const char *objectGetter[] = {"@", ":"};
    const char *statusSetter[] = {"@", ":", "q"};
    const char *verifyArgs[] = {"@", ":", "@?"};
    const char *factoryArgs[] = {"@", ":", "B", "B", "@", "d", "d"};
    if (!HasSignature(verify, "v", 3, verifyArgs) ||
        !HasSignature(factory, "@", 7, factoryArgs) ||
        !HasSignature(class_getInstanceMethod(permissions, @selector(lastKnownPermissionsStatus)), "q", 2, objectGetter) ||
        !HasSignature(class_getInstanceMethod(permissions, @selector(notifyStatusChangeObservers:)), "v", 3, statusSetter) ||
        !HasSignature(class_getClassMethod(environment, @selector(sharedInstance)), "@", 2, objectGetter) ||
        !HasSignature(class_getInstanceMethod(environment, @selector(localStorage)), "@", 2, objectGetter) ||
        !HasSignature(class_getInstanceMethod(storage, @selector(localNetworkPermissionsStatus)), "q", 2, objectGetter) ||
        !HasSignature(class_getInstanceMethod(storage, @selector(setLocalNetworkPermissionsStatus:)), "v", 3, statusSetter)) {
        NSLog(@"[YTLiteLocalNetworkFix] Unsupported method signatures; no hooks installed");
        return NO;
    }
    OriginalBrowserFactory = (BrowserFactoryIMP)method_setImplementation(factory, (IMP)CreateBonjourBrowser);
    method_setImplementation(verify, (IMP)VerifyAccess);
    NSLog(@"[YTLiteLocalNetworkFix] Installed Bonjour permission and Cast discovery hooks (0.1.0)");
    return YES;
}

#ifndef YTLOCALNETWORKFIX_TESTING
__attribute__((constructor)) static void InitializeCastingFix(void) {
    @autoreleasepool { InstallCastingFix(); }
}
#endif
