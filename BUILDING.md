# Сборка и CI

## Локальная сборка

Требуется RAD Studio 13 (`Studio\37.0`), Windows x64. Опционально — Rust (`cargo`) для плагина `mtn.ws`.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # -> bin\MTN2.exe + bin\plugins\
./src/tools/run-panel-smoke.ps1                   # регрессия Test*.dpr (dcc64)
./src/tools/package-release.ps1 -Version v0.3.0   # -> dist\MTN2-v0.3.0-win64.zip
```

`wasmtime.dll` скачивается `src/tools/fetch-wasmtime.ps1`; `7z.dll` (x64) берётся из установленного 7-Zip
или из `MTN2_7Z_DLL` и в релизный архив не входит.

## CI/CD (GitHub Actions)

| Workflow | Где | Что |
|---|---|---|
| `ci.yml` → `checks` | GitHub-hosted (ubuntu) | gitleaks, валидность JSON-ресурсов |
| `ci.yml` → `wasm-plugin` | GitHub-hosted (ubuntu) | `cargo build` плагина `mtn.ws` под `wasm32` |
| `ci.yml` → `delphi` | self-hosted `delphi` | `build.ps1` + `run-panel-smoke.ps1` + zip-артефакт |
| `release.yml` | self-hosted `delphi` | по тегу `v*`: сборка, тесты, GitHub Release с zip |

RAD Studio коммерческая и на GitHub-hosted раннерах отсутствует, поэтому Delphi-часть идёт на своей машине.

### Подключение self-hosted раннера

1. GitHub → *Settings → Actions → Runners → New self-hosted runner* (Windows x64), выполнить показанные команды
   на машине с RAD Studio. При `config.cmd` добавить метку: `--labels delphi`.
2. Запускать раннер **интерактивно** (`run.cmd`, автозапуск при входе), а не как службу: часть тестов (ConPTY,
   буфер обмена, FMX) требует пользовательского сеанса.
3. Нужны PowerShell 7 (`pwsh`), Git, опционально Rust с `wasm32-unknown-unknown`.
4. *Settings → Secrets and variables → Actions → Variables*: `DELPHI_RUNNER = true` — включает job `delphi`
   (без неё CI не будет висеть в очереди в ожидании раннера).
5. *Settings → Actions → General → Fork pull request workflows*: «Require approval for all outside collaborators».
   Job `delphi` и так не запускается для PR из форков.

### Релиз

```powershell
git tag v0.3.0
git push origin v0.3.0
```
