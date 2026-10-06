import QtQuick 2.15
import Lomiri.Content 1.3

Item {
    id: root
    visible: false
    signal filesPicked(var paths)   // array of absolute paths
    signal pickCancelled()

    ContentHub { id: contentHub }

    Connections {
        target: contentHub
        function onImportRequested(transfer) {
            transfer.setItems(transfer.items)
        }
        function onImportFinished(transfer) {
            if (transfer.state !== ContentTransfer.Charged) {
                root.pickCancelled()
                return
            }
            var paths = []
            var items = transfer.items
            for (var i = 0; i < items.length; i++) {
                var u = items[i].url.toString()
                if (u.indexOf("file://") === 0) u = u.substring(7)
                paths.push(u)
            }
            root.filesPicked(paths)
        }
    }

    function open(contentType) {
        root.visible = true
        contentHub.importContent(contentType === undefined ? ContentType.All : contentType)
    }
}