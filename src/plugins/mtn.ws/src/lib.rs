#![no_std]
#![no_main]
#![allow(static_mut_refs)]

//! Workspace panel: empty virtual VFS of *links* to real files and folders.
//! Originals stay on disk. F5 records a reference; F8 drops the reference.

use core::ptr;
use core::slice;

const VER_OK: i64 = 0;
const VER_NOT_FOUND: i64 = 1;
const VER_ALREADY_EXISTS: i64 = 3;
const VER_NOT_SUPPORTED: i64 = 4;
const VER_IO: i64 = 5;
const VER_INVALID_URI: i64 = 6;
const VER_NEEDS_BUF: i64 = 7;

const HEAP_START: u32 = 0x10000;
const HEAP_END: u32 = 0x78000; // last 32 KiB is host scratch
const MAX_NODES: usize = 96;
const FLAG_USED: u8 = 1;
const FLAG_DIR: u8 = 2;
const FLAG_VIRT: u8 = 4;

#[link(wasm_import_module = "mtn_host")]
extern "C" {
    fn register_vfs_scheme(ptr: i32, len: i32, prio: i32) -> i32;
    fn register_panel_plugin(ptr: i32, len: i32, prio: i32) -> i32;
    fn register_menu_item(
        parent_ptr: i32,
        parent_len: i32,
        id_ptr: i32,
        id_len: i32,
        cap_ptr: i32,
        cap_len: i32,
        export_ptr: i32,
        export_len: i32,
        prio: i32,
    ) -> i32;
    fn publish(topic_ptr: i32, topic_len: i32, json_ptr: i32, json_len: i32) -> i32;
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Node {
    path_ptr: u32,
    path_len: u16,
    target_ptr: u32,
    target_len: u16,
    flags: u8,
}

static SCHEME: [u8; 2] = *b"ws";
static PARENT: [u8; 8] = *b"Commands";
static OPEN_ID: [u8; 7] = *b"ws_open";
static OPEN_CAP: [u8; 9] = *b"Workspace";
static CLEAR_ID: [u8; 8] = *b"ws_clear";
static CLEAR_CAP: [u8; 15] = *b"Clear workspace";
static MENU_OPEN: [u8; 9] = *b"menu_open";
static MENU_CLEAR: [u8; 10] = *b"menu_clear";
static TOPIC_NAV: [u8; 14] = *b"panel.navigate";
static JSON_ROOT: [u8; 16] = *b"{\"uri\":\"ws:///\"}";
static JSON_CLEAR: [u8; 29] = *b"{\"uri\":\"ws:///\",\"clear\":true}";

static mut LAST_SIZE: i64 = 0;
static mut HEAP_AT: u32 = HEAP_START;
static mut NODES: [Node; MAX_NODES] = [Node {
    path_ptr: 0,
    path_len: 0,
    target_ptr: 0,
    target_len: 0,
    flags: 0,
}; MAX_NODES];

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

unsafe fn memory_len() -> u32 {
    (core::arch::wasm32::memory_size(0) as u32).saturating_mul(65536)
}

unsafe fn guest_slice(ptr: i32, len: i32) -> Option<&'static [u8]> {
    if ptr < 0 || len < 0 {
        return None;
    }
    let p = ptr as u32;
    let n = len as u32;
    let max = memory_len();
    if p.checked_add(n).map(|e| e > max).unwrap_or(true) {
        return None;
    }
    Some(slice::from_raw_parts(p as *const u8, n as usize))
}

unsafe fn alloc(n: usize) -> Option<u32> {
    if n == 0 {
        return Some(HEAP_AT);
    }
    let aligned = (n + 3) & !3;
    let at = HEAP_AT;
    let end = at.checked_add(aligned as u32)?;
    if end > HEAP_END {
        return None;
    }
    HEAP_AT = end;
    Some(at)
}

unsafe fn store_bytes(src: &[u8]) -> Option<(u32, u16)> {
    if src.len() > u16::MAX as usize {
        return None;
    }
    let p = alloc(src.len())?;
    ptr::copy_nonoverlapping(src.as_ptr(), p as *mut u8, src.len());
    Some((p, src.len() as u16))
}

