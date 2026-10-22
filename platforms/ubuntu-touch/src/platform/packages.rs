// SPDX-License-Identifier: Apache-2.0
//
// Finds application packages (.click / .apk) on the device.
//
// The send tab lets the user share an app with a peer. Ubuntu Touch has no
// installed-app archive to share (unlike Android, where the APK of an
// installed app can be extracted), so the picker lists package *files* that
// are stored on the device. They can live anywhere: the download folder, the
// home directory, an SD card, ... so the whole storage is searched.
//
// The search is split into two phases so the picker is usable immediately:
// the priority roots (the LocalSend receive folder, ~/Downloads, documents,
// removable storage) are scanned first and published, then the rest (the home
// folder, click caches) is walked in the background. Both phases use
// breadth-first traversal with a per-root entry budget and a shared "seen"
// set, so a second phase never walks a directory twice and a huge cache can
// not starve the folders the user actually uses.
//
// The AppArmor hook grants read access to the folders packages are stored in
// (`write_path` on `~/Downloads` also allows reading it, `read_path` adds
// `~/Documents`), which is why the roots below are ordered that way. Anything
// outside those grants is unreadable and simply yields no entries, so the
// remaining roots are best-effort.
//
// The search is split into two phases so the picker is usable immediately:
// the priority roots (`~/Downloads/LocalSend`, `~/Downloads`, `~/Documents`,
// removable storage) are scanned first and published one by one, then the
// rest (the home folder, click caches) is walked in the background. Both
// phases use breadth-first traversal with a per-root entry budget and a shared
// "seen" set, so a later phase never walks a directory twice and a huge cache
// can not starve the folders the user actually uses.

use std::collections::{HashSet, VecDeque};
use std::path::{Path, PathBuf};

/// Maximum directory depth that is walked below a search root.
const MAX_DEPTH: usize = 16;
/// Maximum number of directory entries visited below one priority root.
pub const PRIORITY_BUDGET: usize = 25_000;
/// Maximum number of directory entries visited below one broad root.
pub const BROAD_BUDGET: usize = 60_000;
/// Maximum number of packages that are reported.
const MAX_RESULTS: usize = 4_000;

/// Package file extensions that can be shared.
pub const PACKAGE_EXTENSIONS: &[&str] = &["click", "apk"];

/// Directory names that never contain user packages but can hold hundreds of
/// thousands of files (source trees, caches, thumbnails). Skipping them is the
/// difference between a scan that finishes in milliseconds and one that takes
/// minutes on a phone.
const SKIP_DIRS: &[&str] = &[
    ".git",
    ".hg",
    ".svn",
    ".cache",
    ".config",
    ".mozilla",
    ".thumbnails",
    ".thunderbird",
    ".dart_tool",
    ".pub-cache",
    ".npm",
    ".gradle",
    "node_modules",
    "target",
    "Trash",
];

/// A directory that is searched for packages.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchRoot {
    pub path: PathBuf,
    /// Priority roots are scanned first, while the app picker is already open.
    pub priority: bool,
}

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

/// True when the file name has a package extension (case-insensitive).
fn is_package(path: &Path) -> bool {
    match path.extension().and_then(|e| e.to_str()) {
        Some(ext) => PACKAGE_EXTENSIONS
            .iter()
            .any(|known| known.eq_ignore_ascii_case(ext)),
        None => false,
    }
}

