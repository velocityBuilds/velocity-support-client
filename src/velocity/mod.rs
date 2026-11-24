//! Velocity Remote integration (Velocity Builds And Repairs).
//!
//! Two builds come from this tree, picked at compile time by `VELOCITY_ROLE`:
//!   * `customer`   – Velocity Remote Support, installed on customer PCs (incoming only).
//!   * `technician` – Velocity Remote Technician, for staff (outgoing only).
//!
//! The customer build talks to the Velocity backend (`VELOCITY_API`) from the *server* process:
//! it holds the device credential, sends heartbeats, and checks every incoming connection with
//! [`verify_login`]. A connection is authorized only when BOTH are true:
//!   1. the backend consumes the single-use token the technician app presented, and
//!   2. the customer clicked Accept for that request on this PC in the last two minutes
//!      (recorded only here, in memory, from a local IPC call — the backend cannot fake it).
//! The UI process (Flutter) reaches the server process over the existing IPC channel.
//! Upstream code only gets small hook calls into this module.

use hbb_common::{
    allow_err,
    config::{self, Config},
    log, tokio, ResultType,
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

mod store;

pub const ROLE: &str = match option_env!("VELOCITY_ROLE") {
    Some(r) => r,
    None => "customer",
};
const API_BASE: &str = match option_env!("VELOCITY_API") {
    Some(v) => v,
    None => "",
};

const HEARTBEAT_SECS: u64 = 10;
const LOCAL_APPROVAL_SECS: u64 = 120;
const HTTP_TIMEOUT_SECS: u64 = 15;

#[inline]
pub fn is_technician() -> bool {
    ROLE == "technician"
}

/// Customer builds refuse every connection that did not pass [`verify_login`].
#[inline]
pub fn enforced() -> bool {
    !is_technician()
}

pub fn app_name() -> &'static str {
    if is_technician() {
        "VelocityRemoteTechnician"
    } else {
        "VelocityRemoteSupport"
    }
}

/// Settings that are locked for the whole process (called from `apply_velocity_branding`).
pub fn apply_lockdown() {
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    let mut over = config::OVERWRITE_SETTINGS.write().unwrap();
    let mut builtin = config::BUILTIN_SETTINGS.write().unwrap();
    hard.insert("disable-settings".into(), "Y".into());
    hard.insert("disable-account".into(), "Y".into());
    hard.insert("disable-ab".into(), "Y".into());
    // Never pull stock RustDesk updates over a Velocity build.
    over.insert("allow-auto-update".into(), "N".into());
    // RustDesk's own console sync/audit stays off; Velocity's backend is the authority.
    over.insert("register-device".into(), "N".into());
    if is_technician() {
        hard.insert("conn-type".into(), "outgoing".into());
        return;
    }
    hard.insert("conn-type".into(), "incoming".into());
    // No passwords, no unattended access, no ways around the approval check.
    over.insert("approve-mode".into(), "click".into());
    over.insert("verification-method".into(), "use-temporary-password".into());
    over.insert("allow-hide-cm".into(), "N".into());
    over.insert("enable-trusted-devices".into(), "N".into());
    over.insert("2fa".into(), "".into());
    over.insert("direct-server".into(), "N".into());
    over.insert("enable-lan-discovery".into(), "N".into());
    over.insert("allow-remote-config-modification".into(), "N".into());
    builtin.insert("disable-change-permanent-password".into(), "Y".into());
    builtin.insert("disable-unlock-pin".into(), "Y".into());
    builtin.insert("allow-logon-screen-password".into(), "N".into());
    builtin.insert("hide-tray".into(), "N".into());
}

/* ------------------------------------------------------------------ HTTP */

