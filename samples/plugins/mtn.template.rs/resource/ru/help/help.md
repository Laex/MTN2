# Счётчик (шаблон WASM на Rust)

Заготовка для собственного WASM-плагина на Rust.

## Как пользоваться

**Ctrl+Alt+F6** (*Count* в строке клавиш) прибавляет единицу к счётчику. В строке состояния показано **Count: N**. Счётчик начинается с нуля при каждом запуске MTN2.

## Для авторов

Исходник: `samples/plugins/mtn.template.rs/src/lib.rs`. Модуль `no_std` для `wasm32-unknown-unknown`, WASI не нужен. Он экспортирует `mtn_plugin_get_abi_version`, `mtn_plugin_init`, `mtn_plugin_shutdown` и одну команду, а из модуля `mtn_host` импортирует `register_command`, `register_key_binding`, `set_command_caption` и `set_status_segment`.

Чтобы начать свой плагин, скопируйте каталог и поменяйте `id` в `plugin.json`, имена команд в `lib.rs` и имя крейта в `Cargo.toml`. Сборка и установка:

```
rustup target add wasm32-unknown-unknown
./samples/build-samples.ps1 -Only mtn.template.rs -Install
```

Функции хоста описаны в `docs/PLUGIN_DEVELOPMENT.md`.
