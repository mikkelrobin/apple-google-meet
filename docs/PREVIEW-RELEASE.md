Calendar Meet 0.4.1 — direct Google Calendar conferences, macOS 13+, Intel and Apple Silicon.

The manual Apple Calendar picker creates a pending request. Once saved and synced,
Meet is created on the exact existing Google event via conferenceData, not via a
separate Meet space. No duplicate event is inserted. Reconnect for Calendar access
and enable Google Calendar API. Normal invitation updates remain enabled.

Menu-bar only, original icon, no Dock icon, launch at login default on, right-click
Quit. Generic CI installer needs the team's Desktop OAuth configuration imported.
The local team installer includes that configuration, never user tokens.

Ad-hoc signed preview; Developer ID signing and notarization require Apple credentials.
See docs/VERIFICATION.md for real test results and remaining limits.

Monochrome menu-bar video symbol with green/red authentication dot. Sign Out
removes local login, cancels in-flight work and clears queued account requests.
The original app icon and existing Calendar/Meet events are preserved.
