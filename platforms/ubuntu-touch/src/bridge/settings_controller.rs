// SPDX-License-Identifier: Apache-2.0
//
// QObject wrapper around SettingsService.
// Every property is initialized from the persisted snapshot and updated
// via set_* slots (which also persist to disk).

use std::sync::Arc;

use qmetaobject::prelude::*;

use crate::application::settings_service::SettingsService;

// Word lists for random alias generation (Adjective + Fruit).
const ADJECTIVES: &[&str] = &[
    "Adorable",
    "Beautiful",
    "Big",
    "Bright",
    "Clean",
    "Clever",
    "Cool",
    "Cute",
    "Cunning",
    "Determined",
    "Energetic",
    "Efficient",
    "Fantastic",
    "Fast",
    "Fine",
    "Fresh",
    "Good",
    "Gorgeous",
    "Great",
    "Handsome",
    "Hot",
    "Kind",
    "Lovely",
    "Mystic",
    "Neat",
    "Nice",
    "Patient",
    "Pretty",
    "Powerful",
    "Rich",
    "Secret",
    "Smart",
    "Solid",
    "Special",
    "Strategic",
    "Strong",
    "Tidy",
    "Wise",
];

const FRUITS: &[&str] = &[
    "Apple",
    "Avocado",
    "Banana",
    "Blackberry",
    "Blueberry",
    "Broccoli",
    "Carrot",
    "Cherry",
    "Coconut",
    "Grape",
    "Lemon",
    "Lettuce",
    "Mango",
    "Melon",
    "Mushroom",
    "Onion",
    "Orange",
    "Papaya",
    "Peach",
    "Pear",
    "Pineapple",
    "Potato",
    "Pumpkin",
    "Raspberry",
    "Strawberry",
    "Tomato",
];

#[derive(QObject)]
pub struct SettingsController {
    base: qt_base_class!(trait QObject),

    /// Not exposed to QML.
    service: Arc<SettingsService>,

    // ---------- properties ----------
    alias: qt_property!(QString; NOTIFY changed),
    theme: qt_property!(QString; NOTIFY changed),
    color_mode: qt_property!(QString; NOTIFY changed),
    custom_color: qt_property!(QString; NOTIFY changed),
    enable_animations: qt_property!(bool; NOTIFY changed),
    advanced_settings: qt_property!(bool; NOTIFY changed),
    locale: qt_property!(QString; NOTIFY changed),
    port: qt_property!(u32; NOTIFY changed),
    https: qt_property!(bool; NOTIFY changed),
    send_mode: qt_property!(QString; NOTIFY changed),
    device_type: qt_property!(QString; NOTIFY changed),
    device_model: qt_property!(QString; NOTIFY changed),
    quick_save: qt_property!(bool; NOTIFY changed),
    quick_save_from_favorites: qt_property!(bool; NOTIFY changed),
    receive_pin: qt_property!(QString; NOTIFY changed),
    auto_finish: qt_property!(bool; NOTIFY changed),
    save_to_history: qt_property!(bool; NOTIFY changed),
    verify_checksums: qt_property!(bool; NOTIFY changed),
    destination: qt_property!(QString; NOTIFY changed),
    create_checksums: qt_property!(bool; NOTIFY changed),
    share_via_link_auto_accept: qt_property!(bool; NOTIFY changed),
    receive_via_link_auto_accept: qt_property!(bool; NOTIFY changed),
    discovery_timeout: qt_property!(u32; NOTIFY changed),
    multicast_group: qt_property!(QString; NOTIFY changed),

    changed: qt_signal!(),

