import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../components"
import "../dialogs"

Page {
    id: page
    property var appTheme

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + units.gu(4)
        clip: true

        ColumnLayout {
            id: col
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: units.gu(2)
            }
            spacing: units.gu(1.5)

            // ---------------- General ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.general.title")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1)

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("settingsTab.general.brightness")
                        fontSize: "small"
                        color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
                    }

                    ComboBox {
                        Layout.preferredWidth: units.gu(15)
                        model: [
                            translator.tr("settingsTab.general.brightnessOptions.system"),
                            translator.tr("settingsTab.general.brightnessOptions.light"),
                            translator.tr("settingsTab.general.brightnessOptions.dark")
                        ]
                        readonly property var values: ["system", "light", "dark"]
                        currentIndex: values.indexOf(settingsController.theme) >= 0
                                      ? values.indexOf(settingsController.theme) : 0
                        onActivated: settingsController.set_theme(values[currentIndex])
                    }
                }

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.general.language")
                    buttonLabel: settingsController.locale.length > 0
                                 ? settingsController.locale
                                 : translator.tr("settingsTab.general.languageOptions.system")
                    onTapped: languageDialog.open()
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.general.animations")
                    checked: settingsController.enableAnimations
                    onToggled: settingsController.set_enable_animations(value)
                }
            }

            // ---------------- Receive ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.receive.title")

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.quickSave")
                    checked: settingsController.quickSave
                    onToggled: settingsController.set_quick_save(value)
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.quickSaveFromFavorites")
                    checked: settingsController.quickSaveFromFavorites
                    onToggled: settingsController.set_quick_save_from_favorites(value)
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.autoFinish")
                    checked: settingsController.autoFinish
                    onToggled: settingsController.set_auto_finish(value)
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.saveToHistory")
                    checked: settingsController.saveToHistory
                    onToggled: settingsController.set_save_to_history(value)
                }
            }

            // ---------------- Network ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.network.title")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1)

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("settingsTab.network.server")
                        fontSize: "small"
                        color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
                    }

                    Row {
                        spacing: units.gu(0.5)

                        Button {
                            text: "▶"
                            visible: !serverController.running
                            onClicked: serverController.start(
                                settingsController.alias,
                                settingsController.port,
                                settingsController.https,
                                settingsController.receivePin)
                        }

                        Button {
                            text: "⟲"
                            visible: serverController.running
                            onClicked: {
                                serverController.stop()
                                serverController.start(
                                    settingsController.alias,
                                    settingsController.port,
                                    settingsController.https,
                                    settingsController.receivePin)
                            }
                        }

                        Button {
                            text: "■"
                            enabled: serverController.running
                            onClicked: serverController.stop()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1)

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("settingsTab.network.alias")
                        fontSize: "small"
                        color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
                    }

                    TextField {
                        Layout.preferredWidth: units.gu(15)
                        text: settingsController.alias
                        onEditingFinished: settingsController.set_alias(text)
                    }

                    Button {
                        text: "🎲"
                        onClicked: settingsController.random_alias()
                    }
                }

                SettingsTextField {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.network.port")
                    text: settingsController.port.toString()
                    onEdited: {
                        var p = parseInt(value)
                        if (!isNaN(p) && p > 0 && p < 65536) {
                            settingsController.set_port(p)
                        }
                    }
                }
            }

            // ---------------- Advanced (visible when enabled) ----------------
            SettingsSwitch {
                appTheme: page.appTheme
                label: translator.tr("settingsTab.advancedSettings")
                checked: settingsController.advancedSettings
                onToggled: settingsController.set_advanced_settings(value)
            }

            // ---------------- Other ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.other.title")

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("aboutPage.title")
                    buttonLabel: translator.tr("general.open")
                    onTapped: Qt.openUrlExternally("https://localsend.org")
                }

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.other.privacyPolicy")
                    buttonLabel: translator.tr("general.open")
                    onTapped: Qt.openUrlExternally("https://localsend.org/privacy")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: "Version"
                        fontSize: "small"
                        color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
                    }
                    Label {
                        text: appController.coreVersion
                        fontSize: "small"
                        color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                    }
                }
            }
        }
    }

    LanguageDialog {
        id: languageDialog
        appTheme: page.appTheme
        currentLocale: settingsController.locale
        onLocaleSelected: settingsController.set_locale(code)
    }
}
