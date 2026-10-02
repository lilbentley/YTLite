# Casting fix for sideloaded YouTube

This experimental patch targets YouTube 21.12.4 with YouTube Plus 5.2b4. Enable **Use Bonjour permission checking and Cast discovery** when building from this PR branch, install the resulting IPA, and keep iOS Local Network access enabled. The older prompt-suppression option should remain off. This patch does not require YTABConfig/A/B settings.

## What changes

1. `MDXLocalNetworkPermissions.verifyAccessWithCompletion:` runs a system Bonjour browse for the already declared `_googlecast._tcp` service. A ready browser reports allowed; the DNS policy-denied error reports denied. Other failures and a 30-second timeout preserve YouTube's previous permission state. No actual TV needs to be discovered to determine whether browsing is permitted.
2. A successful or explicitly denied browse updates YouTube's native permission cache and notifies its existing observers when the state changes. A previous multicast failure no longer prevents a fresh permission check. Completion runs on the main queue and is delivered once.
3. The `GCKCastDeviceMDNSScanner` browser factory takes its existing non-custom-multicast branch, constructing `GCKBonjourServiceBrowser`. All other arguments and the original return value are preserved. This uses the existing Cast SDK discovery implementation, rather than reimplementing Chromecast connections.

The patch checks every private method's return type, argument count and argument types before installing either hook. A mismatch disables both hooks and writes a console message. It does not patch binary addresses or report permission as allowed unconditionally. The dylib requires iOS 15 or later.

## Evidence in the inspected executable

These addresses describe the supplied 21.12.4 executable; the implementation never hard-codes them.

| Native behavior | Verified location |
| --- | --- |
| Permission probe calls `sendMSearchRequest` | Block at `0x103417d90`, call at `0x103417dbc` |
| Probe sends UDP to `239.255.255.250` | `sendMSearchRequest` at `0x103417f60` |
| Status values: allowed 1, denied 2, unknown 3 | Probe and `isAuthorized` at `0x1007f697c` |
| Native callback persists known permission status | Block at `0x1034173e0` |
| Custom multicast versus system Bonjour factory branches | Factory at `0x1030f6930` |

The original IPA already declares `_googlecast._tcp`, `_233637DE._googlecast._tcp`, and `NSLocalNetworkUsageDescription`. The helper changes the permission probe and discovery selection; it does not add a multicast entitlement or modify the signing profile. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) distinguishes raw multicast from declared Bonjour operations. [Google's Cast documentation](https://developers.google.com/cast/docs/ios_sender/permissions_and_discovery) describes Bonjour discovery requirements.

## Validation and device test

The macOS host tests exercise the real hook implementations against mock native classes: recovering a cached denial, preserving a genuine denial, retaining the cache on an inconclusive probe, observer updates, single completion delivery, ABI checks, and forwarding all discovery arguments while changing the custom-multicast selection. They do not establish that iOS permission prompts or real devices work. The workflow runs these tests and cross-compiles the dylib for iOS before packaging it.

On the iPhone, fully close the app after installing the new IPA, open it, then open the Cast menu while on the same Wi-Fi as the receiver. Test discovery and reconnecting after disconnecting. SmartTube still requires its documented TV-code pairing and cannot be made automatically discoverable by this sender-side change. Use the native AirPlay entry for AirPlay receivers.

Logs are prefixed `[YTLiteLocalNetworkFix]` and report hook installation, probe outcomes, and the selected browser class. A ready probe with no visible Cast devices means discovery needs further device-specific testing; it does not establish a denied permission. Runtime verification is still required.
