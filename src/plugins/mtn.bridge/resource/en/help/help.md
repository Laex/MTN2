# Service bridge

The plugin connects external services, written in any language, as providers of JSON-RPC services. A server is either a program that reads one JSON message per line from stdin and writes one per line to stdout, or an HTTP address that takes one POST per message. Each tool a server offers becomes the service `bridge.<server>.<tool>`.

Open Plugins, select Service bridge, press Settings. The settings show the servers as a list with the columns number, name, type, program or address, and state.

- **Add**, **Edit** (F2), **Delete** (Del) change the list; **Up** and **Down** (Ctrl+Up, Ctrl+Down) change its order, which is the order the services are registered in.
- **Check** (F5) starts the program or contacts the address, reads the tools and reports the result in the State column: the number of tools or the reason the server is not available. A server that is not approved yet is asked about first.
- OK saves the list, Cancel drops every change made in the dialog.
- The server fields are described below.
- When the settings are saved, the full command line or address of every new or changed server is shown. A program starts, or an address is contacted, only after you allow it; a change asks again.
- The tool lists are read once and kept. Saving the settings clears them; restart the program afterwards.
- A server starts at its first call and is restarted after a failure up to three times in a row.

## Server fields (Add and Edit)

Common to both types:

- **Name** – a short unique name: letters a-z, digits, `_` and `-`. It becomes part of the service name: server `files` with tool `list` gives `bridge.files.list`.
- **Type** – "Program (stdin/stdout)" or "HTTP address". The fields below that do not belong to the type are ignored.
- **Start timeout, ms** – how long to wait for the server at start and at Check. Empty means 10000 (10 seconds).
- **Allowed tools** – names of the server tools to offer, separated by blanks. Empty means all tools.

Type "Program":

- **Program** – an executable or a command from PATH (`python`, `node`, `C:\Tools\server.exe`).
- **Arguments** – separated by blanks; "double quotes" group a value that has blanks.
- **Folder** – the working folder of the program (optional).
- **Environment** – extra variables as `NAME=VALUE`, separated by blanks; quote a value that has blanks.

Type "HTTP address":

- **Address** – the full `http://` or `https://` address that receives the POST requests.
- **Headers** – extra request headers as `NAME=VALUE`, separated by blanks; quote a value that has blanks.

## Examples

A Python program:

| Field | Value |
|---|---|
| Name | `echo` |
| Type | Program (stdin/stdout) |
| Program | `python` |
| Arguments | `C:\Tools\echo_server.py` |

A Node.js program with a folder and environment:

| Field | Value |
|---|---|
| Name | `notes` |
| Program | `node` |
| Arguments | `server.js --verbose` |
| Folder | `D:\Work\notes-server` |
| Environment | `LANG=en NOTES_DIR="D:\My Notes"` |

A local HTTP server:

| Field | Value |
|---|---|
| Name | `local` |
| Type | HTTP address |
| Address | `http://127.0.0.1:8080/rpc` |

A remote HTTP server with headers and a limited set of tools:

| Field | Value |
|---|---|
| Name | `remote` |
| Type | HTTP address |
| Address | `https://example.com/rpc` |
| Headers | `X-Client=mtn2 X-Team="Team 5"` |
| Start timeout, ms | `5000` |
| Allowed tools | `search read` |

After adding, press Check: the State column shows the number of tools or the reason the server is not available.

## How HTTP works

An HTTP server gets every message as a POST with a JSON body. It answers with a JSON body or with an event stream (`text/event-stream`) carrying one message per event; the session header it sets is sent back with the following requests.

The folder of the plugin has `samples/echo_server.py`, a minimal server. The protocol is described in `docs/PLUGIN_SERVICES.md`.
