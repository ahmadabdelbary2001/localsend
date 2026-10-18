// SPDX-License-Identifier: Apache-2.0
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3
import "../js/qrcode.js" as QrLib

Dialog {
    id: root
    property var appTheme
    property string qrData: ""
    property string qrLabel: ""
    property string pin: ""

    title: ""
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(44))
    header: null

    contentItem: ColumnLayout {
        spacing: units.gu(1.5)
        leftPadding: units.gu(2); rightPadding: units.gu(2)
        topPadding: units.gu(2); bottomPadding: units.gu(2)

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: translator.tr("dialogs.qr.title")
            fontSize: "large"
            font.bold: true
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: units.gu(26)
            height: units.gu(26)
            color: "#FFFFFF"
            radius: units.gu(1)
            border.color: "#E0E0E0"
            border.width: units.dp(1)

            Canvas {
                id: qrCanvas
                anchors.centerIn: parent
                width: units.gu(24)
                height: units.gu(24)

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.fillStyle = "#FFFFFF";
                    ctx.fillRect(0, 0, width, height);

                    if (!root.qrData || root.qrData.length === 0) return;

                    try {
                        var qr = QrLib.createQr(root.qrData, 'M');
                        var count = qr.getModuleCount();
                        var padding = 2;
                        var total = count + (padding * 2);
                        var cell = width / total;

                        ctx.fillStyle = "#000000";
                        for (var r = 0; r < count; r++) {
                            for (var c = 0; c < count; c++) {
                                if (qr.isDark(r, c)) {
                                    ctx.fillRect(
                                        Math.floor((c + padding) * cell),
                                        Math.floor((r + padding) * cell),
                                        Math.ceil(cell),
                                        Math.ceil(cell)
                                    );
                                }
                            }
                        }
                    } catch (e) {
                        console.error("QR render error:", e);
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            text: root.qrLabel.length > 0 ? root.qrLabel : root.qrData
            fontSize: "small"
            horizontalAlignment: Text.AlignHCenter
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
            wrapMode: Text.WrapAnywhere
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.pin.length > 0
            spacing: units.gu(0.5)

            Icon {
                name: "stock_key"
                width: units.gu(2); height: units.gu(2)
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.warning : "#FF9800"
            }

            Label {
                text: "PIN: " + root.pin
                fontSize: "medium"
                font.bold: true
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.warning : "#FF9800"
            }
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: units.gu(16)
            text: translator.tr("general.close")
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
            onClicked: root.close()
        }
    }

    onOpened: {
        qrCanvas.requestPaint()
    }
}
