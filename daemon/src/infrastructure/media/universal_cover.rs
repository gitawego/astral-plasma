use crate::domain::branding;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use crate::domain::media::CoverArtResolverPort;

pub struct UniversalCoverResolver {
    cache_dir: PathBuf,
}

impl Default for UniversalCoverResolver {
    fn default() -> Self {
        let dir = branding::art_cache_dir();
        let _ = fs::create_dir_all(&dir);
        Self { cache_dir: dir }
    }
}

impl UniversalCoverResolver {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_cache_dir(dir: PathBuf) -> Self {
        let _ = fs::create_dir_all(&dir);
        Self { cache_dir: dir }
    }

    /// Computes a stable alphanumeric cache key from title and artist.
    pub fn cache_key(title: &str, artist: &str) -> String {
        let normalized = format!("{}:{}", title.trim().to_lowercase(), artist.trim().to_lowercase());
        let mut hash: u64 = 0xcbf29ce484222325; // FNV-1a 64-bit
        for byte in normalized.bytes() {
            hash ^= byte as u64;
            hash = hash.wrapping_mul(0x100000001b3);
        }
        format!("{:016x}", hash)
    }

    /// URL-encodes a string for web queries.
    fn url_encode(input: &str) -> String {
        let mut encoded = String::new();
        for b in input.bytes() {
            if b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'.' || b == b'~' {
                encoded.push(b as char);
            } else if b == b' ' {
                encoded.push('+');
            } else {
                encoded.push_str(&format!("%{:02X}", b));
            }
        }
        encoded
    }

    /// Attempts to query iTunes search API for album art and track duration.
    fn query_itunes(&self, title: &str, artist: &str) -> Option<(String, u64)> {
        let query = format!("{} {}", title, artist);
        let encoded = Self::url_encode(query.trim());
        let url = format!("https://itunes.apple.com/search?term={}&media=music&limit=1", encoded);

        let output = Command::new("curl")
            .args(["-s", "-m", "2", "-A", "Mozilla/5.0", &url])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let raw = String::from_utf8_lossy(&output.stdout);
        let json: serde_json::Value = serde_json::from_str(&raw).ok()?;
        let results = json.get("results").and_then(|r| r.as_array())?;
        if results.is_empty() {
            return None;
        }

        let first = &results[0];
        let mut art_url = first
            .get("artworkUrl100")
            .and_then(|u| u.as_str())
            .unwrap_or_default()
            .to_string();

        if !art_url.is_empty() {
            // Upgrade 100x100 thumbnail to 600x600 high-res
            art_url = art_url.replace("100x100bb.jpg", "600x600bb.jpg");
        }

        let duration = first
            .get("trackTimeMillis")
            .and_then(|d| d.as_u64())
            .unwrap_or(0);

        if !art_url.is_empty() {
            Some((art_url, duration))
        } else {
            None
        }
    }

    /// Attempts to query QQ Music search API for album art and track duration.
    fn query_qqmusic(&self, title: &str, artist: &str) -> Option<(String, u64)> {
        let query = format!("{} {}", title, artist);
        let encoded = Self::url_encode(query.trim());
        let url = format!("https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w={}&n=1&format=json", encoded);

        let output = Command::new("curl")
            .args(["-s", "-m", "2", "-A", "Mozilla/5.0", "-e", "https://y.qq.com/", &url])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let raw = String::from_utf8_lossy(&output.stdout);
        let json: serde_json::Value = serde_json::from_str(&raw).ok()?;
        let songs = json
            .get("data")
            .and_then(|d| d.get("song"))
            .and_then(|s| s.get("list"))
            .and_then(|l| l.as_array())?;

        if songs.is_empty() {
            return None;
        }

        let first = &songs[0];
        let albummid = first
            .get("albummid")
            .and_then(|m| m.as_str())
            .unwrap_or_default();

        let interval = first
            .get("interval")
            .and_then(|i| i.as_u64())
            .unwrap_or(0);

        if !albummid.is_empty() {
            let art_url = format!("https://y.gtimg.cn/music/photo_new/T002R300x300M000{}.jpg", albummid);
            Some((art_url, interval * 1000))
        } else {
            None
        }
    }

