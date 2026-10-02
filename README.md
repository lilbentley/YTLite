# YouTube Plus (ex. YTLite)
A flexible enhancer for YouTube on iOS, featuring over hundred customizable options.

## Table of Contents
- [Screenshots](#screenshots)
- [Main Features](#main-features)
- [FAQ](#faq)
- [Local Network permission prompt workaround](#local-network-permission-prompt-workaround)
- [Reviews](#reviews)
- [How to build a YouTube Plus app using GitHub Actions](#how-to-build-a-youtube-plus-app-using-github-actions)
- [Supported YouTube Version](#supported-youtube-version)
- [Tweak Integration Details](#tweak-integration-details)

## Screenshots
<table>
   <tr>
      <td><img src="Resources/scr1.jpg" alt="Screenshot 1" /></td>
      <td><img src="Resources/scr2.jpg" alt="Screenshot 2" /></td>
      <td><img src="Resources/scr3.jpg" alt="Screenshot 3" /></td>
   </tr>
</table>

<details>
  <summary>More screenshots</summary>
  <table>
    <tr>
      <td><img src="Resources/scr4.jpg" alt="Screenshot 4" /></td>
      <td><img src="Resources/scr5.jpg" alt="Screenshot 5" /></td>
      <td><img src="Resources/scr6.jpg" alt="Screenshot 6" /></td>
    </tr>
    <tr>
      <td><img src="Resources/scr7.jpg" alt="Screenshot 7" /></td>
      <td><img src="Resources/scr8.jpg" alt="Screenshot 8" /></td>
      <td><img src="Resources/scr9.jpg" alt="Screenshot 9" /></td>
    </tr>
  </table>
</details>

## Main Features
<li>Download videos, audio (including audio track selection), thumbnails, posts, and profile pictures</li>
<li>Copy video, comment, and post information</li>
<li>Interface customization: Remove feed elements, reorder tabs, enable OLED mode, and as use Shorts-only mode</li>
<li>Player settings: Gestures, default quality, preferred audio track</li>
<li>Save, Load and Restore settings. Clear cache once or automatically on app startup</li>
<li>Built-in SponsorBlock</li>
<li>And much, much more</li>
<br>


**YouTube Plus preferences can be found in the YouTube Settings**

**All contributors are listed in the Contributors section**
**Used open-source libraries are listed in the Open Source Libraries section**

> [!NOTE]
> Starting from version 5.2, YTPlus requires a subscription.  
> The last free version is [5.2b4](https://github.com/dayanch96/YTLite/releases/tag/v5.2b4).

## FAQ
- [🇺🇸 English FAQ](FAQs/FAQ_EN.md)
- [🇷🇺 ЧаВо на Русском](FAQs/FAQ_RU.md)
- [🇮🇹 FAQ in Italiano](FAQs/FAQ_IT.md)
- [🇵🇱 FAQ po polsku](FAQs/FAQ_PL.md)

## Local Network permission prompt workaround

**The legacy prompt hook failed on YouTube 21.12.4 + YouTube Plus 5.2b4 installed through AltStore.** Build (5) included the library, but the device still displayed the permission screen. The workflow option is now disabled by default and explicitly labelled as a legacy hook.

If enabled, the option adds PoomSmart's [YTNoCheckLocalNetwork](https://poomsmart.github.io/repo/depictions/ytnochecklocalnetwork.html) version 1.0.0, downloaded from its official repository with SHA-256 verification. It changes `YTHotConfig.isPromptForLocalNetworkPermissionsEnabled`. Scanning all seven Mach-O files in the original 21.12.4 IPA found no reference to that selector. The app contains newer `MDXLocalNetworkPermissions` checks instead. A successful build and a packaged library do not establish that a hook affects the current app.

Static inspection of the 5.2b4 library also found that it already installs these three `YTColdConfig` overrides, matching the older [YTLitePlus casting workaround](https://github.com/YTLitePlus/YTLitePlus/blob/main/YTLitePlus.xm):

| Flag | Hook return value |
| --- | --- |
| `cxClientEnableIosLocalNetworkPermissionReliabilityFixes` | `YES` |
| `cxClientEnableIosLocalNetworkPermissionUsingSockets` | `NO` |
| `cxClientEnableIosLocalNetworkPermissionWifiFixes` | `YES` |

Adding those same overrides again is not a new fix. If A/B settings were changed manually, disable YTABConfig and fully restart the app to test without its saved overrides.

The original and built IPAs both already declare `NSLocalNetworkUsageDescription` and the `_googlecast._tcp` / `_233637DE._googlecast._tcp` Bonjour services. Their presence does not establish the capabilities of the app after AltStore signs it. Apple distinguishes the user's Local Network permission from the separate [multicast signing entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast). Raw multicast/broadcast requires the entitlement; browsing declared Bonjour services and using the system AirPlay picker can avoid that requirement. See [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) and [Google's Cast discovery documentation](https://developers.google.com/cast/docs/ios_sender/permissions_and_discovery).

The [upstream casting discussion](https://github.com/dayanch96/YTLite/issues/334) reports that YouTube 20.10.4 works where newer versions fail, and that correctly provisioned multicast signing can restore discovery on newer versions. These are device reports, not a guarantee for every iOS version; another report describes an empty cast menu on 20.10.4 with AltStore and an iOS 26 beta. The signed app and its provisioning profile must both authorize multicast. Adding an entitlement string to this build workflow cannot grant that capability.

For SmartTube, open the TV app and pair through **Settings > Watch on TV > Link with TV code** using its [pairing instructions](https://github.com/yuliskov/SmartTube#casting). SmartTube does not support automatic discovery; the native permission-screen issue can still affect access to the menu. For AirPlay, try the system route picker through Control Centre while a video plays.

The version-based workflows default to the last officially free tweak, **5.2b4**. That does not certify casting compatibility with a given YouTube version. A modern fix would need to address the current permission probe and discovery path; the legacy hook in this draft is not that fix.

## Reviews
Review by [@qbap](https://github.com/qbap) on ONE Jailbreak: https://onejailbreak.com/blog/youtube-plus/

## How to build a YouTube Plus app using Github actions
> [!NOTE]
> If this your first time, complete following steps before starting:
>
> 1. Fork this repository using the fork button on the top right
> 2. On your forked repository, go to **Repository Settings** > **Actions**, enable **Read and Write** permissions.

<details>
  <summary>How to build the YouTube Plus app</summary>
  <ol>
    <li>Click on <strong>Sync fork</strong>, and if your branch is out-of-date, click on <strong>Update branch</strong>.</li>
    <li>Navigate to the <strong>Actions tab</strong> in your forked repository and select <strong>Create YouTube Plus app</strong>.</li>
    <li>Click the <strong>Run workflow</strong> button located on the right side.</li>
    <li>Mark or unmark the tweaks you want to integrate. Learn more about them in the <a href="#tweak-integration-details">Tweak Integration Details</a> section.</li>
    <li>Prepare a decrypted .ipa file <em>(we cannot provide this due to legal reasons)</em>, then upload it to a file provider (e.g., filebin.net, filemail.com, or Dropbox is recommended). Paste the URL of the decrypted IPA file in the provided field.</li>
    <li><strong>NOTE:</strong> Make sure to provide a direct download link to the file, not a link to a webpage. Otherwise, the process will fail.</li>
    <li>Enter the tweak version from the releases (the latest release is selected by default). You can also change the BundleID and Display Name if desired.</li>
    <li>Make sure all inputs are correct, then click <strong>Run workflow</strong> to start the process.</li>
    <li>Wait for the build to finish. You can download the YouTube Plus app from the releases section of your forked repo. (If you can't find the releases section, go to your forked repo and add /releases to the URL, i.e., github.com/user/YTLite/releases.)</li>
  </ol>
</details>


<details>
  <summary>How to build the YouTube Plus app with your own link for the YouTube Plus tweak</summary>
  <ol>
    <blockquote>
      <p><strong>NOTE:</strong> This option is primarily intended for building the YouTube Plus app based on the beta file you have. In other cases, it is generally not needed.</p>
    </blockquote>
    <li>Click on <strong>Sync fork</strong>, and if your branch is out-of-date, click on <strong>Update branch</strong>.</li>
    <li>Navigate to the <strong>Actions tab</strong> in your forked repository and select <strong>[BETA] Build YouTube Plus app</strong>.</li>
    <li>Click the <strong>Run workflow</strong> button located on the right side.</li>
    <li>Mark or unmark the tweaks you want to integrate. Learn more about them in the <a href="#tweak-integration-details">Tweak Integration Details</a> section.</li>
    <li>Prepare a decrypted .ipa file <em>(we cannot provide this due to legal reasons)</em>, then upload it to a file provider (e.g., filebin.net, filemail.com, or Dropbox is recommended). Paste the URL of the decrypted IPA file in the provided field.</li>
    <li>Upload your beta tweak file to a file provider and paste direct link to the <strong>URL to the YouTube Plus tweak file</strong> field. You can also change the BundleID and Display Name if desired.</li>
    <li><strong>NOTE:</strong> Make sure to provide a direct download link to the file, not a link to a webpage. Otherwise, the process will fail.</li>
    <li>Make sure all inputs are correct, then click <strong>Run workflow</strong> to start the process.</li>
    <li>Wait for the build to finish. You can download the YouTube Plus app from the releases section of your forked repo. (If you can't find the releases section, go to your forked repo and add /releases to the URL, i.e., github.com/user/YTLite/releases.)</li>
  </ol>
</details>

## Supported YouTube Version
<ul>
   <li><strong>Latest confirmed:</strong> <em>21.16.2</em></li>
   <li><strong>Date tested:</strong> <em>Jul 17, 2026</em></li>
   <li><strong>YouTube Plus:</strong> <em>5.2.2</em></li>
</ul>

## Tweak Integration Details
<details>
  <summary>YouPiP</summary>
  <p>YouPiP is a tweak developed by <a href="https://github.com/PoomSmart">PoomSmart</a> that enables the native Picture-in-Picture feature for videos in the iOS YouTube app.</p>
  <p><strong>YouPiP preferences</strong> are available in the <strong>YouTube settings</strong>.</p>
  <p>Source code and additional information are available <a href="https://github.com/PoomSmart/YouPiP">in PoomSmart's GitHub repository</a>.</p>
</details>

<details>
  <summary>YTUHD</summary>
  <p>YTUHD is a tweak developed by <a href="https://github.com/PoomSmart">PoomSmart</a> that unlocks 1440p (2K) and 2160p (4K) resolutions in the iOS YouTube app.</p>
  <p><strong>YTUHD preferences</strong> are available in the <strong>Video quality preferences</strong> section under <strong>YouTube settings</strong>.</p>
  <p>Source code and additional information are available <a href="https://github.com/PoomSmart/YTUHD">in PoomSmart's GitHub repository</a>.</p>
</details>

<details>
  <summary>Return YouTube Dislikes</summary>
  <p>Return YouTube Dislikes is a tweak developed by <a href="https://github.com/PoomSmart">PoomSmart</a> that brings back dislikes on the YouTube app.</p>
  <p><strong>Return YouTube Dislikes preferences</strong> are available in the <strong>YouTube settings</strong>.</p>
  <p>Source code and additional information are available <a href="https://github.com/PoomSmart/Return-YouTube-Dislikes">in PoomSmart's GitHub repository</a>.</p>
</details>

<details>
  <summary>YouQuality</summary>
  <p>YouQuality is a tweak developed by <a href="https://github.com/PoomSmart">PoomSmart</a> that allows to view and change video quality directly from the video overlay.</p>
  <p><strong>YouQuality can be enabled</strong> in the <strong>Video overlay</strong> section under <strong>YouTube settings</strong>.</p>
  <p>Source code and additional information are available <a href="https://github.com/PoomSmart/YouQuality">in PoomSmart's GitHub repository</a>.</p>
</details>

<details>
  <summary>DontEatMyContent</summary>
  <p>DontEatMyContent is a tweak developed by <a href="https://github.com/therealFoxster">therealFoxster</a> that prevents the Notch/Dynamic Island from munching on 2:1 video content in the iOS YouTube app.</p>
  <p><strong>DontEatMyContent preferences</strong> are available in the <strong>YouTube settings</strong>.</p>
  <p>Source code and additional information are available <a href="https://github.com/therealFoxster/DontEatMyContent">in therealFoxster's GitHub repository</a>.</p>
</details>
