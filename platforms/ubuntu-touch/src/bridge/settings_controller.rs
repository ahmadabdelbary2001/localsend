// SPDX-License-Identifier: Apache-2.0
//
// SettingsController exposes read-only settings required by ReceivePage
// (alias) and by the theme system (mode / colorMode / customColor).
// The persisted settings service lives in the application layer.

use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct SettingsController {
    base: qt_base_class!(trait QObject),

    alias:        qt_property!(QString; NOTIFY state_changed),
    mode:         qt_property!(QString; NOTIFY state_changed), // "system" | "light" | "dark"
    color_mode:   qt_property!(QString; NOTIFY state_changed), // "localsend" | "oled" | "custom" | "yaru"
    custom_color: qt_property!(QString; NOTIFY state_changed), // "#RRGGBB"

    state_changed: qt_signal!(),
}

impl SettingsController {
    pub fn new() -> Self {
        let mut this = Self::default();
        this.mode = QString::from("system");
        this.color_mode = QString::from("localsend");
        this.custom_color = QString::from("#009688");
        this
    }

    pub fn set_alias(&mut self, alias: String) {
        self.alias = QString::from(alias);
        self.state_changed();
    }
}