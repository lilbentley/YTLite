"""Apply the reviewed 21.12.4 compatibility additions to pinned YouPiP source."""
from pathlib import Path
import shutil
import subprocess
import sys

PIN = "787806b3a88a02aecdd59b6dc2906c935cc1744d"
root = Path(sys.argv[1])
head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
if head != PIN:
    raise SystemExit(f"Unexpected YouPiP revision: {head}; expected {PIN}")
path = root / "Tweak.x"
source = path.read_text()

def replace_once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit(f"YouPiP source anchor mismatch: {old[:80]!r}")
    source = source.replace(old, new, 1)

replace_once('#import "Header.h"', '#import "Header.h"\n#import "Compatibility.h"')
replace_once('static void activatePiPBase(YTPlayerPIPController *controller) {', '''static BOOL YPCCompatible = NO;

static void YPCReportFailure(NSString *reason, BOOL manual) {
    NSLog(@"[YouPiPCompatibility] %@", reason);
    if (manual) FromUser = NO;
    if (!manual || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || [presenter isKindOfClass:UIAlertController.class]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PiP could not start"
        message:reason preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void activatePiPBase(YTPlayerPIPController *controller) {
    if (YPCCompatible) {
        if (!TweakEnabled()) return;
        BOOL manual = FromUser;
        YPCRequest(controller, ^(NSString *reason) { YPCReportFailure(reason, manual); });
        return;
    }''')

replace_once('NSBundle *YouPiPBundle() {', '''// 21.12.4 calls the zero-argument selector; the upstream argument-taking
// hook is not called by that version. Keep the native event and media gates.
%group YPCModern21
%hook YTPlayerPIPController
- (void)appWillResignActive {
    if (!TweakEnabled()) { %orig; return; }
    if (!UseAllPiPMethod() && (UsePiPButton() || UseTabBarPiPButton()) && !FromUser) return;
    %orig;
    if (LegacyPiP() || UseAllPiPMethod()) activatePiPBase(self);
}
- (void)pictureInPictureFailedToStartWithError:(NSError *)error {
    %orig;
    YPCReportFailure([@"iOS rejected the PiP start: " stringByAppendingString:error.localizedDescription ?: @"unknown error"], FromUser);
}
%end
%end

NSBundle *YouPiPBundle() {''')

replace_once('    %init;\n}', '''    %init;
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    Class controllerClass = %c(YTPlayerPIPController);
    YPCCompatible = [version isEqualToString:@"21.12.4"] &&
        YPCClassSignature(controllerClass, @"appWillResignActive", "v", 2) &&
        YPCClassSignature(controllerClass, @"canEnablePictureInPicture", "B", 2) &&
        YPCClassSignature(controllerClass, @"pictureInPictureFailedToStartWithError:", "v", 3) &&
        YPCInstallDefaultOff(%c(YTHotConfig), TweakEnabled);
    if (YPCCompatible) {
        %init(YPCModern21);
    }
    NSLog(@"[YouPiPCompatibility] 21.12.4 compatibility installed: %d", YPCCompatible);
}''')
path.write_text(source)
shutil.copyfile(Path(__file__).with_name("Compatibility.h"), root / "Compatibility.h")
print(f"Applied PiP compatibility patch to YouPiP {PIN}")
