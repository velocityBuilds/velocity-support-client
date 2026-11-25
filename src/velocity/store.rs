//! The device credential for the customer build, kept next to RustDesk's own config.
//! On Windows the file is encrypted with DPAPI (machine scope + app-specific entropy), and it lives
//! in the server process's config folder (the service profile when installed), never in the
//! options that are synced to the UI process.

use hbb_common::{config::Config, log};
use serde_derive::{Deserialize, Serialize};

/// Only the credential is kept. Files written by older versions also had the customer's name; serde
/// ignores those extra fields.
#[derive(Serialize, Deserialize, Clone, Default)]
pub struct Device {
    pub credential: String,
}

const FILE: &str = "velocity-device.dat";
const ENTROPY: &[u8] = b"Velocity Remote Support device credential v1";

fn path() -> std::path::PathBuf {
    Config::path(FILE)
}

pub fn load() -> Option<Device> {
    let raw = std::fs::read(path()).ok()?;
    let plain = unprotect(&raw)?;
    match serde_json::from_slice::<Device>(&plain) {
        Ok(d) if !d.credential.is_empty() => Some(d),
        _ => None,
    }
}

pub fn save(d: &Device) -> std::io::Result<()> {
    let plain = serde_json::to_vec(d).map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
    let enc = protect(&plain).ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "encryption failed"))?;
    let p = path();
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = p.with_extension("tmp");
    std::fs::write(&tmp, enc)?;
    std::fs::rename(tmp, p)
}

pub fn delete() {
    if let Err(e) = std::fs::remove_file(path()) {
        if e.kind() != std::io::ErrorKind::NotFound {
            log::warn!("velocity: could not remove device credential: {e}");
        }
    }
}

/// Copies the installed service may have written (the uninstaller runs as another account).
fn service_paths() -> Vec<std::path::PathBuf> {
    let app = hbb_common::config::APP_NAME.read().unwrap().clone();
    let windir = std::path::PathBuf::from(std::env::var("WINDIR").unwrap_or_else(|_| r"C:\Windows".into()));
    let tail = |base: std::path::PathBuf| base.join("AppData").join("Roaming").join(&app).join("config").join(FILE);
    vec![
        tail(windir.join("ServiceProfiles").join("LocalService")),
        tail(windir.join("System32").join("config").join("systemprofile")),
    ]
}

/// For uninstall: the credential from wherever it was stored, if any.
pub fn load_any() -> Option<Device> {
    load().or_else(|| {
        service_paths().into_iter().find_map(|p| {
            let plain = unprotect(&std::fs::read(p).ok()?)?;
            serde_json::from_slice::<Device>(&plain).ok().filter(|d| !d.credential.is_empty())
        })
    })
}

/// For uninstall: remove every copy.
pub fn delete_all() {
    delete();
    for p in service_paths() {
        let _ = std::fs::remove_file(p);
    }
}

#[cfg(windows)]
fn crypt(data: &[u8], encrypt: bool) -> Option<Vec<u8>> {
    use winapi::um::{
        dpapi::{CryptProtectData, CryptUnprotectData, CRYPTPROTECT_LOCAL_MACHINE, CRYPTPROTECT_UI_FORBIDDEN},
        winbase::LocalFree,
        wincrypt::DATA_BLOB,
    };
    let mut input = DATA_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 };
    let mut entropy = DATA_BLOB { cbData: ENTROPY.len() as u32, pbData: ENTROPY.as_ptr() as *mut u8 };
    let mut output = DATA_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
    let flags = CRYPTPROTECT_LOCAL_MACHINE | CRYPTPROTECT_UI_FORBIDDEN;
    // SAFETY: all blobs point to valid memory for the duration of the call; the output buffer is
    // allocated by Windows and released with LocalFree below.
    let ok = unsafe {
        if encrypt {
            CryptProtectData(&mut input, std::ptr::null(), &mut entropy, std::ptr::null_mut(), std::ptr::null_mut(), flags, &mut output)
        } else {
            CryptUnprotectData(&mut input, std::ptr::null_mut(), &mut entropy, std::ptr::null_mut(), std::ptr::null_mut(), flags, &mut output)
        }
    };
    if ok == 0 || output.pbData.is_null() {
        return None;
    }
    let out = unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec() };
    unsafe { LocalFree(output.pbData as _) };
    Some(out)
}

#[cfg(windows)]
fn protect(data: &[u8]) -> Option<Vec<u8>> {
    crypt(data, true)
}

#[cfg(windows)]
fn unprotect(data: &[u8]) -> Option<Vec<u8>> {
    crypt(data, false)
}

// Velocity Remote ships for Windows only; other targets keep the file unencrypted so the code compiles.
#[cfg(not(windows))]
fn protect(data: &[u8]) -> Option<Vec<u8>> {
    Some(data.to_vec())
}

#[cfg(not(windows))]
fn unprotect(data: &[u8]) -> Option<Vec<u8>> {
    Some(data.to_vec())
}
