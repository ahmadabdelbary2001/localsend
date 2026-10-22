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
    signal detailsRequested()
    signal sendTextRequested()

    function _deviceIcon(type) {
        var t = (type || "").toLowerCase()
        if (t === "mobile" || t === "phone")   return "phone-symbolic"
        if (t === "desktop")                     return "computer-symbolic"
        if (t === "laptop")                      return "computer-symbolic"
        if (t === "tablet")                      return "tablet-symbolic"
        if (t === "web" || t === "browser")      return "stock_website"
        if (t === "server" || t === "headless")  return "network-server-symbolic"
        return "computer-symbolic"
    }

    implicitHeight: units.gu(9)
    radius: appTheme && appTheme.metrics
            ? appTheme.metrics.cardRadius
            : units.gu(1)

    color: mouseArea.pressed
        ? (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1")
        : (appTheme && appTheme.colors ? appTheme.colors.surface : "#ffffff")

    border.color: mouseArea.pressed
        ? (appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C")
        : (appTheme && appTheme.colors ? appTheme.colors.divider : "#e0e0e0")
    border.width: mouseArea.pressed ? units.dp(2) : units.dp(1)
    opacity: card.offline ? 0.55 : 1.0

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.rightMargin: units.gu(13) // Leave trailing buttons clickable
        onClicked: card.tapped()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1.5)

        // Device icon circle
        Rectangle {
            Layout.preferredWidth: units.gu(5.5)
            Layout.preferredHeight: units.gu(5.5)
            radius: width / 2
            color: appTheme && appTheme.colors
                   ? Qt.rgba(0, 0.42, 0.36, 0.12)
                   : "#E8F5E9"

            Icon {
                anchors.centerIn: parent
                width: units.gu(3)
                height: units.gu(3)
                name: card._deviceIcon(card.deviceType)
                color: appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C"
            }

            // Offline indicator dot
            Rectangle {
                visible: card.offline
                anchors { bottom: parent.bottom; right: parent.right; margins: -units.dp(1) }
                width: units.gu(1.4)
                height: units.gu(1.4)
                radius: width / 2
                color: "#B0BEC5"
                border.color: appTheme && appTheme.colors ? appTheme.colors.surface : "#ffffff"
                border.width: units.dp(2)
            }
        }

        // Center device details
        ColumnLayout {
            Layout.fillWidth: true
            spacing: units.gu(0.3)

            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.5)

                Label {
                    Layout.fillWidth: true
                    text: card.alias.length > 0 ? card.alias : translator.tr("general.unknown")
                    fontSize: "medium"
                    font.bold: true
                    elide: Text.ElideRight
                    color: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
                }

                Icon {
                    visible: card.isFavorite
                    Layout.preferredWidth: units.gu(1.8)
                    Layout.preferredHeight: units.gu(1.8)
                    name: "starred"
                    color: appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C"
                }
            }

            // Badges row: Protocol + Model + IP
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.6)

                // Protocol badge (HTTPS / HTTP)
                Rectangle {
                    implicitWidth: protocolLabel.implicitWidth + units.gu(1.2)
                    implicitHeight: protocolLabel.implicitHeight + units.gu(0.4)
                    radius: units.gu(0.5)
                    color: card.https
                           ? Qt.rgba(0, 0.5, 0.2, 0.13)
                           : Qt.rgba(0.6, 0.4, 0, 0.12)

                    Label {
                        id: protocolLabel
                        anchors.centerIn: parent
                        text: card.https ? "HTTPS" : "HTTP"
                        fontSize: "x-small"
                        font.bold: true
                        color: card.https
                            ? (appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C")
                            : "#B45309"
                    }
                }

                // Device Model badge (if present)
                Rectangle {
                    visible: card.deviceModel.length > 0
                    implicitWidth: modelLabel.implicitWidth + units.gu(1)
                    implicitHeight: modelLabel.implicitHeight + units.gu(0.3)
                    radius: units.gu(0.4)
                    color: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"

                    Label {
                        id: modelLabel
                        anchors.centerIn: parent
                        text: card.deviceModel
                        fontSize: "x-small"
                        color: appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#5F6368"
                    }
                }

                // IP Address
                Label {
                    Layout.fillWidth: true
                    text: card.ip.length > 0 ? card.ip : ""
                    fontSize: "x-small"
                    opacity: 0.8
                    elide: Text.ElideRight
                    color: appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#5F6368"
                }
            }
        }

        // Trailing action: Send Message
        Rectangle {
            Layout.preferredWidth: units.gu(4)
            Layout.preferredHeight: units.gu(4)
            radius: units.gu(2)
            color: msgArea.pressed ? (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1") : "transparent"

            Icon {
                anchors.centerIn: parent
                width: units.gu(2.4)
                height: units.gu(2.4)
                name: "message"
                color: appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#888"
            }

            MouseArea {
                id: msgArea
                anchors.fill: parent
                onClicked: card.sendTextRequested()
            }
        }

        // Trailing action: Details Dialog
        Rectangle {
            Layout.preferredWidth: units.gu(4)
            Layout.preferredHeight: units.gu(4)
            radius: units.gu(2)
            color: detailsArea.pressed ? (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1") : "transparent"

            Icon {
                anchors.centerIn: parent
                width: units.gu(2.4)
                height: units.gu(2.4)
                name: "info"
                color: appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#888"
            }

            MouseArea {
                id: detailsArea
                anchors.fill: parent
                onClicked: card.detailsRequested()
            }
        }

        // Trailing action: Star / Favorite toggle
        Rectangle {
            Layout.preferredWidth: units.gu(4)
            Layout.preferredHeight: units.gu(4)
            radius: units.gu(2)
            color: starArea.pressed ? (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1") : "transparent"

            Icon {
                anchors.centerIn: parent
                width: units.gu(2.6)
                height: units.gu(2.6)
                name: card.isFavorite ? "starred" : "non-starred"
                color: card.isFavorite
                       ? (appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C")
                       : (appTheme && appTheme.colors ? appTheme.colors.surfaceTextMuted : "#888")
            }

            MouseArea {
                id: starArea
                anchors.fill: parent
                onClicked: card.toggleFavorite()
            }
        }
    }
}
