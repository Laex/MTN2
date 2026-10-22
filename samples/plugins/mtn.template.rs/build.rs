// A module without WASI gets 1 MiB of linear memory from the host (see
// "memoryMib" in docs/PLUGIN_DEVELOPMENT.md). Rust reserves 1 MiB for the
// stack by default, which does not fit; 64 KiB is plenty for this plugin.
fn main() {
    println!("cargo:rustc-link-arg=-zstack-size=65536");
}
