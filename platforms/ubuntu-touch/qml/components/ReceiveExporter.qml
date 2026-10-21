// SPDX-License-Identifier: Apache-2.0
//
// Fallback export for received files via the content hub.
//
// The click declares `write_path` for ~/Downloads, so received files are
// written directly into `~/Downloads/LocalSend` and normally never reach this
// component. It only handles files that ended up in the app-private folder
// (e.g. after an AppArmor profile update or when the user picked a folder the
// profile does not grant): the content hub runs unconfined and can move them
// where the user can see them.
//
// The module is not available everywhere (e.g. on a desktop), so every call is
// guarded: when the content hub is missing, the file simply stays in the
// app-private folder.

import QtQuick 2.15
import Lomiri.Content 1.3

Item {
    id: root

    /// The received files model (see IncomingFilesModel).
    property var model: null

    /// Folder the app writes received files into when AppArmor does not allow
    /// the user folder. Only files below this path are handed to the content
    /// hub; files that already landed in ~/Downloads/LocalSend are not copied
    /// a second time.
    property string privateDir: ""

    /// Folder the files are copied to for the user. Files that are already
    /// there (the app can write there when the profile allows it) are not
    /// copied twice.
    property string targetDir: ""

    /// Paths that were already handed over to the content hub.
    property var exported: []

    /// True when the content hub is usable.
    readonly property bool available: {
        try {
            return typeof ContentHub !== "undefined" && typeof ContentItem !== "undefined"
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

    Component {
        id: contentItemComponent

        ContentItem { }
    }

    /// Looks up the destination app.
    function destinationPeer() {
        var peers = peerModel.peers
        for (var i = 0; i < peers.length; i++) {
            var appId = peers[i].appId ? peers[i].appId : ""
            if (appId.indexOf("filemanager") !== -1)
                return peers[i]
        }
        return peers.length > 0 ? peers[0] : null
    }

    /// Exports the files that finished since the last call.
    function check() {
        if (!root.available || !root.model)
            return

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

            // Files that were written straight into the user folder need no
            // export. Only the app-private receive folder is exported.
            if (root.privateDir.length > 0 && path.indexOf(root.privateDir) !== 0)
                continue

            // Already in the target folder: nothing to copy.
            var dir = path.substring(0, path.lastIndexOf("/"))
            if (root.targetDir.length > 0 && dir === root.targetDir)
                continue

            root.exported.push(path)
            root.exportFile(path, name)
        }
    }

    /// Gives the file to the content hub.
    function exportFile(path, name) {
        var peer = root.destinationPeer()
        if (!peer) {
            console.warn("[ContentHub] no destination app found")
            return
        }
        try {
            var item = contentItemComponent.createObject()
            if (!item)
                return
            item.url = "file://" + path
            item.name = name

            // A destination peer exports the file to that app: the file
            // manager stores it in the download folder of the user.
            var transfer = peer.request()
            if (!transfer)
                return
            transfer.items = [item]
            transfer.start()
        } catch (e) {
            console.warn("[ContentHub] could not export " + path + ": " + e)
        }
    }
}
