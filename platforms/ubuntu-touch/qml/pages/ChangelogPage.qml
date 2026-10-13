import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Page {
    id: page
    property var appTheme

    header: PageHeader {
        title: translator.tr("changelogPage.title")
        leadingActionBar.actions: [
            Action {
                iconName: "back"
                text: qsTr("Back")
                onTriggered: pageStack.pop()
            }
        ]
    }

    Flickable {
        anchors.fill: parent
        contentWidth: parent.width
        contentHeight: contentText.height + units.gu(4)
        clip: true

        Text {
            id: contentText
            x: units.gu(2)
            y: units.gu(2)
            width: parent.width - units.gu(4)
            text: appController.changelog_text
            textFormat: Text.MarkdownText
            wrapMode: Text.WordWrap
            color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
            font.pixelSize: units.dp(14)
        }
    }
}
