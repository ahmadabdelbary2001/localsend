import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

RowLayout {
    id: root
    property var appTheme
    property string label: ""
    property bool checked: false
    signal toggled(bool value)

    Layout.fillWidth: true
    spacing: units.gu(1)

    Label {
        Layout.fillWidth: true
        text: root.label
        color: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
        fontSize: "small"
        wrapMode: Text.Wrap
        opacity: root.enabled ? 1.0 : 0.5
    }

    Switch {
        id: control
        Layout.preferredWidth: units.gu(6)
        checked: root.checked
        enabled: root.enabled

        // `onClicked` is only emitted for user interaction. Re-establish the
        // binding afterwards so a rejected change (e.g. cancelled PIN dialog)
        // snaps the switch back to the persisted value.
        onClicked: {
            root.toggled(control.checked)
            control.checked = Qt.binding(function() { return root.checked })
        }
    }
}
