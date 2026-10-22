# Образцы плагинов MTN2

Шесть небольших плагинов на разных языках: каждый показывает свою часть возможностей плагинной системы. Справочник – [docs/PLUGIN_DEVELOPMENT.md](../docs/PLUGIN_DEVELOPMENT.md); C-заголовок ABI – [include/mtn_plugin.h](include/mtn_plugin.h).

| Плагин | Язык | Что делает |
|---|---|---|
| `mtn.demo.cpp` | C++ (MSVC, g++) | Считает Copy / Move / Delete, показывает счётчик в статусе; Ctrl+Alt+F10 – диалог со счётчиками |
| `mtn.demo.video` | C++ (MSVC) | F3 на видеофайле проигрывает его во вкладке просмотра (Media Foundation, звук через waveOut) |
| `mtn.demo.img` | Rust | F3 на картинке (JPEG, PNG, BMP, GIF, TIFF, WebP) показывает её во вкладке просмотра: масштаб колесом, перетаскивание, поворот, полный экран; стрелки листают папку; Ctrl+Shift+V – показ в соседней панели |
| `mtn.demo.highlight` | Rust | Подсветка JSON, INI и подобных файлов в просмотрщике и редакторе |
| `mtn.demo.nativeview` | C++ (MSVC) | Ctrl+Shift+G – вкладка с окном самого плагина (анимация GDI) |
| `mtn.demo.texttools` | C++ (MSVC, g++) | Инструменты редактора: регистр, сортировка и удаление повторов строк, «прибрать при сохранении» (перехват `EditorSave`) |
| `mtn.demo.panelkit` | Rust | Копирование путей выбранных файлов в буфер обмена, показ папки в другой панели, выбор файлов с тем же расширением (Ctrl+Shift+X), подсчёт размера папки в фоне (Ctrl+Shift+K), чтение файла под курсором через хост (Ctrl+Shift+L; нужно право `vfs.read`), уведомление о сохранении файла |
| `mtn.demo.wc` | Go (WASM) | Ctrl+Shift+E считает строки, слова и символы выделения или документа |
| `mtn.demo.rs` | Rust | F3 на `.csv` показывает выровненную таблицу |
| `mtn.template.rs` | Rust (WASM) | Заготовка для своего плагина: счётчик в строке состояния, Ctrl+Alt+F6; без WASI, `no_std` |
| `mtn.demo.go` | Go (cgo) | F3 на `.json` показывает форматированный JSON; Ctrl+Alt+F9 – сведения о среде Go |
| `mtn.demo.go.wasm` | Go (WASM, WASI) | Блокирует Shift+Del и Wipe, объясняя это в диалоге |
| `mtn.demo.pas` | Delphi | Ctrl+Alt+F8 – быстрая заметка в `mtn2-notes.txt` |
| `mtn.demo.wat` | WAT | Ctrl+Alt+F7 – счётчик в статусе |
| `mtn.wasm.demo` | WAT | Папка `wasmdemo://` только для чтения с одним текстовым файлом; образец гостевого ABI виртуальной файловой системы |

## Сборка

```powershell
./samples/build-samples.ps1            # собрать всё, что позволяет инструментарий
./samples/build-samples.ps1 -Install   # и поставить в bin\win64\plugins
./samples/build-samples.ps1 -Only mtn.demo.go,mtn.demo.rs
```

Образец, для которого не найден компилятор, пропускается. Нужны:

- C++: Visual Studio с компонентом C++ (`vcvars64.bat`);
- Rust: `cargo` и цель `x86_64-pc-windows-msvc`;
- Rust-шаблон WASM: `cargo` и цель `wasm32-unknown-unknown` (`rustup target add wasm32-unknown-unknown`);
- Go: `go`; для `mtn.demo.go` ещё 64-разрядный gcc для cgo (WinLibs или MSYS2; `gcc` из Free Pascal 32-разрядный и не подходит);
- Delphi: RAD Studio (`rsvars.bat`);
- WAT: ничего, хост собирает текст при загрузке.

Собранное лежит в `samples\.build\<id>` (в git не попадает). После установки плагины загружаются при запуске MTN2 и видны в **Параметры → Плагины...**; там же их можно выключить.

### Сборка под Linux

```bash
./samples/build-samples.sh                              # собрать всё, что позволяет инструментарий
./samples/build-samples.sh --install bin/linux64/plugins
./samples/build-samples.sh --only mtn.demo.cpp,mtn.demo.go.wasm
```

Скрипт делает то же, что `build-samples.ps1`, и кладёт результат в `samples/.build-linux/<id>` (в git не попадает); образец без инструментов пропускается. Нужны: `g++` для `mtn.demo.cpp` и `mtn.demo.texttools`, `cargo` для образцов на Rust, `go` для образцов на Go (для `mtn.demo.go` ещё `gcc`). Образцы на WAT собирать не нужно, а собранный `.wasm` (Go) не зависит от системы и работает и в Windows, и в Linux. Нативный плагин на Linux – это `.so` с тем же ABI и тем же манифестом, что и `.dll`. Скрипт находит `cargo` и `go`, поставленные для пользователя (`~/.cargo/bin`, `~/.local/go/bin`). Образцы, которые разбирают URI файла (`mtn.demo.rs`, `mtn.demo.img`, `mtn.demo.go`, `mtn.demo.panelkit`), понимают и `file:///C:/dir/a.csv`, и `file:///home/user/a.csv`.

Не собираются под Linux `mtn.demo.video` (Media Foundation), `mtn.demo.nativeview` (окно самого плагина) и `mtn.demo.pas` (собирается `dcclinux64`, как сама программа). Вкладка с картинкой, которую открывает плагин (`mtn.demo.img`), работает в `mtn2-sdl`, в том числе с мышью; в `mtn2-tui` её нет.

