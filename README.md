# Calendar Meet

Native macOS Swift app and EventKit virtual conference extension adding **Google
Meet** to Apple Calendar's **Add Location or Video Call** picker.

## 0.3.0 — menu bar and native conference presentation

A minimal menu-bar-only app: click the original icon for Google sign-in/reconnect
and Launch at Login (requested on by default); right-click for Quit. No Dock icon,
setup window, test-meeting controls or signing notices in the app. A team installer
with a bundled Desktop OAuth client needs only the user's Google sign-in. Generic
builds without that configuration show one setup-file button.

The Calendar extension returns a real `EKVirtualConferenceDescriptor` with exactly
one `EKVirtualConferenceURLDescriptor`: the direct HTTPS Google Meet URI, first and
unchanged. Optional titles and duplicate conference notes are omitted, following
Apple's WWDC23 single-entry-point example. This allows system presentation; **it
does not force the visible action label to “Join.”** Apple's public descriptor API
has no action-label property. See [investigation](docs/JOIN-BUTTON.md) and
[verification](docs/VERIFICATION.md) for actual Calendar results.

Google tokens stay in the containing app's login Keychain. The sandboxed extension
opens that app and receives only a meeting URL/error over a short-lived loopback
callback protected by a random one-use capability. Existing OAuth scope and Meet
space creation are preserved. No extra Google Calendar event is created, no
Calendar permission is requested, and private Apple APIs are not used.

Local builds use ad-hoc signatures unless Developer ID credentials are supplied.
Signing and notarization remain supported by the signed release workflow.

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
GitHub's generic prerelease requires import. The signed workflow supports an
optional CI client configuration. Local client-bundled installers can be shared directly.

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
