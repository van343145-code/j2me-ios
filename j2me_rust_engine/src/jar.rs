//! JAR Archive and MIDlet Manifest Loader

use std::collections::HashMap;
use std::io::{Cursor, Read};
use zip::ZipArchive;

#[derive(Debug, Clone)]
pub struct Manifest {
    pub attributes: HashMap<String, String>,
}

impl Manifest {
    pub fn parse(text: &str) -> Self {
        let mut attributes = HashMap::new();
        let mut current_key = String::new();
        let mut current_val = String::new();

        for line in text.lines() {
            if line.starts_with(' ') || line.starts_with('\t') {
                // Continuation line
                current_val.push_str(line.trim_start());
            } else if let Some((k, v)) = line.split_once(':') {
                if !current_key.is_empty() {
                    attributes.insert(current_key.trim().to_string(), current_val.trim().to_string());
                }
                current_key = k.to_string();
                current_val = v.to_string();
            }
        }
        if !current_key.is_empty() {
            attributes.insert(current_key.trim().to_string(), current_val.trim().to_string());
        }

        Self { attributes }
    }

    pub fn midlet_main_class(&self) -> Option<String> {
        // MIDlet-1: Name, Icon, MainClass
        if let Some(val) = self.attributes.get("MIDlet-1") {
            let parts: Vec<&str> = val.split(',').map(|s| s.trim()).collect();
            if parts.len() >= 3 {
                return Some(parts[2].replace('.', "/"));
            }
        }
        None
    }
}

pub struct JarArchive {
    archive: ZipArchive<Cursor<Vec<u8>>>,
    pub manifest: Option<Manifest>,
}

impl JarArchive {
    pub fn from_bytes(bytes: Vec<u8>) -> Result<Self, zip::result::ZipError> {
        let cursor = Cursor::new(bytes);
        let mut archive = ZipArchive::new(cursor)?;

        let mut manifest = None;
        if let Ok(mut mf_file) = archive.by_name("META-INF/MANIFEST.MF") {
            let mut text = String::new();
            if mf_file.read_to_string(&mut text).is_ok() {
                manifest = Some(Manifest::parse(&text));
            }
        }

        Ok(Self { archive, manifest })
    }

    pub fn read_file(&mut self, name: &str) -> Option<Vec<u8>> {
        let clean_name = name.trim_start_matches('/');
        if let Ok(mut file) = self.archive.by_name(clean_name) {
            let mut data = Vec::with_capacity(file.size() as usize);
            if file.read_to_end(&mut data).is_ok() {
                return Some(data);
            }
        }
        None
    }
}
