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

The universal build and packaged DMG passed bundle/signature validation. GitHub
Actions run 44525480744 passed the automated tests, universal build and installer
steps for commit 00b3105. The installed app was reconnected by the user.

A real Apple Calendar test was sent at 13:39 CET on 19 November 2026:
- Title: Calendar Meet 042 fallback invite test.
- Date: 20 November 2026, 11:30–12:30 CET.
- Manually selected Google Meet in the same event editor, then added the user's
  authorized personal recipient and clicked Send. No separate save/reopen step.
- The recipient's iCloud mailbox still showed exactly one result at 13:43 CET,
  more than four minutes after sending, with no guest update messages. Its actual
  HTML contained Join with Google Meet and a real HTTPS meet.google.com link.
- The link exactly matched the saved event's native hangout_link, and opened
  Google's pre-join screen in a separate browser session. No call was joined.
- The organizer received Google's Updated video conference notice, as accepted
  by the user. It was not another guest invitation.
- The test event and received mail were left available for user inspection;
  no cancellation or subsequent event edit was sent during verification.

The original icon, menu-bar-only behavior and the 0.4.1 connection indicator/
sign-out changes are preserved. This is an observed account-specific test;
Google controls delivery and future user edits can cause ordinary updates.

Google controls Calendar server conversion and organizer notices. The app cannot
force the visible Open/Join label. No Developer ID/notarization credentials are
available; preview installers use ad-hoc signatures. Physical Intel/macOS 13,
recurrence and other recipient providers remain separate validation targets.
