## 1.5.6
- Confined AppArmor policy only (`networking`, `content_exchange`,
  `content_exchange_source`). The click no longer declares `read_path` /
  `write_path`, so OpenStore publishes it without a manual review. A confined
  Ubuntu Touch app cannot write into `~/Downloads` or read `~/Documents`
  directly; Content Hub is the supported way to reach shared folders.
- Received files are staged in LocalSend's private storage. "Save received
  files" opens the Content Hub destination picker: choose File Manager and
  `Downloads/LocalSend` (or any folder) to move them there.
- Fixed the save flow: the files are handed to File Manager only after it has
  accepted the Content Hub transfer. Previously they were charged immediately,
  the Content Hub silently discarded that early hand-over and File Manager was
  left with nothing to save.
- Pick `.click` / `.apk` packages through Content Hub ("Open" in the app
  picker); the automatic list covers LocalSend's own storage.
- Settings: the receive folder row explains that shared folders are chosen in
  File Manager after a transfer.
- Store release notes no longer show the package architecture.

## 1.5.5
- The empty bar above the tab content is gone for real: Lomiri draws its
  default (empty) page header when a page sets `header: null`, so the shell
  and the tabs now use a zero-height header.
- Receive: the device name is drawn like the Android app (one line, 48px,
  shrunk to fit instead of being cut off) and the "receive via link" button
  sits at the bottom of the page.
- Settings: the title is centred and no longer bold, matching the Android tab.
- Fix the device card trailing buttons using an unchecked theme lookup.

## 1.5.4
- The AppArmor hook no longer declares read_path / write_path. Those fields are
  click-review redflags, the OpenStore rejects them (HTTP 400) and the manual
  install of 1.5.3 failed because of them.
- Received files are written into the app data folder and exported to the
  download folder through the content hub: one save request per transfer
  instead of one per file.
- The settings row shows the folder files really land in; folders the app may
  not write into are rejected by the picker.
- The content hub module is only used when it exists; a failed export keeps
  the file in the app folder.

## 1.5.3
- Receive straight into ~/Downloads/LocalSend: the AppArmor profile granted
  read access to the home folder and write access to Downloads again. Reverted
  in 1.5.4, the OpenStore refuses those fields.
- App picker: the device is searched in two phases (receive folder and
  downloads first), caches are skipped, results show format/size/folder and a
  manual refresh is available.
- Settings shows the folder files actually land in; a configured destination
  is used before the default.
- No empty header bar above the tabs; the device name is no longer cut off.

## 1.5.2
- Fix the top and bottom bar: the system panel area stays free and the navigation is no longer cut off.
- Random device name on first start instead of "LocalSend".
- App picker: search the whole storage for `.click`/`.apk` files, with a filter.
- Nearby devices: live model and type, favorites no longer duplicated.
- Received files are handed to the content hub, so they land in the download folder.

## 1.5.1
- Fix receiving into ~/Downloads (AppArmor write access) with a writable fallback.
- Fix the Lomiri title bar covering the UI.
- Add a folder picker for the receive folder and for sending folders.
- Send: files, folders, text, apps, manual IP, live progress.
- Receive: accept/decline, quick save, PIN, history, receive via link.

## 1.5.0
- QML frontend on the shared Rust core, no Flutter runtime.
- Settings: theme, color, all bundled languages (live switch, RTL).

## 1.4.x
- QML polish and locale optimization.
- Crash fix when the network adapter changes.
- Window lifecycle and background processing fixes.
- Web Receive: QR codes, copy buttons, HTTPS, PIN.