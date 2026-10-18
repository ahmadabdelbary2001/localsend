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

    property string protocolVersion: ""
    property bool isFavorite: false

    function _deviceIcon(type) {
        var t = (type || "").toLowerCase()
        if (t === "mobile" || t === "phone")   return "phone-smartphone"
        if (t === "desktop" || t === "laptop") return "computer"
        if (t === "tablet")                    return "tablet-portrait"
        if (t === "web" || t === "browser")    return "stock_website"
        if (t === "server" || t === "headless")return "network-server"
        return "computer"
    }

    /// Emitted when user taps the "Favorite" toggle.
    signal toggleFavorite()

    title: qsTr("Device Details")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))

    contentItem: Flickable {
        id: flickable
        implicitHeight: Math.min(col.implicitHeight + units.gu(2), root.parent ? root.parent.height - units.gu(12) : units.gu(60))
        contentHeight: col.implicitHeight
        clip: true

        ColumnLayout {
            id: col
            width: flickable.width
            spacing: units.gu(1.5)

            // ── Device header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1.5)

                Rectangle {
                    width: units.gu(6)
                    height: units.gu(6)
                    radius: width / 2
                    color: root.appTheme && root.appTheme.colors
                           ? Qt.rgba(0, 0.42, 0.36, 0.12)
                           : "#E8F5E9"

                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(3.5)
                        height: units.gu(3.5)
                        name: root._deviceIcon(root.deviceType)
                        color: root.appTheme && root.appTheme.colors
                               ? root.appTheme.colors.primary
                               : "#00695C"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(0.3)

                    Label {
                        Layout.fillWidth: true
                        text: root.alias.length > 0 ? root.alias : qsTr("Unknown Device")
                        fontSize: "large"
                        font.bold: true
                        elide: Text.ElideRight
                        color: root.appTheme && root.appTheme.colors
                               ? root.appTheme.colors.surfaceText
                               : "#1B1D21"
                    }

                    RowLayout {
                        spacing: units.gu(0.6)

                        // HTTP/HTTPS badge
                        Rectangle {
                            implicitWidth: protoLbl.implicitWidth + units.gu(1.2)
                            implicitHeight: protoLbl.implicitHeight + units.gu(0.4)
                            radius: units.gu(0.5)
                            color: root.https
                                   ? Qt.rgba(0, 0.5, 0.2, 0.13)
                                   : Qt.rgba(0.6, 0.4, 0, 0.12)

                            Label {
                                id: protoLbl
                                anchors.centerIn: parent
                                text: root.https ? "HTTPS" : "HTTP"
                                fontSize: "x-small"
                                font.bold: true
                                color: root.https
                                       ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C")
                                       : "#B45309"
                            }
                        }

                        // Device type badge
                        Rectangle {
                            visible: root.deviceType.length > 0
                            implicitWidth: typeLbl.implicitWidth + units.gu(1)
                            implicitHeight: typeLbl.implicitHeight + units.gu(0.3)
                            radius: units.gu(0.4)
                            color: root.appTheme && root.appTheme.colors
                                   ? root.appTheme.colors.surfaceTint
                                   : "#ECEFF1"

                            Label {
                                id: typeLbl
                                anchors.centerIn: parent
                                text: root.deviceType
                                fontSize: "x-small"
                                color: root.appTheme && root.appTheme.colors
                                       ? root.appTheme.colors.surfaceTextMuted
                                       : "#5F6368"
                            }
                        }
                    }
                }
            }

            // ── Divider ──
            Rectangle {
                Layout.fillWidth: true
                height: units.dp(1)
                color: root.appTheme && root.appTheme.colors
                       ? root.appTheme.colors.divider
                       : "#e0e0e0"
            }

            // ── Details grid ──
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: units.gu(2)
                rowSpacing: units.gu(0.6)

                Label { text: qsTr("Model"); fontSize: "small"; opacity: 0.6 }
                Label {
                    text: root.deviceModel.length > 0 ? root.deviceModel : "—"
                    fontSize: "small"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Label { text: qsTr("Address"); fontSize: "small"; opacity: 0.6 }
                Label {
                    text: root.ip + ":" + root.port
                    fontSize: "small"
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                }

                Label { text: qsTr("Protocol"); fontSize: "small"; opacity: 0.6 }
                Label {
                    text: root.protocolVersion.length > 0 ? root.protocolVersion : "—"
                    fontSize: "small"
                    Layout.fillWidth: true
                }
            }

            // ── Fingerprint verification section ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.5)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(0.5)

                    Icon {
                        width: units.gu(2)
                        height: units.gu(2)
                        name: "security-medium"
                        color: root.appTheme && root.appTheme.colors
                               ? root.appTheme.colors.primary
                               : "#00695C"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Device Fingerprint (verify before sending)")
                        fontSize: "small"
                        font.bold: true
                        color: root.appTheme && root.appTheme.colors
                               ? root.appTheme.colors.surfaceText
                               : "#1B1D21"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: fpText.implicitHeight + units.gu(2)
                    color: root.appTheme && root.appTheme.colors
                           ? root.appTheme.colors.surfaceTint
                           : "#ECEFF1"
                    radius: units.gu(0.6)
                    border.color: root.appTheme && root.appTheme.colors
                                  ? root.appTheme.colors.divider
                                  : "#e0e0e0"
                    border.width: units.dp(1)

                    Label {
                        id: fpText
                        anchors { fill: parent; margins: units.gu(1) }
                        text: root.fingerprint.length > 0
                              ? root.fingerprint
                              : qsTr("No fingerprint available")
                        wrapMode: Text.WrapAnywhere
                        font.family: "Ubuntu Mono, Monospace"
                        fontSize: "x-small"
                        color: root.fingerprint.length > 0
                               ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21")
                               : "#888888"
                    }
                }
            }

            // ── Action buttons ──
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)

                Button {
                    Layout.fillWidth: true
                    text: root.isFavorite
                          ? qsTr("★ Remove from Favorites")
                          : qsTr("☆ Add to Favorites")
                    color: root.isFavorite
                           ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B")
                           : (root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C")
                    onClicked: root.toggleFavorite()
                }

                Button {
                    Layout.preferredWidth: units.gu(12)
                    text: qsTr("Close")
                    onClicked: root.close()
                }
            }
        }
    }
}

