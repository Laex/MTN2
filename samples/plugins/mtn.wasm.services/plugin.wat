;; A WebAssembly plugin that provides a service and calls it (docs/PLUGIN_SERVICES.md, 6.1).
;; The menu item Commands -> "Sample: call a WASM service" asks the service sample.hello
;; and shows its answer.
;;
;; A real provider copies the "id" of the request into its response; this sample always
;; uses id 1 for both sides to stay short.
(module
  (import "mtn_host" "service_register"
    (func $register (param i32 i32 i32 i32 i32 i32 i32 i32) (result i32)))
  (import "mtn_host" "service_reply" (func $reply (param i32 i32 i32) (result i32)))
  (import "mtn_host" "service_call"
    (func $call (param i32 i32 i32 i32 i32 i32 i32 i32 i32) (result i32)))
  (import "mtn_host" "service_message" (func $message (param i32 i32 i32) (result i32)))
  (import "mtn_host" "register_menu_item"
    (func $menu (param i32 i32 i32 i32 i32 i32 i32 i32 i32) (result i32)))
  (import "mtn_host" "show_message" (func $show (param i32 i32 i32) (result i32)))

  (memory (export "memory") 1)
  (data (i32.const 16) "Commands")
  (data (i32.const 32) "sample.hello")
  (data (i32.const 48) "on_call")
  (data (i32.const 64) "ask")
  (data (i32.const 72) "on_msg")
  (data (i32.const 88) "wasmsvc.ask")
  (data (i32.const 100) "Sample: call a WASM service")
  (data (i32.const 160) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22method\22:\22sample.hello\22}")
  (data (i32.const 256) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:{\22text\22:\22Hello from a WASM service\22}}")

  (func (export "mtn_plugin_get_abi_version") (result i64) (i64.const 2))

  (func (export "mtn_plugin_init") (result i32)
    ;; the service: name, version 1, no description, export on_call, default priority
    (if (i32.ne
          (call $register (i32.const 32) (i32.const 12) (i32.const 1) (i32.const 0)
            (i32.const 0) (i32.const 48) (i32.const 7) (i32.const 0))
          (i32.const 0))
      (then (return (i32.const 1))))
    (drop (call $menu (i32.const 16) (i32.const 8) (i32.const 88) (i32.const 11)
      (i32.const 100) (i32.const 27) (i32.const 64) (i32.const 3) (i32.const 0)))
    (i32.const 0))

  (func (export "mtn_plugin_shutdown"))

  ;; The host hands a request over as (call, handle, length); service_message copies its text.
  (func (export "on_call") (param $call i32) (param $handle i32) (param $len i32)
    (drop (call $message (local.get $handle) (i32.const 512) (i32.const 512)))
    (drop (call $reply (local.get $call) (i32.const 256) (i32.const 70))))

  ;; The menu item: ask the service and let on_msg show the answer.
  (func (export "ask")
    (drop (call $call (i32.const 0) (i32.const 0) (i32.const 32) (i32.const 12)
      (i32.const 160) (i32.const 48) (i32.const 5000) (i32.const 72) (i32.const 6))))

  ;; The response (or a notification) of the call arrives as (job, handle, length).
  (func (export "on_msg") (param $job i32) (param $handle i32) (param $len i32)
    (local $n i32)
    (local.set $n (call $message (local.get $handle) (i32.const 1024) (i32.const 512)))
    (if (i32.gt_s (local.get $n) (i32.const 0))
      (then (drop (call $show (i32.const 1024) (local.get $n) (i32.const 0)))))))
