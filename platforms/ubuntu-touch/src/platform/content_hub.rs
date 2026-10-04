// SPDX-License-Identifier: Apache-2.0
//
// Ubuntu Touch Content Hub integration.
// Used to pick files (source) and to share received files (destination).

/// Import a file via Content Hub.
///
/// TODO: implement via the Content Hub D-Bus API.
/// For now this is a documented placeholder so QML never touches filesystem.
pub fn pick_file() -> Result<(), ContentHubError> {
    Err(ContentHubError::NotImplemented)
}

/// Export a received file via Content Hub.
pub fn share_file(_path: &str) -> Result<(), ContentHubError> {
    Err(ContentHubError::NotImplemented)
}

#[derive(Debug)]
pub enum ContentHubError {
    NotImplemented,
    Cancelled,
    Failed(String),
}

impl std::fmt::Display for ContentHubError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotImplemented => write!(f, "Content Hub integration not implemented yet"),
            Self::Cancelled => write!(f, "Content Hub operation cancelled"),
            Self::Failed(s) => write!(f, "Content Hub failed: {s}"),
        }
    }
}

impl std::error::Error for ContentHubError {}