import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../components"

// Package picker for the send tab.
//
// Ubuntu Touch ships Click packages, Android ships APKs: Click is listed by
// default, the switch on top toggles to APK. Only package files found in the
// usual user folders are listed; "Open" still allows picking any file.
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

    /// Package format: "click" (Ubuntu Touch, default) or "apk".
    property string kind: "click"

    property var allApps: []
    property var filteredApps: []

    signal appSelected(string path)
    signal pickCustomFile()
    signal canceled()

    function refreshApps() {
        try {
            root.allApps = JSON.parse(sendController.list_installed_apps(root.kind))
        } catch (e) {
            console.warn("[AppPicker] failed to list app packages:", e)
            root.allApps = []
        }
        root.filterApps(searchField.text)
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

    function setKind(value) {
        if (root.kind === value)
            return
        root.kind = value
        root.refreshApps()
        appListView.positionViewAtBeginning()
    }

    onOpened: root.refreshApps()

    title: translator.tr("appPicker.title")
    modal: true
    // Instantiated through a Loader, so the declared parent (the
    // zero-sized Loader item) cannot be used for centering.
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - units.gu(4), units.gu(65))
    height: Math.min(parent.height - units.gu(6), units.gu(75))
    padding: units.gu(1.2)

    contentItem: ColumnLayout {

        // Popups live in the window overlay, outside the mirrored MainView
        // tree, so right-to-left layout has to be re-enabled on the content.
        LayoutMirroring.enabled: translator.rtl
        LayoutMirroring.childrenInherit: true
        spacing: units.gu(1)

        // Click / APK switch
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(0.6)

            Repeater {
                model: [
                    { value: "click", label: translator.tr("appPicker.click") },
                    { value: "apk", label: translator.tr("appPicker.apk") }
                ]

                delegate: AbstractButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gu(4.6)
                    onClicked: root.setKind(modelData.value)

                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.5)
                        color: root.kind === modelData.value
                               ? (root.appTheme && root.appTheme.colors
                                  ? root.appTheme.colors.primary : "#00695C")
                               : (root.appTheme && root.appTheme.colors
                                  ? root.appTheme.colors.surfaceTint : "#ECEFF1")

                        Label {
                            anchors.centerIn: parent
                            text: modelData.label
                            fontSize: "small"
                            color: root.kind === modelData.value
                                   ? (root.appTheme && root.appTheme.colors
                                      ? root.appTheme.colors.primaryText : "#FFFFFF")
                                   : (root.appTheme && root.appTheme.colors
                                      ? root.appTheme.colors.surfaceText : "#1B1D21")
                        }
                    }
                }
            }
        }

        // Search bar
        TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: ""
            onTextChanged: root.filterApps(text)
        }

        Label {
            Layout.fillWidth: true
            text: translator.tr_args("apkPickerPage.apps",
                                     JSON.stringify({ n: root.filteredApps.length }))
            fontSize: "x-small"
            color: root.appTheme && root.appTheme.colors
                   ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
        }

        // App list
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
                                name: modelData.icon && modelData.icon.length > 0 ? modelData.icon : "package-x-generic-symbolic"
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
                    width: parent.width - units.gu(4)
                    visible: root.filteredApps.length === 0
                    text: translator.tr("assetPicker.emptyList")
                    fontSize: "small"
                    horizontalAlignment: Text.AlignHCenter
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#888888"
                }
            }
        }

        // Bottom actions
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                Layout.fillWidth: true
                text: translator.tr("general.open")
                onClicked: {
                    root.pickCustomFile()
                    root.close()
                }
            }

            Button {
                Layout.preferredWidth: units.gu(12)
                text: translator.tr("general.cancel")
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }
        }
    }
}
