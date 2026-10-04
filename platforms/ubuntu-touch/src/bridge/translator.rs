// SPDX-License-Identifier: Apache-2.0
//
// Translator QObject.
//
// Loads app/assets/i18n/<locale>.json at startup, flattens it to
// dotted keys, resolves "@:key" references, and exposes:
//   tr(key)            -> QString
//   trArgs(key, json)  -> QString  (JSON object for {placeholder} args)
//
// English is always available (embedded). Additional locales will be
// loaded from the same directory once the build pipeline copies them
// into the click. Runtime switching is a TODO; the locale property
// exists so QML can bind to it and rebuild when it changes.

use std::collections::HashMap;

use cstr::cstr;
use qmetaobject::prelude::*;
use serde_json::Value;

const EN_JSON: &str = include_str!("../../../../app/assets/i18n/en.json");

#[derive(QObject)]
pub struct Translator {
    base: qt_base_class!(trait QObject),

    /// "en" | "ar" | ...  Read/write to allow future locale switching.
    /// Changing it currently reloads nothing; a TODO will wire it.
    locale: qt_property!(QString; NOTIFY locale_changed),
    locale_changed: qt_signal!(),

    /// Translate a key. Returns the key itself if not found, so missing
    /// translations are visible in the UI instead of blank labels.
    tr: qt_method!(fn(&mut self, key: QString) -> QString),

    /// Translate with {placeholder} substitution.
    /// `args_json` must be a JSON object, e.g. `{"files":3}`.
    tr_args: qt_method!(fn(&mut self, key: QString, args_json: QString) -> QString),

    /// Non-Qt state.
    strings: HashMap<String, String>,
}

impl Translator {
    pub fn new() -> Self {
        let strings = load_and_resolve(EN_JSON);
        log::info!("Translator loaded {} keys", strings.len());

        Self {
            base: Default::default(),
            locale: QString::from("en"),
            locale_changed: Default::default(),
            tr: Default::default(),
            tr_args: Default::default(),
            strings,
        }
    }

    fn tr(&mut self, key: QString) -> QString {
        let k = key.to_string();
        match self.strings.get(&k) {
            Some(s) => QString::from(s.clone()),
            None => {
                log::debug!("missing translation key: {k}");
                QString::from(k)
            }
        }
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

    // Resolve "@:key" references. Iterate a few times because a
    // reference can point to another reference (e.g. settingsTab.receive.requirePin
    // -> webSharePage.requirePin -> a literal).
    for _ in 0..8 {
        let mut changed = false;
        let keys: Vec<String> = flat.keys().cloned().collect();
        for k in keys {
            let v = match flat.get(&k) {
                Some(v) => v.clone(),
                None => continue,
            };
            if let Some(target) = v.strip_prefix("@:") {
                if let Some(resolved) = flat.get(target).cloned() {
                    if resolved != v {
                        flat.insert(k, resolved);
                        changed = true;
                    }
                } else {
                    log::warn!("unresolved i18n reference: {k} -> @:{target}");
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
            // Plural object: {"one": ..., "other": ..., "param": "n"}
            // We pick "other" for now. TODO(plural): pick by n at call site.
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
        Value::Array(_) => {
            // Arrays (e.g. aboutPage.description) are not flattened yet.
            // TODO: expose as List<String> properties when needed.
        }
        _ => {}
    }
}

// silence the unused-import warning if cstr isn't needed
#[allow(dead_code)]
fn _use_cstr() {
    let _ = cstr!("noop");
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
        // "receiveTab.quickSave.off": "@:general.off"  -> "Off"
        assert_eq!(map["receiveTab.quickSave.off"], "Off");
        // "webSharePage.encryption": "@:settingsTab.network.encryption"
        assert_eq!(map["webSharePage.encryption"], "Encryption");
        // Nested reference chain:
        // "settingsTab.receive.requirePin" -> "@:webSharePage.requirePin"
        //   -> "Require PIN"
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
        // Build a tiny map to test substitution logic independently.
        let mut t = Translator {
            base: Default::default(),
            locale: QString::from("en"),
            locale_changed: Default::default(),
            tr: Default::default(),
            tr_args: Default::default(),
            strings: HashMap::new(),
        };
        t.strings
            .insert("x".into(), "Files: {files} / {n}".into());

        // tr_args returns a QString; compare content.
        let out = t.tr_args(
            QString::from("x"),
            QString::from(r#"{"files":3,"n":10}"#),
        );
        assert_eq!(out.to_string(), "Files: 3 / 10");
    }
}