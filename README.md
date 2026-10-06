# Quiet Reels

A SwiftUI iPhone prototype with five tabs: **Shared Reels**, **Recommended** (experimental personalized batch cache), **Offline Videos**, **My Profile**, and **Settings**. Offline playback uses only saved local files. It never fetches another recommendation while you watch a cached batch.

## Cache mode

In **Settings**, the **Recommended Reels Auto Cache** switch controls which source can start new caching. It is **OFF** by default: open an item in Shared Reels to use **Cache Offline**. Turn it **ON** to use **Download Offline Reels** or **Refresh Offline Videos** in Recommended. The switch is saved across launches. It does not delete files, change either downloader's storage format, or restrict playback. **Offline Videos** shows both caches with **Shared** and **Recommended** labels and their combined size. Its **Manage** menu can clear either source independently or clear both, each with confirmation. The Recommended page also retains its own cache list and controls.

## Instagram API and Web limitations

Meta's [Instagram API with Instagram Login](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/) targets professional (Business/Creator) accounts. It does **not** expose a personal user's recommended Reels feed, the official app's personalized ranking, or arbitrary recommended Reels' downloadable media URLs. The [messaging API](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api/) also does not provide general access to a personal DM or group-chat inbox. Own-account professional media endpoints are not a recommendation feed. No official API grants this app a general right to download and retain recommended Reels long term.

The Meta documentation site and Instagram Web returned HTTP 403 from this workspace on October 6, 2026. The current live API behavior and HTML structure **could not be tested here**; recheck the official docs before treating any integration claim as current. This project does not use a private Instagram endpoint or ask for an Instagram API token.

Instagram Web video URLs may use cookies, signed parameters, request headers, expiring CDN links, `blob:`/MediaSource playback, DRM, or other access controls. A Reel page URL is not a video file. A failed or protected URL is not marked as cached. This prototype only attempts direct HTTPS video sources rendered by the Web page and validates the downloaded file before showing it offline. Rights and Instagram's terms may also restrict saving particular content; use only content you are allowed to store.

## Experimental one-tap recommended cache

1. Turn on **Recommended Reels Auto Cache** in **Settings**, then open **Recommended > Open Instagram Web Session** and sign in there. This WebKit session is separate from the Instagram app's login; iOS cannot copy the other app's session. Cookies remain in WebKit storage and are passed only in memory to an ephemeral `URLSession` for video requests. They are not logged or written into the cache index.
2. Choose **10**, **20**, or **50**, then tap **Download Offline Reels** once. The app loads the Instagram Web Reels page, scans rendered Reel links and video elements, scrolls within a bounded number of rounds, and attempts to download the first discovered direct HTTPS media sources. It does not ask you to select each video. The browser DOM and its ordering are undocumented, so this is **not guaranteed to match the Instagram app's ranking**, return the selected count, or work after an Instagram update. If it sees only `blob:` streams or no downloadable media URLs, it reports that limitation rather than inventing results.
3. Progress shows `X / N videos downloaded`, failures, and already cached items. **Pause** cancels the current request and preserves completed files and remaining candidates in memory; **Resume** continues during the same app session. **Cancel** stops the batch and keeps completed videos. Relaunching the app preserves completed videos but requires starting a new batch for unfinished work.
4. **Refresh Offline Videos** discovers current Web recommendations, downloads new playable files, then removes some oldest pre-existing recommended cache entries. It leaves old entries in place if no new download succeeds. The Web page may yield too few fresh items, which is reported explicitly.

Downloaded MP4 files, thumbnails when extraction succeeds, and an atomic JSON index live under Application Support in `QuietReels/RecommendedVideos`. The index records Reel ID, canonical Reel URL, cache time, relative file paths, and byte size. The **Recommended** and **Offline Videos** lists show saved recommended videos, and the local-only player has native pause/scrub controls, replay, and previous/next buttons restricted to the already saved list. No network recommendation request happens in the player.

## Existing shared-message workflow

**Shared Reels** remains a separate manual workflow. Choose a Reel yourself in Instagram DM, including a group chat if applicable, and add its permalink plus a video file you are allowed to save, or a separate authorized direct video URL. Sender and chat names are entered manually. The app cannot read personal DMs or verify that the Reel was shared by a friend. A direct video URL may expire or require authorization. With the cache mode switch OFF, opening a Shared Reels item offers **Cache Offline**, which stores a separate copy in `QuietReels/OfflineVideos` and lists it under **Offline Videos**. That cache retains per-item deletion. It is not the source for the one-tap recommended batch.

**My Profile** displays locally imported content, not a synchronized Instagram profile.

## Verification still needed on an iPhone

The recommended Web discovery and download flow could not be exercised in this Linux workspace. On a device, sign in through the Web Session, request a small batch, confirm the actual count and error messages, force quit and reopen, enable Airplane Mode, and verify local playback and previous/next navigation. Also test Pause/Resume/Cancel, Refresh, and Clear All. A successful Xcode build alone will not prove the Instagram Web prototype works, because Instagram can change the rendered page and media access at any time.

## GitHub Actions

Three workflows run on pushes to `main`, pull requests, or manually from the Actions tab:

- **Swift** parses all app and test Swift files and type-checks `LibraryStore.swift`. This repository is an Xcode app without a `Package.swift`, so the standard Swift Package template would fail here.
- **Xcode - Build and Analyze** builds and analyzes the iOS app for a generic iPhone simulator without code signing.
- **iOS** selects an available iPhone simulator and runs the `QuietReelsTests` XCTest target through `xcodebuild test`. The tests verify that the manual Shared Reels entry points accept only a chosen Reel URL and an HTTPS direct video file URL, rejecting discovery pages and unrelated hosts.

All three use GitHub-hosted macOS runners. The workflows do not require Apple signing credentials. They cannot verify the Instagram Web session, recommendation ranking, or offline playback on a real iPhone.

## Build and export on a Mac

To open the app in iPhone Simulator automatically, run this from the repository directory on your Mac:

```sh
bash scripts/run-ios-simulator.sh
```

The script chooses an available iPhone with iOS 17 or newer, opens Simulator, builds the app without signing, installs it, and launches it. Xcode and an iOS simulator runtime must be installed. You can optionally pass a specific simulator UDID as the first argument. The cloud workspace and GitHub Actions runners cannot display an interactive simulator on your Mac.

Requirements: Xcode 15 or newer with the iOS 17 SDK. No third-party packages are needed. Open `QuietReels.xcodeproj`, choose an iPhone simulator or device, and run the `QuietReels` scheme. The default bundle identifier is `org.example.QuietReels`; use your own unique identifier for device installation. To check the build without signing:

```sh
xcodebuild -project QuietReels.xcodeproj -scheme QuietReels \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For an installable `.ipa`, you need a Mac with Xcode, an Apple Developer team, an appropriate signing certificate, a provisioning profile for the chosen distribution method, and a registered device for development or ad hoc distribution. Set the target's Team and bundle identifier in Xcode, then archive and use **Product > Archive > Distribute App**. For command-line export:

```sh
xcodebuild -project QuietReels.xcodeproj -scheme QuietReels \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/QuietReels.xcarchive archive

cp ExportOptions.example.plist ExportOptions.plist
# Edit ExportOptions.plist: replace YOUR_TEAM_ID and choose the right export method.
xcodebuild -exportArchive -archivePath build/QuietReels.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist
```

The exported IPA will be in `build/export/` after signing succeeds. `ExportOptions.plist` and build outputs are ignored by Git. This Linux workspace has no Xcode, iOS SDK, or Apple signing credentials, so it cannot compile the iOS target or generate a signed `.ipa` here.
