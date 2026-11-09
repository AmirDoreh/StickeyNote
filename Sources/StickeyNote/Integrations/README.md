# Native integrations

The Swift package runs the native editor without network setup. iCloud and widget
distribution require provisioned Xcode app/extension targets. Nothing here uploads
notes until the user enables iCloud sync.

## CloudKit and browser interoperability

Use the Apple Developer container `iCloud.com.stickeynote.app` in both native app
targets and in CloudKit JS. Enable the iCloud **CloudKit** capability, select that
container, and provision both app IDs. Set the app Info.plist Boolean
`StickeyCloudKitEnabled` to `true` for provisioned builds. The service intentionally
declines to create a CKContainer in the unsigned Swift-package preview.

`CloudKitSyncService.start(store:)` checks the signed-in Apple account, pulls the
private database, merges note revisions, and observes further edits. `syncNow()`
provides manual refresh; `stop()` disables future sync. Changes are coalesced for
1.2 seconds and remote changes are checked every 30 seconds while running.

The first account connection binds the local workspace to that Apple user record
ID. Native account-change notifications pause sync immediately; both clients check
the identity before reading, merging, and uploading. A different account is blocked
even after relaunch, leaving local notes intact. Sign back into the original account
to resume. Moving to another account requires an explicitly new workspace after
exporting a backup; there is no silent cross-account migration or account reset UI.

Create this CloudKit schema in the development environment, then deploy it to
production before a release:

| Item | Value |
| --- | --- |
| Database | Private |
| Record type | `StickeyWorkspace` |
| Record name | `device-<persistent UUID>` |
| `archive` | String: JSON manifest described below (legacy whole archives also read) |
| `modifiedAt` | Date/Time |
| `deviceName` | String |
| Index | `recordName` QUERYABLE (for all-record queries) |

Also create `StickeyWorkspaceChunk` with one `archive` String field. It needs no
query index because chunks are fetched directly by deterministic record names.
Both types remain in the private database, using the same schema on all platforms.

Archive version is `1`. Dates are milliseconds since the Unix epoch. UUIDs are
strings. Binary values are base64 strings. The app preserves deletion tombstones
and merges notes by ID and `updatedAt`. Protected notes export only their encrypted
payload; their `content` and `history` are empty even while unlocked in the editor.
Groups also retain modification/deletion metadata when supported by the core codec.

Each device owns one manifest, so simultaneous offline devices do not overwrite
each other's archive. Every pull is paginated. Writes use optimistic concurrency
checks; conflicts retry on the next sync. The app caches decoded archives by change
tag, so unchanged polls fetch small manifests without downloading all note data.

The native and browser clients split JSON UTF-8 bytes into 360,000-byte pieces and
base64-encode each piece. Each chunk's `archive` field is JSON with `chunkVersion:1`,
`deviceID`, `generation` (UUID), `index` (zero-based), `count`, and `payload` (base64).
Chunk names are `device-<deviceID>-<generation>-<index>`. Encoded chunks remain under
500 KB, allowing workspaces much larger than CloudKit's per-record size limit.

After every chunk is saved successfully, the client commits the workspace manifest
as `{chunkVersion:1,deviceID,current,previous?}`. Each generation descriptor contains
`generation`, `count`, `byteCount`, lowercase hexadecimal `sha256`, and `committedAt`
(milliseconds). Readers verify chunk metadata, total bytes, and SHA-256 before
merging. If the current generation is incomplete, readers can use the previous
verified generation. The previous generation is pruned on the next successful
commit. Interrupted uploads cannot replace a committed archive; a process crash
can leave unreferenced chunks, which may require storage cleanup in CloudKit.

Password protection triggers a privacy pass on other device archives. It removes
obsolete plaintext copies and does not retain a previous plaintext generation.
Chunk cleanup is best effort when connectivity is interrupted. Exported backups
and offline-device files cannot be retroactively erased by another device.
The codec retains its 100 MB defensive archive-import bound; cloud storage has no
additional per-workspace cap below that bound. Actual capacity depends on iCloud
storage and device resources.

Run `node --test Web/cloud.test.mjs` for sync/atomicity/privacy tests and
`node Tests/CloudInterop/verify.mjs` on a Mac with Xcode for a two-way Swift/JavaScript
Unicode archive compatibility check.

For the web app, configure a CloudKit JS API token restricted to the deployed web
origin and its sign-in redirect URL. Use the same container and the matching
development/production environment. The API token identifies the app; the user
must still sign in with their Apple account to access their private database.
No Apple credentials or server keys belong in source control.

## Widgets

Create a Widget Extension for iOS/iPadOS and macOS with deployment targets iOS 17
and macOS 14. Compile both:

- `Widgets/StickeyNoteWidget.swift`
- `Sources/StickeyNote/Integrations/WidgetSnapshot.swift`

Use `Widgets/Info.plist`. Add the App Group `group.com.stickeynote.app` to the app
and widget targets; the example widget entitlements file contains this group.
The macOS extension additionally needs the App Sandbox capability when distributed.
Embed the matching widget extension in each application target.

Call `WidgetSnapshotWriter.update(notes:)` when notes change. Debounce typing, but
refresh immediately after password protection or deletion to remove previews.
Protected notes are excluded even if currently unlocked. Widget data contains only
limited text/checklist/drawing previews, not history or encryption keys. Register
the URL scheme `stickeynote`; widgets open `stickeynote://note/<UUID>`.

The extension offers small, medium, and large widgets with an AppIntent note picker.
Small widgets also appear in CarPlay on iOS 26; no dedicated CarPlay app entitlement
is required. Validate layout in StandBy/CarPlay because those contexts remove the
widget background. A dedicated CarPlay app is a separate Apple-approved capability.

## Camera, biometrics, QR, and floating notes

- `QRCodeView(text:)` generates QR codes locally, including an export-safe quiet
  zone; native Share and PNG export are available.
- `ScanCodeView(onScan:)` reads imported images with Vision on both platforms and
  offers VisionKit camera scanning on supported iPhones/iPads. Add
  `NSCameraUsageDescription` to the iOS Info.plist. Scanned URLs are previewed and
  only HTTP/HTTPS links can be opened through the scan UI.
- New native locks use `AppleNoteSecurity`: `LAContext.evaluatePolicy` with
  `deviceOwnerAuthentication` presents Apple's real system prompt with biometrics
  and device password/passcode fallback. Add `NSFaceIDUsageDescription` on iOS.
  A fresh authenticated context retrieves a random credential from a device-only
  Keychain item protected by `userPresence`; the system password never enters the
  app. Public credential IDs survive backups/sync, but the secret does not.
  `BiometricNoteKeys` remains for existing PIN/password locks only.
  Capture the store's security generation before the prompt so backgrounding,
  closing the note, or relocking invalidates a late result. Temporary inactivity
  caused by the system prompt conceals note UI without cancelling the prompt;
  actual background/sleep and post-prompt focus loss cancel pending work.
- On macOS, configure `FloatingNoteWindows.shared` with the shared store and call
  `pin(noteID)` to open a compact independent NSPanel. Notes remain on the desktop
  after the main board closes, with menu-bar access for new notes and show/hide.
  Each panel edits the original note, persists its position/size/topmost setting,
  and restores after relaunch. Unpinning preserves the note. Protected panels lock
  after the configured auto-lock interval (two minutes by default), when the app
  backgrounds, or when the display sleeps; deletion removes the desktop window.
  Switching between the app's own windows does not reset the timer. The app stays resident until
  Quit, which waits for saves before exiting. Sync and widget updates retain app-
  lifetime ownership, including while only desktop notes are open.