async fn http(method: &str, path: &str, body: Option<Value>, auth: Option<&str>, idem: Option<&str>) -> ResultType<(u16, Value)> {
    if API_BASE.is_empty() {
        hbb_common::bail!("This build has no Velocity server configured.");
    }
    let url = format!("{}{}", API_BASE.trim_end_matches('/'), path);
    let client = crate::hbbs_http::create_http_client_async_with_url_strict(&url).await?;
    let mut req = match method {
        "GET" => client.get(&url),
        _ => client.post(&url),
    };
    req = req.timeout(Duration::from_secs(HTTP_TIMEOUT_SECS)).header("user-agent", format!("{}/{}", app_name(), crate::VERSION));
    if let Some(a) = auth {
        req = req.header("authorization", a);
    }
    if let Some(k) = idem {
        req = req.header("idempotency-key", k);
    }
    if let Some(b) = body {
        req = req.header("content-type", "application/json").body(b.to_string());
    }
    let resp = req.send().await?;
    let status = resp.status().as_u16();
    let text = resp.text().await.unwrap_or_default();
    let v = serde_json::from_str(&text).unwrap_or(Value::Null);
    Ok((status, v))
}

fn error_message(v: &Value, fallback: &str) -> String {
    if let Some(fields) = v.pointer("/error/fields").and_then(|f| f.as_object()) {
        if let Some(m) = fields.values().find_map(|m| m.as_str()) {
            return m.to_owned();
        }
    }
    v.pointer("/error/message").and_then(|m| m.as_str()).unwrap_or(fallback).to_owned()
}

fn os_version() -> String {
    let info = crate::get_sysinfo();
    info.get("os").and_then(|v| v.as_str()).unwrap_or("Windows").chars().take(120).collect()
}

/* --------------------------------------------- customer state (server process) */

#[derive(Default)]
struct State {
    online: bool,
    revoked: bool,
    last_error: String,
    pending: Option<Value>,
    ticket: Option<Value>,
    /// requestId -> when the customer clicked Accept on this PC.
    approvals: HashMap<String, Instant>,
    active: Option<SessionInfo>,
    last_ui_poll: Option<Instant>,
    ui_launched_for: Option<String>,
}

lazy_static::lazy_static! {
    static ref STATE: Mutex<State> = Mutex::new(State::default());
    static ref WAKE: tokio::sync::Notify = tokio::sync::Notify::new();
}

fn device_auth() -> Option<String> {
    store::load().map(|d| format!("Device {}", d.credential))
}

/// Start the heartbeat loop. Called once from the server process (`RendezvousMediator::start_all`).
pub fn start_heartbeat() {
    if is_technician() {
        return;
    }
    tokio::spawn(async move {
        loop {
            heartbeat_once().await;
            let _ = tokio::time::timeout(Duration::from_secs(HEARTBEAT_SECS), WAKE.notified()).await;
        }
    });
}

async fn heartbeat_once() {
    let Some(auth) = device_auth() else {
        let mut s = STATE.lock().unwrap();
        s.online = false;
        s.pending = None;
        return;
    };
    let body = json!({ "hostname": crate::common::hostname(), "osVersion": os_version(), "appVersion": crate::VERSION });
    match http("POST", "/api/device/heartbeat", Some(body), Some(&auth), None).await {
        Ok((200, v)) => {
            let pending = v.get("pendingRequest").cloned().filter(|p| !p.is_null());
            let launch_ui = {
                let mut s = STATE.lock().unwrap();
                s.online = true;
                s.revoked = false;
                s.last_error.clear();
                s.ticket = v.get("ticket").cloned().filter(|t| !t.is_null());
                let new_id = pending.as_ref().and_then(|p| p.get("id")).and_then(|i| i.as_str()).map(|i| i.to_owned());
                s.pending = pending;
                // Make sure the customer actually sees the request: open the window if no UI is polling.
                let ui_alive = s.last_ui_poll.map_or(false, |t| t.elapsed() < Duration::from_secs(5));
                let should = new_id.is_some() && !ui_alive && s.ui_launched_for != new_id;
                if should {
                    s.ui_launched_for = new_id;
                }
                should
            };
            if launch_ui {
                open_main_window();
            }
        }
        Ok((401, _)) => {
            let mut s = STATE.lock().unwrap();
            s.online = false;
            s.revoked = true;
            s.pending = None;
            s.last_error = "This computer is no longer linked to Velocity. Enter a new code.".into();
        }
        Ok((status, v)) => {
            let mut s = STATE.lock().unwrap();
            s.online = false;
            s.last_error = error_message(&v, &format!("Velocity server error ({status})."));
        }
        Err(e) => {
            log::warn!("velocity heartbeat failed: {e}");
            let mut s = STATE.lock().unwrap();
            s.online = false;
            s.last_error = "Can't reach Velocity right now. Check your internet connection.".into();
        }
    }
}

