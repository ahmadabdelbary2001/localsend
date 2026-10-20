// SPDX-License-Identifier: Apache-2.0
//
// Translator QObject.
//
// All translations from app/assets/i18n are embedded at build time (see
// build.rs), flattened to dotted keys and resolved ("@:key" references).
// Exposes:
//   tr(key)                 -> QString
//   tr_args(key, json)      -> QString  (JSON object for {placeholder} args)
//   set_locale(locale)      -> switch locale ("system" / "" detects the
//                              system language, unknown tags fall back to en)
//   available_locales()     -> JSON [{ code, name }] of embedded locales
//   rtl                     -> true for right-to-left languages

use std::collections::HashMap;
use std::sync::OnceLock;

use qmetaobject::prelude::*;
use serde_json::Value;

mod generated {
    include!(concat!(env!("OUT_DIR"), "/locales.rs"));
}

pub const DEFAULT_LOCALE: &str = "en";

const RTL_LANGUAGES: &[&str] = &["ar", "fa", "he", "ur"];

/// Order used by the language picker. Mirrors the AppLocale enum in the
/// Flutter app so both frontends present the same list.
const LOCALE_ORDER: &[&str] = &[
    "en", "ar", "az", "be", "bg", "bn", "ca", "cs", "da", "de", "el", "et", "eu", "fa", "fi", "fr",
    "ga", "gl", "gu", "he", "hi", "hu", "hy", "id", "it", "ja", "km", "ko", "ky", "lo", "ml", "mn",
    "ms", "ne", "nl", "pl", "ro", "ru", "si", "sk", "sl", "sr", "sv", "ta", "th", "tr", "uk", "ur",
    "uz", "vi", "en-IN", "es-ES", "fil-PH", "pt-BR", "pt-PT", "sr-Cyrl", "zh-CN", "zh-HK", "zh-TW",
];

/// Native language names, keyed by BCP-47-ish tag (as used by the i18n files).
const LOCALE_NAMES: &[(&str, &str)] = &[
    ("ar", "العربية"),
    ("az", "Azərbaycanca"),
    ("be", "Беларуская"),
    ("bg", "Български"),
    ("bn", "বাংলা"),
    ("ca", "Català"),
    ("cs", "Česky"),
    ("da", "Dansk"),
    ("de", "Deutsch"),
    ("el", "Ελληνικά"),
    ("en", "English"),
    ("en-IN", "English (India)"),
    ("es-ES", "Español"),
    ("et", "Eesti keel"),
    ("eu", "Euskara"),
    ("fa", "فارسی"),
    ("fi", "Suomi"),
    ("fil-PH", "Filipino"),
    ("fr", "Français"),
    ("ga", "Gaeilge"),
    ("gl", "Galego"),
    ("gu", "ગુજરાતી"),
    ("he", "עברית"),
    ("hi", "हिन्दी"),
    ("hu", "Magyar"),
    ("hy", "Հայերեն"),
    ("id", "Bahasa Indonesia"),
    ("it", "Italiano"),
    ("ja", "日本語"),
    ("km", "ភាសាខ្មែរ"),
    ("ko", "한국어"),
    ("ky", "Кыргызча"),
    ("lo", "ລາວ"),
    ("ml", "മലയാളം"),
    ("mn", "Монгол"),
    ("ms", "Bahasa Melayu"),
    ("ne", "नेपाली"),
    ("nl", "Nederlands"),
    ("pl", "Polski"),
    ("pt-BR", "Português (Brasil)"),
    ("pt-PT", "Português (Portugal)"),
    ("ro", "Română"),
    ("ru", "Русский"),
    ("si", "සිංහල"),
    ("sk", "Slovenčina"),
    ("sl", "Slovenščina"),
    ("sr", "Srpski (latinica)"),
    ("sr-Cyrl", "Српски (ћирилица)"),
    ("sv", "Svenska"),
    ("ta", "தமிழ்"),
    ("th", "ไทย"),
    ("tr", "Türkçe"),
    ("uk", "Українська"),
    ("ur", "اردو"),
    ("uz", "Oʻzbekcha"),
    ("vi", "Tiếng Việt"),
    ("zh-CN", "简体中文"),
    ("zh-HK", "繁體中文 (香港)"),
    ("zh-TW", "繁體中文 (台灣)"),
];

