import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

RowLayout {
    id: root
    property var appTheme
    property string label: ""
    property string placeholder: ""
    /// Persisted value. When it changes (random alias, reset), the field is
    /// refreshed; typing only updates `field.text` and is persisted via
    /// `edited` after the debounce.
    property string value: ""
    property int inputMethodHints: Qt.ImhNone
    signal edited(string editedValue)

    Layout.fillWidth: true
    spacing: units.gu(1)

    onValueChanged: {
        if (field.text !== value)
            field.text = value
    }

    Label {
        Layout.fillWidth: true
        text: root.label
        color: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
        fontSize: "small"
        wrapMode: Text.Wrap
    }

    TextField {
        id: field
        Layout.preferredWidth: units.gu(16)
        placeholderText: root.placeholder
        inputMethodHints: root.inputMethodHints
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