fn open_main_window() {
    #[cfg(windows)]
    std::thread::spawn(|| {
        if crate::platform::is_installed() && crate::is_server() {
            allow_err!(crate::platform::run_as_user(vec![]));
        }
    });
}

/// Handle a request from the UI process (IPC `Data::Velocity`). Runs in the server process.
pub async fn ipc_handle(req: String) -> String {
    let req: Value = serde_json::from_str(&req).unwrap_or(Value::Null);
    let op = req.get("op").and_then(|o| o.as_str()).unwrap_or("");
    let args = req.get("args").cloned().unwrap_or(Value::Null);
    let out = match op {
        "state" => Ok(state_json()),
        "enroll" => enroll(&args).await,
        "ticket" => create_ticket(&args).await,
        "respond" => respond(&args).await,
        "unenroll" => unenroll().await,
        "refresh" => {
            WAKE.notify_one();
            Ok(json!({ "ok": true }))
        }
        _ => Err("Unknown request.".to_owned()),
    };
    match out {
        Ok(v) => json!({ "ok": true, "data": v }).to_string(),
        Err(e) => json!({ "ok": false, "error": e }).to_string(),
    }
}

fn state_json() -> Value {
    let dev = store::load();
    let mut s = STATE.lock().unwrap();
    s.last_ui_poll = Some(Instant::now());
    // Drop a pending request the moment it expires locally, even between heartbeats.
    if let Some(exp) = s.pending.as_ref().and_then(|p| p.get("expiresAt")).and_then(|e| e.as_str()) {
        if chrono_expired(exp) {
            s.pending = None;
        }
    }
    json!({
        "enrolled": dev.is_some() && !s.revoked,
        "customerName": dev.as_ref().map(|d| d.customer_name.clone()).unwrap_or_default(),
        "computerName": dev.as_ref().map(|d| d.computer_name.clone()).unwrap_or_default(),
        "hostname": crate::common::hostname(),
        "rustdeskId": Config::get_id(),
        "online": s.online,
        "lastError": s.last_error,
        "pendingRequest": s.pending,
        "ticket": s.ticket,
        "activeSession": s.active.as_ref().map(|a| json!({ "technicianName": a.technician_name, "ticketNumber": a.ticket_number })),
        "version": crate::VERSION,
    })
}

fn chrono_expired(iso: &str) -> bool {
    match chrono::DateTime::parse_from_rfc3339(iso) {
        Ok(t) => t.timestamp_millis() <= chrono::Utc::now().timestamp_millis(),
        Err(_) => false,
    }
}

fn arg<'a>(args: &'a Value, k: &str) -> &'a str {
    args.get(k).and_then(|v| v.as_str()).unwrap_or("")
}

async fn enroll(args: &Value) -> Result<Value, String> {
    let body = json!({
        "code": arg(args, "code"),
        "rustdeskId": Config::get_id(),
        "hostname": crate::common::hostname(),
        "osVersion": os_version(),
        "appVersion": crate::VERSION,
    });
    match http("POST", "/api/device/enroll", Some(body), None, None).await {
        Ok((201, v)) => {
            let d = store::Device {
                credential: v.get("credential").and_then(|c| c.as_str()).unwrap_or("").to_owned(),
                customer_name: v.get("customerName").and_then(|c| c.as_str()).unwrap_or("").to_owned(),
                computer_name: v.get("computerName").and_then(|c| c.as_str()).unwrap_or("").to_owned(),
            };
            if d.credential.is_empty() {
                return Err("Unexpected answer from Velocity.".into());
            }
            store::save(&d).map_err(|e| format!("Could not save the link on this PC: {e}"))?;
            STATE.lock().unwrap().revoked = false;
            WAKE.notify_one();
            Ok(json!({ "customerName": d.customer_name, "computerName": d.computer_name }))
        }
        Ok((_, v)) => Err(error_message(&v, "That code did not work.")),
        Err(_) => Err("Can't reach Velocity right now. Check your internet connection.".into()),
    }
}

