//! Demo plugin in Rust (native DLL): panel tools, a background job and a host event.
//!
//!   Ctrl+Shift+P  copy the full paths of the selected files (or the file under the cursor) to the
//!                 clipboard, one per line
//!   Ctrl+Shift+M  show the folder of the active panel in the other panel too
//!   Ctrl+Shift+X  select every file with the extension of the file under the cursor
//!   Ctrl+Shift+K  count the files and bytes under the active folder in a background thread, with a
//!                 progress notice; press it again while it runs to stop it
//!   Ctrl+Shift+L  read the file under the cursor through the host (any scheme: a folder, an archive,
//!                 sftp://) and tell its size and first line; needs the permission "vfs.read"
//!
//! It also listens to the "doc.saved" event and shows a notice when a file was saved in the editor.
//!
//! Shows: the panel API (panel_info, panel_goto, panel_select), the clipboard, show_message, host
//! events (subscribe), background work (post_to_main, progress_set / progress_end) and the file system
//! read (vfs_read, which the user must allow in Plugins - Permissions). The JSON the
//! host hands over is read with serde_json.

use std::ffi::{c_char, c_void, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr::null_mut;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use serde_json::Value;

const ABI_VERSION: i64 = 2;
const PLUGIN_ID: &[u8] = b"mtn.demo.panelkit\0";
const JOB_ID: &[u8] = b"count\0";

type CommandCb = unsafe extern "C" fn(user: *mut c_void);
/// Called once on the main thread when a `vfs_read` is done: status 0 = ok, then the bytes of the file
/// (valid only during the call).
type VfsDataCb = unsafe extern "C" fn(user: *mut c_void, status: i64, data: *const u8, length: i64);
type EventCb = unsafe extern "C" fn(user: *mut c_void, topic: *const c_char, payload: *const c_char);

/// Mirror of `THostApiTable` (src/Core/uPluginHostAbi.pas). Fields this plugin does not call are
/// plain pointers; only their position matters.
#[repr(C)]
pub struct HostApi {
    abi_version: i64,
    host_publish: *const c_void,
    host_invalidate: *const c_void,
    register_vfs_scheme: *const c_void,
    register_panel_plugin: *const c_void,
    register_key_binding:
        Option<unsafe extern "C" fn(plugin_id: *const c_char, action: *const c_char, combo: *const c_char) -> i64>,
    register_menu_item: *const c_void,
    register_command: Option<
        unsafe extern "C" fn(plugin_id: *const c_char, id: *const c_char, run: CommandCb, user: *mut c_void) -> i64,
    >,
    register_command_hook: *const c_void,
    execute_command: *const c_void,
    register_document_provider: *const c_void,
    open_external: *const c_void,
    show_dialog: *const c_void,
    register_panel_activate: *const c_void,
    set_command_caption: *const c_void,
    set_status_segment: *const c_void,
    register_settings: *const c_void,
    get_setting: *const c_void,
    set_setting: *const c_void,
    surface_open: *const c_void,
    surface_set_frame: *const c_void,
    surface_set_info: *const c_void,
    surface_set_timer: *const c_void,
    surface_close: *const c_void,
    host_info: *const c_void,
    doc_info: *const c_void,
    doc_get_text: *const c_void,
    doc_replace: *const c_void,
    doc_set_cursor: *const c_void,
    panel_info: Option<unsafe extern "C" fn(buf: *mut c_char, size: i64) -> i64>,
    panel_goto: Option<unsafe extern "C" fn(side: i64, uri: *const c_char) -> i64>,
    panel_refresh: *const c_void,
    clipboard_get: *const c_void,
    clipboard_set: Option<unsafe extern "C" fn(text: *const c_char) -> i64>,
    show_message: Option<unsafe extern "C" fn(text: *const c_char, kind: i64) -> i64>,
    subscribe: Option<
        unsafe extern "C" fn(plugin_id: *const c_char, topic: *const c_char, on_event: EventCb, user: *mut c_void) -> i64,
    >,
    panel_list: *const c_void,
    panel_set_cursor: *const c_void,
    panel_select: Option<unsafe extern "C" fn(side: i64, mode: i64, arg: *const c_char) -> i64>,
    doc_set_selection: *const c_void,
    doc_line: *const c_void,
    post_to_main:
        Option<unsafe extern "C" fn(plugin_id: *const c_char, cb: CommandCb, user: *mut c_void) -> i64>,
    progress_set: Option<
        unsafe extern "C" fn(plugin_id: *const c_char, id: *const c_char, text: *const c_char, percent: i64) -> i64,
    >,
    progress_end: Option<unsafe extern "C" fn(plugin_id: *const c_char, id: *const c_char) -> i64>,
    surface_open_ex: *const c_void,
    surface_set_fullscreen: *const c_void,
    surface_native_handle: *const c_void,
    register_highlighter: *const c_void,
    vfs_list: *const c_void,
    vfs_exists: *const c_void,
    vfs_read: Option<
        unsafe extern "C" fn(
            plugin_id: *const c_char,
            uri: *const c_char,
            max_bytes: i64,
            on_done: VfsDataCb,
            user: *mut c_void,
        ) -> i64,
    >,
}

// The host table is copied once at init and stays valid until shutdown.
static HOST: Mutex<usize> = Mutex::new(0);
static CANCEL: AtomicBool = AtomicBool::new(false);
static JOB: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);

