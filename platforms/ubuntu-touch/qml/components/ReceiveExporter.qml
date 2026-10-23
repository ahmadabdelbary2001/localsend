// SPDX-License-Identifier: Apache-2.0
//
// Exports received files through Content Hub. The app writes to its private
// received directory; the user chooses the final destination in File Manager.
//
// The transfer lifecycle is dictated by the Content Hub: requesting an export
// creates a transfer and starts it, which only reaches InProgress once the
// destination app has accepted the request. ContentTransfer silently drops a
// charge in any other state, so the items have to wait for InProgress instead
// of being charged right after ContentPeer.request().

import QtQuick 2.15
import Lomiri.Components 1.3
import Lomiri.Content 1.3

Item {
    id: root
    anchors.fill: parent

    property var model: null
    property string privateDir: ""
    property string targetDir: ""
    property var exported: []
    property var pending: []
    property var activeBatch: []
    property var lastAttempt: []
    property var activeContentItems: []
    property var activeTransfer: null
    property bool pickerVisible: false
    property bool finishing: false
    property bool chargeRequested: false
    property bool itemsHandedOver: false
    property string lastMessage: ""

    // The exporter is a window level overlay, so its actions are only offered
    // while the receive tab is in front.
    readonly property bool onReceiveTab: typeof homeController !== "undefined"
                                         && homeController.current_tab === 0

    function isUnder(path, dir) {
        if (!path || !dir || dir.length === 0)
            return false
        var prefix = dir.charAt(dir.length - 1) === "/" ? dir : dir + "/"
        return path === dir || path.indexOf(prefix) === 0
    }

    function containsPath(items, path) {
        for (var i = 0; i < items.length; i++) {
            if (items[i] && items[i].path === path)
                return true
        }
        return false
    }

    // ContentTransfer takes the ContentItem objects into its own internal list
    // when the transfer is charged and deletes them when the destination
    // collects. Destroying them here as well would delete the same objects
    // twice, so the objects are only destroyed while they never reached the
    // hub.
    function cleanupContentItems() {
        var oldItems = root.activeContentItems
        root.activeContentItems = []
        if (root.itemsHandedOver)
            return
        for (var i = 0; i < oldItems.length; i++) {
            if (oldItems[i]) {
                try { oldItems[i].destroy() } catch (e) { }
            }
        }
    }

    function destroyItems(items) {
        for (var i = 0; i < items.length; i++) {
            if (items[i]) {
                try { items[i].destroy() } catch (e) { }
            }
        }
    }

    function cancelTransfer(transfer) {
        if (!transfer)
            return
        try {
            transfer.state = ContentTransfer.Aborted
        } catch (e) {
            console.warn("[ContentHub] transfer abort failed:", e)
        }
        try {
            transfer.finalize()
        } catch (e2) {
            console.warn("[ContentHub] transfer cleanup failed:", e2)
        }
    }

    function resetActiveTransfer() {
        chargeTimer.stop()
        root.activeTransfer = null
        root.activeBatch = []
        root.chargeRequested = false
        root.pickerVisible = false
        root.finishing = false
        root.cleanupContentItems()
        root.itemsHandedOver = false
    }

    function failActiveExport(message) {
        if (root.finishing)
            return
        root.finishing = true
        var transfer = root.activeTransfer
        root.resetActiveTransfer()
        if (transfer)
            root.cancelTransfer(transfer)
        root.lastMessage = message
        root.finishing = false
        // Keep root.pending unchanged so the user can retry.
    }

    // Some File Manager versions report Aborted after showing the import result,
    // regardless of whether its move succeeded. Never discard the original until
    // the user confirms that the result dialog reported success.
    function markAttemptSaved() {
        if (!root.lastAttempt || root.lastAttempt.length === 0)
            return
        var donePaths = []
        for (var i = 0; i < root.lastAttempt.length; i++) {
            var path = root.lastAttempt[i].path
            if (path && donePaths.indexOf(path) === -1)
                donePaths.push(path)
        }
        root.pending = root.pending.filter(function(entry) {
            return donePaths.indexOf(entry.path) === -1
        })
        for (var j = 0; j < donePaths.length; j++) {
            if (root.exported.indexOf(donePaths[j]) === -1)
                root.exported = root.exported.concat([donePaths[j]])
        }
        root.lastAttempt = []
        root.lastMessage = ""
    }

    function fileUrl(path) {
        var parts = path.split("/")
        for (var i = 0; i < parts.length; i++)
            parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }

    // Called by Main.qml's polling timer. Only completed files staged by this
    // app are eligible for export; files are not marked exported until the
    // Content Hub transfer reports that the receiver collected them.
    function check() {
        if (!root.model || !root.privateDir)
            return
        for (var i = 0; i < root.model.rowCount(); i++) {
            var idx = root.model.index(i, 0)
            var path = root.model.data(idx, 4)
            var name = root.model.data(idx, 0)
            var status = root.model.data(idx, 3)
            if (!path || status !== "finished")
                continue
            if (!root.isUnder(path, root.privateDir))
                continue
            if (root.exported.indexOf(path) !== -1 || root.containsPath(root.pending, path))
                continue
            root.pending = root.pending.concat([{ "path": path, "name": name || path.split("/").pop() }])
        }
    }

    // ContentTransfer only forwards a charge while the transfer is InProgress
    // (the destination app accepted the request) or Downloaded. Charging right
    // after ContentPeer.request() is silently ignored because the transfer is
    // still Initiated, which is what made "Save" look like it did nothing.
    function chargeTransfer() {
        var transfer = root.activeTransfer
        if (!transfer || root.chargeRequested)
            return
        if (!root.activeContentItems || root.activeContentItems.length === 0)
            return

        root.chargeRequested = true
        chargeTimer.stop()
        try {
            transfer.items = root.activeContentItems
            transfer.state = ContentTransfer.Charged
            root.itemsHandedOver = true
        } catch (e) {
            console.warn("[ContentHub] could not charge export transfer:", e)
            root.failActiveExport(translator.tr("receiveExport.failed"))
        }
    }

    function exportToPeer(peer) {
        if (root.activeTransfer || !root.pending.length)
            return

        var batch = root.pending.slice(0)
        var items = []
        peer.selectionType = ContentTransfer.Multiple

        var transfer = null
        try {
            transfer = peer.request()
        } catch (e) {
            console.warn("[ContentHub] destination request failed:", e)
        }
        if (!transfer) {
            root.pickerVisible = false
            root.lastMessage = translator.tr("receiveExport.noDestination")
            return
        }

        // A request that could not create a hub transfer reports Aborted while
        // its internal transfer object is null; touching such an object (even
        // finalize()) would dereference null and crash the app.
        if (transfer.state === ContentTransfer.Aborted) {
            console.warn("[ContentHub] destination returned an unusable transfer")
            root.pickerVisible = false
            root.lastMessage = translator.tr("receiveExport.noDestination")
            return
        }

        for (var i = 0; i < batch.length; i++) {
            var sourcePath = batch[i].path
            if (!sourcePath || !sendController.can_read_file(sourcePath)) {
                console.warn("[ContentHub] export source is missing or not readable in app-private storage:", sourcePath)
                root.destroyItems(items)
                root.cancelTransfer(transfer)
                root.pickerVisible = false
                root.lastMessage = translator.tr("receiveExport.sourceMissing")
                return
            }

            var item = contentItemComponent.createObject(root)
            if (!item) {
                root.destroyItems(items)
                root.cancelTransfer(transfer)
                root.pickerVisible = false
                root.lastMessage = translator.tr("receiveExport.failed")
                return
            }
            var url = root.fileUrl(sourcePath)
            if (!url) {
                root.destroyItems(items)
                root.cancelTransfer(transfer)
                root.pickerVisible = false
                root.lastMessage = translator.tr("receiveExport.sourceMissing")
                return
            }
            item.url = url
            console.log("[ContentHub] prepared export item:", String(item.url))
            items.push(item)
        }

        root.lastAttempt = []
        root.activeBatch = batch
        root.activeContentItems = items
        root.activeTransfer = transfer
        root.chargeRequested = false
        root.itemsHandedOver = false
        root.lastMessage = ""
        root.pickerVisible = false

        if (transfer.state === ContentTransfer.InProgress
                || transfer.state === ContentTransfer.Downloaded) {
            root.chargeTransfer()
        } else {
            console.log("[ContentHub] waiting for the destination to accept the transfer:", transfer.state)
            chargeTimer.restart()
        }
    }

    Component {
        id: contentItemComponent
        ContentItem { }
    }

    // The destination app is started by the content hub. If it never reports
    // that it handled the request, release the transfer instead of leaving the
    // hint spinning forever.
    Timer {
        id: chargeTimer
        interval: 30000
        repeat: false
        onTriggered: {
            console.warn("[ContentHub] destination did not accept the export in time")
            root.failActiveExport(translator.tr("receiveExport.noResponse"))
        }
    }

    Button {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: units.gu(2)
        anchors.bottomMargin: units.gu(10)
        z: 1
        visible: root.onReceiveTab && root.pending.length > 0
                 && !root.pickerVisible && !root.activeTransfer
        text: root.pending.length === 1
              ? translator.tr("receiveExport.saveOne")
              : translator.tr_args("receiveExport.saveMany", JSON.stringify({ n: root.pending.length }))
        onClicked: {
            root.lastMessage = ""
            root.pickerVisible = true
        }
    }

    Button {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: units.gu(2)
        anchors.bottomMargin: units.gu(10)
        z: 1
        visible: root.onReceiveTab && root.lastAttempt.length > 0
                 && !root.pickerVisible && !root.activeTransfer
        text: translator.tr("receiveExport.markSaved")
        onClicked: root.markAttemptSaved()
    }

    Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: units.gu(2)
        anchors.rightMargin: units.gu(2)
        anchors.bottomMargin: units.gu(15)
        z: 1
        visible: root.onReceiveTab && root.lastMessage.length > 0 && !root.pickerVisible
        text: root.lastMessage
        wrapMode: Text.Wrap
        color: "#C0392B"
    }

    ContentPeerPicker {
        id: destinationPicker
        anchors.fill: parent
        z: 2
        visible: root.pickerVisible
        showTitle: true
        contentType: ContentType.All
        handler: ContentHandler.Destination

        onPeerSelected: {
            root.exportToPeer(destinationPicker.peer)
        }
        onCancelPressed: {
            root.pickerVisible = false
        }
    }

    ContentTransferHint {
        anchors.fill: parent
        z: 3
        visible: root.activeTransfer !== null
        activeTransfer: root.activeTransfer
    }

    Connections {
        target: root.activeTransfer

        function onStateChanged() {
            var transfer = root.activeTransfer
            if (!transfer || root.finishing)
                return

            var state = transfer.state
            if (state === ContentTransfer.InProgress || state === ContentTransfer.Downloaded) {
                // The destination accepted the request; now the items can be
                // attached and charged.
                root.chargeTransfer()
            } else if (state === ContentTransfer.Collected) {
                // Collected is the documented positive acknowledgement that the
                // destination has collected the items.
                root.finishing = true
                var completed = root.activeBatch.slice(0)
                var completedPaths = []
                for (var i = 0; i < completed.length; i++)
                    completedPaths.push(completed[i].path)

                root.pending = root.pending.filter(function(entry) {
                    return completedPaths.indexOf(entry.path) === -1
                })
                for (var j = 0; j < completedPaths.length; j++) {
                    if (root.exported.indexOf(completedPaths[j]) === -1)
                        root.exported = root.exported.concat([completedPaths[j]])
                }
                try { transfer.finalize() } catch (e) {
                    console.warn("[ContentHub] transfer finalization failed:", e)
                }
                root.resetActiveTransfer()
                root.cleanupContentItems()
                root.lastAttempt = []
                root.lastMessage = translator.tr("receiveExport.saved")
                root.finishing = false
            } else if (state === ContentTransfer.Aborted || state === ContentTransfer.Finalized) {
                root.finishing = true
                var attempt = root.activeBatch.slice(0)
                if (state === ContentTransfer.Aborted) {
                    try { transfer.finalize() } catch (e2) {
                        console.warn("[ContentHub] transfer finalization after abort failed:", e2)
                    }
                }
                root.resetActiveTransfer()
                root.cleanupContentItems()
                root.lastAttempt = attempt
                root.lastMessage = attempt.length > 0
                                  ? translator.tr("receiveExport.verifyResult")
                                  : translator.tr("receiveExport.failed")
                root.finishing = false
                // File Manager currently reports Aborted after its result dialog
                // is closed, including successful imports. Keep items queued until
                // the user confirms success, or let them retry after a failure.
            }
        }
    }
}