struct LocaleCatalog {
    /// Canonical tags, in picker order.
    tags: Vec<&'static str>,
    translations: HashMap<&'static str, HashMap<String, String>>,
}

fn catalog() -> &'static LocaleCatalog {
    static CATALOG: OnceLock<LocaleCatalog> = OnceLock::new();
    CATALOG.get_or_init(|| {
        let mut by_tag: HashMap<&'static str, HashMap<String, String>> = HashMap::new();
        for (tag, json) in generated::LOCALE_FILES {
            by_tag.insert(tag, load_and_resolve(json));
        }

        // Present the picker in the same order as Flutter, then append any
        // embedded locale that is not part of the Flutter enum yet.
        let mut tags: Vec<&'static str> = LOCALE_ORDER
            .iter()
            .copied()
            .filter(|tag| by_tag.contains_key(tag))
            .collect();
        let mut extra: Vec<&'static str> = by_tag
            .keys()
            .copied()
            .filter(|tag| !tags.contains(tag))
            .collect();
        extra.sort_unstable();
        tags.extend(extra);

        log::info!(
            "Translator embedded {} locale(s): {}",
            tags.len(),
            tags.join(", ")
        );

        LocaleCatalog {
            tags,
            translations: by_tag,
        }
    })
}

fn name_for(tag: &str) -> &'static str {
    LOCALE_NAMES
        .iter()
        .find(|(code, _)| code.eq_ignore_ascii_case(tag))
        .map(|(_, name)| *name)
        // `tag` is a &'static str from the catalog, and unknown locales simply
        // show their tag. Leaking at most a handful of tags is fine.
        .unwrap_or_else(|| Box::leak(tag.to_string().into_boxed_str()))
}

/// True when the language writes right-to-left.
pub fn is_rtl(locale: &str) -> bool {
    let language = locale
        .split(['-', '_'])
        .next()
        .unwrap_or(locale)
        .to_ascii_lowercase();
    RTL_LANGUAGES.contains(&language.as_str())
}

/// Normalizes a POSIX locale (e.g. `es_ES.UTF-8@euro`) to a tag used by the
/// i18n files (`es-ES`). `sr_RS@latin` / `sr_RS@cyrillic` are mapped to the
/// two Serbian variants the app ships.
fn normalize_tag(raw: &str) -> String {
    let raw = raw.trim();
    if raw.is_empty() {
        return String::new();
    }

    let (base, modifier) = match raw.split_once('@') {
        Some((base, modifier)) => (base, Some(modifier)),
        None => (raw, None),
    };

    // Drop the encoding (`.UTF-8`).
    let base = base.split('.').next().unwrap_or(base);
    let tag = base.replace('_', "-");

    let modifier = modifier.unwrap_or("").to_ascii_lowercase();
    if tag.to_ascii_lowercase().starts_with("sr-") {
        if modifier.contains("cyrillic") {
            return "sr-Cyrl".to_string();
        }
        if modifier.contains("latin") {
            return "sr".to_string();
        }
    }

    // Drop a trailing `-C`/`-POSIX` style charset suffix only when it follows
    // a real locale component (e.g. `en_US-POSIX`).
    let parts: Vec<&str> = tag.split('-').collect();
    let tag = if parts.len() > 1 {
        parts
            .into_iter()
            .filter(|part| {
                let lower = part.to_ascii_lowercase();
                !(lower == "utf8" || lower == "posix" || lower == "c")
            })
            .collect::<Vec<_>>()
            .join("-")
    } else {
        tag
    };

    tag
}

fn canonical_tag(tag: &str) -> Option<&'static str> {
    catalog()
        .tags
        .iter()
        .copied()
        .find(|known| known.eq_ignore_ascii_case(tag))
}

/// Best-effort match for a single POSIX locale string.
fn match_candidate(raw: &str) -> Option<&'static str> {
    let tag = normalize_tag(raw);
    if tag.is_empty() {
        return None;
    }
    if let Some(exact) = canonical_tag(&tag) {
        return Some(exact);
    }

    // Language-only fallback: `de_DE` -> `de`, `pt` -> `pt-BR`,
    // `es` -> `es-ES`, `zh` -> `zh-CN`, `sr` -> `sr`, ...
    let language = tag.split('-').next().unwrap_or(&tag).to_ascii_lowercase();
    let preferred = match language.as_str() {
        "en" => "en",
        "es" => "es-ES",
        "pt" => "pt-BR",
        "zh" => "zh-CN",
        "fil" | "tl" => "fil-PH",
        "sr" => "sr",
        other => other,
    };
    if let Some(found) = canonical_tag(preferred) {
        return Some(found);
    }

    catalog()
        .tags
        .iter()
        .copied()
        .find(|known| known.split('-').next().unwrap_or(known).eq_ignore_ascii_case(&language))
}

