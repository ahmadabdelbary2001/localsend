import QtQuick 2.15
import Lomiri.Content 1.1

Item {
    id: root

    visible: false

    property var activeTransfer: null

    signal filesPicked(var paths)
    signal pickCancelled()

    // Ask Content Hub for a source that can provide files.
    ContentPeer {
        id: fileSource

        contentType: ContentType.All
        handler: ContentHandler.Source
        selectionType: ContentTransfer.Multiple
    }

    // Keep imported files in persistent app storage so that Rust can
    // read them after the Content Hub transfer has been finalized.
    ContentStore {
        id: appStore
        scope: ContentScope.App
    }

    ContentTransferHint {
        anchors.fill: parent
        activeTransfer: root.activeTransfer
    }

    function localPathForItem(item) {
        if (!item || !item.url)
            return ""

        var itemUrl = item.url

        // Prefer QUrl's local-file conversion when available.
        try {
            if (typeof itemUrl.toLocalFile === "function") {
                var localPath = itemUrl.toLocalFile()

                if (localPath && localPath.length > 0 &&
                    localPath.charAt(0) === "/") {
                    return localPath
                }
            }
        } catch (error) {
            console.warn(
                "[ContentHubPicker] URL conversion failed"
            )
        }

        // Fall back to decoding an absolute file:// URL.
        var uri = itemUrl.toString()

        if (uri.indexOf("file://") !== 0)
            return ""

        var encodedPath = uri.substring(7)

        if (encodedPath.indexOf("localhost/") === 0)
            encodedPath = encodedPath.substring(9)

        try {
            encodedPath = decodeURIComponent(encodedPath)
        } catch (error) {
            console.warn(
                "[ContentHubPicker] Invalid encoded file URL"
            )
            return ""
        }

        if (encodedPath.length === 0 ||
            encodedPath.charAt(0) !== "/") {
            return ""
        }

        return encodedPath
    }

    Connections {
        target: root.activeTransfer

        function onStateChanged() {
            var transfer = root.activeTransfer

            if (!transfer)
                return

            if (transfer.state === ContentTransfer.Charged) {
                var paths = []
                var items = transfer.items

                // Convert ContentItem URLs to absolute local paths
                // before handing them to the Rust controller.
                for (var i = 0; items && i < items.length; i++) {
                    var path = root.localPathForItem(items[i])

                    if (path.length > 0) {
                        paths.push(path)
                    } else {
                        console.warn(
                            "[ContentHubPicker] Ignoring an item " +
                            "without a usable local file path"
                        )
                    }
                }

                // We have collected the items. Disconnect the active
                // transfer before finalizing it to prevent re-entry.
                transfer.state = ContentTransfer.Collected

                root.activeTransfer = null
                root.visible = false

                // ContentStore.App provides persistent storage for the
                // imported items; finalize can now clean up transfer data.
                try {
                    transfer.finalize()
                } catch (error) {
                    console.warn(
                        "[ContentHubPicker] Transfer finalization failed"
                    )
                }

                if (paths.length > 0) {
                    console.log(
                        "[ContentHubPicker] Selected " +
                        paths.length + " file(s)"
                    )
                    root.filesPicked(paths)
                } else {
                    console.warn(
                        "[ContentHubPicker] No usable files selected"
                    )
                    root.pickCancelled()
                }

            } else if (transfer.state === ContentTransfer.Aborted) {
                root.activeTransfer = null
                root.visible = false

                try {
                    transfer.finalize()
                } catch (error) {
                    console.warn(
                        "[ContentHubPicker] Aborted transfer cleanup failed"
                    )
                }

                console.log("[ContentHubPicker] Selection cancelled")
                root.pickCancelled()
            }
        }
    }

    function open() {
        if (root.activeTransfer)
            return

        root.visible = true

        console.log("[ContentHubPicker] Requesting file selection")

        try {
            var transfer = fileSource.request(appStore)

            if (!transfer) {
                root.visible = false
                console.warn(
                    "[ContentHubPicker] Content Hub returned no transfer"
                )
                root.pickCancelled()
                return
            }

            root.activeTransfer = transfer

        } catch (error) {
            root.activeTransfer = null
            root.visible = false

            console.warn(
                "[ContentHubPicker] Failed to request file selection: " +
                error
            )

            root.pickCancelled()
        }
    }
}
