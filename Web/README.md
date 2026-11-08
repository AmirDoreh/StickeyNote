# StickeyNote for the web

A private, offline-capable notes workspace. Native ES modules and browser APIs keep startup small; no framework, package installation, analytics, or backend is required for local use. Fonts and QR libraries ship with the app.

## Run locally

Use Node 20+ for the build/tests and Python 3 for the preview server:

```sh
npm test
npm run build
python3 -m http.server 5173 --directory dist
```

Open http://127.0.0.1:5173. Serve the built `dist` directory over HTTPS in production. HTTPS or localhost is required for password encryption, the clipboard, and the service worker. The web app can be installed using your browser’s install/Add to Home Screen action.

## Features

Notes and checklists, autosave, groups, search, sort, pins, recoverable trash, 25 colors, 16 font choices, rich text, drawing over note text, eraser/undo/PNG export, version history, password encryption, note-to-QR export, QR/image scanning, and full backup import/export. QR image scanning works offline through the bundled jsQR library. Other barcode formats use the browser’s `BarcodeDetector` where available.

Keyboard shortcuts: Command/Control N for a note, T for a checklist, K/F for search. In checklists, Enter adds a row, Command/Control Enter checks it, and Command/Control Up/Down reorders it. Some browsers reserve new-tab/new-window shortcuts; the visible controls always work.

## iCloud setup

Local notes work immediately. Live iCloud sync needs an Apple Developer-owned CloudKit container with the same identifier and schema as the native apps. Configure `window.STICKEY_CLOUD_CONFIG` in `config.js` with the **public web API token**, `containerIdentifier`, and `environment` (`development` or `production`). Configure the hosting origin in CloudKit Console. Never put a server private key in browser code.

```js
window.STICKEY_CLOUD_CONFIG = {
  containerIdentifier: 'iCloud.com.stickeynote.app',
  apiToken: 'YOUR_PUBLIC_CLOUDKIT_WEB_TOKEN',
  environment: 'production'
};
```

The Settings dialog renders Apple’s sign-in buttons. Data syncs to the signed-in account’s private database. `cloud.js` and `cloud-archive.js` implement the shared native archive format and chunked transport. Until the real container, schema, entitlement, and domain configuration is complete, the UI accurately reports that notes are local. See the main project’s setup guide for the native provisioning steps.

## Data and privacy

Browser storage keeps an atomic primary archive and a recovery copy. Export backups periodically, especially before clearing browser data. Storage quota or disabled storage errors are surfaced. Very large workspaces remain limited by the browser’s storage quota.

Protected content and its history use PBKDF2-HMAC-SHA256 (600,000 iterations) and AES-256-GCM, interoperable with the native Swift app. Decrypted content stays in memory while unlocked and is cleared when the page goes into the background. Passwords are never stored; there is no password recovery. Exported backups retain encrypted envelopes. Copying, QR sharing, and exporting individual unlocked notes intentionally produce readable content.

Imports validate before applying and merge by identity, protection revision, edit time, and revision identifier. Deletions remain recoverable. The data schema is versioned; ordinary note data is not uploaded anywhere until the user connects iCloud or explicitly shares/exports it.

## Verify

`npm test` checks persistence, corruption recovery, encryption interoperability, lock/unlock races, history, deletion and revision merging, and mock CloudKit transport. Live Apple authentication and multi-device sync require the configured production container and real account/device testing.

## Third-party components

`vendor/qrcode.js`: qrcode-generator 1.4.4, copyright Kazuhiko Arase, MIT license. `vendor/jsqr.js`: jsQR 1.4.0, Apache-2.0. DM Sans and Manrope fonts: SIL Open Font License. Licenses are included in `vendor/`. No CDN is used for these assets at runtime; Apple’s official CloudKit SDK loads only when iCloud is connected.
