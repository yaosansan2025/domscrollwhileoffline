# Codex project instructions

## Verify feasibility before implementation

Before changing or recreating an existing product, stop and verify feasibility before writing implementation code.

1. Determine whether the target application is open source.
2. Locate the real source repository and inspect its license to confirm that modification and redistribution are permitted.
3. Do not treat a public API, SDK, integration, or documentation site as evidence that the application itself is open source.
4. Verify that supported APIs provide the authentication, messages, feeds, media URLs, download rights, and storage behavior required by the request.
5. Clearly distinguish among modifying the original application, building an independent client, wrapping a website, and building a companion or accessibility tool.
6. If the original source is unavailable or required APIs do not exist, explain the limitation and agree on the closest alternative with the user before implementation.

For Instagram specifically: the official iOS and Android applications are proprietary and closed source. Do not claim that this repository modifies Instagram or preserves the official native UI while removing features. Instagram's supported integrations do not provide general access to a personal DM inbox, the official personalized Reels recommendation feed, or arbitrary long-term downloadable Reel media.
