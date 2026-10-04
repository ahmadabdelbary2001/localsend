// SPDX-License-Identifier: Apache-2.0
//
// Ubuntu Touch confinement means we cannot assume arbitrary filesystem access.
// All file/URL handoff goes through Content Hub or the app's own confined dirs.

pub mod content_hub;
pub mod filesystem;