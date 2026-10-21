// SPDX-License-Identifier: Apache-2.0
//
// Finds application packages (.click / .apk) on the device.
//
// The send tab lets the user share an app with a peer. Ubuntu Touch has no
// installed-app archive to share (unlike Android, where the APK of an
// installed app can be extracted), so the picker lists package *files* that
// are stored on the device. They can live anywhere: the download folder, the
// home directory, an SD card, ... so the whole storage is searched.

use std::collections::{HashSet, VecDeque};
use std::path::{Path, PathBuf};

/// Maximum directory depth that is walked below a search root.
const MAX_DEPTH: usize = 32;
/// Global maximum number of directory entries visited in one scan.
const MAX_VISITED: usize = 1_200_000;
/// Per-root budget for the three most important user folders.
const MAX_VISITED_PER_PRIORITY_ROOT: usize = 160_000;
/// Budget for each additional root to keep scans bounded on large storage.
const MAX_VISITED_PER_ROOT: usize = 80_000;
/// Maximum number of packages that are reported.
const MAX_RESULTS: usize = 50_000;
/// The first three roots are always visited before broader storage locations.
const PRIORITY_ROOT_COUNT: usize = 3;
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
/// The initial scan order is deliberate: Downloads, Documents, then
/// Downloads/LocalSend. Other user folders and removable/system package
/// locations follow, with the full home directory last. Exact duplicate roots
/// are removed, but nested roots are retained so a priority folder gets its
/// own scan budget if a parent scan reaches its limit.
pub fn search_roots() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/home/phablet"));

    let mut roots = vec![
        home.join("Downloads"),
        home.join("Documents"),
        home.join("Downloads").join("LocalSend"),
    ];

    for child in ["Desktop", "Pictures", "Videos", "Music"] {
        let path = home.join(child);
        if path.is_dir() {
            roots.push(path);
        }
    }

    for dir in [
        "/media",
        "/mnt",
        "/run/media",
        "/storage",
        "/sdcard",
        "/var/cache/click",
        "/var/lib/click",
        "/opt/click.ubuntu.com",
        "/usr/share/click",
    ] {
        let path = PathBuf::from(dir);
        if path.is_dir() {
            roots.push(path);
        }
    }

    if let Some(data_home) = std::env::var_os("XDG_DATA_HOME").map(PathBuf::from) {
        if data_home.is_dir() {
            roots.push(data_home);
        }
    }
    if let Some(cache_home) = std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from) {
        if cache_home.is_dir() {
            roots.push(cache_home);
        }
    }
    if home.is_dir() {
        roots.push(home);
    }

    let mut unique = Vec::with_capacity(roots.len());
    for root in roots {
        if !unique.contains(&root) {
            unique.push(root);
        }
    }
    unique
}
/// Recursively collects package files below `roots`.
///
/// Breadth-first traversal checks files in the top of each priority folder
/// before spending time in deep caches. Each root has its own visit budget, so
/// a huge Downloads tree cannot starve Documents or Downloads/LocalSend. A
/// global cap and depth cap keep the background scan bounded on large devices.
/// Hidden directories are included. Symlinks are not followed.
pub fn scan(roots: &[PathBuf]) -> Vec<PackageFile> {
    let mut found: Vec<PackageFile> = Vec::new();
    let mut seen_paths: HashSet<PathBuf> = HashSet::new();
    let mut visited_total = 0usize;

    for (root_index, root) in roots.iter().enumerate() {
        if visited_total >= MAX_VISITED || found.len() >= MAX_RESULTS {
            break;
        }

        let root_budget = if root_index < PRIORITY_ROOT_COUNT {
            MAX_VISITED_PER_PRIORITY_ROOT
        } else {
            MAX_VISITED_PER_ROOT
        };
        let root_start_visited = visited_total;
        let mut queue: VecDeque<(PathBuf, usize)> = VecDeque::new();
        let mut queued_dirs: HashSet<PathBuf> = HashSet::new();
        queue.push_back((root.clone(), 0));
        queued_dirs.insert(root.clone());

        while let Some((dir, depth)) = queue.pop_front() {
            let used_for_root = visited_total.saturating_sub(root_start_visited);
            if depth > MAX_DEPTH
                || used_for_root >= root_budget
                || visited_total >= MAX_VISITED
                || found.len() >= MAX_RESULTS
            {
                break;
            }
            let Ok(dir_meta) = std::fs::symlink_metadata(&dir) else {
                continue;
            };
            if dir_meta.is_symlink() || !dir_meta.is_dir() {
                continue;
            }

            let Ok(entries) = std::fs::read_dir(&dir) else {
                continue;
            };

            for entry_result in entries {
                let used_for_root = visited_total.saturating_sub(root_start_visited);
                if used_for_root >= root_budget
                    || visited_total >= MAX_VISITED
                    || found.len() >= MAX_RESULTS
                {
                    break;
                }

                visited_total += 1;
                let Ok(entry) = entry_result else {
                    continue;
                };

                let path = entry.path();
                let name = entry.file_name().to_string_lossy().into_owned();
                let Ok(meta) = std::fs::symlink_metadata(&path) else {
                    continue;
                };
                if meta.is_symlink() {
                    continue;
                }

                if meta.is_dir() {
                    if depth < MAX_DEPTH
                        && queued_dirs.insert(path.clone())
                    {
                        queue.push_back((path, depth + 1));
                    }
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
                if !seen_paths.insert(path.clone()) {
                    continue;
                }

                let modified = meta
                    .modified()
                    .ok()
                    .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                found.push(PackageFile {
                    name,
                    path: path.to_string_lossy().to_string(),
                    size: meta.len(),
                    modified,
                });
            }

        }
    }

    found.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then_with(|| a.path.cmp(&b.path))
    });
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
    fn includes_hidden_folders() {
        let root = temp_dir("hidden");
        write(&root.join(".hidden/app.click"), "x");
        write(&root.join("visible/app.click"), "x");

        let found = scan(std::slice::from_ref(&root));
        assert_eq!(found.len(), 2, "{found:?}");
        assert!(found.iter().any(|p| p.path.contains(".hidden")));
        assert!(found.iter().any(|p| p.path.contains("visible")));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn search_roots_prioritize_downloads_documents_and_localsend() {
        let home = std::env::var_os("HOME").map(PathBuf::from).expect("HOME");
        let roots = search_roots();
        assert_eq!(roots[0], home.join("Downloads"));
        assert_eq!(roots[1], home.join("Documents"));
        assert_eq!(roots[2], home.join("Downloads").join("LocalSend"));
    }

    #[test]
    fn scans_click_and_apk_extensions_case_insensitively() {
        let root = temp_dir("mixed-case-formats");
        write(&root.join("Downloads/LOCAL.CLICK"), "click");
        write(&root.join("Documents/nested/Example.APK"), "apk");
        write(&root.join("Documents/ignore.zip"), "not a package");

        let found = scan(std::slice::from_ref(&root));
        assert_eq!(found.len(), 2, "{found:?}");
        assert_eq!(filter(&found, "all", "").len(), 2);
        assert_eq!(filter(&found, "click", "").len(), 1);
        assert_eq!(filter(&found, "apk", "").len(), 1);
        assert_eq!(filter(&found, "all", "example").len(), 1);

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
