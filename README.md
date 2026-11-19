# Calendar Meet

Native macOS Swift app and EventKit virtual conference extension adding **Google
Meet** to Apple Calendar's **Add Location or Video Call** picker.

## 0.4.2 — Meet is ready before the invitation is sent

Create the event in Apple Calendar, manually select Google Meet, add guests and
send as usual. The provider now creates a fresh real Meet space BEFORE returning
its conference descriptor. No temporary setup URL goes into the invitation.

The app no longer searches or patches Google Calendar events, polls pending
requests, or sends conference/description update notifications to guests. Google
can replace the fresh Meet code during Calendar sync and notify the organizer;
the user explicitly accepts that organizer email. A real Apple Calendar test on
19 November 2026 delivered one recipient invitation with a matching, working Meet
link and a separate organizer notice.
See [verification](docs/VERIFICATION.md).

Reconnect once for the `meetings.space.created` permission. Calendar API scopes
are no longer requested or used. The existing desktop OAuth client and Keychain
storage are retained. No hosted server is required.

The monochrome menu-bar video symbol, green/red login dot, original app icon,
Launch at Login default on, no Dock icon, Google reconnect and Sign Out remain.
Sign Out cancels in-flight creation before deleting local login. Existing events
and Meet conferences are preserved. Old Calendar-patching queues are retired and
never replayed after upgrading or switching accounts.

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
Both targets remain sandboxed. No macOS Calendar, contacts, camera or microphone permission is requested.
The app requests only `meetings.space.created`. PKCE S256, random
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
