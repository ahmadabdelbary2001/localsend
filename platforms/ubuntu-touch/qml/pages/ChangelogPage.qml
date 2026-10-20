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
        title: translator.tr("changelogPage.title")
    }

    Flickable {
        // Start below the PageHeader, otherwise the newest entry is hidden
        // behind it (the Flickable would otherwise fill the whole page).
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
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
