use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

pub struct StorageManager {
    root_dir: PathBuf,
}

impl StorageManager {
    pub fn new<P: AsRef<Path>>(root: P) -> Self {
        let p = root.as_ref().to_path_buf();
        let _ = fs::create_dir_all(&p);
        Self { root_dir: p }
    }

    fn sanitize_name(&self, name: &str) -> PathBuf {
        let safe: String = name
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
            .collect();
        self.root_dir.join(format!("{}.rms", safe))
    }

    pub fn load(&self, name: &str) -> Option<Vec<u8>> {
        let path = self.sanitize_name(name);
        fs::read(path).ok()
    }

    pub fn save(&self, name: &str, data: &[u8]) -> bool {
        let path = self.sanitize_name(name);
        fs::write(path, data).is_ok()
    }

    pub fn delete(&self, name: &str) -> bool {
        let path = self.sanitize_name(name);
        fs::remove_file(path).is_ok()
    }

    pub fn list(&self) -> Vec<String> {
        let mut results = Vec::new();
        if let Ok(entries) = fs::read_dir(&self.root_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("rms") {
                    if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                        results.push(stem.to_string());
                    }
                }
            }
        }
        results
    }

    pub fn size(&self, name: &str) -> i64 {
        let path = self.sanitize_name(name);
        fs::metadata(path).map(|m| m.len() as i64).unwrap_or(0)
    }

    pub fn modified(&self, name: &str) -> i64 {
        let path = self.sanitize_name(name);
        fs::metadata(path)
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0)
    }
}

pub static GLOBAL_STORAGE: Mutex<Option<StorageManager>> = Mutex::new(None);

pub fn init_storage<P: AsRef<Path>>(root: P) {
    let mut g = GLOBAL_STORAGE.lock().unwrap();
    *g = Some(StorageManager::new(root));
}
