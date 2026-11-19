#!/usr/bin/env python3
"""Generate bundle metadata and entitlements for the selected signing mode."""
import os, pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1]); preview = sys.argv[2] == 'preview'
base = dict(CFBundleDevelopmentRegion='en', CFBundleInfoDictionaryVersion='6.0',
            CFBundleShortVersionString='0.3.0', CFBundleVersion='3',
            LSMinimumSystemVersion='13.0', CMPreview=preview,
            NSHumanReadableCopyright='Copyright © 2026 Mikkel Robin. MIT License.')
for name, identifier, executable, package in [
    ('App', 'com.mikkelrobin.CalendarMeet', 'CalendarMeet', 'APPL'),
    ('Extension', 'com.mikkelrobin.CalendarMeet.Conference', 'MeetConference', 'XPC!')]:
    info = dict(base, CFBundleIdentifier=identifier, CFBundleExecutable=executable,
                CFBundleName='Calendar Meet', CFBundleDisplayName='Calendar Meet', CFBundlePackageType=package,
                CFBundleIconFile='AppIcon')
    if name == 'App':
        info['NSPrincipalClass'] = 'NSApplication'
        info['LSUIElement'] = True
        info['CFBundleURLTypes'] = [dict(CFBundleURLName='Calendar Meet conference request', CFBundleURLSchemes=['calendarmeet'])]
        info['NSAppTransportSecurity'] = dict(NSAllowsLocalNetworking=True)
    else:
        info['NSExtension'] = dict(NSExtensionPointIdentifier='com.apple.calendar.virtualconference',
                                  NSExtensionPrincipalClass='MeetConference.VirtualConferenceProvider')
        info['XPCService'] = dict(ServiceType='Application')
    entitlements = {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True}
    entitlements['com.apple.security.network.server'] = True
    if name == 'App':
        entitlements['com.apple.security.files.user-selected.read-only'] = True
    if not preview:
        team = os.environ['TEAM_ID']
        entitlements['com.apple.developer.team-identifier'] = team
    for suffix, data in [('Info', info), ('Entitlements', entitlements)]:
        with (root / f'{name}-{suffix}.plist').open('wb') as file: plistlib.dump(data, file)
