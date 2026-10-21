## 1.5.2
- Empty top bar for the system panel, the app content is no longer covered.
- Random device name on first start instead of "LocalSend".
- App picker: search the whole storage for `.click`/`.apk` files, with a filter.
- Nearby devices: live model and type, favorites no longer duplicated.

## 1.5.1
- Fix receiving into ~/Downloads (AppArmor write access) with a writable fallback.
- Fix the Lomiri title bar covering the UI.
- Add a folder picker for the receive folder and for sending folders.
- Send: files, folders, text, apps, manual IP, live progress.

## 1.5.0
- QML frontend on the shared Rust core, no Flutter runtime.
- Receive: accept/decline, quick save, PIN, history, receive via link.
- Settings: theme, color, all bundled languages (live switch, RTL).

## 1.4.x
- QML polish and locale optimization.
- Crash fix when the network adapter changes.
- Window lifecycle and background processing fixes.
- Web Receive: QR codes, copy buttons, HTTPS, PIN.