# Building and CI

**English** | [Русский](BUILDING.ru.md)

## Local build

You need RAD Studio 13 (`Studio\37.0`) and Windows x64. Optional: Rust (`cargo`) for the `mtn.ws` plugin.

A build without `-Config Release` (Debug by default) also builds the samples from `samples\plugins` for which a toolchain was found and installs them into `bin\win64\plugins`; `-NoSamples` turns this off. A Release build leaves the samples alone.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # -> bin\win64\MTN2.exe + bin\win64\plugins\
./src/tests/run-tests.ps1                         # regression tests (DUnitX, dcc64)
./src/tools/package-release.ps1 -Version v0.3.0   # -> dist\MTN2-v0.3.0-win64.zip + -win64-portable.zip
./src/tools/check-release.ps1 -Version v0.3.0     # unpack both and run MTN2.exe --self-check
```

The two archives differ only by the `portable.dat` file (settings next to the exe instead of `%APPDATA%\MTN2`).
The self-updater takes exactly `MTN2-<tag>-win64.zip` and, when unpacked over a portable copy, leaves `portable.dat`
alone. `--self-check` verifies the embedded resources, the language packs `resource\<language>\` (version, strings,
help), `sk4d.dll` and the plugin manifests, prints a report to stdout and exits with code 0/1 without opening a window.

`-Version 0.3.2` (or `v0.3.2`) stamps the number into the exe version resource: the window title shows it and the
self-updater compares against it. Without the parameter the version comes from `MTN2.dproj`; a release build passes the tag.

`wasmtime.dll` is downloaded by `src/tools/fetch-wasmtime.ps1` (a copy is kept in the cache folder: `MTN2_CACHE`, or the
runner's tool cache on GitHub Actions; the Rust plugin's `target` folder lives there too, so a clean `checkout` does not
erase them). `7z.dll` (x64) comes from the installed 7-Zip or from `MTN2_7Z_DLL`, lives in `bin\win64\plugins\mtn.7z\`
and ships in the packages together with the licence text (`src/plugins/mtn.7z/7-Zip-license.txt` ->
`plugins\mtn.7z\license.txt`) and `THIRD-PARTY.md`; `package-release.ps1 -Require7z` stops packaging if it is missing.

`pdfium.dll` (Windows) and `libpdfium.so` (Linux) for the `mtn.pdf` plugin are downloaded by
`src/tools/fetch-pdfium.ps1 [-Linux]` from the pdfium-binaries project into `src/tools/pdfium`; `build.ps1` and
`build-linux.ps1` call it themselves and put the library into the plugin folder. Without it the plugin still builds,
but PDFs open in the document plugin's text viewer.

In the IDE both projects (MTN2 and DialogDesigner) open as the group `src/tools/Group.groupproj`. The resources
`src/MTN2.dres` (dialogs, keys, menus, themes) are not stored in git: `build.ps1` builds them (and `run-tests.ps1` for
the tests). Run `build.ps1` once before the first build from the IDE.

Run: `bin\win64\MTN2.exe [--no-skia] [--fps] [path]`. The switches (`--no-skia`, `--fps` – frame count and frame time in
the title, a path opens in a new tab, and the internal `--wait-pid` and `--self-check`) are described in
[ARCHITECTURE.md](ARCHITECTURE.md) §10.

## Building for Linux

The terminal version `mtn2-tui` is built with the Delphi compiler for Linux64 (`dcclinux64`) straight from Windows,
without the IDE and PAServer. You need RAD Studio 13 and the Linux SDK files (sysroot), which the IDE's SDK Manager
downloads (*Tools -> Options -> Deployment -> SDK Manager*, Ubuntu 22.04 or 24.04) into
`Documents\Embarcadero\Studio.0\PlatformSDKs\Linux64.sdk`. Run and check in WSL.

```powershell
./src/build-linux.ps1                 # -> bin\linux64\mtn2-tui + plugins\<id>\lib*.so
./src/build-linux.ps1 -Sdl            # also bin\linux64\mtn2-sdl (SDL2 window, see LINUX.md)
./src/build-linux.ps1 -NoPlugins      # the program only, without plugins (.so) and libwasmtime.so
./src/build-linux.ps1 -Dump           # build and render one screen as text in WSL
./src/tests/run-tests-linux.ps1       # the same test groups built for Linux64 and run in WSL
```

Platform code lives in pairs of units with the same name: `src/Platform/Windows` and `src/Platform/Posix`; the project
picks one folder through the unit search path, so `{$IFDEF}` is not needed in shared code. Shared code is `src/Core`,
the shared host controller is `src/Hosts/Common`, the terminal host is `src/Hosts/Ansi`, the SDL2 window host is
`src/Hosts/Sdl`, the windowed (FireMonkey) one is `src/Hosts/Fmx` and `src/Forms`.
`src/tools/check-platform.ps1` fails if a unit in `Core` or `Forms` calls a platform API directly (the exceptions list
is `platform-baseline.txt`; it may only shrink).

The resources of the Linux programs (`MTN2Tui.dres`) are built by `src/tools/make-linux-resources.ps1` from
`MTN2Resource.rc`, which adds `RESOURCE_INDEX` - a list of names, because the Linux runtime cannot enumerate resources.

Fixtures that test Windows-only code are listed in `src/tests/linux-excluded.txt`; single tests are marked
`[Category('WindowsOnly')]`. Tests that need POSIX (`TestPosixPaths`, `TestPosixPty`, `TestPosixShellProfiles`) finish
immediately on Windows through `Assert.Pass`.

## Tests

The tests use [DUnitX](https://github.com/VSoftTechnologies/DUnitX) (part of RAD Studio). Each
`src/tests/<group>/TestXxx.pas` is a unit with a `[TestFixture] TTestXxx` fixture whose `[Test]` methods check through
`Assert.*`. A group's fixtures are assembled by a console runner `<Group>Tests.dpr` (for example `vfs/VfsTests.dpr`);
the shared `Main` is in `src/tests/common/uTestRunner.pas`. Groups:

| Group | What it covers |
|---|---|
| `console` | ANSI parser, console buffer, ConPTY, cmd/PowerShell sessions, shell profiles |
| `shell` | tests that start real shells through ConPTY and wait for their output (split from `console` to run in parallel) |
| `panels` | the dual-panel window: input, mouse, tabs, menus, drawing, status, panel model |
| `editor` | editor, viewers, Quick View, Markdown |
| `dialogs` | JSON dialogs, rendering, input history, individual dialogs |
| `vfs` | file operations, VFS, archives, SFTP, drives, long paths |
| `plugins` | plugin host, loader, 7z/tmp/WASM plugins (`SamplePlugin.dpr` is a fixture) |
| `core` | configuration, keymap, message bus, strings, help, input parsing and terminal host output |

```powershell
./src/tests/run-tests.ps1                    # all groups except fixtures of the Manual category
./src/tests/run-tests.ps1 -Group vfs,panels  # selected groups
./src/tests/run-tests.ps1 -Test TestPty*     # fixtures by unit name (masks), Manual ones included
./src/tests/run-tests.ps1 -All               # with Manual
./src/tests/run-tests.ps1 -List              # only list
./src/tests/run-tests.ps1 -Jobs 1            # one group at a time (all at once by default)
```

Groups are independent (each has its own `.dcu` in `src/tests/dcu/obj/<group>`, its own settings folder and its own
exe), so `run-tests.ps1` builds and runs them at the same time (`-Jobs` limits the number) and prints the results in
group order. It compiles a group's runner into `src/tests/dcu` and starts it from the group's folder (paths such as
`..\..\dialogs` in the tests are relative to it). The NUnit XML report is written to `src/tests/dcu/<Group>Tests.xml`;
CI saves it as an artifact. A runner that exceeds `-TimeoutSec` (900 s by default) is killed and counts as failed; the
run does not stop at the first failure and prints a summary at the end.

A group's runner can also be started directly (from the group's folder) with the DUnitX switches: `-h` for help,
`--run:TestToast.TTestToast` for one fixture, `--exclude:Manual`, `--xmlfile:<path>`.

A new test: `src/tests/<group>/TestXxx.pas` modelled on its neighbours (the fixture is registered in `initialization`
through `TDUnitX.RegisterTestFixture`); include Core units without `in` paths - the runner's `-U` finds them. Add the
unit to the group runner's `uses`; `run-tests.ps1` fails if some `Test*.pas` is not listed there. Manual, interactive
and environment-dependent fixtures get `[Category('Manual')]` with a comment giving the reason above the attribute. If
the needed environment (7z.dll, wasmtime.dll) is missing, the test finishes with `Assert.Pass('SKIP: ...')`.

Inside fixture methods `Writeln(...)` resolves to the DUnitX helper `TObject.WriteLn(msg)` (one string argument,
writes to the runner log); for ordinary console output write `System.Writeln`.

## CI/CD (GitHub Actions)

| Workflow | Where | What |
|---|---|---|
| `ci.yml` -> `checks` | GitHub-hosted (ubuntu) | gitleaks, validity of the JSON resources |
| `ci.yml` -> `wasm-plugin` | GitHub-hosted (ubuntu) | `cargo build` of the `mtn.ws` plugin for `wasm32` |
| `ci.yml` -> `delphi` | self-hosted `delphi` | `build.ps1` + `run-tests.ps1` + a zip artifact; on a push to `main` it also publishes to the rolling `dev` prerelease of the `Laex/MTN2-dev` repository |
| `release.yml` | self-hosted `delphi` | on a `v*` tag: build, tests, a GitHub Release with the zip and the matching `CHANGELOG.md` and `CHANGELOG.ru.md` sections |

RAD Studio is commercial and not available on GitHub-hosted runners, so the Delphi part runs on the maintainer's machine.

### Development builds (the dev channel)

On every push to `main` the `delphi` job in `ci.yml` builds an exe with the version
`<version from MTN2.dproj>.<number of commits after its tag>` (for example `0.3.12.57`; computed by
`src/tools/dev-version.ps1`) and puts the packages into the single `dev` prerelease of `Laex/MTN2-dev`; the packages of
the previous build are removed. A separate repository is needed because immutable releases are enabled in `Laex/MTN2`:
a published release cannot be overwritten there. `Laex/MTN2-dev` has no immutable releases or tag rulesets.

A four-number version is newer than the release it counts from and older than the next one (`0.3.13 > 0.3.12.999`),
so the built-in updater moves from the dev channel to releases only when the next release comes out.

A local build with the same number: `./src/build.ps1 -Dev`. The commit count comes from the local history, so a build
of an unpushed commit gets a number higher than the published one and the updater will not offer it an older dev build.
The tag of the current version (`v0.3.12`) must be in the clone: `git fetch --tags`.

The dev steps run only on a push to `main`, not on pull requests: the secret is not available to code from forks. The
application looks the build up through `releases/tags/dev` and takes the package with the highest number in the name
`MTN2-v<major>.<minor>.<patch>.<build>-win64.zip`.

### What is new: `CHANGELOG.md` and `CHANGELOG.ru.md`

`CHANGELOG.md` (English) and `CHANGELOG.ru.md` (Russian) in the root are for users: what appeared, what was fixed, what changed in behaviour, without the internal
kitchen (refactoring, tests and CI are not written there). A change noticeable to the user is recorded at once in the
"Unreleased" section under "New", "Fixed" or "Changed" ("Не выпущено" with "Новое", "Исправлено", "Изменено" in
the Russian file). Both files are put into both archives next to `LICENSE`; the "Open changelog" button after an update
opens the one in the interface language, or the English one if there is no translation. `changelog.ps1` works on both
files together and refuses to stamp or move entries when only one of them has any.

### Release

```powershell
./src/tools/changelog.ps1 -Stamp v0.3.0   # "Unreleased" -> "v0.3.0 - <date>", a new empty "Unreleased"
                                          # and version 0.3.0 in MTN2.dproj; both files go into the commit "Stamp 0.3.0"
git tag v0.3.0
git push origin v0.3.0
```

`release.yml` takes this version's section from both files at the tag (English first) and puts it at the top of the
release page with links to the whole files; without such a section (`-Stamp` was not run) the release stops before the build.

The release exe's version comes from the tag (`build.ps1 -Version`), while a local build without `-Version` takes it
from `MTN2.dproj`. If the dproj is not bumped, the local exe considers itself a version older and the built-in updater
offers to "update" it to the version already installed. To bump only the dproj:
`./src/tools/changelog.ps1 -ProjectVersion v0.3.0`.