fn eq_ci(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter()
        .zip(b.iter())
        .all(|(x, y)| x.to_ascii_lowercase() == y.to_ascii_lowercase())
}

fn starts_with_ci(s: &[u8], prefix: &[u8]) -> bool {
    s.len() >= prefix.len() && eq_ci(&s[..prefix.len()], prefix)
}

fn inner_path(uri: &[u8]) -> Option<&[u8]> {
    if !starts_with_ci(uri, b"ws://") {
        return None;
    }
    let mut rest = &uri[5..];
    while rest.first() == Some(&b'/') {
        rest = &rest[1..];
    }
    while rest.last() == Some(&b'/') {
        rest = &rest[..rest.len() - 1];
    }
    Some(rest)
}

fn parent_of(path: &[u8]) -> &[u8] {
    match path.iter().rposition(|&c| c == b'/') {
        Some(i) => &path[..i],
        None => b"",
    }
}

fn name_of(path: &[u8]) -> &[u8] {
    match path.iter().rposition(|&c| c == b'/') {
        Some(i) => &path[i + 1..],
        None => path,
    }
}

fn filename_of_uri(uri: &[u8]) -> &[u8] {
    let mut s = uri;
    while s.last() == Some(&b'/') && s.len() > 1 {
        s = &s[..s.len() - 1];
    }
    let slash = s
        .iter()
        .rposition(|&c| c == b'/' || c == b'\\')
        .map(|i| i + 1)
        .unwrap_or(0);
    let name = &s[slash..];
    if name.is_empty() {
        b"item"
    } else {
        name
    }
}

fn ext_of(name: &[u8]) -> &[u8] {
    match name.iter().rposition(|&c| c == b'.') {
        Some(i) if i > 0 && i + 1 < name.len() => &name[i + 1..],
        _ => b"",
    }
}

unsafe fn node_path(n: &Node) -> &[u8] {
    slice::from_raw_parts(n.path_ptr as *const u8, n.path_len as usize)
}

unsafe fn node_target(n: &Node) -> &[u8] {
    if n.target_len == 0 {
        b""
    } else {
        slice::from_raw_parts(n.target_ptr as *const u8, n.target_len as usize)
    }
}

unsafe fn find_path(path: &[u8]) -> Option<usize> {
    for i in 0..MAX_NODES {
        let n = &NODES[i];
        if n.flags & FLAG_USED == 0 {
            continue;
        }
        if eq_ci(node_path(n), path) {
            return Some(i);
        }
    }
    None
}

unsafe fn find_free() -> Option<usize> {
    (0..MAX_NODES).find(|&i| NODES[i].flags & FLAG_USED == 0)
}

unsafe fn is_descendant(path: &[u8], dir: &[u8]) -> bool {
    if dir.is_empty() {
        return !path.is_empty();
    }
    if path.len() <= dir.len() {
        return false;
    }
    eq_ci(&path[..dir.len()], dir) && path[dir.len()] == b'/'
}

unsafe fn ensure_parent(path: &[u8]) -> i64 {
    let parent = parent_of(path);
    if parent.is_empty() {
        return VER_OK;
    }
    if let Some(i) = find_path(parent) {
        if NODES[i].flags & FLAG_DIR == 0 {
            return VER_IO;
        }
        return VER_OK;
    }
    let st = ensure_parent(parent);
    if st != VER_OK {
        return st;
    }
    match alloc_node(parent, b"", true, true) {
        Some(_) => VER_OK,
        None => VER_IO,
    }
}

unsafe fn alloc_node(path: &[u8], target: &[u8], is_dir: bool, virt: bool) -> Option<usize> {
    let i = find_free()?;
    let (pp, pl) = store_bytes(path)?;
    let (tp, tl) = if target.is_empty() {
        (0u32, 0u16)
    } else {
        store_bytes(target)?
    };
    let mut flags = FLAG_USED;
    if is_dir {
        flags |= FLAG_DIR;
    }
    if virt {
        flags |= FLAG_VIRT;
    }
    NODES[i] = Node {
        path_ptr: pp,
        path_len: pl,
        target_ptr: tp,
        target_len: tl,
        flags,
    };
    Some(i)
}

