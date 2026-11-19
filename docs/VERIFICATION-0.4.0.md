# Verification — Calendar Meet 0.4.0, 19 November 2026

## Automated

85 checks passed locally. Coverage includes OAuth PKCE/state/loopback, old-grant
migration, persisted pending requests, strict local setup URL parsing, calendar
pagination/eligibility, exact marker verification, existing-event PATCH with
native hangoutsMeet data/version, stable request IDs, ETags on both phases,
preserving notes/dates/participants, finalizing only after the native URI exists,
idempotent finalization, rejecting non-organizer/cancelled/recurring-exception
events and existing conferences, asynchronous creation, and HTTP error handling.
Google HTTP responses are mocked; loopback callbacks use actual local sockets.
Universal binaries for arm64/x86_64, macOS 13+ pass strict recursive ad-hoc signature,
bundle, sandbox, icon and extension metadata checks. Intel linker compatibility
archive warnings remain as in 0.3.0; physical Intel/macOS 13 tests were not performed.

## Live Google/Calendar validation

The user enabled Google Calendar API and personally granted the new Calendar
OAuth permissions. Existing Google login required reconnect for these broader
scopes. Google tokens remain in the app's login Keychain.

The integration was tested with disposable events without attendees in the user's
primary Google calendar, created via Apple Calendar's normal event UI and manual
Google Meet picker. The server returned native event-owned Meet conferences and
preserved the original notes, times and reminder. Event searches verified one
existing event rather than an inserted duplicate. App restart recovered a saved
pending request and completed native creation.

The first prototypes exposed a sync problem: removing the temporary URI, or its
exported description block, could leave a stale/empty conference in Apple Calendar.
The final flow instead replaces just the exact marker with the same event's native
Meet URI after Google reports success. An explicit test of this replacement
produced a real meet.google.com conference row in Calendar; clicking it opened
the verified matching Meet URL in Safari without a temporary-link warning. No call
was joined. Apple still visibly displayed **Open**, with accessibility description
**Join**; no public API forces the literal label.

The early prototype's custom-scheme warning was cancelled; automatic approval
review rejected opening that temporary link. The final verified action uses the
correct event-owned HTTPS Meet URI, so no warning bypass is needed.

Gmail searches including Sent/Trash found the earlier 0.3.0/Testing code-update
messages, confirming the correct mailbox, but no messages for the 0.4.0 test titles
at the observation times. This proves no such mail was observed during testing,
not that Google can never send any email. Normal guest updates remain enabled.

The final 0.4.0 build was then tested again with a NEW event, “Calendar Meet 040
automatic acceptance,” with original notes and no guests. Both Calendar API phases
ran automatically in the installed app, with no diagnostic/manual event patches.
Read-back confirmed a native Google Meet link, unchanged dates/reminder/notes and
only one matching event. After sync/reopening Calendar, its conference row showed
meet.google.com, and clicking Open loaded the EXACT matching native Meet URI in
Safari without the temporary-link warning. No actual call was joined.

All named disposable test events were deleted in Calendar and disappeared from
the visible week. Existing events were left untouched. Created Meet conferences
are not deleted when the test Calendar events are removed.

The final DMG was mounted read-only: packaged signatures, architectures, extension,
icons, sandbox and Applications shortcut passed. SHA-256 checksum verification
passed. No Developer ID or notarization is claimed. Prior results are in VERIFICATION-0.3.0.md.

## Limits

- Meet is created after saving/syncing; the draft's temporary link is not ready to join.
- Only connected-account Google events organized by that account are eligible.
  iCloud/Exchange and recurring exceptions are not supported. Recurring-series
  code paths and guest invitation delivery require additional real-world testing.
- Sync timing is controlled by Apple/Google and can take longer than the ten-second
  app polling interval. Quitting the menu-bar app postpones work until relaunch.
- No trusted Developer ID/notarization credentials are available locally. The team
  installer is ad-hoc signed and may require macOS approval on downloaded copies.
- Right-click Quit, actual reboot/login and physical Intel use remain untested
  interactively. The menu-bar UI and original icon are retained.
