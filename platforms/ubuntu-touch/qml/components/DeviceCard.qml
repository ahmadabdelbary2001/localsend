import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Rectangle {
    id: card
    property var appTheme
    property string fingerprint: ""
    property string alias: ""
    property string deviceModel: ""
    property string deviceType: ""
    property string ip: ""
    property int port: 0
    property bool https: false
    property bool isFavorite: false
    property bool offline: false

    signal tapped()
    signal toggleFavorite()

    height: units.gu(9)
    radius: appTheme && appTheme.metrics
            ? appTheme.metrics.cardRadius
            : units.gu(0.6)

    color: appTheme && appTheme.colors
        ? appTheme.colors.surface
        : "#ffffff"

    border.color: appTheme && appTheme.colors
                ? appTheme.colors.divider
                : "#e0e0e0"
    border.width: units.dp(1)
    opacity: card.offline ? 0.6 : 1.0

    RowLayout {
        anchors.fill: parent
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1.5)

        Rectangle {
            Layout.preferredWidth: units.gu(6)
            Layout.preferredHeight: units.gu(6)
            radius: units.gu(3)
            color: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"

            Label {
                anchors.centerIn: parent
                text: card.deviceType.length > 0
                      ? card.deviceType.charAt(0).toUpperCase()
                      : "?"
                fontSize: "x-large"
                color: appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C"
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
                color: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
            }

            Label {
                Layout.fillWidth: true
                text: card.ip + ":" + card.port + (card.https ? "  HTTPS" : "  HTTP")
                fontSize: "x-small"
                opacity: 0.7
                elide: Text.ElideRight
                color: appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#5F6368"
            }

            Label {
                Layout.fillWidth: true
                text: card.deviceModel.length > 0 ? card.deviceModel : card.deviceType
                fontSize: "x-small"
                opacity: 0.5
                elide: Text.ElideRight
                color: appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#5F6368"
            }
        }

        // Star
        Icon {
            Layout.preferredWidth: units.gu(3)
            Layout.preferredHeight: units.gu(3)
            name: card.isFavorite ? "starred" : "non-starred"
            color: card.isFavorite
                   ? (appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C")
                   : (appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#888")

            MouseArea {
                anchors.fill: parent
                anchors.margins: -units.gu(0.8)
                onClicked: card.toggleFavorite()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.rightMargin: units.gu(5) // don't steal star clicks
        onClicked: card.tapped()
    }
}
