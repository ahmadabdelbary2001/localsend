// SPDX-License-Identifier: Apache-2.0
//
// QML resources are compiled into the binary via qmetaobject-rs `qrc!`.
// This avoids shipping loose .qml files in the .click and keeps the
// frontend self-contained.

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
        }
    );

    init_resources();
}