unsafe fn remove_at(i: usize) {
    NODES[i].flags = 0;
}

unsafe fn remove_tree(path: &[u8]) {
    for i in 0..MAX_NODES {
        if NODES[i].flags & FLAG_USED == 0 {
            continue;
        }
        let p = node_path(&NODES[i]);
        if eq_ci(p, path) || is_descendant(p, path) {
            remove_at(i);
        }
    }
}

fn json_escape_into(dst: &mut [u8], mut w: usize, src: &[u8]) -> Option<usize> {
    for &c in src {
        let need = match c {
            b'\\' | b'"' => 2,
            _ => 1,
        };
        if w + need > dst.len() {
            return None;
        }
        if need == 2 {
            dst[w] = b'\\';
            w += 1;
        }
        dst[w] = c;
        w += 1;
    }
    Some(w)
}

fn push(dst: &mut [u8], w: usize, s: &[u8]) -> Option<usize> {
    if w + s.len() > dst.len() {
        return None;
    }
    dst[w..w + s.len()].copy_from_slice(s);
    Some(w + s.len())
}

unsafe fn write_list_json(parent: &[u8], out: &mut [u8]) -> Option<usize> {
    let mut w = push(out, 0, b"[")?;
    let mut first = true;
    for i in 0..MAX_NODES {
        let n = &NODES[i];
        if n.flags & FLAG_USED == 0 {
            continue;
        }
        let path = node_path(n);
        if !eq_ci(parent_of(path), parent) {
            continue;
        }
        let name = name_of(path);
        if name.is_empty() {
            continue;
        }
        if !first {
            w = push(out, w, b",")?;
        }
        first = false;
        w = push(out, w, b"{\"name\":\"")?;
        w = json_escape_into(out, w, name)?;
        w = push(out, w, b"\",\"ext\":\"")?;
        w = json_escape_into(out, w, ext_of(name))?;
        w = push(out, w, b"\",\"size\":0,\"isDir\":")?;
        w = push(
            out,
            w,
            if n.flags & FLAG_DIR != 0 {
                b"true"
            } else {
                b"false"
            },
        )?;
        let target = node_target(n);
        if !target.is_empty() {
            w = push(out, w, b",\"isLink\":true,\"targetUri\":\"")?;
            w = json_escape_into(out, w, target)?;
            w = push(out, w, b"\"")?;
        } else {
            w = push(out, w, b",\"isLink\":false")?;
        }
        w = push(out, w, b"}")?;
    }
    w = push(out, w, b"]")?;
    Some(w)
}

unsafe fn dest_path(from: &[u8], to: &[u8]) -> Result<[u8; 256], i64> {
    let inner = match inner_path(to) {
        Some(p) => p,
        None => return Err(VER_INVALID_URI),
    };
    let mut buf = [0u8; 256];
    if inner.is_empty() {
        let name = filename_of_uri(from);
        if name.len() > buf.len() {
            return Err(VER_IO);
        }
        buf[..name.len()].copy_from_slice(name);
        Ok(buf)
    } else if let Some(i) = find_path(inner) {
        if NODES[i].flags & FLAG_DIR != 0 && NODES[i].flags & FLAG_VIRT != 0 {
            let name = filename_of_uri(from);
            let need = inner.len() + 1 + name.len();
            if need > buf.len() {
                return Err(VER_IO);
            }
            buf[..inner.len()].copy_from_slice(inner);
            buf[inner.len()] = b'/';
            buf[inner.len() + 1..need].copy_from_slice(name);
            Ok(buf)
        } else {
            if inner.len() > buf.len() {
                return Err(VER_IO);
            }
            buf[..inner.len()].copy_from_slice(inner);
            Ok(buf)
        }
    } else {
        if inner.len() > buf.len() {
            return Err(VER_IO);
        }
        buf[..inner.len()].copy_from_slice(inner);
        Ok(buf)
    }
}

fn path_bytes(buf: &[u8; 256]) -> &[u8] {
    let n = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    &buf[..n]
}

#[no_mangle]
pub extern "C" fn mtn_plugin_get_abi_version() -> i64 {
    1
}

