#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if (( $# < 1 || $# > 2 )); then
    print -u2 "Usage: $0 <archive|submit|package> [version, default 1.0.0]"
    exit 2
fi
STICKEY_RELEASE_STAGE="$1"
STICKEY_RELEASE_VERSION="${2:-1.0.0}"
if [[ ! "$STICKEY_RELEASE_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "Version must have the form 1.0.0."
    exit 2
fi
case "$STICKEY_RELEASE_STAGE" in
    archive|submit|package) ;;
    *) print -u2 "Unknown stage: $STICKEY_RELEASE_STAGE"; exit 2 ;;
esac

STICKEY_RELEASE_ROOT="$PWD/build/release-v$STICKEY_RELEASE_VERSION"
STICKEY_RELEASE_ARCHIVE="$STICKEY_RELEASE_ROOT/StickeyNote.xcarchive"
STICKEY_RELEASE_OPTIONS="$PWD/Config/Mac-ExportOptions.plist"
STICKEY_RELEASE_TEAM=$(python3 - "$STICKEY_RELEASE_OPTIONS" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as file:
    options = plistlib.load(file)
for key, expected in {'method': 'developer-id', 'destination': 'upload', 'signingStyle': 'automatic'}.items():
    if options.get(key) != expected:
        sys.exit(f'Export options must set {key}={expected}.')
if options.get('teamID') != '8ZA2YW2U9D':
    sys.exit('Release signing must preserve team 8ZA2YW2U9D and its note Keychain access.')
print(options['teamID'])
PY
)
mkdir -p "$STICKEY_RELEASE_ROOT"

if [[ "$STICKEY_RELEASE_STAGE" == archive ]]; then
    if [[ -e "$STICKEY_RELEASE_ARCHIVE" ]]; then
        print -u2 "Archive already exists: $STICKEY_RELEASE_ARCHIVE"
        print -u2 "Use submit to continue, or move the archive aside before rebuilding."
        exit 1
    fi
    xcodebuild -project StickeyNote.xcodeproj -scheme StickeyNotePreview \
        -configuration Release -destination 'generic/platform=macOS' \
        -derivedDataPath "$PWD/build/mac-release" \
        -archivePath "$STICKEY_RELEASE_ARCHIVE" -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$STICKEY_RELEASE_TEAM" \
        MARKETING_VERSION="$STICKEY_RELEASE_VERSION" \
        ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME=YES archive
    print "Archived $STICKEY_RELEASE_ARCHIVE"
    print "Next: zsh scripts/release-mac.sh submit $STICKEY_RELEASE_VERSION"
    exit 0
fi

if [[ ! -d "$STICKEY_RELEASE_ARCHIVE" ]]; then
    print -u2 "Missing archive: $STICKEY_RELEASE_ARCHIVE"
    exit 1
fi
# Refuse to submit or package an archive with a different version or app identity.
python3 - "$STICKEY_RELEASE_ARCHIVE" "$STICKEY_RELEASE_VERSION" <<'PY'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
apps = list((root / 'Products/Applications').glob('*.app'))
if len(apps) != 1:
    sys.exit('Expected exactly one application in the archive.')
with (apps[0] / 'Contents/Info.plist').open('rb') as file:
    info = plistlib.load(file)
if info.get('CFBundleShortVersionString') != sys.argv[2]:
    sys.exit('Archive version does not match the requested release.')
if info.get('CFBundleIdentifier') != 'com.stickeynote.app.preview':
    sys.exit('Archive must preserve the existing Mac app bundle identifier.')
PY

if [[ "$STICKEY_RELEASE_STAGE" == submit ]]; then
    print "Submitting to Apple for Developer ID signing and notarization using the Xcode account."
    xcodebuild -exportArchive -archivePath "$STICKEY_RELEASE_ARCHIVE" \
        -exportOptionsPlist "$STICKEY_RELEASE_OPTIONS" \
        -exportPath "$STICKEY_RELEASE_ROOT/submission" -allowProvisioningUpdates
    print "After Apple accepts notarization, run: zsh scripts/release-mac.sh package $STICKEY_RELEASE_VERSION"
    exit 0
fi

STICKEY_RELEASE_ZIP="Stickey-Notes-v$STICKEY_RELEASE_VERSION-macOS-universal.zip"
if [[ -e "$STICKEY_RELEASE_ROOT/$STICKEY_RELEASE_ZIP" || -e "$STICKEY_RELEASE_ROOT/SHA256SUMS.txt" ]]; then
    print -u2 "Release assets already exist. Move them aside before packaging again."
    exit 1
fi
STICKEY_RELEASE_STAGING=$(mktemp -d "$STICKEY_RELEASE_ROOT/package.XXXXXX")
trap 'rm -rf "$STICKEY_RELEASE_STAGING"' EXIT
# This command only exports an archive whose Apple notarization has succeeded.
if ! xcodebuild -exportNotarizedApp -archivePath "$STICKEY_RELEASE_ARCHIVE" \
    -exportPath "$STICKEY_RELEASE_STAGING/export"; then
    print -u2 "Notarized export failed. Check the archive in Xcode Organizer; retry package after Apple accepts it."
    exit 1
fi
STICKEY_RELEASE_APP="$STICKEY_RELEASE_STAGING/export/Stickey Notes.app"
python3 scripts/verify-mac-release.py "$STICKEY_RELEASE_APP" "$STICKEY_RELEASE_VERSION"
ditto -c -k --sequesterRsrc --keepParent "$STICKEY_RELEASE_APP" "$STICKEY_RELEASE_STAGING/$STICKEY_RELEASE_ZIP"
(
    cd "$STICKEY_RELEASE_STAGING"
    shasum -a 256 "$STICKEY_RELEASE_ZIP" > SHA256SUMS.txt
)
mv "$STICKEY_RELEASE_STAGING/$STICKEY_RELEASE_ZIP" "$STICKEY_RELEASE_ROOT/$STICKEY_RELEASE_ZIP"
mv "$STICKEY_RELEASE_STAGING/SHA256SUMS.txt" "$STICKEY_RELEASE_ROOT/SHA256SUMS.txt"
print "Verified release assets:"
print "$STICKEY_RELEASE_ROOT/$STICKEY_RELEASE_ZIP"
print "$STICKEY_RELEASE_ROOT/SHA256SUMS.txt"
