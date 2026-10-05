;; Demo plugin in WebAssembly text: a counter that lives in the plugin.
;; Ctrl+Alt+F7 ("Count" in the function bar) adds one and shows the number in
;; the status line.
;;
;; Shows: the smallest useful WASM plugin - host imports with (ptr, len)
;; strings in linear memory, a plugin command, a bar caption, and a status
;; segment. The host assembles this file when it loads the plugin. No WASI.

(module
  (import "mtn_host" "register_command"
    (func $register_command (param i32 i32 i32 i32) (result i32)))
  (import "mtn_host" "register_key_binding"
    (func $bind (param i32 i32 i32 i32) (result i32)))
  (import "mtn_host" "set_command_caption"
    (func $set_caption (param i32 i32 i32 i32) (result i32)))
  (import "mtn_host" "set_status_segment"
    (func $set_status (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; 16: command id, 48: export name, 64: caption, 80: segment id,
  ;; 96: status text "Count: " followed by up to 10 digits (built at runtime),
  ;; 128: the key chord.
  (data (i32.const 16) "demo.wat.count")
  (data (i32.const 48) "on_count")
  (data (i32.const 64) "Count")
  (data (i32.const 80) "count")
  (data (i32.const 96) "Count: ")
  (data (i32.const 128) "Ctrl+Alt+F7")

  (global $count (mut i32) (i32.const 0))

  ;; Writes the decimal digits of $n after "Count: " (offset 103) and returns
  ;; the length of the whole text.
  (func $format (param $n i32) (result i32)
    (local $digits i32) (local $v i32) (local $pos i32)
    (local.set $v (local.get $n))
    (local.set $digits (i32.const 1))
    (block $done
      (loop $count_digits
        (br_if $done (i32.lt_u (local.get $v) (i32.const 10)))
        (local.set $v (i32.div_u (local.get $v) (i32.const 10)))
        (local.set $digits (i32.add (local.get $digits) (i32.const 1)))
        (br $count_digits)))
    (local.set $pos (i32.add (i32.const 103) (local.get $digits)))
    (local.set $v (local.get $n))
    (loop $write
      (local.set $pos (i32.sub (local.get $pos) (i32.const 1)))
      (i32.store8 (local.get $pos)
        (i32.add (i32.const 48) (i32.rem_u (local.get $v) (i32.const 10))))
      (local.set $v (i32.div_u (local.get $v) (i32.const 10)))
      (br_if $write (i32.gt_u (local.get $pos) (i32.const 103))))
    (i32.add (i32.const 7) (local.get $digits)))

  (func $show
    (drop (call $set_status (i32.const 80) (i32.const 5) (i32.const 96)
      (call $format (global.get $count)))))

  (func (export "mtn_plugin_get_abi_version") (result i64) (i64.const 2))

  (func (export "mtn_plugin_init") (result i32)
    (drop (call $register_command (i32.const 16) (i32.const 14) (i32.const 48) (i32.const 8)))
    (drop (call $bind (i32.const 16) (i32.const 14) (i32.const 128) (i32.const 11)))
    (drop (call $set_caption (i32.const 16) (i32.const 14) (i32.const 64) (i32.const 5)))
    (call $show)
    (i32.const 0))

  (func (export "mtn_plugin_shutdown"))

  (func (export "on_count")
    (global.set $count (i32.add (global.get $count) (i32.const 1)))
    (call $show)))
