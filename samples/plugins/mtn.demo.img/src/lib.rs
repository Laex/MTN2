//! Demo plugin in Rust (native DLL): a picture viewer for MTN2.
//!
//! F3 on a picture shows it in a viewer tab. The plugin decodes the file with the `image` crate
//! (JPEG, PNG, BMP, GIF, TIFF, WebP), turns it upright by its EXIF orientation and renders what is
//! visible at the zoom you asked for into a frame the size of the tab; the host draws the frame.
//!
//!   wheel          zoom around the pointer           drag (left button)  move the picture
//!   double click   fit <-> 100 %                      + / - / 0 / 1       zoom in / out / fit / 100 %
//!   r / R          rotate clockwise / back             f                   full screen on / off
//!   Right, Space   next picture of the folder          Left, Backspace     previous picture
//!   Home / End     first / last picture                Esc                 leaves full screen, then closes
//!   Ctrl+Shift+V   show the picture of the file under the panel cursor in the other panel (like
//!                  Quick View) and follow the cursor; press again to close it
//!   Ctrl+Shift+Y   rotate the picture shown in the other panel
//!
//! Shows: surface_open_ex (tab, full screen, panel), mouse events and the size of the area, panel
//! events (panel.cursor, panel.dir) and panel_info, EXIF orientation.

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr::null_mut;

use serde_json::Value;

const ABI_VERSION: i64 = 2;
const PLUGIN_ID: &[u8] = b"mtn.demo.img\0";
const EXTENSIONS: &[u8] = b".jpg;.jpeg;.bmp;.png;.gif;.tif;.tiff;.webp\0";
const MODE_VIEW: i64 = 1;
/// Longest side kept in memory; bigger pictures are shrunk first.
const MAX_SIDE: u32 = 4096;

type DocumentCb = unsafe extern "C" fn(
    user: *mut c_void,
    uri: *const c_char,
    mode: *const c_char,
    redirect: *mut c_char,
    redirect_cap: i64,
) -> i64;
type CommandCb = unsafe extern "C" fn(user: *mut c_void);
type KeyCb = unsafe extern "C" fn(user: *mut c_void, key: *const c_char) -> i64;
type ClosedCb = unsafe extern "C" fn(user: *mut c_void);
type MouseCb = unsafe extern "C" fn(
    user: *mut c_void,
    kind: i64,
    x: i64,
    y: i64,
    width: i64,
    height: i64,
    button: i64,
    extra: i64,
    shift: i64,
) -> i64;
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
    open_external: *const c_void,
    show_dialog: *const c_void,
    register_panel_activate: *const c_void,
    set_command_caption: *const c_void,
    set_status_segment: *const c_void,
    register_settings: *const c_void,
    get_setting: *const c_void,
    set_setting: *const c_void,
    surface_open: *const c_void,
    surface_set_frame: Option<
        unsafe extern "C" fn(handle: i64, width: i64, height: i64, pixels: *const u8, length: i64) -> i64,
    >,
    surface_set_info:
        Option<unsafe extern "C" fn(handle: i64, title: *const c_char, status: *const c_char) -> i64>,
    surface_set_timer: *const c_void,
    surface_close: Option<unsafe extern "C" fn(handle: i64) -> i64>,
    host_info: *const c_void,
    doc_info: *const c_void,
    doc_get_text: *const c_void,
    doc_replace: *const c_void,
    doc_set_cursor: *const c_void,
    panel_info: Option<unsafe extern "C" fn(buf: *mut c_char, size: i64) -> i64>,
    panel_goto: *const c_void,
    panel_refresh: *const c_void,
    clipboard_get: *const c_void,
    clipboard_set: *const c_void,
    show_message: Option<unsafe extern "C" fn(text: *const c_char, kind: i64) -> i64>,
    subscribe: Option<
        unsafe extern "C" fn(plugin_id: *const c_char, topic: *const c_char, on_event: EventCb, user: *mut c_void) -> i64,
    >,
    panel_list: *const c_void,
    panel_set_cursor: *const c_void,
    panel_select: *const c_void,
    doc_set_selection: *const c_void,
    doc_line: *const c_void,
    post_to_main: *const c_void,
    progress_set: *const c_void,
    progress_end: *const c_void,
    surface_open_ex: Option<
        unsafe extern "C" fn(
            plugin_id: *const c_char,
            title: *const c_char,
            mode: i64,
            on_key: Option<KeyCb>,
            on_tick: *const c_void,
            on_closed: Option<ClosedCb>,
            on_mouse: Option<MouseCb>,
            user: *mut c_void,
        ) -> i64,
    >,
    surface_set_fullscreen: Option<unsafe extern "C" fn(handle: i64, on: i64) -> i64>,
    surface_native_handle: *const c_void,
    register_highlighter: *const c_void,
    vfs_list: *const c_void,
    vfs_exists: *const c_void,
    vfs_read: *const c_void,
    vfs_open: *const c_void,
    vfs_size: *const c_void,
    vfs_read_at: *const c_void,
    vfs_close: *const c_void,
    vfs_cancel: *const c_void,
    surface_get_fullscreen: *const c_void,
}

