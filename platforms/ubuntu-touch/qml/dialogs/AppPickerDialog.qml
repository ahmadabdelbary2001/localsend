import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Dialog {
    id: root
    property var appTheme
    property var allApps: []
    property var filteredApps: []

    signal appSelected(string path)
    signal pickCustomFile()
    signal canceled()

    function refreshApps() {
        try {
            var json = sendController.list_installed_apps()
            root.allApps = JSON.parse(json)
            root.filterApps(searchField.text)
        } catch (e) {
            console.warn("[AppPicker] failed to list installed apps:", e)
            root.allApps = []
            root.filteredApps = []
        }
    }

    function filterApps(query) {
        var q = (query || "").toLowerCase().trim()
        if (q.length === 0) {
            root.filteredApps = root.allApps
            return
        }
        root.filteredApps = root.allApps.filter(function(item) {
            return (item.name || "").toLowerCase().indexOf(q) !== -1 ||
                   (item.path || "").toLowerCase().indexOf(q) !== -1
        })
    }

    Component.onCompleted: {
        root.refreshApps()
    }

    title: qsTr("Select App")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(65))
    height: Math.min(parent.height - units.gu(6), units.gu(75))

    contentItem: ColumnLayout {
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1.2)

        // Search Bar
        TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: qsTr("Search apps…")
            onTextChanged: root.filterApps(text)
        }

        // App List
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: units.gu(0.5)
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surface : "#ffffff"
            border.color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.divider : "#e0e0e0"
            border.width: units.dp(1)
            clip: true

            ListView {
                id: appListView
                anchors.fill: parent
                model: root.filteredApps

                delegate: Rectangle {
                    width: appListView.width
                    height: units.gu(7)
                    color: itemArea.pressed ? (root.appTheme ? root.appTheme.colors.surfaceTint : "#ECEFF1") : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                        spacing: units.gu(1.5)

                        Rectangle {
                            width: units.gu(4.5)
                            height: units.gu(4.5)
                            radius: units.gu(1)
                            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTint : "#ECEFF1"

                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(3)
                                height: units.gu(3)
                                name: modelData.icon && modelData.icon.length > 0 ? modelData.icon : "package"
                                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: units.gu(0.2)

                            Label {
                                Layout.fillWidth: true
                                text: modelData.name
                                fontSize: "small"
                                font.bold: true
                                elide: Text.ElideRight
                                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                            }

                            Label {
                                Layout.fillWidth: true
                                text: modelData.path
                                fontSize: "x-small"
                                elide: Text.ElideMiddle
                                opacity: 0.7
                                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
                            }
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        onClicked: {
                            root.appSelected(modelData.path)
                            root.close()
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: root.filteredApps.length === 0
                    text: qsTr("No apps found")
                    fontSize: "small"
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#888888"
                }
            }
        }

        // Bottom Actions
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                Layout.fillWidth: true
                text: qsTr("Browse File (.click)")
                onClicked: {
                    root.pickCustomFile()
                    root.close()
                }
            }

            Button {
                Layout.preferredWidth: units.gu(12)
                text: qsTr("Cancel")
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }
        }
    }
}
