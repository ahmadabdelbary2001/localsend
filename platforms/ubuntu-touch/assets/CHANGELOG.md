## 1.5.1
- Fix receiving into ~/Downloads (AppArmor write access) with a writable fallback.
- Fix the Lomiri title bar covering the UI.
- Add a folder picker for the receive folder and for sending folders.
- Add an app picker (`.click`/APK) and a per-file list with thumbnails and remove buttons.

## 1.5.0
- QML frontend on the shared Rust core, no Flutter runtime.
- Send: files, folders, text, apps, manual IP, live progress.
- Receive: accept/decline, quick save, PIN, history, receive via link.
- Settings: theme, color, all bundled languages (live switch, RTL).
- Fixes: dialog placement, back navigation, header overlap, locale switching.

## 1.4.x
- QML polish and locale optimization.
- Crash fix when the network adapter changes.
- Window lifecycle and background processing fixes.
- Web Receive: QR codes, copy buttons, HTTPS, PIN.