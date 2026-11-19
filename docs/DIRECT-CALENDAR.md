# Direct Google Calendar conferences — 0.4.0

## User flow

1. Reconnect Google once and grant Calendar event read/write plus calendar-list read access.
2. Create/edit an event in Apple Calendar, select Google Meet manually, and save it to the connected Google calendar.
3. The extension returns an explicit local setup URL, not a detached Meet URI.
4. The menu-bar app polls every ten seconds while requests are pending. It searches
   writable Meet-capable calendars using the random per-selection marker and
   verifies the exact setup URL in each result. No date/title matching is used.
5. If exactly one event matches, persist its actual Google calendar/event IDs,
   re-fetch it, and PATCH only conferenceData. If-Match protects concurrent edits.
6. Google generates the event's own Meet conference asynchronously. Poll that
   saved event ID until the native video entry point is returned.
7. Replace only this request's exact pending URL in description/location with the
   same event's native Meet URL, using another conditional PATCH. Leave Calendar's
   exported video-call block and all user notes intact. This step is essential:
   deleting the marker or its block can leave a stale/broken conference record in
   Apple Calendar. The replacement uses a conference already attached to THIS event,
   so no detached Meet code is introduced.
8. Calendar sync replaces its original join target with that verified native URL.
   Wait for sync before using the event's video-call button. Until it completes,
   the temporary custom-scheme link is not a usable meeting invitation.

## Safety and lifecycle

No events are inserted or deleted by the integration. Only organizer-owned events
with the explicit marker are eligible. Existing video conferences are preserved.
Multiple exact matches fail closed; copied pending links must be replaced by a new
selection on each event. Recurring exceptions fail closed; a series master can be
processed. Removing the marker before patching cancels the request. Deleted events
are not recreated. Cancelled unsaved drafts produce no Google request. A saved
event can still be processed while its editor is open; the event must sync first.

Requests are persisted before replying to the extension, including the stable
conference creation request ID. The actual target IDs are persisted before PATCH,
so a lost HTTP response or app restart resumes the same event and request rather
than generating another conference. Failed async creation requires selecting a
new request. Requests expire after 24 hours; this bounds scans for abandoned drafts.
No polling runs without pending requests. Quitting delays work until app relaunch.

Google event updates use sendUpdates=all so invitees receive the real conference.
Ordinary invitation/update mail can therefore occur. No blanket suppression of
security or invitation messages is attempted. The app avoids inserting an external
Meet code, the documented trigger for Google's special code-replacement behavior.

Replacement of the provisional UI depends on Google/Apple account sync; it was
verified on the test Mac. HTTPS conferences still showed Open in that test. The public EventKit callback still provides no
event context, so the explicit persisted marker is necessary for safe association.

## References

- [Google Events PATCH](https://developers.google.com/workspace/calendar/api/v3/reference/events/patch)
- [Google conference creation](https://developers.google.com/workspace/calendar/api/guides/create-events#conferencing)
- [Google event search](https://developers.google.com/workspace/calendar/api/v3/reference/events/list)
- [Google meeting-code replacement behavior](https://support.google.com/calendar/answer/16876004)
- [Apple virtual conference providers](https://developer.apple.com/documentation/eventkit/implementing-a-virtual-conference-extension)
