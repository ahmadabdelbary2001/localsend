// SPDX-License-Identifier: Apache-2.0
//
// Translator QObject.
//
// Loads app/assets/i18n/<locale>.json at startup, flattens it to
// dotted keys, resolves "@:key" references, and exposes:
//   tr(key)            -> QString
//   trArgs(key, json)  -> QString  (JSON object for {placeholder} args)
//   set_locale(locale) -> QString  ("system" / "" detects system language)

use std::collections::HashMap;

use qmetaobject::prelude::*;
use serde_json::Value;

const EN_JSON: &str = include_str!("../../../../app/assets/i18n/en.json");
const AR_JSON: &str = include_str!("../../../../app/assets/i18n/ar.json");

/// Detect system language code from standard POSIX / system environment variables.
pub fn detect_system_locale() -> String {
    let raw = std::env::var("LC_ALL")
        .or_else(|_| std::env::var("LC_MESSAGES"))
        .or_else(|_| std::env::var("LANG"))
        .unwrap_or_default();
    let lower = raw.to_lowercase();
    let code = lower.split(|c| c == '.' || c == '_' || c == '-').next().unwrap_or("");
    if code == "ar" {
        "ar".to_string()
    } else {
        "en".to_string()
    }
}

#[derive(QObject)]
pub struct Translator {
    base: qt_base_class!(trait QObject),

    /// "en" | "ar" | ...
    locale: qt_property!(QString; NOTIFY locale_changed),
    locale_changed: qt_signal!(),

    /// Translate a key. Returns the key itself if not found, so missing
    /// translations are visible in the UI instead of blank labels.
    tr: qt_method!(fn(&mut self, key: QString) -> QString),

    /// Translate with {placeholder} substitution.
    /// `args_json` must be a JSON object, e.g. `{"files":3}`.
    tr_args: qt_method!(fn(&mut self, key: QString, args_json: QString) -> QString),
    set_locale: qt_method!(fn(&mut self, loc: QString)),

    /// Non-Qt state.
    strings: HashMap<String, String>,
    ar_strings: HashMap<String, String>,
    en_strings: HashMap<String, String>,
}

impl Translator {
    pub fn new(initial_locale: Option<String>) -> Self {
        let en_strings = load_and_resolve(EN_JSON);
        let ar_strings = load_and_resolve(AR_JSON);
        log::info!("Translator loaded {} EN keys, {} AR keys", en_strings.len(), ar_strings.len());

        let active = match initial_locale.as_deref() {
            Some(loc) if !loc.is_empty() && loc != "system" => loc.to_string(),
            _ => detect_system_locale(),
        };

        log::info!("Translator active locale initialized to: '{active}'");

        let strings = if active == "ar" {
            ar_strings.clone()
        } else {
            en_strings.clone()
        };

        Self {
            base: Default::default(),
            locale: QString::from(active),
            locale_changed: Default::default(),
            tr: Default::default(),
            tr_args: Default::default(),
            set_locale: Default::default(),
            strings,
            ar_strings,
            en_strings,
        }
    }

    pub fn set_locale(&mut self, loc: QString) {
        let s = loc.to_string();
        let target = if s.is_empty() || s == "system" {
            detect_system_locale()
        } else {
            s
        };
        log::info!("Translator switching locale to: '{target}'");
        self.locale = QString::from(target.clone());
        if target == "ar" {
            self.strings = self.ar_strings.clone();
        } else {
            self.strings = self.en_strings.clone();
        }
        self.locale_changed();
    }

    fn tr(&mut self, key: QString) -> QString {
        let k = key.to_string();
        if let Some(s) = self.strings.get(&k) {
            return QString::from(s.clone());
        }
        // Fallback to English if not found in current locale
        if let Some(s) = self.en_strings.get(&k) {
            return QString::from(s.clone());
        }
        // Fallback to Arabic if not found in English
        if let Some(s) = self.ar_strings.get(&k) {
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
        Value::Array(_) => {}
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_english() {
        let map = load_and_resolve(EN_JSON);
        assert!(map.contains_key("appName"));
        assert_eq!(map["appName"], "LocalSend");
        assert_eq!(map["receiveTab.title"], "Receive");
        assert_eq!(map["settingsTab.general.brightness"], "Theme");
    }

    #[test]
    fn resolves_references() {
        let map = load_and_resolve(EN_JSON);
        assert_eq!(map["receiveTab.quickSave.off"], "Off");
        assert_eq!(map["webSharePage.encryption"], "Encryption");
        assert_eq!(map["settingsTab.receive.requirePin"], "Require PIN");
    }

    #[test]
    fn prunes_internal_keys() {
        let map = load_and_resolve(EN_JSON);
        assert!(!map.keys().any(|k| k.contains("@info")));
        assert!(!map.keys().any(|k| k.contains("@combination")));
    }

    #[test]
    fn placeholder_substitution_works() {
        let mut t = Translator {
            base: Default::default(),
            locale: QString::from("en"),
            locale_changed: Default::default(),
            tr: Default::default(),
            tr_args: Default::default(),
            set_locale: Default::default(),
            strings: HashMap::new(),
            ar_strings: HashMap::new(),
            en_strings: HashMap::new(),
        };
        t.strings.insert("x".into(), "Files: {files} / {n}".into());
        let out = t.tr_args(QString::from("x"), QString::from(r#"{"files":3,"n":10}"#));
        assert_eq!(out.to_string(), "Files: 3 / 10");
    }

    #[test]
    fn loads_arabic() {
        let map = load_and_resolve(AR_JSON);
        assert!(map.contains_key("appName"));
        assert_eq!(map["appName"], "LocalSend");
        assert_eq!(map["receiveTab.title"], "استلام");
        assert_eq!(map["webSharePage.title"], "مشاركة عبر الرابط");
        assert_eq!(map["webSharePage.autoAccept"], "قبول الطلبات تلقائيًا");
        assert_eq!(map["webSharePage.requirePin"], "يتطلب رمز PIN");
        assert_eq!(map["webSharePage.encryption"], "التعمية");
    }
}
