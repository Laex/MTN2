//! Demo plugin in Rust (native DLL): F3 on a `.csv` file shows an aligned
//! table instead of the raw text.
//!
//! Shows: a document provider that answers with a redirect. The plugin renders
//! the CSV into a text file in the temp folder and tells the host to open that
//! file in its built-in viewer; F4 (edit) is left to the built-in editor.

use std::ffi::{c_char, c_void, CStr};
use std::fs;
use std::path::PathBuf;

const ABI_VERSION: i64 = 2;
const PLUGIN_ID: &[u8] = b"mtn.demo.rs\0";
const MODE_VIEW: i64 = 1;
const MAX_BYTES: u64 = 4 * 1024 * 1024;

type DocumentCb = unsafe extern "C" fn(
    user: *mut c_void,
    uri: *const c_char,
    mode: *const c_char,
    redirect: *mut c_char,
    redirect_cap: i64,
) -> i64;

/// Mirror of `THostApiTable` (src/Core/uPluginHostAbi.pas). Fields this plugin
/// does not call are plain pointers; only their position matters.
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
    register_document_provider: Option<
        unsafe extern "C" fn(
            plugin_id: *const c_char,
            extensions: *const c_char,
            modes: i64,
            handler: DocumentCb,
            user: *mut c_void,
            priority: i64,
        ) -> i64,
    >,
}

/// `file:///C:/dir/a%20b.csv` -> `C:\dir\a b.csv`.
fn uri_to_path(uri: &str) -> Option<PathBuf> {
    let rest = uri.strip_prefix("file:///")?;
    let mut bytes = Vec::with_capacity(rest.len());
    let raw = rest.as_bytes();
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

/// Splits one CSV record on `delimiter`, honouring double quotes.
fn split_record(line: &str, delimiter: char) -> Vec<String> {
    let mut cells = Vec::new();
    let mut cell = String::new();
    let mut quoted = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    cell.push('"');
                    chars.next();
                } else {
                    quoted = false;
                }
            } else {
                cell.push(c);
            }
        } else if c == '"' {
            quoted = true;
        } else if c == delimiter {
            cells.push(std::mem::take(&mut cell));
        } else {
            cell.push(c);
        }
    }
    cells.push(cell);
    cells
}

/// Aligned text table of a CSV document; the delimiter is the commonest of
/// `,` `;` and tab in the first line.
fn render_table(text: &str) -> String {
    let first = text.lines().next().unwrap_or("");
    let delimiter = [',', ';', '\t']
        .into_iter()
        .max_by_key(|d| first.matches(*d).count())
        .unwrap_or(',');
    let rows: Vec<Vec<String>> = text
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| split_record(l, delimiter))
        .collect();
    let columns = rows.iter().map(Vec::len).max().unwrap_or(0);
    let mut widths = vec![0usize; columns];
    for row in &rows {
        for (i, cell) in row.iter().enumerate() {
            widths[i] = widths[i].max(cell.chars().count());
        }
    }
    let mut out = String::new();
    for (n, row) in rows.iter().enumerate() {
        let mut line = String::new();
        for (i, width) in widths.iter().enumerate() {
            let cell = row.get(i).map(String::as_str).unwrap_or("");
            line.push_str(cell);
            line.extend(std::iter::repeat(' ').take(width - cell.chars().count()));
            if i + 1 < widths.len() {
                line.push_str(" | ");
            }
        }
        out.push_str(line.trim_end());
        out.push('\n');
        if n == 0 {
            let rule: Vec<String> = widths.iter().map(|w| "-".repeat(*w)).collect();
            out.push_str(&rule.join("-+-"));
            out.push('\n');
        }
    }
    out
}

fn fnv(s: &str) -> u64 {
    s.bytes()
        .fold(0xcbf29ce484222325, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3))
}

/// Renders the CSV at `uri` and returns the URI of the text file.
fn render_to_temp(uri: &str) -> Option<String> {
    let path = uri_to_path(uri)?;
    if fs::metadata(&path).ok()?.len() > MAX_BYTES {
        return None;
    }
    let text = String::from_utf8_lossy(&fs::read(&path).ok()?).into_owned();
    let table = render_table(text.trim_start_matches('\u{feff}'));
    let out = std::env::temp_dir().join(format!("mtn2-csv-{:016x}.txt", fnv(uri)));
    fs::write(&out, table).ok()?;
    Some(format!("file:///{}", out.to_string_lossy().replace('\\', "/")))
}

unsafe extern "C" fn on_document(
    _user: *mut c_void,
    uri: *const c_char,
    mode: *const c_char,
    redirect: *mut c_char,
    redirect_cap: i64,
) -> i64 {
    if uri.is_null() || mode.is_null() || redirect.is_null() {
        return 0;
    }
    if CStr::from_ptr(mode).to_bytes() != b"view" {
        return 0; // F4: the built-in editor
    }
    let Ok(uri) = CStr::from_ptr(uri).to_str() else { return 0 };
    let Some(target) = render_to_temp(uri) else { return 0 };
    let bytes = target.as_bytes();
    if bytes.len() as i64 + 1 > redirect_cap {
        return 0;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), redirect as *mut u8, bytes.len());
    *redirect.add(bytes.len()) = 0;
    2 // open the redirect URI in the built-in viewer
}

#[no_mangle]
pub extern "C" fn mtn_plugin_get_abi_version() -> i64 {
    ABI_VERSION
}

/// # Safety
/// `host` is the table the host passes to `mtn_plugin_init`.
#[no_mangle]
pub unsafe extern "C" fn mtn_plugin_init(host: *const HostApi) -> i64 {
    let Some(host) = host.as_ref() else { return -1 };
    if host.abi_version < ABI_VERSION {
        return -1;
    }
    let Some(register) = host.register_document_provider else { return -1 };
    register(
        PLUGIN_ID.as_ptr() as *const c_char,
        b".csv\0".as_ptr() as *const c_char,
        MODE_VIEW,
        on_document,
        std::ptr::null_mut(),
        100,
    )
}

#[no_mangle]
pub extern "C" fn mtn_plugin_shutdown() {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aligns_columns_and_picks_the_delimiter() {
        let t = render_table("name;qty\nap;1\nbanana;20\n");
        assert_eq!(t, "name   | qty\n-------+----\nap     | 1\nbanana | 20\n");
    }

    #[test]
    fn quotes_hide_the_delimiter() {
        assert_eq!(split_record("a,\"b,c\",\"d\"\"e\"", ','), vec!["a", "b,c", "d\"e"]);
    }

    #[test]
    fn converts_file_uris() {
        assert_eq!(
            uri_to_path("file:///C:/My%20Dir/a.csv").unwrap(),
            PathBuf::from("C:\\My Dir\\a.csv")
        );
        assert!(uri_to_path("sftp://h/a.csv").is_none());
    }
}