fn dir_name_is_skipped(name: &std::ffi::OsStr) -> bool {
    match name.to_str() {
        Some(name) => SKIP_DIRS.contains(&name),
        None => false,
    }
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

/// Directories that are searched for packages.
///
/// The order is deliberate: `~/Downloads/LocalSend` (where received packages
/// land), `~/Downloads` and `~/Documents` are the folders the hook grants read
/// access to, so they are read first and published while the remaining roots
/// (removable storage, click caches, the rest of the home folder) are still
/// being walked.
pub fn search_roots() -> Vec<SearchRoot> {
    let mut roots: Vec<SearchRoot> = Vec::new();
    let mut push = |path: PathBuf, priority: bool| {
        if path.is_dir() && !roots.iter().any(|root| root.path == path) {
            roots.push(SearchRoot { path, priority });
        }
    };

    if let Some(home) = home_dir() {
        // Where LocalSend stores received files, so a package that was just
        // received shows up first.
        push(home.join("Downloads").join("LocalSend"), true);
        push(home.join("Downloads"), true);
        for child in ["Documents", "Desktop"] {
            push(home.join(child), true);
        }
    }

    // Removable storage: packages are often copied there from a computer.
    for dir in ["/media", "/run/media", "/mnt"] {
        push(PathBuf::from(dir), true);
    }

    // Click keeps downloaded packages in its cache.
    push(PathBuf::from("/var/cache/click"), true);

    // Installed click packages. They are unpacked, but some come with a
    // bundled .click next to them.
    for dir in [
        "/opt/click.ubuntu.com",
        "/var/lib/click",
        "/usr/share/click",
    ] {
        push(PathBuf::from(dir), false);
    }

    // Last resort: everything else in the home directory (Pictures, Music,
    // a custom folder, ...). Already scanned priority folders are skipped by
    // the shared seen set, not by the budget.
    if let Some(home) = home_dir() {
        push(home, false);
    }

    roots
}

/// State shared by the priority and the broad scan phase.
///
/// Keeping the visited directories and files in one place means the broad
/// phase does not walk `~/Downloads` again after the priority phase already
/// covered it.
#[derive(Default)]
pub struct ScanSession {
    seen_dirs: HashSet<PathBuf>,
    seen_files: HashSet<PathBuf>,
    found: Vec<PackageFile>,
}

impl ScanSession {
    pub fn new() -> Self {
        Self::default()
    }

    /// Walks `roots` breadth-first and collects package files.
    ///
    /// Returns when the budget of a root is exhausted, the depth limit is hit
    /// or `MAX_RESULTS` packages were found. Directories that were visited by
    /// an earlier call are skipped, so phases can be chained.
    pub fn scan(&mut self, roots: &[SearchRoot], budget: usize) {
        for root in roots {
            if self.found.len() >= MAX_RESULTS {
                return;
            }
            self.scan_root(root, budget);
        }
    }

    fn scan_root(&mut self, root: &SearchRoot, budget: usize) {
        if self.found.len() >= MAX_RESULTS {
            return;
        }
        let mut queue: VecDeque<(PathBuf, usize)> = VecDeque::new();
        queue.push_back((root.path.clone(), 0));
        let mut visited = 0usize;

        while let Some((dir, depth)) = queue.pop_front() {
            if depth > MAX_DEPTH {
                continue;
            }
            // A directory is read at most once per session: overlapping roots
            // (`~/Downloads/LocalSend` inside `~/Downloads`) are free.
            if !self.seen_dirs.insert(dir.clone()) {
                continue;
            }
            let entries = match std::fs::read_dir(&dir) {
                Ok(entries) => entries,
                Err(error) => {
                    // AppArmor denies everything outside the granted folders;
                    // that is expected and must not stop the scan.
                    if error.kind() == std::io::ErrorKind::PermissionDenied {
                        log::debug!("package scan cannot read {}: {error}", dir.display());
                    }
                    continue;
                }
            };

            for entry in entries.flatten() {
                visited += 1;
                if visited >= budget || self.found.len() >= MAX_RESULTS {
                    return;
                }
                let Ok(file_type) = entry.file_type() else {
                    continue;
                };
                // Never follow symlinks: loops and links into other clicks.
                if file_type.is_symlink() {
                    continue;
                }
                if file_type.is_dir() {
                    if !dir_name_is_skipped(&entry.file_name()) {
                        queue.push_back((entry.path(), depth + 1));
                    }
                    continue;
                }
                if !file_type.is_file() {
                    continue;
                }

                let path = entry.path();
                if !is_package(&path) {
                    continue;
                }
                if !self.seen_files.insert(path.clone()) {
                    continue;
                }
                let Ok(meta) = entry.metadata() else {
                    continue;
                };
                let modified = meta
                    .modified()
                    .ok()
                    .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                self.found.push(PackageFile {
                    name: entry.file_name().to_string_lossy().to_string(),
                    path: path.to_string_lossy().to_string(),
                    size: meta.len(),
                    modified,
                });
            }
        }
    }

    /// Sorted, de-duplicated packages.
    pub fn packages(&mut self) -> Vec<PackageFile> {
        self.sort();
        self.found.clone()
    }

    /// Consumes the session and returns the sorted packages.
    pub fn into_packages(mut self) -> Vec<PackageFile> {
        self.sort();
        self.found
    }

    fn sort(&mut self) {
        self.found.sort_by_cached_key(|package| {
            (package.name.to_lowercase(), package.path.to_lowercase())
        });
        self.found.dedup_by(|a, b| a.path == b.path);
        self.found.truncate(MAX_RESULTS);
    }
}

/// Scans `roots` in one go. Used by the tests and by callers that do not need
/// the two-phase behaviour.
pub fn scan(roots: &[SearchRoot], budget: usize) -> Vec<PackageFile> {
    let mut session = ScanSession::new();
    session.scan(roots, budget);
    session.into_packages()
}

/// Keeps the packages that match `kind` ("click", "apk" or "all") and the
/// search text. The text matches the file name as well as the full path, so
/// searching for ".click" or a folder name works as well.
pub fn filter<'a>(packages: &'a [PackageFile], kind: &str, query: &str) -> Vec<&'a PackageFile> {
    let kind = kind.trim().to_ascii_lowercase();
    let query = query.trim().to_lowercase();
    let all_kinds = kind.is_empty() || kind == "all";

    packages
        .iter()
        .filter(|p| all_kinds || p.kind() == kind)
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

    /// Scans `roots` in one go; the production code chains both phases in a
    /// single `ScanSession` instead.
    fn scan(roots: &[SearchRoot], budget: usize) -> Vec<PackageFile> {
        let mut session = ScanSession::new();
        session.scan(roots, budget);
        session.into_packages()
    }

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

    fn roots(paths: &[&Path]) -> Vec<SearchRoot> {
        paths
            .iter()
            .map(|path| SearchRoot {
                path: path.to_path_buf(),
                priority: true,
            })
            .collect()
    }

    #[test]
    fn finds_packages_in_nested_folders() {
        let root = temp_dir("nested");
        write(&root.join("app.click"), "x");
        write(&root.join("sub/deep/other.apk"), "x");
        write(&root.join("sub/readme.txt"), "x");

        let found = scan(&roots(&[&root]), PRIORITY_BUDGET);
        let names: Vec<&str> = found.iter().map(|p| p.name.as_str()).collect();
        assert!(names.contains(&"app.click"), "{names:?}");
        assert!(names.contains(&"other.apk"), "{names:?}");
        assert!(!names.contains(&"readme.txt"), "{names:?}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn includes_hidden_folders_but_skips_caches() {
        let root = temp_dir("hidden");
        write(&root.join(".hidden/app.click"), "x");
        write(&root.join("visible/app.click"), "x");
        write(&root.join(".git/objects/ignored.click"), "x");
        write(&root.join("node_modules/ignored.apk"), "x");

        let found = scan(&roots(&[&root]), PRIORITY_BUDGET);
        assert_eq!(found.len(), 2, "{found:?}");
        assert!(found.iter().any(|p| p.path.contains(".hidden")));
        assert!(found.iter().any(|p| p.path.contains("visible")));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn overlapping_roots_do_not_duplicate_packages() {
        let root = temp_dir("overlap");
        write(&root.join("nested/app.click"), "x");

        let found = scan(&roots(&[&root.join("nested"), &root]), PRIORITY_BUDGET);
        assert_eq!(found.len(), 1, "{found:?}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn budget_limits_how_much_one_root_is_walked() {
        let root = temp_dir("budget");
        for i in 0..200 {
            write(&root.join(format!("dir{i}/noise.txt")), "x");
        }
        write(&root.join("zzz/deep/app.click"), "x");

        // A tiny budget stops before the only package is reached.
        let found = scan(&roots(&[&root]), 10);
        assert!(found.is_empty(), "{found:?}");

        // The full budget finds it.
        let found = scan(&roots(&[&root]), PRIORITY_BUDGET);
        assert_eq!(found.len(), 1, "{found:?}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn packages_are_sorted_by_name() {
        let root = temp_dir("sorted");
        write(&root.join("zeta.click"), "x");
        write(&root.join("Alpha.apk"), "x");

        let found = scan(&roots(&[&root]), PRIORITY_BUDGET);
        let names: Vec<&str> = found.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["Alpha.apk", "zeta.click"]);
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
        assert_eq!(filter(&packages, "APK", "").len(), 1);
        assert_eq!(filter(&packages, "all", "").len(), 2);
        assert_eq!(filter(&packages, "", "").len(), 2);
        assert_eq!(filter(&packages, "all", ".apk").len(), 1);
        assert_eq!(filter(&packages, "all", "one").len(), 1);
        assert_eq!(filter(&packages, "all", "download").len(), 0);
    }
}