fn host() -> Option<&'static HostApi> {
    let address = *HOST.lock().ok()?;
    unsafe { (address as *const HostApi).as_ref() }
}

/// `file:///C:/dir/a%20b.txt` -> `C:\dir\a b.txt`.
fn uri_to_path(uri: &str) -> Option<PathBuf> {
    let rest = uri.strip_prefix("file:///")?;
    let raw = rest.as_bytes();
    let mut bytes = Vec::with_capacity(raw.len());
    let mut i = 0;
    while i < raw.len() {
        if raw[i] == b'%' && i + 2 < raw.len() {
            let hex = std::str::from_utf8(&raw[i + 1..i + 3]).ok();
            if let Some(v) = hex.and_then(|h| u8::from_str_radix(h, 16).ok()) {
                bytes.push(v);
                i += 3;
                continue;
            }
        }
        bytes.push(if raw[i] == b'/' { b'\\' } else { raw[i] });
        i += 1;
    }
    String::from_utf8(bytes).ok().map(PathBuf::from)
}

fn say(text: &str, kind: i64) {
    if let (Some(h), Ok(c)) = (host(), CString::new(text.replace('\0', ""))) {
        if let Some(show) = h.show_message {
            unsafe { show(c.as_ptr(), kind) };
        }
    }
}

/// The JSON describing both panels, read through the "text out" convention of the host API.
fn panel_info() -> Option<Value> {
    let call = host()?.panel_info?;
    let mut buf = vec![0u8; 8192];
    for _ in 0..3 {
        let n = unsafe { call(buf.as_mut_ptr() as *mut c_char, buf.len() as i64) };
        if n < 0 {
            return None;
        }
        if (n as usize) < buf.len() {
            return serde_json::from_slice(&buf[..n as usize]).ok();
        }
        buf = vec![0u8; n as usize + 1];
    }
    None
}

unsafe extern "C" fn copy_paths(_user: *mut c_void) {
    let Some(info) = panel_info() else {
        say("The file panels are not on screen.", 1);
        return;
    };
    let side = info["active"].as_str().unwrap_or("left");
    let panel = &info[side];
    // The selected files; with none selected, the one under the cursor.
    let mut uris: Vec<&str> = panel["selected"]
        .as_array()
        .map(|a| a.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();
    if uris.is_empty() {
        if let Some(cursor) = panel["cursor"].as_str() {
            uris.push(cursor);
        }
    }
    let paths: Vec<String> = uris
        .iter()
        .map(|u| uri_to_path(u).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|| (*u).to_owned()))
        .collect();
    if paths.is_empty() {
        say("Nothing to copy.", 1);
        return;
    }
    let (Some(h), Ok(text)) = (host(), CString::new(paths.join("\n").replace('\0', ""))) else {
        return;
    };
    if let Some(set) = h.clipboard_set {
        if set(text.as_ptr()) == 0 {
            say(&format!("Copied {} path(s) to the clipboard", paths.len()), 0);
        }
    }
}