/// A decoded picture: top-down BGRA.
struct Picture {
    width: usize,
    height: usize,
    pixels: Vec<u8>,
}

struct Viewer {
    host: *const HostApi,
    /// Surface handle; 0 = nothing open.
    surface: i64,
    /// 0 = a tab, 2 = the panel opposite the active one.
    mode: i64,
    files: Vec<PathBuf>,
    index: usize,
    current: Option<PathBuf>,
    picture: Option<Picture>,
    /// 0 = fit; the scale is `fit * zoom`.
    zoom: f64,
    /// Center of the visible part, in pixels of the rotated picture.
    cx: f64,
    cy: f64,
    rotation: u8,
    view_w: usize,
    view_h: usize,
    /// Drag in progress: pointer position and center when it started.
    drag: Option<(i64, i64, f64, f64)>,
    fullscreen: bool,
}

thread_local! {
    static VIEWER: RefCell<Viewer> = const {
        RefCell::new(Viewer {
            host: std::ptr::null(),
            surface: 0,
            mode: 0,
            files: Vec::new(),
            index: 0,
            current: None,
            picture: None,
            zoom: 1.0,
            cx: 0.0,
            cy: 0.0,
            rotation: 0,
            view_w: 960,
            view_h: 540,
            drag: None,
            fullscreen: false,
        })
    };
}

/// `file:///C:/dir/a%20b.jpg` -> `C:\dir\a b.jpg`.
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

fn is_picture(path: &Path) -> bool {
    let ext = path.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase).unwrap_or_default();
    matches!(ext.as_str(), "jpg" | "jpeg" | "bmp" | "png" | "gif" | "tif" | "tiff" | "webp")
}

/// The pictures of `path`'s folder in name order.
fn siblings(path: &Path) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = path
        .parent()
        .and_then(|dir| std::fs::read_dir(dir).ok())
        .map(|entries| entries.filter_map(Result::ok).map(|e| e.path()).filter(|p| p.is_file() && is_picture(p)).collect())
        .unwrap_or_default();
    files.sort_by_key(|p| p.file_name().map(|n| n.to_string_lossy().to_lowercase()));
    files
}

/// Decodes `path` upright (EXIF orientation applied) as BGRA, shrunk to `MAX_SIDE` at most.
fn decode(path: &Path) -> Option<Picture> {
    let mut decoder = image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.into_decoder().ok()?;
    let orientation = image::ImageDecoder::orientation(&mut decoder).ok();
    let mut picture = image::DynamicImage::from_decoder(decoder).ok()?;
    if let Some(orientation) = orientation {
        picture.apply_orientation(orientation);
    }
    if picture.width().max(picture.height()) > MAX_SIDE {
        picture = picture.resize(MAX_SIDE, MAX_SIDE, image::imageops::FilterType::Triangle);
    }
    let rgba = picture.to_rgba8();
    let (width, height) = (rgba.width() as usize, rgba.height() as usize);
    let mut pixels = rgba.into_raw();
    for px in pixels.chunks_exact_mut(4) {
        px.swap(0, 2);
    }
    Some(Picture { width, height, pixels })
}