/// Detects the system language from the standard POSIX environment
/// variables, honoring `LANGUAGE`'s priority list.
pub fn detect_system_locale() -> String {
    let mut candidates: Vec<String> = Vec::new();

    if let Ok(language) = std::env::var("LANGUAGE") {
        candidates.extend(
            language
                .split(':')
                .map(str::trim)
                .filter(|part| !part.is_empty())
                .map(str::to_string),
        );
    }
    for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
        if let Ok(value) = std::env::var(key) {
            if !value.trim().is_empty() {
                candidates.push(value);
            }
        }
    }

    resolve_first(&candidates).unwrap_or_else(|| DEFAULT_LOCALE.to_string())
}

/// Resolves the first candidate that maps to an embedded locale.
fn resolve_first(candidates: &[String]) -> Option<String> {
    for candidate in candidates {
        if candidate.eq_ignore_ascii_case("c") || candidate.eq_ignore_ascii_case("posix") {
            continue;
        }
        if let Some(tag) = match_candidate(candidate) {
            return Some(tag.to_string());
        }
    }
    None
}

/// Resolves a stored locale setting (`None`/empty/"system" -> detection).
pub fn resolve_locale(requested: Option<&str>) -> String {
    match requested {
        Some(value) if !value.is_empty() && !value.eq_ignore_ascii_case("system") => {
            match_candidate(value).unwrap_or(DEFAULT_LOCALE).to_string()
        }
        _ => detect_system_locale(),
    }
}

/// Looks up a single key for an arbitrary locale (used by the web upload
/// page, which is rendered by the Rust core, not by QML).
pub fn translate(locale: &str, key: &str) -> String {
    if let Some(value) = catalog()
        .translations
        .get(locale)
        .and_then(|map| map.get(key))
    {
        return value.clone();
    }
    catalog()
        .translations
        .get(DEFAULT_LOCALE)
        .and_then(|map| map.get(key))
        .cloned()
        .unwrap_or_else(|| key.to_string())
}

fn strings_for(locale: &str) -> HashMap<String, String> {
    catalog()
        .translations
        .get(locale)
        .cloned()
        .unwrap_or_default()
}

#[derive(QObject)]
pub struct Translator {
    base: qt_base_class!(trait QObject),

    /// Active locale tag, e.g. "en" or "es-ES".
    locale: qt_property!(QString; NOTIFY locale_changed),
    locale_changed: qt_signal!(),

    /// True when the active locale is right-to-left.
    rtl: qt_property!(bool; NOTIFY locale_changed),

    /// Translate a key. Returns the key itself if not found, so missing
    /// translations are visible in the UI instead of blank labels.
    tr: qt_method!(fn(&mut self, key: QString) -> QString),

    /// Translate with {placeholder} substitution.
    /// `args_json` must be a JSON object, e.g. `{"files":3}`.
    tr_args: qt_method!(fn(&mut self, key: QString, args_json: QString) -> QString),

    set_locale: qt_method!(fn(&mut self, loc: QString)),

    /// JSON array `[{"code":"en","name":"English"}, ...]` in picker order.
    available_locales: qt_method!(fn(&self) -> QString),

    /// Non-Qt state.
    strings: HashMap<String, String>,
}

impl Translator {
    pub fn new(initial_locale: Option<String>) -> Self {
        let active = resolve_locale(initial_locale.as_deref());
        let strings = strings_for(&active);
        log::info!(
            "Translator active locale initialized to '{active}' ({} keys)",
            strings.len()
        );

        Self {
            base: Default::default(),
            locale: QString::from(active.clone()),
            locale_changed: Default::default(),
            rtl: is_rtl(&active),
            tr: Default::default(),
            tr_args: Default::default(),
            set_locale: Default::default(),
            available_locales: Default::default(),
            strings,
        }
    }

