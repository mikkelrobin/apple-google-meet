# Verification — Calendar Meet 0.2.0, 19 November 2026

## Live end-to-end result: passed on this Mac

Tested on Apple Silicon macOS 27.0.1 with ad-hoc signatures only, no Apple Developer
membership, no provisioning profiles and no App Group / Keychain sharing entitlement.
Both app and extension remain sandboxed.

1. Built universal arm64 + x86_64 binaries and bundled the user-supplied Google
   Desktop client locally. No client export or token is in the public repository.
2. The user completed Google browser consent with their Workspace account.
   The app displayed **Google connected** after saving tokens in its own login
   Keychain. Restarting and rebuilding the unsigned app preserved that login.
3. macOS pluginkit discovered and enabled version 0.2.0 of the extension.
4. Created a disposable event without attendees in the user's Google calendar.
   Calendar's existing Add Video Call menu showed **Google Meet** next to FaceTime.
5. Selected Google Meet. The containing app created a real meeting through Google
   Meet API, and returned its URL to the actual Calendar extension callback. The
   final version required no additional confirmation in the app.
6. Committed and reopened the event. Calendar displayed **meet.google.com** and a
   **Join/Open** button. Google Calendar sync rewrote the meeting code and added
   its own conference notes/dial-in details, including its automatic meeting-code
   security notice. This is server-side behavior; the app's original URI can differ
   from the saved URI after sync.
7. Repeated with a separately saved event and the containing app fully quit before
   selection. Calendar launched the app on demand, created the meeting, and the
   reopened event again showed the saved Meet conference and Join button.
8. Deleted both named disposable Calendar events and confirmed no Calendar Meet
   test events remained in the visible week. No attendees were invited. Test Meet
   spaces already created at Google are not deleted when an event is removed.

The earliest draft hit stale Launch Services registration and delayed requests
while replacing the app in-place. Refreshing development registration resolved
handler discovery. The final implementation does not wait indefinitely for app
launch, ignores expired callbacks and duplicate URL delivery, and reuses an
existing setup window. Do not infer that a failed/timed-out POST created no space.

## Automated / package checks

**48 checks passed locally:** OAuth PKCE RFC vector, secure verifier, form encoding,
Desktop client validation, scope, state/duplicate-state validation, denied consent,
offline token exchange, refresh-token preservation, Meet POST and result validation,
HTTP errors without leaking response bodies, provider room listing, unknown/missing
host rejection, OAuth loopback CSRF/cancellation, one-time conference callback,
unsafe-callback rejection, invalid result rejection, active/expired callback
preflight, deadlines and cancellation. Google calls in these tests are mocked;
the real Google/Calendar behavior is tested separately above.

Universal bundle verification checks both architectures, minimum OS 13, correct
extension principal class and extension point, original icons, sandbox/network
entitlements, and absence of App Group or shared Keychain groups. Strict recursive
ad-hoc signature verification passes before packaging. Installer checks include
read-only mounting, payload signature validation, Applications shortcut, unsigned
warning and SHA-256 checksum.

## Remaining limits

- This locally built unsigned app is not Developer ID signed or notarized. A
  downloaded copy may need per-app approval in macOS; managed-device policies can
  block it. The Apple gate on a colleague's Mac is not proven by local launch.
- Only this Apple Silicon Mac and macOS version were exercised interactively.
  Intel, macOS 13 and other macOS releases require physical-device tests.
- Joining an actual call, invitations, recurrence, cross-device/colleague behavior,
  live token refresh after one hour and live revocation were not exercised here.
- The local automatic deep-link endpoint is not caller-authenticated. The user
  explicitly chose creation without extra confirmation. Other local applications
  can request new Meet spaces; callbacks receive only a meeting URL or error, never
  Google tokens. Callback URLs cannot target external hosts or follow redirects.
- File-based macOS Keychain is used through public SecItem APIs and ACL protection,
  rather than the newer provisioned Data Protection Keychain. Code-signature
  changes may trigger per-app Keychain authorization on future updates.

The GitHub generic prerelease and the locally bundled NanoPing installer contain
the same source. The generic CI build needs a Desktop client imported; the local
team build already includes it. Neither artifact contains a user's Google tokens.