async fn create_ticket(args: &Value) -> Result<Value, String> {
    let auth = device_auth().ok_or("This computer is not linked to Velocity yet.")?;
    let body = json!({ "category": arg(args, "category"), "subject": arg(args, "subject"), "description": arg(args, "description") });
    let key = arg(args, "key");
    match http("POST", "/api/device/tickets", Some(body), Some(&auth), Some(key)).await {
        Ok((200 | 201, v)) => {
            WAKE.notify_one();
            Ok(v)
        }
        Ok((_, v)) => Err(error_message(&v, "Could not send your request.")),
        Err(_) => Err("Can't reach Velocity right now. Check your internet connection.".into()),
    }
}

async fn respond(args: &Value) -> Result<Value, String> {
    let auth = device_auth().ok_or("This computer is not linked to Velocity yet.")?;
    let id = arg(args, "requestId").to_owned();
    if id.len() != 36 {
        return Err("Unknown request.".into());
    }
    let accept = args.get("accept").and_then(|a| a.as_bool()).unwrap_or(false);
    let path = format!("/api/device/requests/{}/{}", id, if accept { "approve" } else { "decline" });
    let result = http("POST", &path, Some(json!({})), Some(&auth), None).await;
    {
        let mut s = STATE.lock().unwrap();
        s.pending = None;
        if accept && matches!(result, Ok((200, _))) {
            // The local half of the approval. Only this IPC call (the customer's click) creates it.
            s.approvals.retain(|_, t| t.elapsed() < Duration::from_secs(LOCAL_APPROVAL_SECS));
            s.approvals.insert(id.clone(), Instant::now());
        }
    }
    WAKE.notify_one();
    match result {
        Ok((200, _)) => Ok(json!({ "accepted": accept })),
        Ok((_, v)) => Err(error_message(&v, "This request is no longer waiting.")),
        Err(_) => Err("Can't reach Velocity right now. Check your internet connection.".into()),
    }
}

async fn unenroll() -> Result<Value, String> {
    if let Some(auth) = device_auth() {
        let _ = http("POST", "/api/device/unenroll", Some(json!({})), Some(&auth), None).await;
    }
    store::delete();
    let mut s = STATE.lock().unwrap();
    s.pending = None;
    s.ticket = None;
    s.online = false;
    Ok(json!({ "ok": true }))
}

/// Uninstall hook: tell Velocity this PC is gone and remove the stored credential.
pub fn on_uninstall() {
    if is_technician() {
        return;
    }
    if let Some(d) = store::load_any() {
        if let Ok(rt) = tokio::runtime::Builder::new_current_thread().enable_all().build() {
            let auth = format!("Device {}", d.credential);
            rt.block_on(async {
                let _ = http("POST", "/api/device/unenroll", Some(json!({})), Some(&auth), None).await;
            });
        }
    }
    store::delete_all();
}

/* ------------------------------------------------------ connection gate */

#[derive(Clone, Debug)]
pub struct SessionInfo {
    pub session_id: String,
    pub technician_name: String,
    pub ticket_number: String,
}

/// Held by an authorized `Connection`; reports the end of the session when dropped.
pub struct SessionGuard {
    pub info: SessionInfo,
    pub reason: String,
}

impl Drop for SessionGuard {
    fn drop(&mut self) {
        let info = self.info.clone();
        let reason = if self.reason.is_empty() { "Disconnected".to_owned() } else { self.reason.chars().take(200).collect() };
        {
            let mut s = STATE.lock().unwrap();
            if s.active.as_ref().map_or(false, |a| a.session_id == info.session_id) {
                s.active = None;
            }
        }
        std::thread::spawn(move || {
            let Some(auth) = device_auth() else { return };
            if let Ok(rt) = tokio::runtime::Builder::new_current_thread().enable_all().build() {
                rt.block_on(async {
                    let path = format!("/api/device/sessions/{}/ended", info.session_id);
                    allow_err!(http("POST", &path, Some(json!({ "reason": reason })), Some(&auth), None).await);
                });
            }
        });
    }
}

pub const NOT_APPROVED: &str = "This computer only accepts connections approved through Velocity Remote.";

