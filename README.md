# Calendar Meet

A small native macOS Swift app that adds **Google Meet** to Apple Calendar's
existing **Add Location or Video Call** picker using the supported EventKit
virtual conference extension. No calendar scraping, UI automation or fake links.

**Status: development preview.** Universal Apple Silicon + Intel binaries target
macOS 13+. Google OAuth and Meet creation are implemented. No Google Cloud client
or Apple signing identities were available during initial development. The
unsigned installer has login disabled; a signed, App Group provisioned build and
real-account validation are required before this is ready for colleagues.

![Original Calendar Meet icon](docs/AppIcon.png)

## Use

Install a signed build in Applications, import your team's Google Desktop OAuth
JSON (unless bundled), connect Google once, then choose **Google Meet** on an
Apple Calendar event. The app does not need to remain open.

[Setup, signing, Google prerequisites and troubleshooting](docs/SETUP.md)

## Build

```sh
bash Scripts/test.sh
bash Scripts/build.sh
bash Scripts/package.sh
```

Outputs are in `dist/`, explicitly labelled `UNSIGNED-PREVIEW` by default. No
third-party dependencies or project generators. The scripts compile the app and
its embedded `.appex` with the active macOS SDK. Open this folder in Xcode or your
editor; a generated `.xcodeproj` is not needed. The preview workflow builds,
tests, uploads artifacts and publishes a prerelease on pushes to `main`.
The separate manual signed-release workflow requires the documented secrets.

## Security and privacy

System-browser OAuth uses random state, PKCE S256, an ephemeral callback bound
only to `127.0.0.1`, a three-minute deadline and explicit cancellation. Tokens
are stored in the shared Data Protection Keychain, never preferences or plaintext
files. Only `meetings.space.created` is requested. API response bodies and tokens
are not logged. No analytics, backend, Calendar permission, camera or microphone
permission. Revocation is available in the setup window.

## Platform evidence

- [Apple: Implementing a virtual conference extension](https://developer.apple.com/documentation/eventkit/implementing-a-virtual-conference-extension)
- [Apple: EKVirtualConferenceProvider](https://developer.apple.com/documentation/eventkit/ekvirtualconferenceprovider)
- [Apple: Discover Calendar and EventKit (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10052/)
- [Apple: Sharing access to Keychain items](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
- [Apple: App Groups on macOS and iOS](https://developer.apple.com/forums/thread/721701)
- [Google: Desktop OAuth and PKCE](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google: spaces.create](https://developers.google.com/workspace/meet/api/reference/rest/v2/spaces/create)
- [Google: Meet authentication and scope classification](https://developers.google.com/workspace/meet/api/guides/authenticate-authorize)

The installed SDK headers mark the provider APIs macOS 12+. Apple's macOS Xcode
template specifies the `com.apple.calendar.virtualconference` extension point and
App Sandbox. The sample's newer minimum version is not the API introduction date.

See [verification results](docs/VERIFICATION.md) for what has actually been tested.
Original icon drawn from geometric shapes in `Scripts/Icon.swift`; no Google logo.
This is an independent utility, not affiliated with Apple or Google. MIT license.
