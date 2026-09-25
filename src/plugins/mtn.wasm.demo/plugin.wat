;; MTN2 stage-30 demo plugin: read-only fake VFS on wasmdemo://
;; Compiled at load time by Wasmtime wat2wasm. Guest never sees host pointers —
;; list/exists/read copy UTF-8 through linear memory. No WASI imports.
;; Status is a single i64; byte size / isDir is exported as mtn_last_size.

(module
  (import "mtn_host" "register_vfs_scheme"
    (func $reg_vfs (param i32 i32 i32) (result i32)))
  (import "mtn_host" "register_panel_plugin"
    (func $reg_panel (param i32 i32 i32) (result i32)))

  (memory (export "memory") 1)
  (global $last (mut i64) (i64.const 0))

  (data (i32.const 16) "wasmdemo")
  (data (i32.const 32) "[{\22name\22:\22hello.txt\22,\22ext\22:\22txt\22,\22size\22:11,\22isDir\22:false},{\22name\22:\22docs\22,\22ext\22:\22\22,\22size\22:0,\22isDir\22:true}]")
  (data (i32.const 160) "hello, wasm")
  (data (i32.const 176) "wasmdemo://")

  (func $memcpy (param $dst i32) (param $src i32) (param $n i32)
    (block $done
      (loop $copy
        (br_if $done (i32.eqz (local.get $n)))
        (i32.store8 (local.get $dst) (i32.load8_u (local.get $src)))
        (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
        (local.set $src (i32.add (local.get $src) (i32.const 1)))
        (local.set $n (i32.sub (local.get $n) (i32.const 1)))
        (br $copy))))

  (func $prefix_ok (param $uri i32) (param $ulen i32) (result i32)
    (local $i i32)
    (if (i32.lt_u (local.get $ulen) (i32.const 11))
      (then (return (i32.const 0))))
    (local.set $i (i32.const 0))
    (block $done
      (loop $cmp
        (br_if $done (i32.eq (local.get $i) (i32.const 11)))
        (if (i32.ne
              (i32.load8_u (i32.add (local.get $uri) (local.get $i)))
              (i32.load8_u (i32.add (i32.const 176) (local.get $i))))
          (then (return (i32.const 0))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $cmp)))
    (i32.const 1))

  (func (export "mtn_plugin_get_abi_version") (result i64)
    (i64.const 1))

  (func (export "mtn_plugin_init") (result i32)
    (drop (call $reg_vfs (i32.const 16) (i32.const 8) (i32.const 25)))
    (drop (call $reg_panel (i32.const 16) (i32.const 8) (i32.const 25)))
    (i32.const 0))

  (func (export "mtn_plugin_shutdown"))

  (func (export "mtn_last_size") (result i64)
    (global.get $last))

  (func (export "mtn_vfs_list")
    (param $uri i32) (param $ulen i32) (param $out i32) (param $cap i32)
    (result i64)
    (if (i32.eqz (call $prefix_ok (local.get $uri) (local.get $ulen)))
      (then
        (global.set $last (i64.const 0))
        (return (i64.const 6))))
    (if (i32.lt_u (local.get $cap) (i32.const 105))
      (then
        (global.set $last (i64.const 105))
        (return (i64.const 7))))
    (call $memcpy (local.get $out) (i32.const 32) (i32.const 105))
    (global.set $last (i64.const 105))
    (i64.const 0))

  (func (export "mtn_vfs_exists")
    (param $uri i32) (param $ulen i32)
    (result i64)
    (if (i32.eqz (call $prefix_ok (local.get $uri) (local.get $ulen)))
      (then
        (global.set $last (i64.const 0))
        (return (i64.const 6))))
    (global.set $last (i64.extend_i32_u (i32.le_u (local.get $ulen) (i32.const 12))))
    (i64.const 0))

  (func (export "mtn_vfs_read_text")
    (param $uri i32) (param $ulen i32) (param $out i32) (param $cap i32)
    (result i64)
    (if (i32.eqz (call $prefix_ok (local.get $uri) (local.get $ulen)))
      (then
        (global.set $last (i64.const 0))
        (return (i64.const 6))))
    (if (i32.lt_u (local.get $cap) (i32.const 11))
      (then
        (global.set $last (i64.const 11))
        (return (i64.const 7))))
    (call $memcpy (local.get $out) (i32.const 160) (i32.const 11))
    (global.set $last (i64.const 11))
    (i64.const 0))
)
