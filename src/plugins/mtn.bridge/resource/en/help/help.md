# Service bridge

The plugin connects external programs, written in any language, as providers of JSON-RPC services. A program reads one JSON message per line from stdin and writes one per line to stdout; each tool it offers becomes the service `bridge.<server>.<tool>`.

Open Plugins, select Service bridge, press Settings.

- **Servers** is a JSON list. Each entry has `name`, `command` and, optionally, `args`, `cwd`, `env`, `startTimeoutMs` and `allow` (the tools that may be offered).
- When the settings are saved, the full command line of every new or changed server is shown. A program starts only after you allow it; a changed command asks again.
- The tool lists are read once and kept. Saving the settings clears them; restart the program afterwards.
- A server starts at its first call and is restarted after a failure up to three times in a row.

Example:

    [{"name": "sample", "command": "python", "args": ["C:/Tools/echo_server.py"]}]

The folder of the plugin has `samples/echo_server.py`, a minimal server. The protocol is described in `docs/PLUGIN_SERVICES.md`.
