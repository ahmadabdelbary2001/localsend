// SPDX-License-Identifier: Apache-2.0
//
// Exports received files through Content Hub. The app writes to its private
// received directory; the user chooses the final destination in File Manager.

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
    property var activeContentItems: []
    property var activeTransfer: null
    property bool pickerVisible: false
    property bool finishing: false
    property string lastMessage: ""

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

    function cleanupContentItems() {
        var oldItems = root.activeContentItems
        root.activeContentItems = []
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
            transfer.finalize()
        } catch (e) {
            console.warn("[ContentHub] transfer cleanup failed:", e)
        }
    }

    function failActiveExport(message) {
        root.finishing = true
        var transfer = root.activeTransfer
        root.activeTransfer = null
        root.pickerVisible = false
        root.activeBatch = []
        root.cleanupContentItems()
        if (transfer)
            root.cancelTransfer(transfer)
        root.lastMessage = message
        root.finishing = false
        // Keep root.pending unchanged so the user can retry.
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

        // ContentPeer.request() returns the transfer for this export. Populate
        // it and mark it Charged, without assuming an undocumented initial state.
        for (var i = 0; i < batch.length; i++) {
            var item = contentItemComponent.createObject(root)
            if (!item) {
                root.destroyItems(items)
                root.cancelTransfer(transfer)
                root.pickerVisible = false
                root.lastMessage = translator.tr("receiveExport.failed")
                return
            }
            item.url = root.fileUrl(batch[i].path)
            // ContentItem exposes a URL; the exported filename comes from the URL.
            items.push(item)
        }

        root.activeBatch = batch
        root.activeContentItems = items
        root.activeTransfer = transfer
        root.lastMessage = ""
        try {
            transfer.items = items
            transfer.state = ContentTransfer.Charged
            root.pickerVisible = false
        } catch (e2) {
            console.warn("[ContentHub] could not charge export transfer:", e2)
            root.failActiveExport(translator.tr("receiveExport.failed"))
        }
    }

    Component {
        id: contentItemComponent
        ContentItem { }
    }

    Button {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: units.gu(2)
        anchors.bottomMargin: units.gu(10)
        z: 1
        visible: root.pending.length > 0 && !root.pickerVisible && !root.activeTransfer
        text: root.pending.length === 1
              ? translator.tr("receiveExport.saveOne")
              : translator.tr_args("receiveExport.saveMany", JSON.stringify({ n: root.pending.length }))
        onClicked: {
            root.lastMessage = ""
            root.pickerVisible = true
        }
    }

    Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: units.gu(2)
        anchors.rightMargin: units.gu(2)
        anchors.bottomMargin: units.gu(15)
        z: 1
        visible: root.lastMessage.length > 0 && !root.pickerVisible
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
            if (state === ContentTransfer.Collected || state === ContentTransfer.Finalized) {
                root.finishing = true
                var completed = root.activeBatch.slice(0)
                var completedPaths = []
                for (var i = 0; i < completed.length; i++)
                    completedPaths.push(completed[i].path)

                var remaining = []
                for (var j = 0; j < root.pending.length; j++) {
                    if (completedPaths.indexOf(root.pending[j].path) === -1)
                        remaining.push(root.pending[j])
                }
                root.pending = remaining
                root.exported = root.exported.concat(completedPaths)

                if (state === ContentTransfer.Collected) {
                    try { transfer.finalize() } catch (e) {
                        console.warn("[ContentHub] transfer finalization failed:", e)
                    }
                }
                root.activeTransfer = null
                root.activeBatch = []
                root.cleanupContentItems()
                root.pickerVisible = false
                root.lastMessage = translator.tr("receiveExport.saved")
                root.finishing = false
            } else if (state === ContentTransfer.Aborted) {
                root.finishing = true
                try { transfer.finalize() } catch (e2) { }
                root.activeTransfer = null
                root.activeBatch = []
                root.cleanupContentItems()
                root.pickerVisible = false
                root.lastMessage = translator.tr("receiveExport.failed")
                root.finishing = false
                // Do not remove the files from pending; retry remains available.
            }
        }
    }
}