    pub fn set_locale(&mut self, loc: QString) {
        let requested = loc.to_string();
        let target = resolve_locale(Some(&requested));
        log::info!("Translator switching locale to: '{target}' (requested '{requested}')");
        self.locale = QString::from(target.clone());
        self.rtl = is_rtl(&target);
        self.strings = strings_for(&target);
        self.locale_changed();
    }

    fn tr(&mut self, key: QString) -> QString {
        let k = key.to_string();
        if let Some(s) = self.strings.get(&k) {
            return QString::from(s.clone());
        }
        // Fallback to English if the active locale lacks the key.
        if let Some(s) = catalog()
            .translations
            .get(DEFAULT_LOCALE)
            .and_then(|map| map.get(&k))
        {
            return QString::from(s.clone());
        }
        log::debug!("missing translation key: {k}");
        QString::from(k)
    }

    fn tr_args(&mut self, key: QString, args_json: QString) -> QString {
        let template = self.tr(key).to_string();
        let json = args_json.to_string();
        if json.is_empty() {
            return QString::from(template);
        }
        let args: HashMap<String, Value> = match serde_json::from_str(&json) {
            Ok(m) => m,
            Err(e) => {
                log::warn!("trArgs: invalid JSON '{json}': {e}");
                return QString::from(template);
            }
        };
        let mut out = template;
        for (k, v) in args {
            let placeholder = format!("{{{k}}}");
            let repl = match v {
                Value::String(s) => s,
                Value::Number(n) => n.to_string(),
                Value::Bool(b) => b.to_string(),
                _ => continue,
            };
            out = out.replace(&placeholder, &repl);
        }
        QString::from(out)
    }

    fn available_locales(&self) -> QString {
        let entries: Vec<Value> = catalog()
            .tags
            .iter()
            .map(|tag| {
                serde_json::json!({
                    "code": tag,
                    "name": name_for(tag),
                })
            })
            .collect();
        QString::from(Value::Array(entries).to_string())
    }
}

// ---------- loading & resolution ----------

fn load_and_resolve(json: &str) -> HashMap<String, String> {
    let value: Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(e) => {
            log::error!("failed to parse i18n JSON: {e}");
            return HashMap::new();
        }
    };

    let mut flat: HashMap<String, String> = HashMap::new();
    flatten(&value, "", &mut flat);

    // Resolve "@:key" references (both direct "@:key" and inline "@:key" / "@:.relativeKey").
    // Iterate a few times to resolve chained references.
    for _ in 0..8 {
        let mut changed = false;
        let keys: Vec<String> = flat.keys().cloned().collect();
        for k in keys {
            let v = match flat.get(&k) {
                Some(v) => v.clone(),
                None => continue,
            };

            // Direct reference: "@:target"
            if let Some(target) = v.strip_prefix("@:") {
                let resolved_target = if let Some(rel) = target.strip_prefix('.') {
                    let parent = k.rsplit_once('.').map(|(p, _)| p).unwrap_or("");
                    if parent.is_empty() { rel.to_string() } else { format!("{parent}.{rel}") }
                } else {
                    target.to_string()
                };

                if let Some(resolved) = flat.get(&resolved_target).cloned() {
                    if resolved != v {
                        flat.insert(k.clone(), resolved);
                        changed = true;
                        continue;
                    }
                }
            }

            // Inline references: replace any "@:some.key" or "@:.relKey" within text
            if v.contains("@:") {
                let mut new_v = v.clone();
                let mut inline_changed = false;
                for part in v.split_whitespace() {
                    if let Some(target) = part.strip_prefix("@:") {
                        let clean_target = target.trim_matches(|c: char| !c.is_alphanumeric() && c != '.' && c != '_');
                        let resolved_target = if let Some(rel) = clean_target.strip_prefix('.') {
                            let parent = k.rsplit_once('.').map(|(p, _)| p).unwrap_or("");
                            if parent.is_empty() { rel.to_string() } else { format!("{parent}.{rel}") }
                        } else {
                            clean_target.to_string()
                        };

                        if let Some(resolved) = flat.get(&resolved_target) {
                            new_v = new_v.replace(&format!("@:{clean_target}"), resolved);
                            inline_changed = true;
                        }
                    }
                }
                if inline_changed && new_v != v {
                    flat.insert(k, new_v);
                    changed = true;
                }
            }
        }
        if !changed {
            break;
        }
    }

    // Prune "@..." informational keys.
    flat.retain(|k, _| !k.split('.').any(|seg| seg.starts_with('@')));

    flat
}