/// Check an incoming login. `token` is `LoginRequest.velocity_token`, `peer_id` is `LoginRequest.my_id`.
pub async fn verify_login(token: &[u8], peer_id: &str) -> Result<SessionGuard, &'static str> {
    if token.is_empty() || token.len() > 100 {
        return Err(NOT_APPROVED);
    }
    let token = std::str::from_utf8(token).map_err(|_| NOT_APPROVED)?;
    let auth = device_auth().ok_or(NOT_APPROVED)?;
    let body = json!({ "token": token, "technicianRustdeskId": peer_id });
    let v = match http("POST", "/api/device/sessions/verify", Some(body), Some(&auth), None).await {
        Ok((200, v)) => v,
        Ok((status, _)) => {
            log::warn!("velocity: connection refused by backend ({status})");
            return Err(NOT_APPROVED);
        }
        Err(e) => {
            log::warn!("velocity: verify failed: {e}");
            return Err("Velocity could not confirm this connection. Please try again.");
        }
    };
    let request_id = v.get("requestId").and_then(|x| x.as_str()).unwrap_or("").to_owned();
    let info = SessionInfo {
        session_id: v.get("sessionId").and_then(|x| x.as_str()).unwrap_or("").to_owned(),
        technician_name: v.get("technicianName").and_then(|x| x.as_str()).unwrap_or("").to_owned(),
        ticket_number: v.get("ticketNumber").and_then(|x| x.as_str()).unwrap_or("").to_owned(),
    };
    let mut s = STATE.lock().unwrap();
    // The local half: the customer must have clicked Accept for this request on this PC, recently.
    let clicked = s.approvals.remove(&request_id).map_or(false, |t| t.elapsed() < Duration::from_secs(LOCAL_APPROVAL_SECS));
    if !clicked || info.session_id.is_empty() {
        log::warn!("velocity: backend approved {request_id} but there is no local Accept for it");
        drop(s);
        // Close the session record that the backend just opened.
        let _ = SessionGuard { info, reason: "Refused: no local approval".into() };
        return Err(NOT_APPROVED);
    }
    s.active = Some(info.clone());
    Ok(SessionGuard { info, reason: String::new() })
}

/* ------------------------------------------------ technician side (UI process) */

#[derive(Default)]
struct Tech {
    token: Option<String>,
    user: Value,
}

lazy_static::lazy_static! {
    static ref TECH: Mutex<Tech> = Mutex::new(Tech::default());
    /// peer id -> (single-use connection token, when it was fetched)
    static ref LOGIN_TOKENS: Mutex<HashMap<String, (String, Instant)>> = Mutex::new(HashMap::new());
    /// peer id -> customer/ticket info shown in the remote window
    static ref SESSION_INFO: Mutex<HashMap<String, Value>> = Mutex::new(HashMap::new());
}

/// Token for `LoginRequest.velocity_token` when connecting to `peer_id` (technician build only).
pub fn login_token(peer_id: &str) -> Vec<u8> {
    let mut m = LOGIN_TOKENS.lock().unwrap();
    m.retain(|_, (_, t)| t.elapsed() < Duration::from_secs(90));
    m.get(peer_id).map(|(tok, _)| tok.as_bytes().to_vec()).unwrap_or_default()
}