    // ---------- slots ----------
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
    set_quick_save: qt_method!(fn(&mut self, v: bool)),
    set_quick_save_from_favorites: qt_method!(fn(&mut self, v: bool)),
    set_receive_pin: qt_method!(fn(&mut self, v: QString)),
    set_auto_finish: qt_method!(fn(&mut self, v: bool)),
    set_save_to_history: qt_method!(fn(&mut self, v: bool)),
    set_verify_checksums: qt_method!(fn(&mut self, v: bool)),
    set_destination: qt_method!(fn(&mut self, v: QString)),
    set_create_checksums: qt_method!(fn(&mut self, v: bool)),
    set_share_via_link_auto_accept: qt_method!(fn(&mut self, v: bool)),
    set_receive_via_link_auto_accept: qt_method!(fn(&mut self, v: bool)),
    set_discovery_timeout: qt_method!(fn(&mut self, v: u32)),
    set_multicast_group: qt_method!(fn(&mut self, v: QString)),
    random_alias: qt_method!(fn(&mut self)),
    use_system_name: qt_method!(fn(&mut self)),
}

impl SettingsController {
    pub fn new(service: Arc<SettingsService>) -> Self {
        let s = service.snapshot();

        let mut this = Self {
            base: Default::default(),
            service,
            alias: QString::from(s.alias),
            theme: QString::from(s.theme),
            color_mode: QString::from(s.color_mode),
            custom_color: QString::from(s.custom_color),
            enable_animations: s.enable_animations,
            advanced_settings: s.advanced_settings,
            locale: QString::from(s.locale.unwrap_or_default()),
            port: s.port as u32,
            https: s.https,
            send_mode: QString::from(s.send_mode),
            device_type: QString::from(s.device_type.unwrap_or_default()),
            device_model: QString::from(s.device_model.unwrap_or_default()),
            quick_save: s.quick_save,
            quick_save_from_favorites: s.quick_save_from_favorites,
            receive_pin: QString::from(s.receive_pin.unwrap_or_default()),
            auto_finish: s.auto_finish,
            save_to_history: s.save_to_history,
            verify_checksums: s.verify_checksums,
            destination: QString::from(s.destination.unwrap_or_default()),
            create_checksums: s.create_checksums,
            share_via_link_auto_accept: s.share_via_link_auto_accept,
            receive_via_link_auto_accept: s.receive_via_link_auto_accept,
            discovery_timeout: s.discovery_timeout,
            multicast_group: QString::from(s.multicast_group),
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
            set_quick_save: Default::default(),
            set_quick_save_from_favorites: Default::default(),
            set_receive_pin: Default::default(),
            set_auto_finish: Default::default(),
            set_save_to_history: Default::default(),
            set_verify_checksums: Default::default(),
            set_destination: Default::default(),
            set_create_checksums: Default::default(),
            set_share_via_link_auto_accept: Default::default(),
            set_receive_via_link_auto_accept: Default::default(),
            set_discovery_timeout: Default::default(),
            set_multicast_group: Default::default(),
            random_alias: Default::default(),
            use_system_name: Default::default(),
        };
        // silence: use once so field never flagged
        this.changed = Default::default();
        this
    }

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
        if !matches!(
            s.as_str(),
            "system" | "localsend" | "oled" | "yaru" | "custom"
        ) {
            log::warn!("set_color_mode: invalid value '{s}'");
            return;
        }
        self.service.update(|st| st.color_mode = s.clone());
        self.color_mode = QString::from(s);
        self.changed();
    }

    fn set_custom_color(&mut self, v: QString) {
        let s = v.to_string();
        if !s.starts_with('#') || !(s.len() == 7 || s.len() == 9) {
            log::warn!("set_custom_color: invalid value '{s}'");
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
        let opt = if s.is_empty() { None } else { Some(s.clone()) };
        self.service.update(|st| st.locale = opt);
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
        if !s.is_empty()
            && !matches!(
                s.as_str(),
                "mobile" | "desktop" | "laptop" | "tablet" | "web" | "headless" | "server"
            )
        {
            log::warn!("set_device_type: invalid value '{s}'");
            return;
        }
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

    // quick-save cross logic mirrors settings_provider.dart:
    // turning one on turns the other off.
    fn set_quick_save(&mut self, v: bool) {
        self.service.update(|st| {
            st.quick_save = v;
            if v {
                st.quick_save_from_favorites = false;
            }
        });
        let snap = self.service.snapshot();
        self.quick_save = snap.quick_save;
        self.quick_save_from_favorites = snap.quick_save_from_favorites;
        self.changed();
    }

    fn set_quick_save_from_favorites(&mut self, v: bool) {
        self.service.update(|st| {
            st.quick_save_from_favorites = v;
            if v {
                st.quick_save = false;
            }
        });
        let snap = self.service.snapshot();
        self.quick_save = snap.quick_save;
        self.quick_save_from_favorites = snap.quick_save_from_favorites;
        self.changed();
    }

    fn set_receive_pin(&mut self, v: QString) {
        let s = v.to_string();
        let opt = if s.is_empty() { None } else { Some(s.clone()) };
        self.service.update(|st| st.receive_pin = opt);
        self.receive_pin = QString::from(s);
        self.changed();
    }

    fn set_auto_finish(&mut self, v: bool) {
        self.service.update(|st| st.auto_finish = v);
        self.auto_finish = v;
        self.changed();
    }

    fn set_save_to_history(&mut self, v: bool) {
        self.service.update(|st| st.save_to_history = v);
        self.save_to_history = v;
        self.changed();
    }

    fn set_verify_checksums(&mut self, v: bool) {
        self.service.update(|st| st.verify_checksums = v);
        self.verify_checksums = v;
        self.changed();
    }

    fn set_destination(&mut self, v: QString) {
        let s = v.to_string();
        let opt = if s.trim().is_empty() {
            None
        } else {
            Some(s.clone())
        };
        self.service.update(|st| st.destination = opt);
        self.destination = QString::from(s);
        self.changed();
    }

    fn set_create_checksums(&mut self, v: bool) {
        self.service.update(|st| st.create_checksums = v);
        self.create_checksums = v;
        self.changed();
    }

    fn set_share_via_link_auto_accept(&mut self, v: bool) {
        self.service.update(|st| st.share_via_link_auto_accept = v);
        self.share_via_link_auto_accept = v;
        self.changed();
    }

    fn set_receive_via_link_auto_accept(&mut self, v: bool) {
        self.service.update(|st| st.receive_via_link_auto_accept = v);
        self.receive_via_link_auto_accept = v;
        self.changed();
    }

    fn set_discovery_timeout(&mut self, v: u32) {
        // Mirrors Flutter: a timeout of 0 would make discovery useless.
        if v == 0 || v > 60_000 {
            log::warn!("set_discovery_timeout: out of range {v}");
            return;
        }
        self.service.update(|st| st.discovery_timeout = v);
        self.discovery_timeout = v;
        self.changed();
    }

    fn set_multicast_group(&mut self, v: QString) {
        let s = v.trimmed().to_string();
        if !s.is_empty() {
            match s.parse::<std::net::Ipv4Addr>() {
                Ok(ip) if ip.is_multicast() => {}
                _ => {
                    log::warn!("set_multicast_group: invalid IPv4 multicast address '{s}'");
                    return;
                }
            }
        }
        self.service.update(|st| st.multicast_group = s.clone());
        self.multicast_group = QString::from(s);
        self.changed();
    }

    fn random_alias(&mut self) {
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as usize)
            .unwrap_or(0);
        let adj = ADJECTIVES[seed % ADJECTIVES.len()];
        let fruit = FRUITS[(seed / ADJECTIVES.len()) % FRUITS.len()];
        let alias = format!("{adj} {fruit}");
        self.set_alias(QString::from(alias));
    }

    fn use_system_name(&mut self) {
        let name = std::fs::read_to_string("/proc/sys/kernel/hostname")
            .or_else(|_| std::fs::read_to_string("/etc/hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "LocalSend".to_string());
        self.set_alias(QString::from(name));
    }
}
