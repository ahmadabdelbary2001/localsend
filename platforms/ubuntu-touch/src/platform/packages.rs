// SPDX-License-Identifier: Apache-2.0
//
// Finds application packages (.click / .apk) on the device.
//
// The send tab lets the user share an app with a peer. Ubuntu Touch has no
// installed-app archive to share (unlike Android, where the APK of an
// installed app can be extracted), so the picker lists package *files* that
// are stored on the device. They can live anywhere: the download folder, the
// home directory, an SD card, ... so the whole storage is searched.

use std::path::{Path, PathBuf};

/// Maximum directory depth that is walked below a search root.
const MAX_DEPTH: usize = 8;
/// Maximum number of directory entries that are visited in one scan.
const MAX_VISITED: usize = 40_000;
/// Maximum number of packages that are reported.
const MAX_RESULTS: usize = 500;

/// Package file extensions that can be shared.
pub const PACKAGE_EXTENSIONS: &[&str] = &["click", "apk"];

/// A package file that can be sent to a peer.
#[derive(Clone, Debug, PartialEq)]
pub struct PackageFile {
    pub name: String,
    pub path: String,
    pub size: u64,
    /// Modification time in seconds since the epoch (0 when unknown).
    pub modified: u64,
}

impl PackageFile {
    /// The package format: "click" or "apk".
    pub fn kind(&self) -> &'static str {
        match extension(&self.path) {
            Some(ext) if ext.eq_ignore_ascii_case("apk") => "apk",
            _ => "click",
        }
    }
}

fn extension(path: &str) -> Option<&str> {
    Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.trim_start_matches('.'))
}

/// Directories that are searched for packages.
///
/// The home directory covers the download folder, documents, ... and the
/// external storage is mounted below /media on Ubuntu Touch.
pub fn search_roots() -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = Vec::new();
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        roots.push(home);
    }
    for dir in ["/media", "/run/media", "/var/cache/click"] {
        let path = PathBuf::from(dir);
        if path.is_dir() {
            roots.push(path);
        }
    }
    roots
}

/// Recursively collects package files below `roots`.
///
/// Hidden directories are skipped (they hold caches and app data, not user
/// files) and symlinked directories are not followed, so the scan cannot
/// loop or leave the user's storage.
pub fn scan(roots: &[PathBuf]) -> Vec<PackageFile> {
    let mut found: Vec<PackageFile> = Vec::new();
    let mut visited = 0usize;

    for root in roots {
        let mut stack: Vec<(PathBuf, usize)> = vec![(root.clone(), 0)];
        while let Some((dir, depth)) = stack.pop() {
            if depth > MAX_DEPTH || visited >= MAX_VISITED {
                continue;
            }
            let Ok(entries) = std::fs::read_dir(&dir) else {
                continue;
            };
            for entry in entries.flatten() {
                visited += 1;
                if visited >= MAX_VISITED {
                    break;
                }
                let path = entry.path();
                let name = entry.file_name();
                let name = name.to_string_lossy();

                // `symlink_metadata` does not follow symlinks.
                let Ok(meta) = std::fs::symlink_metadata(&path) else {
                    continue;
                };
                if meta.is_symlink() {
                    continue;
                }

                if meta.is_dir() {
                    if name.starts_with('.') {
                        continue;
                    }
                    stack.push((path, depth + 1));
                    continue;
                }
                if !meta.is_file() {
                    continue;
                }
                let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
                    continue;
                };
                if !PACKAGE_EXTENSIONS
                    .iter()
                    .any(|known| known.eq_ignore_ascii_case(ext))
                {
                    continue;
                }

                let modified = meta
                    .modified()
                    .ok()
                    .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                found.push(PackageFile {
                    name: name.to_string(),
                    path: path.to_string_lossy().to_string(),
                    size: meta.len(),
                    modified,
                });
                if found.len() >= MAX_RESULTS {
                    found.sort_by(|a, b| {
                        a.name
                            .to_lowercase()
                            .cmp(&b.name.to_lowercase())
                            .then_with(|| a.path.cmp(&b.path))
                    });
                    return found;
                }
            }
        }
    }

    found.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then_with(|| a.path.cmp(&b.path))
    });
    found.dedup_by(|a, b| a.path == b.path);
    found
}

/// Keeps the packages that match `kind` ("click", "apk" or "all") and the
/// search text. The text matches the file name as well as the full path, so
/// searching for ".click" or a folder name works as well.
pub fn filter<'a>(
    packages: &'a [PackageFile],
    kind: &str,
    query: &str,
) -> Vec<&'a PackageFile> {
    let kind = kind.trim().to_ascii_lowercase();
    let query = query.trim().to_lowercase();
    packages
        .iter()
        .filter(|p| kind.is_empty() || kind == "all" || p.kind() == kind)
        .filter(|p| {
            query.is_empty()
                || p.name.to_lowercase().contains(&query)
                || p.path.to_lowercase().contains(&query)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "localsend-packages-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or_default()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write(path: &Path, content: &str) {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::write(path, content).unwrap();
    }

    #[test]
    fn finds_packages_in_nested_folders() {
        let root = temp_dir("nested");
        write(&root.join("app.click"), "x");
        write(&root.join("sub/deep/other.apk"), "x");
        write(&root.join("sub/readme.txt"), "x");

        let found = scan(std::slice::from_ref(&root));
        let names: Vec<&str> = found.iter().map(|p| p.name.as_str()).collect();
        assert!(names.contains(&"app.click"), "{names:?}");
        assert!(names.contains(&"other.apk"), "{names:?}");
        assert!(!names.contains(&"readme.txt"), "{names:?}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn skips_hidden_folders() {
        let root = temp_dir("hidden");
        write(&root.join(".hidden/app.click"), "x");
        write(&root.join("visible/app.click"), "x");

        let found = scan(std::slice::from_ref(&root));
        assert_eq!(found.len(), 1, "{found:?}");
        assert!(found[0].path.contains("visible"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn filters_by_kind_and_query() {
        let packages = vec![
            PackageFile {
                name: "one.click".into(),
                path: "/home/user/one.click".into(),
                size: 1,
                modified: 0,
            },
            PackageFile {
                name: "two.apk".into(),
                path: "/home/user/two.apk".into(),
                size: 1,
                modified: 0,
            },
        ];
        assert_eq!(filter(&packages, "click", "").len(), 1);
        assert_eq!(filter(&packages, "apk", "").len(), 1);
        assert_eq!(filter(&packages, "all", "").len(), 2);
        assert_eq!(filter(&packages, "all", ".apk").len(), 1);
        assert_eq!(filter(&packages, "all", "one").len(), 1);
    }
}
