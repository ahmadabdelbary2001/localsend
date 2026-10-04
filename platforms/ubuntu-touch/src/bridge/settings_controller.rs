// SPDX-License-Identifier: Apache-2.0
//
// QObject wrapper around application::settings_service::SettingsService.
// Every property is read from the in-memory snapshot on construction
// and updated via the set_* slots (which also persist to disk).

use std::sync::Arc;

use qmetaobject::prelude::*;

use crate::application::settings_service::SettingsService;

#[derive(QObject)]
pub struct SettingsController {
    base: qt_base_class!(trait QObject),

    service: Arc<SettingsService>,

    // ---------- properties exposed to QML ----------
    alias: qt_property!(QString; NOTIFY changed),
    theme: qt_property!(QString; NOTIFY changed),        // "system" | "light" | "dark"
    color_mode: qt_property!(QString; NOTIFY changed),   // "system" | "localsend" | "oled" | "yaru" | "custom"
    custom_color: qt_property!(QString; NOTIFY changed), // "#RRGGBB"
    enable_animations: qt_property!(bool; NOTIFY changed),
    advanced_settings: qt_property!(bool; NOTIFY changed),
    locale: qt_property!(QString; NOTIFY changed),
    port: qt_property!(u32; NOTIFY changed),
    https: qt_property!(bool; NOTIFY changed),
    send_mode: qt_property!(QString; NOTIFY changed),
    device_type: qt_property!(QString; NOTIFY changed),
    device_model: qt_property!(QString; NOTIFY changed),

    changed: qt_signal!(),

    // ---------- slots callable from QML ----------
    set_alias: qt_method!(fn(&mut self, v: QString)),
    set_theme: qt_method!(fn(&mut self, v: QString)),
    set_color_mode: qt_method!(fn(&mut self, v: QString)),
    set_custom_color: qt_method!(fn(&mut self, v: QString)),
    set_enable_animations: qt_method!(fn(&mut self, v: bool)),
    set_advanced_settings: qt_method!(fn(&mut self, v: bool)),
    set_locale: qt_method!(fn(&mut self, v: QString)),
    set_port: qt_method!(fn(&mut self, v: u32)),
    set_https: qt_method!(fn(&mut self, v: bool)),
    set_send_mode: qt_method!(fn(&mut self, v: QString)),
    set_device_type: qt_method!(fn(&mut self, v: QString)),
    set_device_model: qt_method!(fn(&mut self, v: QString)),
}

impl SettingsController {
    pub fn new(service: Arc<SettingsService>) -> Self {
        let s = service.snapshot();

        let mut this = Self {
            base: Default::default(),
            service,
            alias: Default::default(),
            theme: Default::default(),
            color_mode: Default::default(),
            custom_color: Default::default(),
            enable_animations: Default::default(),
            advanced_settings: Default::default(),
            locale: Default::default(),
            port: Default::default(),
            https: Default::default(),
            send_mode: Default::default(),
            device_type: Default::default(),
            device_model: Default::default(),
            changed: Default::default(),
            set_alias: Default::default(),
            set_theme: Default::default(),
            set_color_mode: Default::default(),
            set_custom_color: Default::default(),
            set_enable_animations: Default::default(),
            set_advanced_settings: Default::default(),
            set_locale: Default::default(),
            set_port: Default::default(),
            set_https: Default::default(),
            set_send_mode: Default::default(),
            set_device_type: Default::default(),
            set_device_model: Default::default(),
        };

        this.alias = QString::from(s.alias);
        this.theme = QString::from(s.theme);
        this.color_mode = QString::from(s.color_mode);
        this.custom_color = QString::from(s.custom_color);
        this.enable_animations = s.enable_animations;
        this.advanced_settings = s.advanced_settings;
        this.locale = QString::from(s.locale.unwrap_or_default());
        this.port = s.port as u32;
        this.https = s.https;
        this.send_mode = QString::from(s.send_mode);
        this.device_type = QString::from(s.device_type.unwrap_or_default());
        this.device_model = QString::from(s.device_model.unwrap_or_default());
        this
    }

    // ---- setter implementations ----

    fn set_alias(&mut self, v: QString) {
        let s = v.to_string();
        self.service.update(|st| st.alias = s.clone());
        self.alias = QString::from(s);
        self.changed();
    }

    fn set_theme(&mut self, v: QString) {
        let s = v.to_string();
        if !matches!(s.as_str(), "system" | "light" | "dark") {
            log::warn!("set_theme: invalid value '{s}'");
            return;
        }
        self.service.update(|st| st.theme = s.clone());
        self.theme = QString::from(s);
        self.changed();
    }

    fn set_color_mode(&mut self, v: QString) {
        let s = v.to_string();
        if !matches!(s.as_str(), "system" | "localsend" | "oled" | "yaru" | "custom") {
            log::warn!("set_color_mode: invalid value '{s}'");
            return;
        }
        self.service.update(|st| st.color_mode = s.clone());
        self.color_mode = QString::from(s);
        self.changed();
    }

    fn set_custom_color(&mut self, v: QString) {
        let s = v.to_string();
        if !s.starts_with('#') || !matches!(s.len(), 7 | 9) {
            log::warn!("set_custom_color: invalid '#RRGGBB' value '{s}'");
            return;
        }
        self.service.update(|st| st.custom_color = s.clone());
        self.custom_color = QString::from(s);
        self.changed();
    }

    fn set_enable_animations(&mut self, v: bool) {
        self.service.update(|st| st.enable_animations = v);
        self.enable_animations = v;
        self.changed();
    }

    fn set_advanced_settings(&mut self, v: bool) {
        self.service.update(|st| st.advanced_settings = v);
        self.advanced_settings = v;
        self.changed();
    }

    fn set_locale(&mut self, v: QString) {
        let s = v.to_string();
        let s_opt = if s.is_empty() { None } else { Some(s.clone()) };
        self.service.update(|st| st.locale = s_opt);
        self.locale = QString::from(s);
        self.changed();
    }

    fn set_port(&mut self, v: u32) {
        if v == 0 || v > u16::MAX as u32 {
            log::warn!("set_port: out of range {v}");
            return;
        }
        let p = v as u16;
        self.service.update(|st| st.port = p);
        self.port = v;
        self.changed();
    }

    fn set_https(&mut self, v: bool) {
        self.service.update(|st| st.https = v);
        self.https = v;
        self.changed();
    }

    fn set_send_mode(&mut self, v: QString) {
        let s = v.to_string();
        if !matches!(s.as_str(), "single" | "multiple" | "link") {
            log::warn!("set_send_mode: invalid '{s}'");
            return;
        }
        self.service.update(|st| st.send_mode = s.clone());
        self.send_mode = QString::from(s);
        self.changed();
    }

    fn set_device_type(&mut self, v: QString) {
        let s = v.to_string();
        let opt = if s.is_empty() { None } else { Some(s.clone()) };
        self.service.update(|st| st.device_type = opt);
        self.device_type = QString::from(s);
        self.changed();
    }

    fn set_device_model(&mut self, v: QString) {
        let s = v.to_string();
        let opt = if s.is_empty() { None } else { Some(s.clone()) };
        self.service.update(|st| st.device_model = opt);
        self.device_model = QString::from(s);
        self.changed();
    }
}