impl Viewer {
    /// Size of the picture after the rotation.
    fn rotated_size(&self) -> (f64, f64) {
        match &self.picture {
            Some(p) if self.rotation % 2 == 1 => (p.height as f64, p.width as f64),
            Some(p) => (p.width as f64, p.height as f64),
            None => (1.0, 1.0),
        }
    }

    fn fit_scale(&self) -> f64 {
        let (rw, rh) = self.rotated_size();
        (self.view_w as f64 / rw).min(self.view_h as f64 / rh)
    }

    fn scale(&self) -> f64 {
        self.fit_scale() * self.zoom
    }

    /// Keeps the center where the picture still covers the area (or centered when it is smaller).
    fn clamp_center(&mut self) {
        let (rw, rh) = self.rotated_size();
        let s = self.scale();
        let (half_w, half_h) = (self.view_w as f64 / (2.0 * s), self.view_h as f64 / (2.0 * s));
        self.cx = if rw <= 2.0 * half_w { rw / 2.0 } else { self.cx.clamp(half_w, rw - half_w) };
        self.cy = if rh <= 2.0 * half_h { rh / 2.0 } else { self.cy.clamp(half_h, rh - half_h) };
    }

    fn fit(&mut self) {
        self.zoom = 1.0;
        let (rw, rh) = self.rotated_size();
        self.cx = rw / 2.0;
        self.cy = rh / 2.0;
    }

    /// The visible part of the picture rendered into a BGRA frame of the size of the area.
    fn render(&mut self) -> Vec<u8> {
        self.clamp_center();
        let (w, h) = (self.view_w, self.view_h);
        let mut frame = vec![0u8; w * h * 4];
        let Some(pic) = &self.picture else {
            return frame;
        };
        let s = self.scale();
        let (rw, rh) = self.rotated_size();
        let (pw, ph) = (pic.width as f64, pic.height as f64);
        let bilinear = s < 2.0;
        for y in 0..h {
            let v = self.cy + (y as f64 + 0.5 - h as f64 / 2.0) / s;
            for x in 0..w {
                let u = self.cx + (x as f64 + 0.5 - w as f64 / 2.0) / s;
                let out = &mut frame[(y * w + x) * 4..(y * w + x) * 4 + 4];
                if u < 0.0 || v < 0.0 || u >= rw || v >= rh {
                    out.copy_from_slice(&[16, 16, 16, 255]);
                    continue;
                }
                // The point of the rotated picture in the source picture.
                let (sx, sy) = match self.rotation % 4 {
                    0 => (u, v),
                    1 => (v, ph - u),
                    2 => (pw - u, ph - v),
                    _ => (pw - v, u),
                };
                let sample = |ix: i64, iy: i64| -> [f64; 3] {
                    let ix = ix.clamp(0, pic.width as i64 - 1) as usize;
                    let iy = iy.clamp(0, pic.height as i64 - 1) as usize;
                    let p = &pic.pixels[(iy * pic.width + ix) * 4..];
                    [p[0] as f64, p[1] as f64, p[2] as f64]
                };
                let color = if bilinear {
                    let (fx, fy) = (sx - 0.5, sy - 0.5);
                    let (x0, y0) = (fx.floor(), fy.floor());
                    let (tx, ty) = (fx - x0, fy - y0);
                    let (x0, y0) = (x0 as i64, y0 as i64);
                    let (a, b, c, d) = (sample(x0, y0), sample(x0 + 1, y0), sample(x0, y0 + 1), sample(x0 + 1, y0 + 1));
                    let mut mixed = [0.0; 3];
                    for k in 0..3 {
                        mixed[k] = (a[k] * (1.0 - tx) + b[k] * tx) * (1.0 - ty) + (c[k] * (1.0 - tx) + d[k] * tx) * ty;
                    }
                    mixed
                } else {
                    sample(sx.floor() as i64, sy.floor() as i64)
                };
                out.copy_from_slice(&[color[0] as u8, color[1] as u8, color[2] as u8, 255]);
            }
        }
        frame
    }

