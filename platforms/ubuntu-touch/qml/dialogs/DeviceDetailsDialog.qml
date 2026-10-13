import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Dialog {
    id: root
    property var appTheme
    property string fingerprint: ""
    property string alias: ""
    property string deviceModel: ""
    property string deviceType: ""
    property string ip: ""
    property int port: 0
    property bool https: false

    /// Emitted when user taps the "Favorite" toggle.
    signal toggleFavorite()

    title: qsTr("Device details")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))
    height: Math.min(parent.height - units.gu(8), units.gu(70))

    contentItem: Flickable {
        contentHeight: col.implicitHeight
        clip: true

        ColumnLayout {
            id: col
            width: parent.width
            spacing: units.gu(1.5)

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: units.gu(2)
                rowSpacing: units.gu(0.5)

                Label { text: qsTr("Name"); fontSize: "small"; opacity: 0.6 }
                Label { text: root.alias; fontSize: "small"; wrapMode: Text.Wrap; Layout.fillWidth: true }

                Label { text: qsTr("Model"); fontSize: "small"; opacity: 0.6 }
                Label { text: root.deviceModel.length > 0 ? root.deviceModel : "-"; fontSize: "small"; wrapMode: Text.Wrap; Layout.fillWidth: true }

                Label { text: qsTr("Type"); fontSize: "small"; opacity: 0.6 }
                Label { text: root.deviceType.length > 0 ? root.deviceType : "-"; fontSize: "small" }

                Label { text: qsTr("Address"); fontSize: "small"; opacity: 0.6 }
                Label { text: root.ip + ":" + root.port + (root.https ? "  HTTPS" : "  HTTP"); fontSize: "small" }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: units.gu(1)
                text: qsTr("Verify the device's fingerprint")
                fontSize: "small"
                opacity: 0.6
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: fpText.implicitHeight + units.gu(2)
                color: root.appTheme ? root.appTheme.colors.surfaceTint : "#ECEFF1"
                radius: units.gu(0.5)

                Label {
                    id: fpText
                    anchors { fill: parent; margins: units.gu(1) }
                    text: root.fingerprint
                    wrapMode: Text.WrapAnywhere
                    font.family: "monospace"
                    fontSize: "x-small"
                    color: root.appTheme ? root.appTheme.colors.surfaceText : "#1B1D21"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Favorite")
                    onClicked: root.toggleFavorite()
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Close")
                    color: root.appTheme ? root.appTheme.colors.primary : "#00695C"
                    onClicked: root.close()
                }
            }
        }
    }
}
