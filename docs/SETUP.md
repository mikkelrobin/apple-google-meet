# Setup

## Google Cloud — once for the team

1. Create a project at [Google Cloud Console](https://console.cloud.google.com/).
2. Enable **Google Meet REST API** (`meet.googleapis.com`).
3. In **Google Auth Platform**, configure branding, support contact and audience.
   Choose **Internal** if all users belong to your Workspace organization and your
   project supports that audience; otherwise choose **External**.
4. Add just this scope to Data Access:
   `https://www.googleapis.com/auth/meetings.space.created`.
5. Create a client under **Clients → Create client → Desktop app**. Download its JSON.
   A Web client, API key or service account JSON will not work.
6. For External / Testing, add each colleague as a test user. Testing refresh
   tokens usually expire after seven days for this scope. For lasting external
   distribution, publish the consent app and complete Google's verification as
   required for this sensitive scope. Internal apps can still require your
   Workspace administrator's approval. Account eligibility and organization
   policies may restrict Meet API access.
7. In a **signed build**, import that JSON and choose Connect Google. Each person
   authorizes their own account. Never distribute access or refresh tokens.

The Desktop client ID and its desktop client secret identify a public installed
client; they are not a server secret. PKCE is mandatory in this app. You can ship
one client in the signed app using `GOOGLE_CLIENT_JSON=/absolute/path/client.json`
when building; then colleagues only see Connect Google. Keep any other secrets,
service account credentials and tokens out of the repository and build assets.

## Apple signing — required for the secure shared login

The public EventKit APIs support macOS 12+. This app targets macOS 13+ for its
SwiftUI setup UI. Both targets are sandboxed. The app and extension share tokens
in the **Data Protection Keychain**, using this registered App Group:

`group.com.mikkelrobin.CalendarMeet`

Register the following explicit App IDs in your Apple Developer team:

- `com.mikkelrobin.CalendarMeet`
- `com.mikkelrobin.CalendarMeet.Conference`

Enable App Groups on both and assign the same group above. Create **Developer
ID provisioning profiles** for both IDs that authorize the group. Install a
**Developer ID Application** certificate with its private key. An ordinary Apple
Development certificate is not suitable for distributing to colleagues.

Build using the macOS SDK / Command Line Tools (Swift 5.7+; current Xcode or CLT
recommended). Do not change the shared group in only one target.

```sh
MODE=signed TEAM_ID=YOURTEAMID \
SIGN_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)' \
APP_PROFILE=/absolute/path/App.provisionprofile \
EXT_PROFILE=/absolute/path/Extension.provisionprofile \
GOOGLE_CLIENT_JSON=/absolute/path/client.json \
bash Scripts/build.sh
```

Create a notarytool Keychain credential profile locally using Apple's documented
`notarytool store-credentials` flow, then package:

```sh
MODE=signed SIGN_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)' \
NOTARY_PROFILE=CalendarMeetNotary bash Scripts/package.sh
```

The packaging script requires Accepted notarization, staples the DMG ticket and
runs Gatekeeper assessment. Do not label a build notarized before these pass.
Provisioning profiles are embedded locally into both bundles, never committed.

### GitHub Actions signed release

Set repository secrets: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`,
`APPLE_TEAM_ID`, `APPLE_SIGN_IDENTITY`, `APP_PROFILE_BASE64`, `EXT_PROFILE_BASE64`,
`APPLE_ID`, `APPLE_APP_PASSWORD`. An app-specific password is for Apple's
notarization service; do not use your regular Apple password.

Optional `GOOGLE_CLIENT_JSON_BASE64` bundles the Desktop OAuth client. Use the
**Signed release** workflow manually after secrets are set. It creates a temporary
Keychain, builds and tests universal binaries, notarizes the DMG, then publishes a
release. No certificates or tokens are written to logs or repository files.

## Unsigned preview

```sh
bash Scripts/test.sh
bash Scripts/build.sh
bash Scripts/package.sh
```

Default mode is `preview`: binaries have an ad-hoc integrity signature (needed on
Apple Silicon) but **no trusted Developer ID signature and no notarization**.
Protected App Group entitlements are deliberately absent, and Google login is
disabled. This avoids pretending a distributable secure login can work without
Apple credentials. The preview can demonstrate setup and the extension's room
listing, subject to macOS allowing local development extensions. Do not share
it as a ready-to-use team release. No insecure plaintext-token fallback exists.

## Troubleshooting and limits

- No Google Meet in Calendar: install in Applications, launch once, enable the
  extension in System Settings, fully quit/reopen Calendar. Use
  `pluginkit -m -v -i com.mikkelrobin.CalendarMeet.Conference` to inspect discovery.
  Paths/extension UI differ between macOS versions. Registration alone is not
  proof that Calendar executed a conference callback.
- Keychain error `-34018`: shared entitlement/provisioning is missing. Check both
  profiles and the signing team. Preview login is intentionally disabled.
- HTTP 403: enable Meet REST API, check consent/test users and Workspace policy.
- Revoked/expired login: use Reconnect Google. No network POSTs are automatically
  retried, to avoid accidentally creating duplicate spaces.
- Removing a link or cancelling a Calendar edit does not delete the already
  created Meet space. EventKit provides a room identifier, **not event dates,
  attendees or a cancellation callback**. Each selection creates a new space;
  recurrence uses the link stored by Calendar. This app does not manage the
  lifecycle of an existing Google Calendar conference.
- The selected calendar must allow event editing. Google Calendar server sync,
  recurrence, invitations and non-Apple clients need a real-account manual test.
- Disconnect → Remove local login only clears this app's Keychain entry. Use
  Revoke Google access and disconnect to revoke at Google as well; network
  failures are reported and do not silently claim success.

## Verification before team release

On a signed, provisioned build: import the Desktop client, connect, create a test
meeting, close the app, select Google Meet inside Calendar, save the event, reopen
it and join the returned link. Confirm invitations on a colleague's device.
Repeat after access-token expiry, revoked consent, offline mode and reconnect.
Check that cancelling browser login returns promptly. Test both supported CPU
architectures on actual Macs. Until this checklist passes, a build is a preview.
