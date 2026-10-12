import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

RowLayout {
    id: root
    property var appTheme
    property string label: ""
    property string placeholder: ""
    property alias text: field.text
    signal edited(string value)

    Layout.fillWidth: true
    spacing: units.gu(1)

    Label {
        Layout.fillWidth: true
        text: root.label
        color: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
        fontSize: "small"
        wrapMode: Text.Wrap
    }

    TextField {
        id: field
        Layout.preferredWidth: units.gu(15)
        placeholderText: root.placeholder
        onTextChanged: debounce.restart()
    }

    // Emits `edited` 600ms after the user stops typing.
    Timer {
        id: debounce
        interval: 600
        repeat: false
        onTriggered: root.edited(field.text)
    }
}