    /// Sends the current frame and the text of the tab to the host.
    fn show(&mut self) {
        if self.surface == 0 || self.host.is_null() {
            return;
        }
        let frame = self.render();
        let host = unsafe { &*self.host };
        if let Some(set_frame) = host.surface_set_frame {
            unsafe { set_frame(self.surface, self.view_w as i64, self.view_h as i64, frame.as_ptr(), frame.len() as i64) };
        }
        if let (Some(set_info), Some(path), Some(pic)) = (host.surface_set_info, &self.current, &self.picture) {
            let name = path.file_name().map(|n| n.to_string_lossy().replace('\0', "")).unwrap_or_default();
            let title = CString::new(name).unwrap_or_default();
            let place = if self.mode == 0 && !self.files.is_empty() {
                format!("  {}/{}", self.index + 1, self.files.len())
            } else {
                String::new()
            };
            let status = CString::new(format!(
                "{}x{}  {:.0}%{}",
                pic.width,
                pic.height,
                self.scale() * 100.0,
                place
            ))
            .unwrap_or_default();
            unsafe { set_info(self.surface, title.as_ptr(), status.as_ptr()) };
        }
    }

    /// Loads `path` and starts at fit; false when it does not decode.
    fn load(&mut self, path: &Path) -> bool {
        let Some(picture) = decode(path) else {
            return false;
        };
        self.picture = Some(picture);
        self.current = Some(path.to_path_buf());
        self.rotation = 0;
        self.drag = None;
        self.fit();
        true
    }

    /// Shows the previous (-1) or next (1) picture of the folder, skipping files that do not decode.
    fn step(&mut self, delta: isize) {
        let count = self.files.len() as isize;
        for n in 1..=count {
            let index = (self.index as isize + delta * n).rem_euclid(count) as usize;
            let path = self.files[index].clone();
            if self.load(&path) {
                self.index = index;
                self.show();
                return;
            }
        }
    }

    fn jump(&mut self, index: usize) {
        if let Some(path) = self.files.get(index).cloned() {
            if self.load(&path) {
                self.index = index;
                self.show();
            }
        }
    }

    fn zoom_by(&mut self, factor: f64, anchor: Option<(f64, f64)>) {
        let before = self.scale();
        let (ax, ay) = anchor.unwrap_or((self.view_w as f64 / 2.0, self.view_h as f64 / 2.0));
        // The point of the picture under the anchor stays under it.
        let (u, v) = (self.cx + (ax - self.view_w as f64 / 2.0) / before, self.cy + (ay - self.view_h as f64 / 2.0) / before);
        self.zoom = (self.zoom * factor).clamp(0.05, 64.0);
        let after = self.scale();
        self.cx = u - (ax - self.view_w as f64 / 2.0) / after;
        self.cy = v - (ay - self.view_h as f64 / 2.0) / after;
        self.show();
    }

    fn rotate(&mut self, delta: i8) {
        self.rotation = (self.rotation as i8 + delta).rem_euclid(4) as u8;
        self.fit();
        self.show();
    }
}

/// Runs `f` on the viewer. The host may call back while the plugin is inside one of its own calls
/// (opening a tab publishes panel events, for example); that nested call finds the viewer busy and
/// does nothing.
fn with_viewer<R: Default>(f: impl FnOnce(&mut Viewer) -> R) -> R {
    VIEWER.with(|v| match v.try_borrow_mut() {
        Ok(mut viewer) => f(&mut viewer),
        Err(_) => R::default(),
    })
}

unsafe extern "C" fn on_key(_user: *mut c_void, key: *const c_char) -> i64 {
    let key = CStr::from_ptr(key).to_str().unwrap_or("");
    with_viewer(|v| {
        match key {
            "Right" | "Down" | "Space" | "PageDown" if v.mode == 0 && !v.files.is_empty() => v.step(1),
            "Left" | "Up" | "Backspace" | "PageUp" if v.mode == 0 && !v.files.is_empty() => v.step(-1),
            "Home" if v.mode == 0 => v.jump(0),
            "End" if v.mode == 0 => v.jump(v.files.len().saturating_sub(1)),
            "+" | "=" => v.zoom_by(1.25, None),
            "-" => v.zoom_by(0.8, None),
            "0" => {
                v.fit();
                v.show();
            }
            "1" => {
                v.zoom = 1.0 / v.fit_scale();
                v.show();
            }
            "r" => v.rotate(1),
            "R" | "l" => v.rotate(-1),
            "f" | "F" => {
                v.fullscreen = !v.fullscreen;
                if let Some(set) = (&*v.host).surface_set_fullscreen {
                    set(v.surface, v.fullscreen as i64);
                }
            }
            _ => return 0,
        }
        1
    })
}

