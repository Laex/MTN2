# Counter (Rust, WASM template)

A starting point for your own WASM plugin in Rust.

## Use

**Ctrl+Alt+F6** (*Count* on the function bar) adds one to a counter. The status line shows **Count: N**. The counter starts at zero each time MTN2 starts.

## For authors

Source: `samples/plugins/mtn.template.rs/src/lib.rs`. A `no_std` module for `wasm32-unknown-unknown`; it needs no WASI. It exports `mtn_plugin_get_abi_version`, `mtn_plugin_init`, `mtn_plugin_shutdown` and one command, and imports `register_command`, `register_key_binding`, `set_command_caption` and `set_status_segment` from the `mtn_host` module.

To start your own plugin, copy the folder, change `id` in `plugin.json`, the command names in `lib.rs` and the crate name in `Cargo.toml`. Build and install:

```
rustup target add wasm32-unknown-unknown
./samples/build-samples.ps1 -Only mtn.template.rs -Install
```

See `docs/PLUGIN_DEVELOPMENT.md` for the host functions.