unsafe extern "C" fn mirror_folder(_user: *mut c_void) {
    let Some(info) = panel_info() else {
        say("The file panels are not on screen.", 1);
        return;
    };
    let (from, to) = if info["active"].as_str() == Some("right") { ("right", 0) } else { ("left", 1) };
    let Some(uri) = info[from]["uri"].as_str().and_then(|u| CString::new(u).ok()) else {
        return;
    };
    if let Some(goto) = host().and_then(|h| h.panel_goto) {
        goto(to, uri.as_ptr());
    }
}

unsafe extern "C" fn select_same_extension(_user: *mut c_void) {
    let Some(info) = panel_info() else {
        say("The file panels are not on screen.", 1);
        return;
    };
    let side = info["active"].as_str().unwrap_or("left");
    let extension = info[side]["cursor"]
        .as_str()
        .and_then(uri_to_path)
        .and_then(|p| p.extension().map(|e| e.to_string_lossy().into_owned()));
    let Some(extension) = extension else {
        say("The file under the cursor has no extension.", 1);
        return;
    };
    let mask = CString::new(format!("*.{}", extension)).unwrap_or_default();
    if let Some(select) = host().and_then(|h| h.panel_select) {
        // mode 0 = select the files matching the mask; side -1 = the active panel.
        select(-1, 0, mask.as_ptr());
    }
}

unsafe extern "C" fn peek_done(_user: *mut c_void, status: i64, data: *const u8, length: i64) {
    if status != 0 {
        let why = match status {
            1 => "not found",
            2 => "access denied",
            3 => "not supported or larger than 1 MB",
            _ => "could not be read",
        };
        say(&format!("Peek: the file {}.", why), 1);
        return;
    }
    let bytes = if data.is_null() { &[][..] } else { std::slice::from_raw_parts(data, length as usize) };
    let text = String::from_utf8_lossy(bytes);
    let first: String = text.lines().next().unwrap_or("").chars().take(60).collect();
    say(&format!("Peek: {} bytes, {} lines. First line: {}", length, text.lines().count(), first), 0);
}

unsafe extern "C" fn peek_file(_user: *mut c_void) {
    let Some(info) = panel_info() else {
        say("The file panels are not on screen.", 1);
        return;
    };
    let side = info["active"].as_str().unwrap_or("left");
    let Some(uri) = info[side]["cursor"].as_str().and_then(|u| CString::new(u).ok()) else {
        say("Put the cursor on a file.", 1);
        return;
    };
    let Some(read) = host().and_then(|h| h.vfs_read) else {
        say("This version of MTN2 cannot read files for plugins.", 1);
        return;
    };
    match read(PLUGIN_ID.as_ptr() as *const c_char, uri.as_ptr(), 1 << 20, peek_done, null_mut()) {
        0 => {}
        -2 => say("Peek needs the permission to read files: Parameters - Plugins - Permissions...", 1),
        _ => say("Peek could not start.", 1),
    }
}

/// What the counting thread tells the main thread.
struct Report {
    text: String,
    done: bool,
}

/// Runs on the main thread (posted by the counting thread): shows or ends the progress notice.
unsafe extern "C" fn show_report(user: *mut c_void) {
    let report = Box::from_raw(user as *mut Report);
    let Some(h) = host() else {
        return;
    };
    let id = JOB_ID.as_ptr() as *const c_char;
    let plugin = PLUGIN_ID.as_ptr() as *const c_char;
    if report.done {
        if let Some(end) = h.progress_end {
            end(plugin, id);
        }
        say(&report.text, 0);
    } else if let (Some(set), Ok(text)) = (h.progress_set, CString::new(report.text)) {
        set(plugin, id, text.as_ptr(), -1);
    }
}

fn post(report: Report) {
    let Some(post_to_main) = host().and_then(|h| h.post_to_main) else {
        return;
    };
    let raw = Box::into_raw(Box::new(report)) as *mut c_void;
    // The host drops a call for an unloaded plugin, so a report is never delivered into a DLL
    // that is gone; the leaked box in that case is a few bytes.
    unsafe { post_to_main(PLUGIN_ID.as_ptr() as *const c_char, show_report, raw) };
}

