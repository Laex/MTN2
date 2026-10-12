# Contributing to MTN2

Thank you for your interest in MTN2. You can help in many ways: report a bug, suggest an idea, create a theme or
plugin, improve documentation or translations, or fix code.

## Where to ask

- **Bug or missing behavior** – open a [new issue](https://github.com/Laex/MTN2/issues/new/choose). Include the version
  (≡ → About), operating system, display scale and font, reproduction steps, and a screenshot when possible.
- **Question, idea, theme, or plugin** – use [Discussions](https://github.com/Laex/MTN2/discussions).
- **Vulnerability** – report it privately using [SECURITY.md](SECURITY.md); do not open a public issue.
- Frequently asked questions are in [docs/FAQ.en.md](docs/FAQ.en.md).

Issues intended for newcomers are marked [good first issue](https://github.com/Laex/MTN2/labels/good%20first%20issue);
issues that need help are marked [help wanted](https://github.com/Laex/MTN2/labels/help%20wanted).

## What you can do without Delphi knowledge

- **Themes.** A theme is a JSON file ([docs/THEMES.md](docs/THEMES.md)); share a finished theme in Discussions.
- **Interface languages.** Strings are stored in `src/strings/<language>.json`; a custom language can be added as
  `strings\<language>.json` next to `MTN2.exe`.
- **Plugins.** Native DLLs and WebAssembly (C, C++, Rust, Go, and others); contracts are documented in
  [docs/PLUGIN_DEVELOPMENT.md](docs/PLUGIN_DEVELOPMENT.md), with examples in [samples](samples).
- **Documentation and help.** Text lives in `docs/` and `bin/win64/help`.

## Building and testing

RAD Studio 13 and Windows x64 are required; see [docs/BUILDING.md](docs/BUILDING.md) for details.

```powershell
./src/build.ps1 -Config Release -Platform Win64
./src/tests/run-tests.ps1
```

Build only through `src/build.ps1`. The Linux version is built with `src/build-linux.ps1`.

## Proposing a change

1. For a large change, open a discussion or issue first so the direction can be agreed on.
2. Keep one change per pull request and do not include unrelated formatting changes.
3. Add a test for a bug fix (DUnitX tests live under `src/tests`); every test must check something with `Assert`.
   Name tests after the behavior they verify.
4. If the change is user-visible, add an entry to the “Not released” section of [CHANGELOG.md](CHANGELOG.md), in
   Russian and in the third person, describing what the user sees.
5. Build the project and run the tests before submitting the change.

## Style

- Source files use UTF-8; preserve the existing line endings and BOM where present.
- Comments are short and in English: explain why the code is written that way rather than restating what it does.
  Use ASCII punctuation only in comments (`-`, `->`, `...`, and straight quotes).
- Platform code belongs in `src/Platform/Windows` and `src/Platform/Posix`. Shared code accesses the platform through
  matching modules rather than `{$IFDEF}` blocks.
- Commit messages are in English, imperative, about 60 characters or fewer, and have no period at the end.
- Markdown documentation uses an en dash – (U+2013).

## License

By submitting changes, you agree that they are distributed under the terms of the
[Mozilla Public License 2.0](LICENSE).
