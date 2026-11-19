# Verification — 19 November 2026

## Confirmed locally

- Read Apple's current virtual conference extension documentation and Google's
  Desktop OAuth / Meet API documentation. Checked the installed EventKit headers
  and macOS Xcode extension template. Public provider API available since macOS 12.
- Compiled both Swift targets for **arm64 and x86_64**, targeting macOS 13. Built a
  universal setup app containing a native virtual conference `.appex`.
- **34 checks passed**, covering the RFC 7636 PKCE vector, random verifier, form
  escaping, Desktop client import, minimum OAuth scope, state validation and
  duplicate-state rejection, offline-token exchange, token preservation on
  refresh, Meet POST request and URL validation, safe HTTP errors, provider room
  listing and unknown-room handling. Real local loopback callbacks tested with
  valid state, forged state, denied consent and task cancellation. Google calls
  used an in-memory mocked URLSession; no Google account was accessed.
- Bundle validation passed: universal architectures, version/minimum OS, correct
  extension point and principal class, original ICNS icons, sandbox/network
  entitlements and preview mode. `codesign --verify --deep --strict` passed for
  ad-hoc integrity signatures; this is not Developer ID signing or notarization.
- Launched the setup app on Apple Silicon macOS 27.0.1 and inspected its native
  window and screenshot. Setup text and controls fit without clipping; unsigned
  preview and disabled login are visible.
- After launching the app, `pluginkit -m -v -i
  com.mikkelrobin.CalendarMeet.Conference` listed **one plug-in** at the embedded
  extension path. This confirms system discovery, not execution inside Calendar.
- Generated a drag-to-Applications DMG with preview warning and SHA-256 checksum.
  Mounted the installer read-only and verified its embedded app signature,
  Applications shortcut and preview warning. Packaging stages outside cloud-synced
  Documents to prevent file-provider metadata invalidating the app signature.

The active Command Line Tools emit a warning that their Swift compatibility packs
archive lacks x86_64. Both binaries still link and contain both architectures.
Intel runtime operation and minimum-OS operation were not tested on physical
machines. GitHub's macOS/Xcode runner rebuild is recorded separately in Actions.
Full Xcode on this machine has an unaccepted license, so local builds used the
already available Command Line Tools; no license was accepted on the user's behalf.

## Not verified / release blockers

- No Google Desktop OAuth client supplied; browser consent, live refresh,
  revocation and Google `spaces.create` have not been exercised against Google.
- No valid Apple signing identities were present. Developer ID signing,
  provisioning validation, shared Keychain access across both processes,
  notarization and Gatekeeper acceptance of a trusted release remain untested.
- Actual Google Meet selection/execution inside Calendar, event persistence,
  invitation delivery, cross-device sync, recurrence and real colleague use remain
  untested. Follow the checklist in SETUP.md on a signed build.
- The signed release workflow is provided but cannot be run successfully without
  the Apple and Google prerequisites. Its first successful output must be reviewed
  against the manual checklist before publication.

The development preview deliberately cannot connect Google. It is an inspectable
artifact, not a finished working team installer. The complete implementation and
release automation are in source; credentials and real-account validation remain
necessary to finish deployment.
