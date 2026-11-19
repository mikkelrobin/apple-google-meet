# Calendar Meet

Native macOS Swift app and EventKit virtual conference extension adding **Google
Meet** to Apple Calendar's **Add Location or Video Call** picker.

## 0.2.0 — membership-free experiment

The containing app handles Google OAuth and conference creation, and stores tokens
in its own **macOS login Keychain**. The sandboxed Calendar extension has no Google
tokens, App Group, shared Keychain or provisioning profile. It opens its containing
app explicitly and receives a meeting URL or error through a short-lived callback
bound to `127.0.0.1`, protected by a random 256-bit one-use capability.

Selecting **Google Meet** in Calendar creates the meeting automatically and returns
the link. The app is started on demand if closed. There is no per-meeting dialog.
The user explicitly requested this automatic behavior. Requests are deduplicated,
checked for a live callback, and bounded by a timeout. Local applications can
request new Meet spaces through this integration; they never receive OAuth tokens.

Default builds are ad-hoc signed **UNSIGNED-PREVIEW**, without Developer ID or
notarization. A paid Apple membership is not used by this architecture. macOS or
corporate policies may block unsigned apps. Exact live test results and limits
are recorded in [VERIFICATION.md](docs/VERIFICATION.md).

![Original Calendar Meet icon](docs/AppIcon.png)

## Build

```sh
bash Scripts/test.sh
GOOGLE_CLIENT_JSON=/absolute/path/DesktopClient.json bash Scripts/build.sh
bash Scripts/package.sh
```

Without `GOOGLE_CLIENT_JSON`, the app prompts to import the team's Desktop OAuth
file. Do not commit client exports, tokens, certificates or local configuration.
The local Google client supplied during setup is deliberately not in this repo.
GitHub's generic prerelease requires import unless the optional CI client secret
is configured. Local client-bundled installers can be shared directly.

Universal arm64 + x86_64, macOS 13+. No third-party libraries or project generator.
Both targets remain sandboxed. No Calendar, contacts, camera or microphone access.
Only the Google `meetings.space.created` scope is requested. PKCE S256, random
OAuth state, loopback-only callbacks, deadlines, cancellation, refresh and revocation
are implemented. Tokens and API response bodies are not logged.

[Google setup, optional signing and troubleshooting](docs/SETUP.md).
Optional Developer ID signing/notarization remains available for easier installation;
it is no longer required for shared OAuth storage because no storage is shared.

## Platform references

- [Apple virtual conference extension](https://developer.apple.com/documentation/eventkit/implementing-a-virtual-conference-extension)
- [Apple NSWorkspace explicit app opening](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Apple macOS Keychain implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)
- [Google Desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google Meet spaces.create](https://developers.google.com/workspace/meet/api/reference/rest/v2/spaces/create)

EventKit provider APIs are public since macOS 12; this SwiftUI app targets macOS 13.
No UI scripting or Calendar database access is used by the app. Original icon in
Scripts/Icon.swift. Independent utility, not affiliated with Apple or Google. MIT.
