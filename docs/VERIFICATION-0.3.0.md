# Verification — Calendar Meet 0.3.0, 19 November 2026

## Automated checks

52 checks pass locally, including actual loopback callback exchanges, OAuth,
API error handling, conference creation, and four new descriptor assertions:
exactly one join option, unchanged direct Meet URI, nil optional titles, and no
duplicate generic URL in notes. Google HTTP responses in automated tests are mocked.
The loopback tests need networking permitted by the execution environment.

## Investigation

The old installed 0.2.0 event was observed in Apple Calendar: **button Open,
Description Join**. Thus an accessibility description alone is not proof that the
visible label is Join. See JOIN-BUTTON.md for the supported API boundaries.

## Live and distribution checks

- Universal arm64 + x86_64 app/extension built with the installed macOS 27.2 SDK,
  minimum deployment target macOS 13. The command-line toolchain emitted warnings
  about an arm64-only compatibility archive while linking Intel; Intel binaries
  linked successfully, but have not been run on physical Intel hardware.
- Both bundles pass strict recursive ad-hoc signature verification, architecture,
  sandbox, original icon, extension point/principal class and LSUIElement checks.
- Installed over the existing app; pluginkit selected **0.3.0** from /Applications.
- Live test on this Apple Silicon Mac: quit/reopened Calendar, created a disposable
  Google-calendar event without attendees, selected Google Meet in the actual
  video-call picker, saved it and reopened it. A real Meet link returned without
  a per-meeting app dialog. Google sync added its own dial-in/security notes.
- The saved event visibly showed **Open**, and AX reported **button Open,
  Description Join**. The nil-title descriptor does NOT solve the literal label
  on this system. No unsupported API is used to alter it.
- Deleted the disposable event and verified it disappeared. The generated Meet
  space is not deleted by removing a Calendar event. No attendees were invited.
- Opened the new app's popover: only original icon/name, Google connected,
  Reconnect Google Account and Launch at Login. Existing Keychain login survived.
  Launch at Login was initially on; switched off and back on successfully,
  reopened the popover and verified on. Actual login after reboot is untested.
- Right-click Quit is implemented through NSStatusItem and NSMenu and compiles;
  the computer-use interface did not expose the status item for that interaction,
  so the right-click/quit path has not been exercised interactively.
- Fresh OAuth/reconnect browser consent was not repeated; existing login and real
  API creation worked. Google OAuth protocol coverage passes automated tests.
- Mounted the final DMG read-only; payload signature, universal bundle checks,
  Applications shortcut and SHA-256 checksum all passed.
- Developer ID signing/notarization is not available locally. Installer is an
  ad-hoc signed preview with a bundled team Desktop OAuth client (no user tokens).
  A downloaded copy may need macOS approval, and managed-device policy can block it.
  This is recorded in distribution notes, with no signing disclaimer in app UI.

Historical 0.2.0 results are preserved separately in VERIFICATION-0.2.0.md; they are
not evidence that the 0.3.0 build has passed live tests.
