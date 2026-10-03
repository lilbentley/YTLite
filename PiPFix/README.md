# PiP compatibility for YouTube 21.12.4

The fork applies a small source patch to YouPiP at `787806b3a88a02aecdd59b6dc2906c935cc1744d`. It is included whenever YouPiP is selected; its added runtime hooks activate only for YouTube 21.12.4 after checking the native method signatures. Other YouTube versions retain upstream behavior. The casting helper remains separate and unchanged.

## Findings and changes

In the supplied 21.12.4 executable, `YTPlayerPIPController.isPlayableInPictureInPicture:` (`0x103c689f8`) first checks media playability and GL rendering. At `0x103c68a54` it reads `iosPlayerClientSharedConfigDefaultOffPremiumPip`. When this experiment is enabled and `backgroundPlaybackModeModified` is false, it reads the player response's `isPipOffByDefault` (`0x103c68ad0`), which can reject otherwise playable content. Existing YouPiP hooks do not change this branch. The patch returns false for that experiment while YouPiP is enabled, selecting the original method's user-settings branch (`0x103c68a7c`). It preserves the background playback setting and the native eligibility and renderer checks. It never replaces `canEnablePictureInPicture` with an unconditional true result.

The native background event is `appWillResignActive` (`v16@0:8`, `0x103c68434`), while upstream hooks `appWillResignActive:`. The added zero-argument hook honors button-only activation and starts PiP on dismissal when Unrestricted PiP Activation or Legacy PiP is selected.

Native `MLPIPController.activatePiPController` (`0x103cd967c`) creates or refreshes an AVKit content source. Upstream checks `pictureInPicturePossible` immediately afterwards, and silently returns if it is not yet ready. The patch waits up to two seconds, rechecking the native permission for PiP and the current video before each attempt. Concurrent button presses share an attempt. A changed video or active TV/AirPlay playback cancels the request. It does not force Legacy PiP or change the video decoder.

Manual failures display a reason, including missing controller, background-policy rejection, native eligibility rejection, renderer readiness timeout, or an AVKit start error. Automatic attempts log their outcome without opening an alert in the background. Console messages use `[YouPiPCompatibility]`.

These are executable/source findings, not a diagnosis confirmed by a runtime trace from the user's phone. Build (7)'s PiP failure remained after settings changes. All earlier downloaded builds have identical YouPiP executable code; the first downloaded IPA used YouTube 21.39.4, whereas subsequent free 5.2b4 builds use 21.12.4. A [similar upstream report](https://github.com/PoomSmart/YouPiP/issues/139) concerns 21.33.6, so it is supporting context rather than proof for this version.

## Validation

macOS tests compile the exact activation and experiment-hook code against mock native classes. They cover delayed readiness, duplicate requests, restoration when YouPiP is disabled, signature rejection, background policy, unsupported hardware, embargo, force-disabled playback, GL rendering, unplayable media, casting becoming active, video changes, timeout and missing controllers. The workflow also compiles patched YouPiP for arm64 iOS and packages the result. These checks cannot establish successful PiP playback on an iPhone; the new IPA requires that device test.
