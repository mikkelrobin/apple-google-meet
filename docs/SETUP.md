# Calendar Meet 0.3.0 setup

## Google — once per team

1. In a Google Cloud project owned by your Workspace organization, enable Google
   Meet API (`meet.googleapis.com`). A project named Calendar Meet was created
   under the nanoping.com organization during this setup.
2. Configure Google Auth Platform branding and **Internal** audience for colleagues
   in that same Workspace organization. This is a project-level configuration.
3. Use only `https://www.googleapis.com/auth/meetings.space.created`.
4. Create a **Desktop app** OAuth client, name it Calendar Meet macOS, and download
   the JSON. A Web client or service account file will not work.
5. Bundle that Desktop client during a local build with `GOOGLE_CLIENT_JSON`, or
   import it in the app. Each person connects their own account. Never bundle or
   distribute an access token, refresh token or service-account private key.
6. Workspace administrators may need to approve the client for Meet access.

External projects can be used for testing with explicit test users, but testing
refresh tokens commonly expire after seven days for this scope. External production
distribution may require Google verification. Internal organizational use avoids
that external verification route, subject to Workspace policy.

The Desktop client secret is part of a public installed client, not a server
secret. PKCE protects each login. Client exports stay out of this public source
repository. The user-supplied client is kept in local ignored Configuration/.

## Install and use without Apple membership

Build or download an explicitly labelled unsigned preview. Drag the app into
Applications, open it, click its menu-bar icon, and use Sign in with Google. If macOS blocks this specific app,
review it and use the per-app approval flow in Privacy & Security if appropriate.
No global Gatekeeper changes or removal of quarantine are needed by the app.
Managed-device policies may prohibit this entirely.

Enable its extension if requested in System Settings. Fully quit and reopen
Calendar, then choose Google Meet in Add Location or Video Call. The containing
app opens in the background, creates the meeting, and returns its URL automatically.
There is no confirmation or copy/paste step. The bridge has a 55-second timeout;
Calendar may impose its own earlier deadline.

Launch at Login defaults on. Click the menu-bar icon to reconnect or toggle it;
right-click for Quit. The app has no Dock icon. It can be quit between uses. No shared Keychain or App Group is involved.
The app alone stores credentials in the classic macOS login Keychain (ACL based),
and only returns the finished URL or error to the waiting extension. Ad-hoc signed
updates may cause Keychain access prompts because the code identity changes. Never
select an option that grants all applications access to the Keychain item.

A deep-link request does not authenticate its originating application. The user
explicitly chose automatic meeting creation without a per-request dialog. Other
local software can request creation of a new Meet space using this integration;
it cannot retrieve OAuth credentials or request arbitrary Google operations.
Callbacks must be live and bound to IPv4 loopback, requests are deduplicated, and
HTTP redirects are refused. This is an intentional tradeoff for automatic use.

## Optional trusted distribution

Apple Developer ID membership is only needed if you want Developer ID signing
and notarization. No App Group, restricted Keychain entitlement or provisioning
profiles are needed for the 0.2 architecture.

```sh
MODE=signed TEAM_ID=YOURTEAMID \
SIGN_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)' \
GOOGLE_CLIENT_JSON=/absolute/path/DesktopClient.json bash Scripts/build.sh
MODE=signed SIGN_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)' \
NOTARY_PROFILE=CalendarMeetNotary bash Scripts/package.sh
```

The optional signed workflow uses repository secrets APPLE_CERTIFICATE_P12_BASE64,
APPLE_CERTIFICATE_PASSWORD, APPLE_TEAM_ID, APPLE_SIGN_IDENTITY, APPLE_ID and
APPLE_APP_PASSWORD; GOOGLE_CLIENT_JSON_BASE64 is optional. Use a notarization
app-specific password, not a normal Apple password. Signed packaging requires
Accepted notarization and staples the DMG. The first signed release is a draft
until real-account tests have passed.

## Troubleshooting and release checklist

- Missing menu option: open the installed app once, enable its extension, restart
  Calendar. Inspect `pluginkit -m -v -i com.mikkelrobin.CalendarMeet.Conference`.
  Discovery is not proof of a live Calendar callback. See VERIFICATION.md.
- OAuth permission: Google client must be Desktop, account must belong to Internal
  organization, Meet API must be enabled; check admin app access policy on 403.
- Keychain: unlock login Keychain and authorize this app only if prompted.
- Timeout: select Google Meet again. Delayed callbacks are ignored. A space may
  already have been created if Google's response was lost; POST is not retried.
- Cancel or remove a Calendar event: an already created Meet space is not deleted.
  EventKit supplies a room type, not event dates/attendees or a cancellation hook.
- To remove access, use your Google Account’s third-party connections settings.
  The minimal app offers reconnect; it no longer exposes disconnect controls.
- Before sharing widely, test actual Calendar insertion, save/reopen, invitations,
  recurrence and joining on a colleague's device. Test Intel and oldest supported
  macOS on real hardware. No attendees are added by the app itself.
