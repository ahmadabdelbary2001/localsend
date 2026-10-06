import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Rectangle {
    id: card
    property var theme

    property string fingerprint: ""
    property string alias: ""
    property string deviceModel: ""
    property string deviceType: ""
    property string ip: ""
    property int port: 0
    property bool https: false

    signal tapped()

    height: units.gu(9)
    radius: theme ? theme.metrics.cardRadius : units.gu(0.6)
    color: theme ? theme.colors.surface : "#ffffff"
    border.color: theme ? theme.colors.divider : "#e0e0e0"
    border.width: units.dp(1)

    RowLayout {
        anchors.fill: parent
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1.5)

        // Placeholder icon (no assets yet)
        Rectangle {
            Layout.preferredWidth: units.gu(6)
            Layout.preferredHeight: units.gu(6)
            radius: units.gu(3)
            color: theme ? theme.colors.surfaceTint : "#ECEFF1"

            Label {
                anchors.centerIn: parent
                text: card.deviceType.length > 0
                      ? card.deviceType.charAt(0).toUpperCase()
                      : "?"
                fontSize: "x-large"
                color: theme ? theme.colors.primary : "#00695C"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: units.gu(0.3)

            Label {
                Layout.fillWidth: true
                text: card.alias
                fontSize: "medium"
                elide: Text.ElideRight
                color: theme ? theme.colors.onSurface : "#1B1D21"
            }

            Label {
                Layout.fillWidth: true
                text: card.ip + ":" + card.port + (card.https ? " (HTTPS)" : " (HTTP)")
                fontSize: "x-small"
                opacity: 0.7
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: card.deviceModel.length > 0
                      ? card.deviceModel
                      : card.deviceType
                fontSize: "x-small"
                opacity: 0.5
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: card.tapped()
    }
}