unsafe extern "C" fn on_mouse(
    _user: *mut c_void,
    kind: i64,
    x: i64,
    y: i64,
    width: i64,
    height: i64,
    button: i64,
    extra: i64,
    _shift: i64,
) -> i64 {
    with_viewer(|v| match kind {
        5 => {
            // The area changed size: the next frame is rendered for it.
            v.view_w = width.max(16) as usize;
            v.view_h = height.max(16) as usize;
            v.show();
            1
        }
        3 => {
            v.zoom_by(1.25f64.powi(extra.clamp(-5, 5) as i32), Some((x as f64, y as f64)));
            1
        }
        0 if button == 1 => {
            v.drag = Some((x, y, v.cx, v.cy));
            1
        }
        2 => {
            if let Some((sx, sy, cx, cy)) = v.drag {
                let s = v.scale();
                v.cx = cx - (x - sx) as f64 / s;
                v.cy = cy - (y - sy) as f64 / s;
                v.show();
                1
            } else {
                0
            }
        }
        1 => {
            v.drag = None;
            1
        }
        4 if button == 1 => {
            // Fit <-> 100 %.
            if (v.zoom - 1.0).abs() < 1e-6 {
                v.zoom_by(1.0 / v.fit_scale(), Some((x as f64, y as f64)));
            } else {
                v.fit();
                v.show();
            }
            1
        }
        _ => 0,
    })
}

unsafe extern "C" fn on_closed(_user: *mut c_void) {
    with_viewer(|v| {
        v.surface = 0;
        v.mode = 0;
        v.picture = None;
        v.fullscreen = false;
        v.drag = None;
    });
}

/// Opens the surface in `mode` when none is open; true when one is ready.
fn ensure_surface(v: &mut Viewer, mode: i64) -> bool {
    if v.surface != 0 {
        return v.mode == mode;
    }
    let Some(open) = (unsafe { v.host.as_ref() }).and_then(|h| h.surface_open_ex) else {
        return false;
    };
    let handle = unsafe {
        open(
            PLUGIN_ID.as_ptr() as *const c_char,
            b"Picture\0".as_ptr() as *const c_char,
            mode,
            Some(on_key),
            std::ptr::null(),
            Some(on_closed),
            Some(on_mouse),
            null_mut(),
        )
    };
    if handle <= 0 {
        return false;
    }
    v.surface = handle;
    v.mode = mode;
    v.fullscreen = false;
    // Until the host reports the size of the area, a frame of the last size is used.
    true
}

/// The file under the cursor of the active panel, from `panel_info`.
fn panel_cursor_file() -> Option<PathBuf> {
    let call = with_viewer(|v| unsafe { v.host.as_ref() }.and_then(|h| h.panel_info))?;
    let mut buf = vec![0u8; 8192];
    for _ in 0..3 {
        let n = unsafe { call(buf.as_mut_ptr() as *mut c_char, buf.len() as i64) };
        if n < 0 {
            return None;
        }
        if (n as usize) < buf.len() {
            let info: Value = serde_json::from_slice(&buf[..n as usize]).ok()?;
            let side = info["active"].as_str().unwrap_or("left");
            return info[side]["cursor"].as_str().and_then(uri_to_path).filter(|p| is_picture(p));
        }
        buf = vec![0u8; n as usize + 1];
    }
    None
}

/// Panel mode: shows the picture under the panel cursor.
fn follow_panel() {
    let Some(path) = panel_cursor_file() else {
        return;
    };
    with_viewer(|v| {
        if v.surface == 0 || v.mode != 2 || v.current.as_deref() == Some(path.as_path()) {
            return;
        }
        if v.load(&path) {
            v.show();
        }
    });
}

