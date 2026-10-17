## 1.3.2
- Selection bar on Send page: pick File, Media, or compose a Text message.
- ContentPeerPicker integration for selecting source app (File Manager / Gallery).
- Dynamic dialog loading and QRC registration to ensure robust startup.

## 1.3.1
- PIN dialog for receivers protected by a PIN (matches Dart's
  pin_dialog.dart).
- Distinct final statuses: receiver declined, receiver busy, too many
  attempts, canceled by sender.
- Retry of 1.3.0 publish after OpenStore returned HTTP 500 on upload.

## 1.3.0
- Complete send flow: file selection via Content Hub, per-file status,
  explicit error on unreadable files.
- Sender identity (alias, port, https) now read from Settings, not
  hardcoded.
- Session outcome reflects per-file failures and receiver rejections.
- Send progress dialog: session status header, per-file icons, error
  details dialog.
- Send page clears selection after dispatch; shows "N files ready".

## 1.0.0 (2022-12-29)

- Initial Release