fn count_tree(root: &Path) -> Option<(u64, u64, u64)> {
    let (mut files, mut folders, mut bytes) = (0u64, 0u64, 0u64);
    let mut stack = vec![root.to_path_buf()];
    let mut last = Instant::now();
    while let Some(dir) = stack.pop() {
        if CANCEL.load(Ordering::Relaxed) {
            return None;
        }
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(meta) = entry.metadata() else {
                continue;
            };
            if meta.is_dir() {
                folders += 1;
                stack.push(entry.path());
            } else {
                files += 1;
                bytes += meta.len();
            }
            if last.elapsed() > Duration::from_millis(250) {
                last = Instant::now();
                post(Report { text: format!("Counting... {} files, {} folders", files, folders), done: false });
            }
        }
    }
    Some((files, folders, bytes))
}

unsafe extern "C" fn count_in_background(_user: *mut c_void) {
    let mut job = JOB.lock().unwrap();
    if let Some(running) = job.as_ref() {
        if !running.is_finished() {
            // A second press stops the count.
            CANCEL.store(true, Ordering::Relaxed);
            return;
        }
    }
    if let Some(finished) = job.take() {
        let _ = finished.join();
    }
    let Some(info) = panel_info() else {
        say("The file panels are not on screen.", 1);
        return;
    };
    let side = info["active"].as_str().unwrap_or("left");
    let Some(root) = info[side]["uri"].as_str().and_then(uri_to_path) else {
        say("This folder is not on a local disk.", 1);
        return;
    };
    CANCEL.store(false, Ordering::Relaxed);
    *job = Some(std::thread::spawn(move || {
        let text = match count_tree(&root) {
            Some((files, folders, bytes)) => {
                format!("{}: {} files, {} folders, {:.1} MB", root.display(), files, folders, bytes as f64 / 1_048_576.0)
            }
            None => "Counting stopped".to_owned(),
        };
        post(Report { text, done: true });
    }));
}

unsafe extern "C" fn on_event(_user: *mut c_void, _topic: *const c_char, payload: *const c_char) {
    let Ok(text) = CStr::from_ptr(payload).to_str() else {
        return;
    };
    let uri = serde_json::from_str::<Value>(text).ok().and_then(|v| v["uri"].as_str().map(str::to_owned));
    if let Some(path) = uri.as_deref().and_then(uri_to_path) {
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        say(&format!("Saved: {}", name), 0);
    }
}

#[no_mangle]
pub extern "C" fn mtn_plugin_get_abi_version() -> i64 {
    ABI_VERSION
}

/// # Safety
/// `host` must be null or point to a host table that stays valid until shutdown.
#[no_mangle]
pub unsafe extern "C" fn mtn_plugin_init(host: *const HostApi) -> i64 {
    let Some(api) = host.as_ref() else {
        return -1;
    };
    if api.abi_version < 2
        || api.panel_info.is_none()
        || api.panel_goto.is_none()
        || api.panel_select.is_none()
        || api.post_to_main.is_none()
        || api.clipboard_set.is_none()
        || api.show_message.is_none()
        || api.subscribe.is_none()
    {
        return -1;
    }
    let (Some(register), Some(bind), Some(subscribe)) =
        (api.register_command, api.register_key_binding, api.subscribe)
    else {
        return -1;
    };
    *HOST.lock().unwrap() = host as usize;
    let id = PLUGIN_ID.as_ptr() as *const c_char;
    let commands: [(&[u8], CommandCb, &[u8]); 5] = [
        (b"panelkit.copypaths\0", copy_paths, b"Ctrl+Shift+P\0"),
        (b"panelkit.mirror\0", mirror_folder, b"Ctrl+Shift+M\0"),
        (b"panelkit.selectext\0", select_same_extension, b"Ctrl+Shift+X\0"),
        (b"panelkit.count\0", count_in_background, b"Ctrl+Shift+K\0"),
        (b"panelkit.peek\0", peek_file, b"Ctrl+Shift+L\0"),
    ];
    for (name, run, chord) in commands {
        register(id, name.as_ptr() as *const c_char, run, null_mut());
        bind(id, name.as_ptr() as *const c_char, chord.as_ptr() as *const c_char);
    }
    subscribe(id, b"doc.saved\0".as_ptr() as *const c_char, on_event, null_mut());
    0
}

/// Stops the counting thread before the DLL goes.
#[no_mangle]
pub extern "C" fn mtn_plugin_shutdown() {
    CANCEL.store(true, Ordering::Relaxed);
    if let Ok(mut job) = JOB.lock() {
        if let Some(running) = job.take() {
            let _ = running.join();
        }
    }
    *HOST.lock().unwrap() = 0;
}
