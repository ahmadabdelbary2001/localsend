// SPDX-License-Identifier: Apache-2.0
//
// Library entry point. Exposes the same modules as main.rs so that
// unit tests can run with `cargo test --lib` without launching Qt.

pub mod application;
pub mod bridge;
pub mod model;
pub mod platform;
pub mod resources;