#[no_mangle]
pub extern "C" fn mtn_plugin_init() -> i32 {
    unsafe {
        HEAP_AT = HEAP_START;
        for n in NODES.iter_mut() {
            *n = Node {
                path_ptr: 0,
                path_len: 0,
                target_ptr: 0,
                target_len: 0,
                flags: 0,
            };
        }
        register_vfs_scheme(SCHEME.as_ptr() as i32, SCHEME.len() as i32, 26);
        register_panel_plugin(SCHEME.as_ptr() as i32, SCHEME.len() as i32, 26);
        register_menu_item(
            PARENT.as_ptr() as i32,
            PARENT.len() as i32,
            OPEN_ID.as_ptr() as i32,
            OPEN_ID.len() as i32,
            OPEN_CAP.as_ptr() as i32,
            OPEN_CAP.len() as i32,
            MENU_OPEN.as_ptr() as i32,
            MENU_OPEN.len() as i32,
            42,
        );
        register_menu_item(
            PARENT.as_ptr() as i32,
            PARENT.len() as i32,
            CLEAR_ID.as_ptr() as i32,
            CLEAR_ID.len() as i32,
            CLEAR_CAP.as_ptr() as i32,
            CLEAR_CAP.len() as i32,
            MENU_CLEAR.as_ptr() as i32,
            MENU_CLEAR.len() as i32,
            43,
        );
    }
    0
}

#[no_mangle]
pub extern "C" fn mtn_plugin_shutdown() {}

#[no_mangle]
pub extern "C" fn mtn_last_size() -> i64 {
    unsafe { LAST_SIZE }
}

#[no_mangle]
pub extern "C" fn menu_open() {
    unsafe {
        publish(
            TOPIC_NAV.as_ptr() as i32,
            TOPIC_NAV.len() as i32,
            JSON_ROOT.as_ptr() as i32,
            JSON_ROOT.len() as i32,
        );
    }
}

#[no_mangle]
pub extern "C" fn menu_clear() {
    unsafe {
        for n in NODES.iter_mut() {
            n.flags = 0;
        }
        HEAP_AT = HEAP_START;
        publish(
            TOPIC_NAV.as_ptr() as i32,
            TOPIC_NAV.len() as i32,
            JSON_CLEAR.as_ptr() as i32,
            JSON_CLEAR.len() as i32,
        );
    }
}

