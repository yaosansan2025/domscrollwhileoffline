# Offline Feed

**Latest release: [1.2.0](https://github.com/yaosansan2025/nonscrolling/releases/tag/1.2.0)** — an independent iPhone app for scrolling through videos saved on your device.

[Download OfflineFeed-1.2.0-unsigned.ipa](https://github.com/yaosansan2025/nonscrolling/releases/download/1.2.0/OfflineFeed-1.2.0-unsigned.ipa) · [SHA-256 file](https://github.com/yaosansan2025/nonscrolling/releases/download/1.2.0/OfflineFeed-1.2.0-unsigned.ipa.sha256)

**The IPA is unsigned.** It needs Apple signing before it can be installed on a normal iPhone. The [1.2.0 tag](https://github.com/yaosansan2025/nonscrolling/tree/1.2.0) contains the source that produced this IPA. The default branch still contains an earlier prototype while the [1.2.0 pull request](https://github.com/yaosansan2025/nonscrolling/pull/1) is in draft.

## What the 1.2.0 app does

- Imports multiple MP4, MOV, or M4V files from the iPhone Files app. It checks that each file is playable and copies it into the app's local library.
- Plays a vertical swipe feed without a network connection. Videos loop, and the feed returns to the start after the last video.
- Lets you add a creator username in **Accounts** and import files into that account's collection later. The main **Feed** shows all imported videos.
- Lets you remove individual videos, clear a collection, or remove an account label. Removing an account label keeps its videos in the main feed.

## Add videos

1. While online, obtain video files you have permission to keep. If an Instagram Reel offers an official **Download** option and saves to Photos, use **Share → Save to Files** to put the video in Files.
2. Open **Offline Feed → Import videos**, or open **Accounts**, add a username, tap that account, and choose **Import videos**.
3. Select one or several files. Once imported, you can scroll through them offline.

An Instagram **Save** bookmark is not a downloaded video file. Adding a username only labels a local collection; it does not sign in, fetch posts, or start a download. The app does not retrieve Instagram's recommended or Following feed, and it does not modify or wrap Instagram. No Instagram account, Meta developer app, or auth token is needed for local playback.

## Build from source

Requires Xcode 15 or newer and iOS 17 or newer. There are no third-party dependencies. Check out the [1.2.0 source tag](https://github.com/yaosansan2025/nonscrolling/tree/1.2.0), open `QuietReels.xcodeproj`, and select the `QuietReels` scheme. For a simulator build without signing:

```sh
xcodebuild -project QuietReels.xcodeproj -scheme QuietReels \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

To install on a physical iPhone, set your Apple signing team and a unique bundle identifier in Xcode, then build or archive for that device. The repository's GitHub Actions workflows check Swift parsing, Xcode build and analysis, simulator tests, and unsigned IPA packaging.
