# Verification — Calendar Meet 0.4.2, 19 November 2026

## Why the Calendar-patching design was removed

The user reported three guest emails: the initial invitation followed by a
conference update and a description update. The 0.4.0/0.4.1 native Calendar path
explicitly requested sendUpdates=all for both technical PATCH requests.

An experimental candidate set BOTH to sendUpdates=none. All 102 automated checks
passed, including assertions for silent requests, but a real invitation test to
the user's authorized personal mailbox FAILED the product requirement: one email
arrived, but its content contained calendarmeet://pending/... instead of a usable
Meet URI. The real Google event acquired its native Meet link later, which cannot
retroactively update the already-sent email. That candidate was not released.
The exact named test event was removed using sendUpdates=none, so cleanup did not
request another cancellation email. The received test email was left for review.

The user rejected delaying guest entry until after setup, and rejected a hosted
stable-link redirect service. They explicitly asked to return to the original
Meet-first behavior, accepting a Google organizer update email provided the guest
receives only one invitation. 0.4.2 therefore removes the Calendar API path.

## Final implementation and automated checks

67 checks pass: 54 OAuth/Meet/provider/HTTP/loopback checks and 13 isolated model
checks covering sign-out, cancelling an in-flight Meet request, credential removal,
retaining client configuration, status and failure handling. Google HTTP responses
are mocked; callbacks use real local sockets. The sign-out tests use an in-memory
store and do not remove the real user's Google login.

The provider receives a validated real https://meet.google.com URI before returning.
Temporary local links are rejected. The app makes a fresh spaces.create request
per selection and no Google Calendar event/list/patch requests. It never retries
a possibly successful POST automatically. Existing account Calendar grants do not
qualify as a Meet grant; reconnect is required. Cancelled refresh work cannot save
credentials after logout. Retired Calendar queue/cache keys are cleared on upgrade.

## Live validation and limits

Universal build, Google Meet reconnect and recipient-mailbox verification are in
progress and will be recorded before delivery. The original icon, menu-bar-only
behavior and the 0.4.1 connection indicator/sign-out changes are preserved.

Google controls Calendar server conversion and organizer notices. The app cannot
force the visible Open/Join label. No Developer ID/notarization credentials are
available; preview installers use ad-hoc signatures. Physical Intel/macOS 13,
recurrence and other recipient providers remain separate validation targets.
