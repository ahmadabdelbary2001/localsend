// SPDX-License-Identifier: Apache-2.0
//
// HomeController is the QObject analogue of home_page_controller.dart.
// It owns only the current tab index. All real work goes through
// the application layer.

use qmetaobject::prelude::*;

/// Values must match the HomeTab enum in home_page.dart.
pub const HOME_TAB_RECEIVE: i32 = 0;
pub const HOME_TAB_SEND: i32 = 1;
pub const HOME_TAB_SETTINGS: i32 = 2;

#[derive(QObject, Default)]
pub struct HomeController {
    base: qt_base_class!(trait QObject),

    current_tab: qt_property!(i32; NOTIFY current_tab_changed),
    current_tab_changed: qt_signal!(),

    change_tab: qt_method!(fn(&mut self, index: i32)),
}

impl HomeController {
    pub fn new() -> Self {
        let mut this = Self::default();
        this.current_tab = HOME_TAB_RECEIVE;
        this
    }

    fn change_tab(&mut self, index: i32) {
        if index == self.current_tab {
            return;
        }
        if !(HOME_TAB_RECEIVE..=HOME_TAB_SETTINGS).contains(&index) {
            log::warn!("HomeController::change_tab: invalid index {index}");
            return;
        }
        self.current_tab = index;
        self.current_tab_changed();
    }
}