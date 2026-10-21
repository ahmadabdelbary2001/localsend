// SPDX-License-Identifier: Apache-2.0
//
// QML and the Ubuntu Touch logo are embedded in the binary. Runtime-loaded
// components must also be listed here; files copied into the .click alone
// are not visible to a qrc:/qml/... URL.

use qmetaobject::qrc;

pub fn register() {
    qrc!(init_resources,
        "/qml" {
            "qml/Main.qml" as "Main.qml",
            "qml/shell/AppShell.qml" as "shell/AppShell.qml",
            "qml/shell/BottomNavigation.qml" as "shell/BottomNavigation.qml",
            "qml/pages/AboutPage.qml" as "pages/AboutPage.qml",
            "qml/pages/ChangelogPage.qml" as "pages/ChangelogPage.qml",
            "qml/pages/ReceivePage.qml" as "pages/ReceivePage.qml",
            "qml/pages/SendPage.qml" as "pages/SendPage.qml",
            "qml/pages/SettingsPage.qml" as "pages/SettingsPage.qml",
            "qml/pages/WebReceivePage.qml" as "pages/WebReceivePage.qml",
            "qml/js/qrcode.js" as "js/qrcode.js",
            "qml/dialogs/QrDialog.qml" as "dialogs/QrDialog.qml",
            "qml/assets/qr-code.svg" as "assets/qr-code.svg",
            "qml/theme/Theme.qml" as "theme/Theme.qml",
            "qml/pickers/ContentHubPicker.qml" as "pickers/ContentHubPicker.qml",
            "qml/components/DeviceCard.qml" as "components/DeviceCard.qml",
            "qml/components/BigButton.qml" as "components/BigButton.qml",
            "qml/components/SettingsSection.qml"   as "components/SettingsSection.qml",
            "qml/components/SettingsSwitch.qml"    as "components/SettingsSwitch.qml",
            "qml/components/SettingsButton.qml"    as "components/SettingsButton.qml",
            "qml/components/SettingsTextField.qml" as "components/SettingsTextField.qml",
            "qml/components/DialogFrame.qml"       as "components/DialogFrame.qml",
            "qml/components/IconButton.qml"        as "components/IconButton.qml",
            "qml/dialogs/IncomingTransferDialog.qml" as "dialogs/IncomingTransferDialog.qml",
            "qml/dialogs/SendProgressDialog.qml" as "dialogs/SendProgressDialog.qml",
            "qml/dialogs/HistoryDialog.qml" as "dialogs/HistoryDialog.qml",
            "qml/dialogs/DeviceDetailsDialog.qml" as "dialogs/DeviceDetailsDialog.qml",
            "qml/dialogs/PinDialog.qml" as "dialogs/PinDialog.qml",
            "qml/dialogs/MessageInputDialog.qml"   as "dialogs/MessageInputDialog.qml",
            "qml/dialogs/ManualSendDialog.qml"     as "dialogs/ManualSendDialog.qml",
            "qml/dialogs/FolderPickerDialog.qml"   as "dialogs/FolderPickerDialog.qml",
            "qml/dialogs/AppPickerDialog.qml"      as "dialogs/AppPickerDialog.qml",
            "qml/dialogs/LanguageDialog.qml"       as "dialogs/LanguageDialog.qml",
            "qml/dialogs/OptionPickDialog.qml"     as "dialogs/OptionPickDialog.qml",
            "assets/logo.png" as "assets/logo.png",
        }
    );

    init_resources();
}
