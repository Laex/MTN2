# Образцы плагинов MTN2

Шесть небольших плагинов на разных языках: каждый показывает свою часть возможностей плагинной системы. Справочник – [docs/PLUGIN_DEVELOPMENT.md](../docs/PLUGIN_DEVELOPMENT.md); C-заголовок ABI – [include/mtn_plugin.h](include/mtn_plugin.h).

| Плагин | Язык | Что делает |
|---|---|---|
| `mtn.demo.cpp` | C++ (MSVC) | Считает Copy / Move / Delete, показывает счётчик в статусе; Ctrl+Alt+F10 – диалог со счётчиками |
| `mtn.demo.rs` | Rust | F3 на `.csv` показывает выровненную таблицу |
| `mtn.demo.go` | Go (cgo) | F3 на `.json` показывает форматированный JSON; Ctrl+Alt+F9 – сведения о среде Go |
| `mtn.demo.go.wasm` | Go (WASM, WASI) | Блокирует Shift+Del и Wipe, объясняя это в диалоге |
| `mtn.demo.pas` | Delphi | Ctrl+Alt+F8 – быстрая заметка в `mtn2-notes.txt` |
| `mtn.demo.wat` | WAT | Ctrl+Alt+F7 – счётчик в статусе |

## Сборка

```powershell
./samples/build-samples.ps1            # собрать всё, что позволяет инструментарий
./samples/build-samples.ps1 -Install   # и поставить в bin\plugins
./samples/build-samples.ps1 -Only mtn.demo.go,mtn.demo.rs
```

Образец, для которого не найден компилятор, пропускается. Нужны:

- C++: Visual Studio с компонентом C++ (`vcvars64.bat`);
- Rust: `cargo` и цель `x86_64-pc-windows-msvc`;
- Go: `go`; для `mtn.demo.go` ещё 64-разрядный gcc для cgo (WinLibs или MSYS2; `gcc` из Free Pascal 32-разрядный и не подходит);
- Delphi: RAD Studio (`rsvars.bat`);
- WAT: ничего, хост собирает текст при загрузке.

Собранное лежит в `samples\.build\<id>` (в git не попадает). После установки плагины загружаются при запуске MTN2 и видны в **Параметры → Плагины...**; там же их можно выключить.
