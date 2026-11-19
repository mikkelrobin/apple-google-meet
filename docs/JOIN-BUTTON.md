# Calendar “Open” versus “Join” — 0.3.0

## Supported implementation

The extension already used EventKit virtual conference descriptors in 0.2.0, not
`EKEvent.url` or a plain location string. Merely renaming a title to “Join Google
Meet” is not a supported way to set the button label.

0.3.0 follows Apple's WWDC23 example for one join option: nil conference title,
nil URL title, one direct `https://meet.google.com/...` entry point, and nil optional
notes. The room picker still says Google Meet. This removes duplicate link text
and lets Calendar choose presentation. The original Google URI is preserved;
Calendar/account sync can subsequently transform event metadata.

The installed SDK's `EKVirtualConferenceDescriptor.h` exposes only title,
URLDescriptors and conferenceDetails. URL descriptors expose only title and URL.
There is no public action-label, conference-provider-type, or Google conferenceData
property. A nil title is specifically recommended when there is one way to join.
Apple's provider callback receives a room-type identifier, not the event, target
calendar, Google event ID, attendees, dates, or save/cancel outcome. It therefore
cannot reliably patch the corresponding server event with Google metadata.

## Google Calendar metadata

Native Google Calendar conferences use `conferenceData`, a `hangoutsMeet` solution,
video `entryPoints`, and server-generated signature/status data. Creation uses a
unique `conferenceData.createRequest.requestId`, with `conferenceDataVersion=1` on
event modifications, followed by checking asynchronous creation status. These are
Google Calendar event resource fields, not EventKit descriptor fields.

The existing app calls Meet `spaces.create` with `meetings.space.created` and gets
a real meeting URI. That does not itself write Calendar `conferenceData`. Adding
Calendar scopes and inventing a second Google event would create duplicates and
fail for iCloud/other calendars, edited events and cancelled drafts. Matching
arbitrary events by date/title would be unreliable. No such workaround is added.
A separate Google Calendar event-management feature could use conferenceData when
it owns the actual event ID, but that is outside this manual conference provider.

## Label limitation

Calendar chooses the visible action label and provider recognition, including
account sync behavior. The public API cannot promise the literal “Join” label on
every macOS/account. The old event observed on this Mac showed visible **Open**
with accessibility description **Join**; those must not be confused in testing.
See VERIFICATION.md for the new build's observed result.

## Primary references

- [Apple WWDC23 example and transcript](https://developer.apple.com/videos/play/wwdc2023/10052/), virtual conferences, 18:01 onward.
- [Apple URL descriptor](https://developer.apple.com/documentation/eventkit/ekvirtualconferenceurldescriptor).
- [Apple preferred URL ordering](https://developer.apple.com/documentation/eventkit/ekvirtualconferencedescriptor/urldescriptors).
- [Apple extension implementation](https://developer.apple.com/documentation/eventkit/implementing-a-virtual-conference-extension).
- [Google Calendar event resource](https://developers.google.com/workspace/calendar/api/v3/reference/events).
- [Google conference creation](https://developers.google.com/workspace/calendar/api/guides/create-events#conferencing).
- [Google Meet spaces.create](https://developers.google.com/workspace/meet/api/reference/rest/v2/spaces/create).