fn flatten(v: &Value, prefix: &str, out: &mut HashMap<String, String>) {
    match v {
        Value::String(s) => {
            out.insert(prefix.to_string(), s.clone());
        }
        Value::Object(map) => {
            if map.contains_key("other") {
                if let Some(Value::String(s)) = map.get("other") {
                    out.insert(prefix.to_string(), s.clone());
                    return;
                }
            }
            for (k, val) in map {
                let new_key = if prefix.is_empty() {
                    k.clone()
                } else {
                    format!("{prefix}.{k}")
                };
                flatten(val, &new_key, out);
            }
        }
        Value::Array(items) => {
            // Arrays in the i18n files are paragraph lists (e.g.
            // aboutPage.description, dialogs.quickSaveFromFavoritesNotice).
            let joined = items
                .iter()
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join("\n\n");
            if !joined.is_empty() {
                out.insert(prefix.to_string(), joined);
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn en_json() -> &'static str {
        generated::LOCALE_FILES
            .iter()
            .find(|(tag, _)| *tag == "en")
            .map(|(_, json)| *json)
            .expect("en.json embedded")
    }

    fn ar_json() -> &'static str {
        generated::LOCALE_FILES
            .iter()
            .find(|(tag, _)| *tag == "ar")
            .map(|(_, json)| *json)
            .expect("ar.json embedded")
    }

    #[test]
    fn loads_english() {
        let map = load_and_resolve(en_json());
        assert!(map.contains_key("appName"));
        assert_eq!(map["appName"], "LocalSend");
        assert_eq!(map["receiveTab.title"], "Receive");
        assert_eq!(map["settingsTab.general.brightness"], "Theme");
    }

    #[test]
    fn resolves_references() {
        let map = load_and_resolve(en_json());
        assert_eq!(map["receiveTab.quickSave.off"], "Off");
        assert_eq!(map["webSharePage.encryption"], "Encryption");
        assert_eq!(map["settingsTab.receive.requirePin"], "Require PIN");
    }

    #[test]
    fn joins_translation_arrays() {
        let map = load_and_resolve(en_json());
        // Array entries are paragraph lists, not single strings.
        assert!(map["aboutPage.description"].contains("\n\n"));
        assert!(map["dialogs.quickSaveFromFavoritesNotice.content"].contains("favorites"));
    }

    #[test]
    fn prunes_internal_keys() {
        let map = load_and_resolve(en_json());
        assert!(!map.keys().any(|k| k.contains("@info")));
        assert!(!map.keys().any(|k| k.contains("@combination")));
    }

    #[test]
    fn placeholder_substitution_works() {
        let mut t = Translator::new(Some("en".to_string()));
        t.strings
            .insert("x".into(), "Files: {files} / {n}".into());
        let out = t.tr_args(QString::from("x"), QString::from(r#"{"files":3,"n":10}"#));
        assert_eq!(out.to_string(), "Files: 3 / 10");
    }

    #[test]
    fn loads_arabic() {
        let map = load_and_resolve(ar_json());
        assert!(map.contains_key("appName"));
        assert_eq!(map["appName"], "LocalSend");
        assert_eq!(map["receiveTab.title"], "استلام");
        assert_eq!(map["webSharePage.title"], "مشاركة عبر الرابط");
    }

    #[test]
    fn catalog_contains_all_embedded_locales() {
        let catalog = catalog();
        assert!(catalog.tags.len() >= 59, "found only {}", catalog.tags.len());
        assert!(catalog.tags.contains(&"sr-Cyrl"));
        assert!(catalog.tags.contains(&"zh-HK"));
        assert!(catalog.tags.contains(&"fil-PH"));
        assert!(catalog.tags.contains(&"km"));
    }

    #[test]
    fn normalizes_posix_locales() {
        assert_eq!(normalize_tag("es_ES.UTF-8"), "es-ES");
        assert_eq!(normalize_tag("pt_BR"), "pt-BR");
        assert_eq!(normalize_tag("de_DE.UTF-8"), "de-DE");
        assert_eq!(normalize_tag("sr_RS@latin"), "sr");
        assert_eq!(normalize_tag("sr_RS@cyrillic"), "sr-Cyrl");
        assert_eq!(normalize_tag("C"), "C");
    }

    #[test]
    fn resolves_locales_with_fallback() {
        assert_eq!(match_candidate("es_ES.UTF-8"), Some("es-ES"));
        assert_eq!(match_candidate("pt_BR.UTF-8"), Some("pt-BR"));
        assert_eq!(match_candidate("pt_PT.UTF-8"), Some("pt-PT"));
        assert_eq!(match_candidate("de_DE.UTF-8"), Some("de"));
        assert_eq!(match_candidate("zh_CN.UTF-8"), Some("zh-CN"));
        assert_eq!(match_candidate("zh_HK.UTF-8"), Some("zh-HK"));
        assert_eq!(match_candidate("sr_RS@latin"), Some("sr"));
        assert_eq!(match_candidate("sr_RS@cyrillic"), Some("sr-Cyrl"));
        assert_eq!(match_candidate("fil_PH"), Some("fil-PH"));
        assert_eq!(match_candidate("fr_FR.UTF-8"), Some("fr"));
        assert_eq!(match_candidate("xx_YY"), None);
    }

    #[test]
    fn resolve_locale_handles_system_and_unknown() {
        assert_eq!(resolve_locale(Some("es_ES")), "es-ES");
        assert_eq!(resolve_locale(Some("xx_YY")), DEFAULT_LOCALE);
        assert!(!resolve_locale(None).is_empty());
    }

    #[test]
    fn detect_system_locale_uses_language_priority() {
        let candidates = vec![
            "de_DE.UTF-8".to_string(),
            "fr_FR.UTF-8".to_string(),
        ];
        assert_eq!(resolve_first(&candidates).as_deref(), Some("de"));
        assert_eq!(resolve_first(&["C".to_string()]), None);
    }

    #[test]
    fn rtl_languages_are_detected() {
        assert!(is_rtl("ar"));
        assert!(is_rtl("he"));
        assert!(is_rtl("fa"));
        assert!(is_rtl("ur"));
        assert!(!is_rtl("en"));
        assert!(!is_rtl("es-ES"));
    }

    #[test]
    fn available_locales_is_json() {
        let t = Translator::new(Some("en".to_string()));
        let json = t.available_locales().to_string();
        let parsed: Value = serde_json::from_str(&json).unwrap();
        let arr = parsed.as_array().unwrap();
        assert!(arr.len() >= 59);
        assert_eq!(arr[0]["code"], "en");
        assert!(arr.iter().any(|e| e["name"] == "العربية"));
    }

    /// Every `translator.tr("...")` / `tr_args("...")` key used in QML must
    /// exist in the embedded English catalog. A missing key is rendered
    /// verbatim (e.g. "webSharePage.openLink.other"), which is easy to miss.
    #[test]
    fn qml_translation_keys_exist() {
        use std::path::{Path, PathBuf};

        fn collect_qml(dir: &Path, out: &mut Vec<PathBuf>) {
            let Ok(entries) = std::fs::read_dir(dir) else {
                return;
            };
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    collect_qml(&path, out);
                } else if path.extension().and_then(|e| e.to_str()) == Some("qml") {
                    out.push(path);
                }
            }
        }

        fn keys_in(source: &str, needle: &str, out: &mut Vec<String>) {
            let mut rest = source;
            while let Some(idx) = rest.find(needle) {
                rest = &rest[idx + needle.len()..];
                let Some(end) = rest.find('"') else {
                    break;
                };
                out.push(rest[..end].to_string());
            }
        }

        let qml_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("qml");
        let mut files = Vec::new();
        collect_qml(&qml_dir, &mut files);
        assert!(!files.is_empty(), "no QML files under {}", qml_dir.display());

        let en = load_and_resolve(en_json());
        let mut missing = Vec::new();
        for file in &files {
            let Ok(source) = std::fs::read_to_string(file) else {
                continue;
            };
            let mut keys = Vec::new();
            keys_in(&source, "translator.tr(\"", &mut keys);
            keys_in(&source, "translator.tr_args(\"", &mut keys);
            for key in keys {
                if !en.contains_key(&key) {
                    missing.push(format!("{}: {key}", file.display()));
                }
            }
        }

        missing.sort();
        missing.dedup();
        assert!(
            missing.is_empty(),
            "QML uses translation keys missing from en.json:\n{}",
            missing.join("\n")
        );
    }
}
