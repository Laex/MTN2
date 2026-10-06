//! Demo plugin in Rust (native DLL): colors configuration-style text.
//!
//! JSON, INI and similar files (`.json`, `.ini`, `.cfg`, `.conf`, `.toml`, `.yaml`) get their
//! strings, numbers, constants, keys, sections and comments colored in the viewer (F3) and the
//! editor (F4). The plugin only names a class for each part of a line; the colors are the
//! program's and follow the theme.
//!
//! Shows: register_highlighter. The host calls the handler with one line (UTF-8) and room for
//! spans of three 32-bit integers (start byte, byte length, class); a line it has seen is not
//! asked again.

use std::ffi::{c_char, c_void, CStr};
use std::ptr::null_mut;

const ABI_VERSION: i64 = 2;
const PLUGIN_ID: &[u8] = b"mtn.demo.highlight\0";
const EXTENSIONS: &[u8] = b".json;.ini;.cfg;.conf;.toml;.yaml;.yml\0";

const COMMENT: i32 = 1;
const STRING: i32 = 2;
const NUMBER: i32 = 3;
const TYPE: i32 = 5;
const OPERATOR: i32 = 7;
const CONSTANT: i32 = 9;
const KEY: i32 = 10;

type HighlightCb = unsafe extern "C" fn(user: *mut c_void, line: *const c_char, spans: *mut i32, cap: i64) -> i64;

/// Mirror of `THostApiTable` (src/Core/uPluginHostAbi.pas). Fields this plugin does not call
/// are plain pointers; only their position matters.
#[repr(C)]
pub struct HostApi {
    abi_version: i64,
    host_publish: *const c_void,
    host_invalidate: *const c_void,
    register_vfs_scheme: *const c_void,
    register_panel_plugin: *const c_void,
    register_key_binding: *const c_void,
    register_menu_item: *const c_void,
    register_command: *const c_void,
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
    panel_info: *const c_void,
    panel_goto: *const c_void,
    panel_refresh: *const c_void,
    clipboard_get: *const c_void,
    clipboard_set: *const c_void,
    show_message: *const c_void,
    subscribe: *const c_void,
    panel_list: *const c_void,
    panel_set_cursor: *const c_void,
    panel_select: *const c_void,
    doc_set_selection: *const c_void,
    doc_line: *const c_void,
    post_to_main: *const c_void,
    progress_set: *const c_void,
    progress_end: *const c_void,
    surface_open_ex: *const c_void,
    surface_set_fullscreen: *const c_void,
    surface_native_handle: *const c_void,
    register_highlighter: Option<
        unsafe extern "C" fn(
            plugin_id: *const c_char,
            extensions: *const c_char,
            handler: HighlightCb,
            user: *mut c_void,
        ) -> i64,
    >,
}

/// A colored part of a line: byte offset, byte length, class.
type Span = (usize, usize, i32);

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_' || b == b'-' || b == b'.'
}

/// The spans of one line of a JSON / INI / YAML-like file.
fn highlight(line: &[u8]) -> Vec<Span> {
    let mut spans = Vec::new();
    let start = line.iter().position(|b| !b.is_ascii_whitespace()).unwrap_or(line.len());
    let rest = &line[start..];
    if rest.is_empty() {
        return spans;
    }
    // Comments and INI sections take the whole line.
    if rest[0] == b';' || rest[0] == b'#' || rest.starts_with(b"//") {
        spans.push((start, rest.len(), COMMENT));
        return spans;
    }
    if rest[0] == b'[' && rest.iter().rposition(|&b| b == b']').is_some() && !rest.contains(&b'"') {
        spans.push((start, rest.len(), TYPE));
        return spans;
    }
    // INI / YAML entry: a word at the start of the line followed by '=' or ':'.
    let mut i = start;
    let word_end = line[start..].iter().position(|&b| !is_word(b)).map_or(line.len(), |n| start + n);
    if word_end > start {
        let after = line[word_end..].iter().position(|b| !b.is_ascii_whitespace()).map(|n| word_end + n);
        if let Some(a) = after {
            if line[a] == b'=' || line[a] == b':' {
                spans.push((start, word_end - start, KEY));
                spans.push((a, 1, OPERATOR));
                i = a + 1;
            }
        }
    }
    while i < line.len() {
        let b = line[i];
        match b {
            b'"' | b'\'' => {
                let mut j = i + 1;
                while j < line.len() && line[j] != b {
                    if line[j] == b'\\' {
                        j += 1;
                    }
                    j += 1;
                }
                let end = (j + 1).min(line.len());
                // A JSON member name: a string followed by a colon.
                let colon = line[end..].iter().find(|c| !c.is_ascii_whitespace()) == Some(&b':');
                spans.push((i, end - i, if colon { KEY } else { STRING }));
                i = end;
            }
            b'{' | b'}' | b'[' | b']' | b',' | b':' | b'=' => {
                spans.push((i, 1, OPERATOR));
                i += 1;
            }
            b'-' | b'0'..=b'9' if i == 0 || !is_word(line[i - 1]) => {
                let mut j = i + 1;
                while j < line.len() && (line[j].is_ascii_digit() || matches!(line[j], b'.' | b'e' | b'E' | b'+' | b'-' | b'x' | b'a'..=b'd' | b'f')) {
                    j += 1;
                }
                if j > i + 1 || b.is_ascii_digit() {
                    spans.push((i, j - i, NUMBER));
                }
                i = j.max(i + 1);
            }
            _ if is_word(b) => {
                let mut j = i;
                while j < line.len() && is_word(line[j]) {
                    j += 1;
                }
                let word = &line[i..j];
                if matches!(word, b"true" | b"false" | b"null" | b"yes" | b"no" | b"on" | b"off") {
                    spans.push((i, j - i, CONSTANT));
                }
                i = j;
            }
            _ => i += 1,
        }
    }
    spans
}

unsafe extern "C" fn on_highlight(_user: *mut c_void, line: *const c_char, spans: *mut i32, cap: i64) -> i64 {
    let bytes = CStr::from_ptr(line).to_bytes();
    let found = highlight(bytes);
    let count = found.len().min(cap as usize);
    for (n, (start, len, class)) in found.into_iter().take(count).enumerate() {
        *spans.add(n * 3) = start as i32;
        *spans.add(n * 3 + 1) = len as i32;
        *spans.add(n * 3 + 2) = class;
    }
    count as i64
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
    let Some(register) = api.register_highlighter else {
        return -1;
    };
    register(
        PLUGIN_ID.as_ptr() as *const c_char,
        EXTENSIONS.as_ptr() as *const c_char,
        on_highlight,
        null_mut(),
    );
    0
}

#[no_mangle]
pub extern "C" fn mtn_plugin_shutdown() {}
