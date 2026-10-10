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
            "qml/pages/ReceivePage.qml" as "pages/ReceivePage.qml",
            "qml/pages/SendPage.qml" as "pages/SendPage.qml",
            "qml/pages/SettingsPage.qml" as "pages/SettingsPage.qml",
            "qml/theme/Theme.qml" as "theme/Theme.qml",
            "qml/theme/Colors.qml" as "theme/Colors.qml",
            "qml/theme/Metrics.qml" as "theme/Metrics.qml",
            "qml/components/ContentHubPicker.qml" as "components/ContentHubPicker.qml",
            "qml/components/DeviceCard.qml" as "components/DeviceCard.qml",
            "qml/dialogs/IncomingTransferDialog.qml" as "dialogs/IncomingTransferDialog.qml",
            "qml/dialogs/SendProgressDialog.qml" as "dialogs/SendProgressDialog.qml",
            "assets/logo.png" as "assets/logo.png",
        }
    );

    init_resources();
}
