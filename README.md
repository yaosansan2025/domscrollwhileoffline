# Offline Feed

An independent iPhone app for swiping through a local library of videos. Import MP4, MOV, or M4V files you have permission to keep; the app copies and checks each video before adding it to the feed. Playback works without a network connection, account, or auth token. Videos loop, and the feed returns to the start after the last video. You can import several files at once, remove individual videos, or clear the library. Imported videos from the previous version remain in the same local library.

## Get videos into the feed

Save authorized video files to the iPhone's Files app, open Offline Feed, then tap **Import videos**. Select one or several files. The app does not fetch Instagram's recommended feed. Meta's supported API does not expose a personal account's recommendations or permit arbitrary offline copies of other people's Reels. This app does not modify or wrap Instagram.

The **Accounts** tab lets you add a creator username later. Tap the account to import video files into that account's offline collection. The main feed continues to show every imported video. Removing a username keeps its files in the main feed. A username is a local label; adding it does not authenticate, sync, or download posts.

## Build

Requires Xcode 15 or newer and iOS 17 or newer. It has no third-party dependencies. To build without signing on a Mac:

```sh
xcodebuild -project QuietReels.xcodeproj -scheme QuietReels \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow builds an unsigned iPhone IPA for preview. An unsigned IPA needs Apple signing before it can be installed on a normal iPhone. The app makes no network requests and needs no Meta developer app or authentication server.
