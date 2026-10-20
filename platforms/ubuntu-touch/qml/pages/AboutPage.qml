import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Page {
    id: page
    property var appTheme
    // Lomiri PageStack that owns this page, used to open the changelog.
    property var navigationStack

    // The PageStack installs a working back action on the PageHeader
    // automatically, so no custom leading action is needed here.
    header: PageHeader {
        title: translator.tr("aboutPage.title")
    }

    Flickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: col.height + units.gu(6)
        clip: true

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
            spacing: units.gu(1.5)

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: units.gu(16)
                Layout.preferredHeight: units.gu(16)
                source: "qrc:/qml/assets/logo.png"
                fillMode: Image.PreserveAspectFit
                visible: source.toString().length > 0
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: "LocalSend"
                fontSize: "x-large"
                color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: appController.core_version
                fontSize: "small"
                color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: units.gu(2)
                text: "© 2022-" + new Date().getFullYear() + " Tien Do Nam"
                fontSize: "small"
                horizontalAlignment: Text.AlignHCenter
                color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: units.gu(1)
                text: translator.tr("aboutPage.description")
                wrapMode: Text.Wrap
                fontSize: "small"
                color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: units.gu(2)
                spacing: units.gu(0.5)

                Button {
                    Layout.fillWidth: true
                    text: "localsend.org"
                    onClicked: Qt.openUrlExternally("https://localsend.org")
                }
                Button {
                    Layout.fillWidth: true
                    text: "Source Code (GitHub)"
                    onClicked: Qt.openUrlExternally("https://github.com/localsend/localsend")
                }
                Button {
                    Layout.fillWidth: true
                    text: "Source Code (Codeberg)"
                    onClicked: Qt.openUrlExternally("https://codeberg.org/localsend/localsend")
                }
                Button {
                    Layout.fillWidth: true
                    text: "Apache License 2.0"
                    onClicked: Qt.openUrlExternally("https://www.apache.org/licenses/LICENSE-2.0")
                }

                Button {
                    Layout.fillWidth: true
                    text: translator.tr("changelogPage.title")
                    onClicked: if (page.navigationStack) page.navigationStack.push(Qt.resolvedUrl("ChangelogPage.qml"), {
                        appTheme: page.appTheme,
                        navigationStack: page.navigationStack
                    })
                }
            }
        }
    }
}
