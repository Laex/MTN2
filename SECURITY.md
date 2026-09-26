# Security Policy

## Supported versions

Only the latest release published on
[GitHub Releases](https://github.com/Laex/MTN2/releases/latest) receives fixes.
MTN2 updates itself from there (after asking the user), so a fix ships as a new release.

## Reporting a vulnerability

Please **do not open a public issue**. Report privately via
[Security → Report a vulnerability](https://github.com/Laex/MTN2/security/advisories/new)
and include the MTN2 version (≡ → About), Windows version, steps to reproduce and the impact.

Areas of particular interest:

- the self-updater (release lookup, download, SHA-256 check, install/restart);
- plugin loading (native DLL and WebAssembly plugins);
- SSH/SFTP connections and stored connection settings;
- archive handling (path traversal, malformed archives);
- ConPTY / terminal escape-sequence parsing.

You should get a reply within a week. Once a fix is released, the advisory is published
with credit to the reporter unless you prefer otherwise.

---

**RU.** Об уязвимостях сообщайте не через issue, а приватно:
[Security → Report a vulnerability](https://github.com/Laex/MTN2/security/advisories/new).
Исправления выходят только в последней версии.
