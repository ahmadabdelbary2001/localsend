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
        color: appTheme ? appTheme.colors.surfaceText : "#1B1D21"
        fontSize: "small"
        wrapMode: Text.Wrap
    }

    Switch {
        Layout.preferredWidth: units.gu(6)
        checked: root.checked
        onCheckedChanged: {
            if (checked !== root.checked) {
                root.toggled(checked)
            }
        }
    }
}
