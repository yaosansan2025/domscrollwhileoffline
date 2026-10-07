# Reels Library

An independent native iOS client for a **Business or Creator account's own Instagram media**, plus a local video library. It uses Meta's official Instagram API with Instagram Login. It does not modify Instagram, access a personal account's recommended feed, or use a WebView for browsing videos.

## What the app does

- **My Videos:** Pages through your professional account's media and plays available videos in a native vertical feed. The currently visible video plays and loops; videos outside the page pause. Creator, caption, and counts appear when the API returns them. Paging ends when your own media ends.
- **Profile:** Displays your professional profile and posts returned by the API.
- **Offline:** Imports video files you are authorized to keep, or saves an accessible video from your own account after a rights confirmation. Only validated local files appear in the offline feed. They remain playable without a network connection.
- **Settings:** Starts Meta's browser-based consent flow, stores the resulting token in the iOS Keychain, refreshes an expiring long-lived token, and logs out. Videos and profile use native UI after sign-in.

The Instagram Login API may not identify which video posts are Reels, so My Videos includes all playable videos from your account. The Instagram API does **not** expose your personalized recommended Reels, its infinite ranking, personal DMs, or arbitrary recommended media downloads. This app makes no claim to provide them. Audio labels are omitted because the selected official media fields do not supply a reliable audio title. Video playback and offline saving may fail if a returned media URL expires, is inaccessible, or does not resolve to a playable file. Licensed audio may also restrict local copies. Imported files and your own saved videos are separate from Instagram's official app cache.

## Required Meta setup

1. Create a Meta developer app with **Instagram API with Instagram Login** and connect a Business or Creator Instagram account. Request `instagram_business_basic`. For use outside app roles/test accounts, complete any required Meta App Review.
2. Set a public HTTPS redirect URI in the Meta app's Instagram Business Login settings, for example `https://auth.example.com/auth/callback`.
3. Deploy the included [auth-server/server.mjs](auth-server/server.mjs) behind HTTPS. It needs Node.js 18 or newer and these environment variables:

   | Variable | Value |
   | --- | --- |
   | `IG_CLIENT_ID` | Instagram App ID from Meta's Instagram product settings |
   | `IG_CLIENT_SECRET` | Instagram App Secret; keep on the server |
   | `IG_REDIRECT_URI` | Exact HTTPS URI registered in Meta, including path |
   | `HOST`, `PORT` | Optional bind address and port; defaults to `127.0.0.1:8787` |

   The service has `/auth/start`, the redirect callback, and `/auth/redeem`. It keeps short-lived OAuth state and one-time tickets in memory. A restart during sign-in cancels that attempt. Use one instance or sticky routing for this sample service. Do not expose its HTTP listener directly to the internet; terminate HTTPS at a trusted reverse proxy. Keep the app secret in deployment secrets, not source control.
4. Open the Xcode project, set a unique bundle identifier and signing team, and build for an iPhone. In **Settings**, enter the service's HTTPS origin, such as `https://auth.example.com`, then tap **Sign in with Instagram**. Meta's consent page appears in the system authentication session and returns to the app. The service exchanges the code and sends a one-time ticket to the app; the access token is returned over HTTPS and saved in Keychain. No password, cookie, client secret, or access token is hard-coded in the app.

The service uses the custom URL scheme `quietreels` to return the ticket. If the deployment changes that scheme, update the service, `Info.plist`, and `InstagramAuth.swift` together. A production deployment should use a claimed Universal Link to strengthen callback ownership.

## Offline behavior

Open **Offline > Import from Files** for a local `.mp4`, `.mov`, or `.m4v`. To save one of your own Instagram videos, swipe to it in **My Videos**, open the menu, and choose **Save current video offline**. Confirm only when you have the rights to store that video, including its audio. The app accepts a successful direct video response, verifies it is nonempty and playable, and writes a local index. Duplicate API media IDs are skipped. Failed downloads do not enter the feed. The feed swipes through saved files, autoplays, and loops each video; it stops at the end of the library.

The prior experimental Instagram Web downloader is removed from the app. Existing files created by that prototype are left on device under its old Application Support directories and are not displayed by the new library. This avoids silently treating unverified Web downloads as authorized content.

## Build and verification

Requires Xcode 15 or newer and iOS 17 or newer. The project has no third-party dependencies. To build without signing on a Mac:

```sh
xcodebuild -project QuietReels.xcodeproj -scheme QuietReels \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Run the `QuietReelsTests` target to check the API media model. The Linux workspace cannot compile or launch the iOS app, and no Meta credentials or signed-in device are available here. On an iPhone, test the full OAuth redirect, profile and media fields, paging, video playback, authorized download, Airplane Mode playback, token refresh, and logout. The Node service can be syntax-checked with `node --check auth-server/server.mjs`.

Official scope reference: [Meta's Instagram API with Instagram Login collection](https://www.postman.com/meta/instagram/folder/1z5vxzu/instagram-api-with-instagram-login). The exact fields and access permissions should be checked in the Meta app dashboard for the configured API version and account.
