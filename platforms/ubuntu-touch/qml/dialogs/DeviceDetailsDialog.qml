import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../components"

Dialog {
    id: root
    property var appTheme

    // QQuickControls popups are drawn with the application palette; mirror the
    // app palette so dialogs stay readable in dark / OLED modes.
    palette.window: appTheme && appTheme.colors ? appTheme.colors.surface : "#FFFFFF"
    palette.windowText: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
    palette.base: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"
    palette.text: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
    palette.button: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"
    palette.buttonText: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"

    background: DialogFrame { appTheme: root.appTheme }
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
        if (t === "mobile" || t === "phone")   return "phone"
        if (t === "desktop" || t === "laptop") return "computer"
        if (t === "tablet")                    return "tablet-portrait"
        if (t === "web" || t === "browser")    return "stock_website"
        if (t === "server" || t === "headless")return "network-server"
        return "computer"
    }

    /// Emitted when user taps the "Favorite" toggle.
    signal toggleFavorite()

    title: translator.tr("deviceDetailsPage.title")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))
    // Height is driven by the content; binding it here (instead of via the
    // Flickable's implicitHeight) avoids a width -> implicitHeight -> height
    // -> width binding loop.
    height: Math.min(col.implicitHeight + topPadding + bottomPadding, units.gu(55))

    contentItem: Flickable {
        id: flickable
        contentHeight: col.implicitHeight
        contentWidth: width
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
                        text: root.alias.length > 0 ? root.alias : translator.tr("general.unknown")
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

                Label { text: translator.tr("settingsTab.network.deviceModel"); fontSize: "small"; opacity: 0.6 }
                Label {
                    text: root.deviceModel.length > 0 ? root.deviceModel : "—"
                    fontSize: "small"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Label { text: translator.tr("deviceDetailsPage.info.address"); fontSize: "small"; opacity: 0.6 }
                Label {
                    text: root.ip + ":" + root.port
                    fontSize: "small"
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                }

                Label { text: translator.tr("deviceDetailsPage.info.version"); fontSize: "small"; opacity: 0.6 }
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
                        name: "stock_key"
                        color: root.appTheme && root.appTheme.colors
                               ? root.appTheme.colors.primary
                               : "#00695C"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("deviceDetailsPage.verify")
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
                              : translator.tr("general.unknown")
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
                          ? translator.tr("dialogs.favoriteDeleteDialog.title")
                          : translator.tr("dialogs.favoriteEditDialog.titleAdd")
                    color: root.isFavorite
                           ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B")
                           : (root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C")
                    onClicked: root.toggleFavorite()
                }

                Button {
                    Layout.preferredWidth: units.gu(12)
                    text: translator.tr("general.close")
                    onClicked: root.close()
                }
            }
        }
    }
}

