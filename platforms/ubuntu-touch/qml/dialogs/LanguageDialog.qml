import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Dialog {
    id: root
    property var appTheme
    property string currentLocale: ""
    signal localeSelected(string code)

    title: translator.tr("settingsTab.general.language")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))
    height: Math.min(parent.height - units.gu(8), units.gu(75))

    // Locale codes and their self-names (language name in that language).
    // Matches the AppLocale enum in the Flutter app.
    readonly property var locales: [
        { code: "",          name: qsTr("System") },
        { code: "en",        name: "English" },
        { code: "ar",        name: "العربية" },
        { code: "az",        name: "Azərbaycanca" },
        { code: "be",        name: "Беларуская" },
        { code: "bg",        name: "Български" },
        { code: "bn",        name: "বাংলা" },
        { code: "ca",        name: "Català" },
        { code: "cs",        name: "Česky" },
        { code: "da",        name: "Dansk" },
        { code: "de",        name: "Deutsch" },
        { code: "el",        name: "Ελληνικά" },
        { code: "es_ES",     name: "Español" },
        { code: "et",        name: "Eesti keel" },
        { code: "eu",        name: "Euskara" },
        { code: "fa",        name: "فارسی" },
        { code: "fi",        name: "Suomi" },
        { code: "fr",        name: "Français" },
        { code: "ga",        name: "Gaeilge" },
        { code: "gl",        name: "Galego" },
        { code: "gu",        name: "ગુજરાતી" },
        { code: "he",        name: "עברית" },
        { code: "hi",        name: "हिन्दी" },
        { code: "hu",        name: "Magyar" },
        { code: "hy",        name: "Հայերեն" },
        { code: "id",        name: "Bahasa Indonesia" },
        { code: "it",        name: "Italiano" },
        { code: "ja",        name: "日本語" },
        { code: "ko",        name: "한국어" },
        { code: "ms",        name: "Bahasa Melayu" },
        { code: "nl",        name: "Nederlands" },
        { code: "pl",        name: "Polski" },
        { code: "pt_BR",     name: "Português (Brasil)" },
        { code: "pt_PT",     name: "Português (Portugal)" },
        { code: "ro",        name: "Română" },
        { code: "ru",        name: "Русский" },
        { code: "sv",        name: "Svenska" },
        { code: "th",        name: "ไทย" },
        { code: "tr",        name: "Türkçe" },
        { code: "uk",        name: "Українська" },
        { code: "ur",        name: "اردو" },
        { code: "vi",        name: "Tiếng Việt" },
        { code: "zh_CN",     name: "简体中文" },
        { code: "zh_TW",     name: "繁體中文 (台灣)" }
    ]

    contentItem: ListView {
        clip: true
        model: root.locales

        delegate: ListItem {
            height: units.gu(6)
            onClicked: {
                root.localeSelected(modelData.code)
                root.close()
            }

            ListItemLayout {
                title.text: modelData.name
                title.color: root.appTheme ? root.appTheme.colors.surfaceText : "#1B1D21"

                Icon {
                    SlotsLayout.position: SlotsLayout.Trailing
                    name: "tick"
                    visible: modelData.code === root.currentLocale
                    color: root.appTheme ? root.appTheme.colors.primary : "#00695C"
                }
            }
        }
    }
}