    /// Caches an image from an HTTP URL to disk and returns the local file URI.
    fn download_to_cache(&self, url: &str, key: &str) -> Option<String> {
        let target_path = self.cache_dir.join(format!("{}.jpg", key));
        let path_str = target_path.to_str().unwrap_or_default().to_string();

        if target_path.exists() {
            if let Ok(meta) = fs::metadata(&target_path) {
                if meta.len() > 100 {
                    return Some(format!("file://{}", path_str));
                }
            }
        }

        let clean_url = url.split('?').next().unwrap_or(url);
        let _ = Command::new("curl")
            .args(["-s", "-m", "3", "-A", "Mozilla/5.0", clean_url, "-o", &path_str])
            .output();

        if target_path.exists() {
            if let Ok(meta) = fs::metadata(&target_path) {
                if meta.len() > 100 {
                    return Some(format!("file://{}", path_str));
                }
            }
        }

        // Return direct HTTP URL as fallback if download could not complete in time
        Some(url.to_string())
    }

    /// Resolves metadata and cover art directly.
    pub fn resolve_metadata(&self, title: &str, artist: &str, raw_url: Option<&str>) -> (Option<String>, u64) {
        if title.trim().is_empty() {
            return (None, 0);
        }

        let key = Self::cache_key(title, artist);
        let cached_file = self.cache_dir.join(format!("{}.jpg", key));

        // 1. If explicit local file URI was provided
        if let Some(url) = raw_url {
            let trimmed = url.trim();
            if trimmed.starts_with("file://") {
                let local_path = trimmed.trim_start_matches("file://");
                if Path::new(local_path).exists() {
                    return (Some(trimmed.to_string()), 0);
                }
            } else if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
                if let Some(art) = self.download_to_cache(trimmed, &key) {
                    return (Some(art), 0);
                }
            }
        }

        // 2. Check if this track is already cached locally from a previous lookup
        if cached_file.exists() {
            if let Ok(meta) = fs::metadata(&cached_file) {
                if meta.len() > 100 {
                    let path_str = cached_file.to_str().unwrap_or_default();
                    return (Some(format!("file://{}", path_str)), 0);
                }
            }
        }

        // 3. Multi-tier Online Resolution: Tier 1 - iTunes API (Fast, Western/Global)
        if let Some((art_url, duration)) = self.query_itunes(title, artist) {
            let local_art = self.download_to_cache(&art_url, &key).unwrap_or(art_url);
            return (Some(local_art), duration);
        }

        // 4. Multi-tier Online Resolution: Tier 2 - QQ Music API (Asian, C-Pop, Indie)
        if let Some((art_url, duration)) = self.query_qqmusic(title, artist) {
            let local_art = self.download_to_cache(&art_url, &key).unwrap_or(art_url);
            return (Some(local_art), duration);
        }

        (None, 0)
    }

    pub fn resolve_art(&self, title: &str, artist: &str, raw_url: Option<&str>) -> Option<String> {
        self.resolve_metadata(title, artist, raw_url).0
    }
}

impl CoverArtResolverPort for UniversalCoverResolver {
    fn resolve_metadata(&self, title: &str, artist: &str, raw_url: Option<&str>) -> (Option<String>, u64) {
        self.resolve_metadata(title, artist, raw_url)
    }

    fn resolve_art(&self, title: &str, artist: &str, raw_url: Option<&str>) -> Option<String> {
        self.resolve_art(title, artist, raw_url)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_key_generation() {
        let key1 = UniversalCoverResolver::cache_key("Nobody New", "The Marías");
        let key2 = UniversalCoverResolver::cache_key("nobody new  ", "the marías");
        assert_eq!(key1, key2);
        assert_eq!(key1.len(), 16);
    }

    #[test]
    fn test_local_file_url_resolution() {
        let temp = tempfile::tempdir().expect("tempdir");
        let resolver = UniversalCoverResolver::with_cache_dir(temp.path().to_path_buf());
        let test_file = temp.path().join("test.jpg");
        fs::write(&test_file, b"test image content that is long enough").expect("write");

        let file_url = format!("file://{}", test_file.display());
        let (art, _) = resolver.resolve_metadata("Test Song", "Test Artist", Some(&file_url));
        assert_eq!(art, Some(file_url));
    }
}
