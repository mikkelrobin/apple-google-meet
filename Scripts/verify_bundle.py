#!/usr/bin/env python3
import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1]); preview = sys.argv[2] == 'preview'
ext = app / 'Contents/PlugIns/MeetConference.appex'
for bundle in (app, ext):
    info = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    assert info['CMPreview'] == preview
    assert info['LSMinimumSystemVersion'] == '13.0'
    executable = bundle/'Contents/MacOS'/info['CFBundleExecutable']
    arches = subprocess.check_output(['lipo', '-archs', str(executable)], text=True)
    assert 'arm64' in arches and 'x86_64' in arches
    assert (bundle/'Contents/Resources/AppIcon.icns').stat().st_size > 1000
    entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL))
    assert entitlements['com.apple.security.app-sandbox']
    assert entitlements['com.apple.security.network.client']
    assert 'com.apple.security.application-groups' not in entitlements
    assert 'keychain-access-groups' not in entitlements
info=plistlib.loads((ext/'Contents/Info.plist').read_bytes())
assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.calendar.virtualconference'
assert info['NSExtension']['NSExtensionPrincipalClass'] == 'MeetConference.VirtualConferenceProvider'
print('Bundle metadata, architectures, sandbox, icons and signing mode verified.')