async fn tech_call(op: &str, args: &Value) -> Result<Value, String> {
    let bearer = || TECH.lock().unwrap().token.clone().map(|t| format!("Bearer {t}"));
    match op {
        "login" => {
            let body = json!({ "email": arg(args, "email"), "password": arg(args, "password") });
            match http("POST", "/api/tech/login", Some(body), None, None).await {
                Ok((200, v)) => {
                    let mut t = TECH.lock().unwrap();
                    t.token = v.get("token").and_then(|x| x.as_str()).map(|x| x.to_owned());
                    t.user = v.get("user").cloned().unwrap_or(Value::Null);
                    Ok(json!({ "user": t.user }))
                }
                Ok((_, v)) => Err(error_message(&v, "Sign-in failed.")),
                Err(_) => Err("Can't reach Velocity right now.".into()),
            }
        }
        "logout" => {
            if let Some(b) = bearer() {
                let _ = http("POST", "/api/tech/logout", Some(json!({})), Some(&b), None).await;
            }
            *TECH.lock().unwrap() = Tech::default();
            Ok(json!({ "ok": true }))
        }
        "me" => {
            let t = TECH.lock().unwrap();
            Ok(json!({ "signedIn": t.token.is_some(), "user": t.user, "rustdeskId": Config::get_id(), "version": crate::VERSION }))
        }
        "ready" => {
            let b = bearer().ok_or("signed_out")?;
            match http("POST", "/api/tech/ready", Some(json!({ "rustdeskId": Config::get_id() })), Some(&b), None).await {
                Ok((200, v)) => Ok(v),
                Ok((401, _)) => {
                    *TECH.lock().unwrap() = Tech::default();
                    Err("signed_out".into())
                }
                Ok((_, v)) => Err(error_message(&v, "Velocity server error.")),
                Err(_) => Err("Can't reach Velocity right now.".into()),
            }
        }
        "token" => {
            let b = bearer().ok_or("signed_out")?;
            let id = arg(args, "requestId");
            if id.len() != 36 {
                return Err("Unknown request.".into());
            }
            let path = format!("/api/tech/requests/{id}/token");
            match http("POST", &path, Some(json!({ "rustdeskId": Config::get_id() })), Some(&b), None).await {
                Ok((200, v)) => {
                    let peer = v.get("peerId").and_then(|x| x.as_str()).unwrap_or("").to_owned();
                    let tok = v.get("token").and_then(|x| x.as_str()).unwrap_or("").to_owned();
                    if peer.is_empty() || tok.is_empty() {
                        return Err("Unexpected answer from Velocity.".into());
                    }
                    LOGIN_TOKENS.lock().unwrap().insert(peer.clone(), (tok, Instant::now()));
                    if let Some(info) = args.get("info") {
                        SESSION_INFO.lock().unwrap().insert(peer.clone(), info.clone());
                    }
                    // Only the peer id goes back to the UI; the token stays in Rust.
                    Ok(json!({ "peerId": peer }))
                }
                Ok((_, v)) => Err(error_message(&v, "Could not start the connection.")),
                Err(_) => Err("Can't reach Velocity right now.".into()),
            }
        }
        "session_info" => Ok(SESSION_INFO.lock().unwrap().get(arg(args, "peerId")).cloned().unwrap_or(Value::Null)),
        _ => Err("Unknown request.".into()),
    }
}

async fn customer_ipc(op: &str, args: Value) -> String {
    let req = json!({ "op": op, "args": args }).to_string();
    let res: ResultType<String> = async {
        let mut c = crate::ipc::connect(1000, "").await?;
        c.send(&crate::ipc::Data::Velocity(req)).await?;
        match c.next_timeout(HTTP_TIMEOUT_SECS * 1000 + 3000).await? {
            Some(crate::ipc::Data::Velocity(resp)) => Ok(resp),
            _ => hbb_common::bail!("no answer"),
        }
    }
    .await;
    res.unwrap_or_else(|_| json!({ "ok": false, "error": "The Velocity background service is not running. Restart the app." }).to_string())
}

/// Entry point for the Flutter UI (`bind.velocityCall`). Returns `{ok, data|error}` JSON.
#[tokio::main(flavor = "current_thread")]
pub async fn ui_call(op: &str, args: &str) -> String {
    let args: Value = serde_json::from_str(args).unwrap_or(Value::Null);
    if let Some(tech_op) = op.strip_prefix("tech_") {
        if !is_technician() {
            return json!({ "ok": false, "error": "Not available." }).to_string();
        }
        return match tech_call(tech_op, &args).await {
            Ok(v) => json!({ "ok": true, "data": v }).to_string(),
            Err(e) => json!({ "ok": false, "error": e }).to_string(),
        };
    }
    if op == "notify" {
        notify(arg(&args, "title"), arg(&args, "body"));
        return json!({ "ok": true }).to_string();
    }
    if is_technician() {
        return json!({ "ok": false, "error": "Not available." }).to_string();
    }
    customer_ipc(op, args).await
}

fn notify(title: &str, body: &str) {
    #[cfg(windows)]
    {
        use tauri_winrt_notification::{Duration as ToastDuration, Sound, Toast};
        allow_err!(Toast::new(Toast::POWERSHELL_APP_ID)
            .title(title)
            .text1(body)
            .sound(Some(Sound::Default))
            .duration(ToastDuration::Long)
            .show());
    }
    #[cfg(not(windows))]
    let _ = (title, body);
}
