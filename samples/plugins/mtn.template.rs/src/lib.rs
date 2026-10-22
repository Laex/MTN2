// Template for a WASM plugin in Rust: a counter that lives in the plugin.
// Ctrl+Alt+F6 ("Count" in the function bar) adds one and shows the number in
// the status line.
//
// Shows: the minimum every WASM plugin needs (ABI version, init, shutdown),
// host imports that take (ptr, len) strings in linear memory, a plugin
// command exported by name, a key chord, a bar caption and a status segment.
// The module needs no WASI: "wasi" is left out of plugin.json. build.rs
// shrinks the stack so the module fits the 1 MiB memory limit of such a plugin.
//
// To start your own plugin: copy this folder, change "id" in plugin.json and
// the names below, and replace `on_count` with your command.
//
// Build: cargo build --release --target wasm32-unknown-unknown
// Install: copy target/wasm32-unknown-unknown/release/mtn_template_rs.wasm
// as plugin.wasm, with plugin.json and resource/, to plugins/<id>/.
#![no_std]

use core::fmt::Write;

#[link(wasm_import_module = "mtn_host")]
extern "C" {
    fn register_command(id: *const u8, id_len: usize, export: *const u8, export_len: usize) -> i32;
    fn register_key_binding(id: *const u8, id_len: usize, combo: *const u8, combo_len: usize) -> i32;
    fn set_command_caption(id: *const u8, id_len: usize, text: *const u8, text_len: usize) -> i32;
    fn set_status_segment(id: *const u8, id_len: usize, text: *const u8, text_len: usize) -> i32;
}

const COMMAND_ID: &str = "template.rs.count";
const EXPORT_NAME: &str = "on_count";
const SEGMENT_ID: &str = "count";

static mut COUNT: u32 = 0;

/// A fixed buffer for the status text; the module has no allocator.
struct Text {
    buf: [u8; 32],
    len: usize,
}

impl Write for Text {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        let end = self.len + s.len();
        if end > self.buf.len() {
            return Err(core::fmt::Error);
        }
        self.buf[self.len..end].copy_from_slice(s.as_bytes());
        self.len = end;
        Ok(())
    }
}

fn show(count: u32) {
    let mut text = Text { buf: [0; 32], len: 0 };
    let _ = write!(text, "Count: {}", count);
    unsafe {
        set_status_segment(SEGMENT_ID.as_ptr(), SEGMENT_ID.len(), text.buf.as_ptr(), text.len);
    }
}

#[no_mangle]
pub extern "C" fn mtn_plugin_get_abi_version() -> i64 {
    2
}

#[no_mangle]
pub extern "C" fn mtn_plugin_init() -> i32 {
    let combo = "Ctrl+Alt+F6";
    let caption = "Count";
    unsafe {
        if register_command(COMMAND_ID.as_ptr(), COMMAND_ID.len(), EXPORT_NAME.as_ptr(), EXPORT_NAME.len()) != 0 {
            return -1;
        }
        register_key_binding(COMMAND_ID.as_ptr(), COMMAND_ID.len(), combo.as_ptr(), combo.len());
        set_command_caption(COMMAND_ID.as_ptr(), COMMAND_ID.len(), caption.as_ptr(), caption.len());
    }
    show(0);
    0
}

#[no_mangle]
pub extern "C" fn mtn_plugin_shutdown() {}

#[no_mangle]
pub extern "C" fn on_count() {
    let count = unsafe {
        COUNT += 1;
        COUNT
    };
    show(count);
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
