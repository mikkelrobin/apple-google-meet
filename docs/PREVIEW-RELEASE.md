Calendar Meet 0.2.0 — membership-free architecture experiment, macOS 13+, Intel and Apple Silicon.

**UNSIGNED PREVIEW:** ad-hoc integrity signature only. No Developer ID or Apple
notarization. macOS or managed-device policies may block installation.

Google login is now enabled without shared App Groups or Keychain entitlements.
Credentials stay in the containing app's login Keychain. The Calendar extension
opens the app and waits for a finished link over a one-use local callback.
Choosing Google Meet in Calendar creates the meeting automatically, with no extra
confirmation. The user opted into this behavior. Live callbacks are checked and
requests deduplicated. Local apps can request new meeting spaces through the local
integration; Google tokens never leave the main app's Keychain.

This generic GitHub build requires importing your team's Desktop OAuth client.
No client export, token or certificate is committed to this repository. A locally
built client-bundled installer is a separate artifact.

See docs/VERIFICATION.md for exact live Calendar results and remaining limits;
API compilation and extension discovery alone do not prove integration works.
