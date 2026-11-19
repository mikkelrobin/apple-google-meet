# Verification — Calendar Meet 0.4.1, 19 November 2026

All 101 checks pass: 88 regression checks and 13 isolated sign-out model checks. The latter
compile the actual production SetupModel with an in-memory credential store and
a cancellable fake refresh actor: no real user login is removed. They verify
cancelling in-flight work before credential deletion, ignoring repeated clicks,
clearing pending/account-specific cache, retaining team client configuration,
publishing disconnected state, and preserving login/reporting error on failure.
Additional checks distinguish revoked login/refresh from invalid event requests,
so a generic HTTP 400 does not falsely turn the indicator red.

The status item uses a template SF Symbol in an NSImageView tinted with labelColor,
plus a separate non-template NSView layer dot (systemGreen/systemRed). It observes
published connection status with Combine. Tooltip/accessibility include the state.
The original app/extension/installer icon is unchanged.

Built universal arm64/x86_64 binaries targeting macOS 13+. Strict recursive
ad-hoc signature, sandbox, icon and bundle verification passed. The final DMG was
mounted read-only and its embedded app verified; checksum also passed. Installed
over the previous app and relaunched, preserving the actual user's login. Intel
linker compatibility-archive warnings remain as previously documented.

The computer-use interface could launch this menu-bar-only app but could not
expose its popover/status item for a fresh visual inspection. Red/green state and
sign-out were verified through the production-model tests and source inspection;
the real user's login was deliberately not removed. Live light/dark appearance
and clicking Sign Out on a real account remain manual UI checks. Live Calendar conference tests from 0.4.0 remain documented separately
in VERIFICATION-0.4.0.md; no conference creation flow is changed in 0.4.1 except
cancellation/authentication state handling around sign-out.

Sign Out is local logout, not Google-wide OAuth revocation. Existing Calendar/Meet
conferences are retained; unfinished requests are dropped to prevent execution
under a subsequently selected account. The status is stored authentication state,
not real-time network availability; external revocation is detected on API use.
