import QtQuick 2.15
import Lomiri.Components 1.3

// Language picker: OptionPickDialog fed by translator.available_locales(),
// so the list can never drift from the embedded translation files.
OptionPickDialog {
    id: root

    property string currentLocale: ""
    signal localeSelected(string code)

    // Re-evaluated when the active language changes so the "System" entry is
    // always labelled in the current language.
    property string activeLocale: translator.locale

    readonly property var locales: {
        var active = root.activeLocale
        var list = []
        try {
            list = JSON.parse(translator.available_locales())
        } catch (e) {
            console.warn("[LanguageDialog] failed to parse locales:", e)
            list = []
        }
        // The picker list comes from build.rs / translator.available_locales(),
        // so QML and the embedded i18n files can never drift apart.
        var options = list.map(function(entry) {
            return { value: entry.code, label: entry.name }
        })
        options.unshift({
            value: "",
            label: translator.tr("settingsTab.general.languageOptions.system")
        })
        return options
    }

    title: translator.tr("settingsTab.general.language")
    options: root.locales
    currentValue: root.currentLocale
    onPicked: root.localeSelected(value)
}
