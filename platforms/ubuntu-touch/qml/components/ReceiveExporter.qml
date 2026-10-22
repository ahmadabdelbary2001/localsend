// SPDX-License-Identifier: Apache-2.0
//
// Exports received files through the content hub.
//
// Received files are written straight into `~/Downloads/LocalSend` (the
// AppArmor hook declares `write_path` for `~/Downloads`), so normally there is
// nothing to export. This component is the fallback for the cases where the
// app could not write into the folder it was asked to use: the file stays in
// the app data folder and is handed to the content hub afterwards, so the file
// manager (unconfined) writes it where the user wants it.
//
// The files of one receive session are collected and exported as a single
// transfer, so the save dialog shows up once per session instead of once per
// file.
//
// The module is not available everywhere (e.g. on a desktop), so every call is
// guarded: when the content hub is missing, the file simply stays in the
// app-private folder and can still be opened from the history.

import QtQuick 2.15
import Lomiri.Content 1.3

Item {
    id: root

    /// The received files model (see IncomingFilesModel).
    property var model: null

    /// Folder the app writes received files into. Only files below this path
    /// are exported; files that already landed in the user folder are not
    /// copied a second time.
    property string privateDir: ""

    /// Folder the files are exported to. Used to skip files that are already
    /// there; the file manager asks for the final folder itself.
    property string targetDir: ""

    /// Paths that were already handed over to the content hub.
    property var exported: []

    /// Files waiting for the next export: [{ "path": ..., "name": ... }].
    property var pending: []

    /// True when the content hub is usable.
    readonly property bool available: {
        try {
            return typeof ContentTransfer !== "undefined" && typeof ContentItem !== "undefined"
        } catch (e) {
            return false
        }
    }

    // Apps that can store the file: the file manager saves it in a folder of
    // the user's choice (~/Downloads by default).
    ContentPeerModel {
        id: peerModel
        handler: ContentHandler.Destination
        contentType: ContentType.All
    }

    // Batches the files of one session: a transfer is only started when no
    // further file finished for a moment.
    Timer {
        id: flushTimer
        interval: 1200
        repeat: false
        onTriggered: root.exportPending()
    }

    Component {
        id: transferComponent

        ContentTransfer { }
    }

    Component {
        id: itemComponent

        ContentItem { }
    }

    /// Collects finished files and schedules the export.
    function check() {
        if (!root.available || !root.model)
            return

        var added = false
        for (var i = 0; i < root.model.rowCount(); i++) {
            var idx = root.model.index(i, 0)
            var path = root.model.data(idx, 4)
            var name = root.model.data(idx, 0)
            var status = root.model.data(idx, 3)

            // Only finished files, and only once.
            if (!path || path.length === 0 || status !== "finished")
                continue
            if (root.exported.indexOf(path) !== -1)
                continue

            // Only files the app received itself are exported.
            if (!root.isUnder(path, root.privateDir))
                continue

            root.exported.push(path)

            // Already in the target folder: nothing to copy.
            if (root.isUnder(path, root.targetDir))
                continue

            root.pending.push({ "path": path, "name": name })
            added = true
        }

        if (added)
            flushTimer.restart()
    }

    /// Exports everything that is pending as one transfer.
    function exportPending() {
        if (root.pending.length === 0)
            return

        var batch = root.pending
        root.pending = []

        var items = []
        for (var i = 0; i < batch.length; i++) {
            var item = itemComponent.createObject(root)
            if (!item)
                continue
            item.url = root.fileUrl(batch[i].path)
            item.name = batch[i].name
            items.push(item)
        }
        if (items.length === 0)
            return

        var transfer = root.newTransfer()
        if (!transfer) {
            console.warn("[ContentHub] could not start an export transfer")
            return
        }
        try {
            transfer.items = items
            transfer.start()
        } catch (e) {
            console.warn("[ContentHub] export failed:", e)
        }
    }

    /// A transfer that exports to the file manager.
    function newTransfer() {
        var peer = root.destinationPeer()
        if (!peer)
            return null

        // The documented way: the destination peer hands out a transfer.
        try {
            var requested = peer.request()
            if (requested) {
                requested.selectionType = ContentTransfer.MultipleTransfer
                return requested
            }
        } catch (e) {
            console.warn("[ContentHub] peer request failed:", e)
        }

        // Fallback for builds where the peer does not hand out a transfer.
        try {
            var transfer = transferComponent.createObject(root)
            if (transfer) {
                transfer.direction = ContentTransfer.ExportTransfer
                transfer.destination = peer
                transfer.contentType = ContentType.All
                transfer.selectionType = ContentTransfer.MultipleTransfer
                return transfer
            }
        } catch (e2) {
            console.warn("[ContentHub] cannot create a transfer:", e2)
        }
        return null
    }

    /// The destination peer that saves the file (the file manager).
    function destinationPeer() {
        var peers = peerModel.peers
        for (var i = 0; i < peers.length; i++) {
            var appId = peers[i].appId ? peers[i].appId : ""
            if (appId.indexOf("filemanager") !== -1)
                return peers[i]
        }
        return peers.length > 0 ? peers[0] : null
    }

    /// True when `path` is `dir` itself or a file inside it.
    function isUnder(path, dir) {
        if (!path || !dir || dir.length === 0)
            return false
        var prefix = dir.charAt(dir.length - 1) === "/" ? dir : dir + "/"
        return path === dir || path.indexOf(prefix) === 0
    }

    /// `file://` URL of a path, with the segments percent-encoded so spaces
    /// and non-ASCII names survive the transfer.
    function fileUrl(path) {
        var parts = path.split("/")
        for (var i = 0; i < parts.length; i++)
            parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }
}