#[no_mangle]
pub extern "C" fn mtn_vfs_list(uri_ptr: i32, uri_len: i32, out_ptr: i32, out_cap: i32) -> i64 {
    unsafe {
        LAST_SIZE = 0;
        let uri = match guest_slice(uri_ptr, uri_len) {
            Some(s) => s,
            None => return VER_INVALID_URI,
        };
        let parent = match inner_path(uri) {
            Some(p) => p,
            None => return VER_INVALID_URI,
        };
        if !parent.is_empty() {
            match find_path(parent) {
                Some(i) if NODES[i].flags & FLAG_DIR != 0 => {}
                Some(_) => return VER_IO,
                None => return VER_NOT_FOUND,
            }
        }
        let out = match guest_slice(out_ptr, out_cap) {
            Some(s) => slice::from_raw_parts_mut(s.as_ptr() as *mut u8, s.len()),
            None => return VER_IO,
        };
        match write_list_json(parent, out) {
            Some(n) => {
                LAST_SIZE = n as i64;
                VER_OK
            }
            None => {
                LAST_SIZE = 4096;
                VER_NEEDS_BUF
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn mtn_vfs_exists(uri_ptr: i32, uri_len: i32) -> i64 {
    unsafe {
        LAST_SIZE = 0;
        let uri = match guest_slice(uri_ptr, uri_len) {
            Some(s) => s,
            None => return VER_INVALID_URI,
        };
        if let Some(inner) = inner_path(uri) {
            if inner.is_empty() {
                LAST_SIZE = 1;
                return VER_OK;
            }
            return match find_path(inner) {
                Some(i) => {
                    LAST_SIZE = i64::from(NODES[i].flags & FLAG_DIR != 0);
                    VER_OK
                }
                None => VER_NOT_FOUND,
            };
        }
        // F8 unlink passes the row's targetUri (file://...).
        for i in 0..MAX_NODES {
            if NODES[i].flags & FLAG_USED == 0 {
                continue;
            }
            if eq_ci(node_target(&NODES[i]), uri) {
                LAST_SIZE = i64::from(NODES[i].flags & FLAG_DIR != 0);
                return VER_OK;
            }
        }
        VER_NOT_FOUND
    }
}

#[no_mangle]
pub extern "C" fn mtn_vfs_read_text(
    _uri_ptr: i32,
    _uri_len: i32,
    _out_ptr: i32,
    _out_cap: i32,
) -> i64 {
    unsafe {
        LAST_SIZE = 0;
    }
    VER_NOT_SUPPORTED
}

#[no_mangle]
pub extern "C" fn mtn_vfs_mkdir(uri_ptr: i32, uri_len: i32) -> i64 {
    unsafe {
        let uri = match guest_slice(uri_ptr, uri_len) {
            Some(s) => s,
            None => return VER_INVALID_URI,
        };
        let inner = match inner_path(uri) {
            Some(p) if !p.is_empty() => p,
            _ => return VER_INVALID_URI,
        };
        if find_path(inner).is_some() {
            return VER_ALREADY_EXISTS;
        }
        let st = ensure_parent(inner);
        if st != VER_OK {
            return st;
        }
        match alloc_node(inner, b"", true, true) {
            Some(_) => VER_OK,
            None => VER_IO,
        }
    }
}

#[no_mangle]
pub extern "C" fn mtn_vfs_delete(uri_ptr: i32, uri_len: i32) -> i64 {
    unsafe {
        let uri = match guest_slice(uri_ptr, uri_len) {
            Some(s) => s,
            None => return VER_INVALID_URI,
        };
        if let Some(inner) = inner_path(uri) {
            if inner.is_empty() {
                for n in NODES.iter_mut() {
                    n.flags = 0;
                }
                HEAP_AT = HEAP_START;
                return VER_OK;
            }
            if find_path(inner).is_none() {
                return VER_NOT_FOUND;
            }
            remove_tree(inner);
            return VER_OK;
        }
        let mut any = false;
        for i in 0..MAX_NODES {
            if NODES[i].flags & FLAG_USED == 0 {
                continue;
            }
            if eq_ci(node_target(&NODES[i]), uri) {
                remove_tree(node_path(&NODES[i]));
                any = true;
            }
        }
        if any {
            VER_OK
        } else {
            VER_NOT_FOUND
        }
    }
}

#[no_mangle]
pub extern "C" fn mtn_vfs_copy(
    from_ptr: i32,
    from_len: i32,
    to_ptr: i32,
    to_len: i32,
    is_dir: i32,
    overwrite: i32,
) -> i64 {
    unsafe {
        let from = match guest_slice(from_ptr, from_len) {
            Some(s) => s,
            None => return VER_INVALID_URI,
        };
        let to = match guest_slice(to_ptr, to_len) {
            Some(s) => s,
            None => return VER_INVALID_URI,
        };
        let packed = match dest_path(from, to) {
            Ok(b) => b,
            Err(c) => return c,
        };
        let dest = path_bytes(&packed);
        if dest.is_empty() {
            return VER_INVALID_URI;
        }

        let mut target = from;
        let mut dir = is_dir != 0;
        let mut virt = false;
        if inner_path(from).is_some() {
            let src_inner = inner_path(from).unwrap();
            match find_path(src_inner) {
                Some(i) => {
                    target = node_target(&NODES[i]);
                    dir = NODES[i].flags & FLAG_DIR != 0;
                    virt = NODES[i].flags & FLAG_VIRT != 0;
                    if virt {
                        target = b"";
                    }
                }
                None => return VER_NOT_FOUND,
            }
        }

        if let Some(i) = find_path(dest) {
            if overwrite == 0 {
                return VER_ALREADY_EXISTS;
            }
            remove_tree(dest);
            let _ = i;
        }
        let st = ensure_parent(dest);
        if st != VER_OK {
            return st;
        }
        match alloc_node(dest, target, dir, virt && target.is_empty()) {
            Some(_) => VER_OK,
            None => VER_IO,
        }
    }
}
