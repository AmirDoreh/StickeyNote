#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Apple-authenticated Keychain items require a provisioned signature. The preview
# target keeps the local app identity/storage, without iCloud, widgets, or sandboxing.
STICKEY_PREVIEW_DERIVED_DATA="$PWD/build/mac-preview"
xcodebuild -project StickeyNote.xcodeproj -scheme StickeyNotePreview \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$STICKEY_PREVIEW_DERIVED_DATA" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration "$@" build

STICKEY_PREVIEW_BUILT_APP="$STICKEY_PREVIEW_DERIVED_DATA/Build/Products/Release/Stickey Notes.app"
if [[ ! -f "$STICKEY_PREVIEW_BUILT_APP/Contents/embedded.provisionprofile" ]]; then
    print -u2 "The Mac preview needs an Apple development provisioning profile for note locking. Check Signing & Capabilities for StickeyNotePreview in Xcode."
    exit 1
fi
codesign --verify --deep --strict "$STICKEY_PREVIEW_BUILT_APP"

STICKEY_PREVIEW_STAGING=$(mktemp -d "$PWD/build/stickey-preview.XXXXXX")
trap 'rm -rf "$STICKEY_PREVIEW_STAGING"' EXIT
ditto "$STICKEY_PREVIEW_BUILT_APP" "$STICKEY_PREVIEW_STAGING/Stickey Notes.app"
codesign --verify --deep --strict "$STICKEY_PREVIEW_STAGING/Stickey Notes.app"
rm -rf "build/Stickey Notes.app"
mv "$STICKEY_PREVIEW_STAGING/Stickey Notes.app" "build/Stickey Notes.app"
print "Built $PWD/build/Stickey Notes.app with Apple Keychain access"