unsafe extern "C" fn on_panel_event(_user: *mut c_void, _topic: *const c_char, _payload: *const c_char) {
    follow_panel();
}

/// Ctrl+Shift+V: the picture of the cursor file in the other panel, following the cursor.
unsafe extern "C" fn toggle_panel(_user: *mut c_void) {
    let close = with_viewer(|v| {
        if v.surface != 0 {
            let surface = v.surface;
            if let Some(close) = (v.host.as_ref()).and_then(|h| h.surface_close) {
                close(surface);
            }
            v.surface = 0;
            v.mode = 0;
            v.picture = None;
            v.fullscreen = false;
            v.drag = None;
            true
        } else {
            false
        }
    });
    if close {
        return;
    }
    let opened = with_viewer(|v| ensure_surface(v, 2));
    if !opened {
        say("Switch to the file panels first.", 1);
        return;
    }
    follow_panel();
}

unsafe extern "C" fn rotate_panel(_user: *mut c_void) {
    with_viewer(|v| {
        if v.surface != 0 {
            v.rotate(1);
        }
    });
}

fn say(text: &str, kind: i64) {
    let show = with_viewer(|v| unsafe { v.host.as_ref() }.and_then(|h| h.show_message));
    if let (Some(show), Ok(c)) = (show, CString::new(text)) {
        unsafe { show(c.as_ptr(), kind) };
    }
}

/// Handled (1) when the picture is on screen; 0 lets the next provider try.
unsafe extern "C" fn on_document(
    _user: *mut c_void,
    uri: *const c_char,
    _mode: *const c_char,
    _redirect: *mut c_char,
    _redirect_cap: i64,
) -> i64 {
    let Some(path) = CStr::from_ptr(uri).to_str().ok().and_then(uri_to_path) else {
        return 0;
    };
    if !is_picture(&path) {
        return 0;
    }
    with_viewer(|v| {
        // A picture shown in the panel is replaced by the tab.
        if v.surface != 0 && v.mode != 0 {
            let surface = v.surface;
            if let Some(close) = (v.host.as_ref()).and_then(|h| h.surface_close) {
                close(surface);
            }
            v.surface = 0;
            v.mode = 0;
        }
        if !ensure_surface(v, 0) {
            return 0;
        }
        let files = siblings(&path);
        let index = files.iter().position(|p| *p == path).unwrap_or(0);
        if !v.load(&path) {
            return 0;
        }
        v.files = files;
        v.index = index;
        v.show();
        1
    })
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
    if api.abi_version < 2 || api.surface_open_ex.is_none() || api.surface_set_frame.is_none() {
        return -1;
    }
    let (Some(register), Some(register_command), Some(bind), Some(subscribe)) =
        (api.register_document_provider, api.register_command, api.register_key_binding, api.subscribe)
    else {
        return -1;
    };
    VIEWER.with(|v| v.borrow_mut().host = host);
    let id = PLUGIN_ID.as_ptr() as *const c_char;
    register(id, EXTENSIONS.as_ptr() as *const c_char, MODE_VIEW, on_document, null_mut(), 100);
    let commands: [(&[u8], CommandCb, &[u8]); 2] = [
        (b"img.panel\0", toggle_panel, b"Ctrl+Shift+V\0"),
        (b"img.rotate\0", rotate_panel, b"Ctrl+Shift+Y\0"),
    ];
    for (name, run, chord) in commands {
        register_command(id, name.as_ptr() as *const c_char, run, null_mut());
        bind(id, name.as_ptr() as *const c_char, chord.as_ptr() as *const c_char);
    }
    subscribe(id, b"panel.cursor\0".as_ptr() as *const c_char, on_panel_event, null_mut());
    subscribe(id, b"panel.dir\0".as_ptr() as *const c_char, on_panel_event, null_mut());
    0
}

/// The host closes the plugin's surface when the plugin is unloaded.
#[no_mangle]
pub extern "C" fn mtn_plugin_shutdown() {
    VIEWER.with(|v| {
        let mut v = v.borrow_mut();
        v.host = std::ptr::null();
        v.surface = 0;
        v.picture = None;
        v.files.clear();
    });
}
