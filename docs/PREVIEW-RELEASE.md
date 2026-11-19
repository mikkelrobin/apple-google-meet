Native macOS setup app and EventKit virtual conference extension; Apple Silicon and Intel, macOS 13+.

**UNSIGNED DEVELOPER PREVIEW — not ready for team use.** Ad-hoc integrity signatures only; no Developer ID signature or notarization. Google login is disabled in this build because secure sharing of OAuth credentials with the sandboxed Calendar extension requires Apple signing and App Group provisioning. macOS may block this preview.

Google OAuth with PKCE, refresh/revocation, Meet API conference creation, shared Keychain storage, original icon, tests and signed release automation are included in source. Before a usable team release, configure a Google Desktop OAuth client and Apple Developer ID profiles/certificate, then validate Google login and actual Calendar conference creation on a signed build.

Download the DMG and checksum below. Drag the app to Applications. See [setup and prerequisites](https://github.com/mikkelrobin/apple-google-meet/blob/main/docs/SETUP.md).
