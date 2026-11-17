# Plugin services (JSON-RPC)

**English** | [Русский](PLUGIN_SERVICES.ru.md)

> **Document role:** the contract of *services* – named capabilities that a plugin offers to the host and to other plugins, called with JSON-RPC 2.0 messages.
> **Context:** [PLUGIN_BOUNDARIES.md](PLUGIN_BOUNDARIES.md) (what stays in the core), [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md) (how to write a plugin), [ARCHITECTURE.md](ARCHITECTURE.md) §6.
> **Status:** the contract is described; the Host API functions of §6 are not exported yet (planned for the next ABI version).

---

## 1. Scope and roles

A **service** is a named capability with a version, for example `search.files`. A **provider** is a plugin that registers a service. A **caller** is the host or another plugin that sends the service a request.

The service layer is the single way for the host to hand a task to a plugin without a new Host API function per task: the first service is `search.files`, which lets Alt+F7 use a fast file index (the Everything plugin) or a fast content search (a ripgrep plugin) instead of walking the disk itself. The same mechanism later serves other tasks (metadata, previews) and a bridge to external processes.

What a service is not: it is not a replacement for the VFS, panel or dialog contracts. A panel still gets its rows from a VFS scheme; a service answers a question and returns data.

---

## 2. Service model

| Term | Meaning |
|---|---|
| Name | Lower-case words joined by dots: `search.files`. Names are unique per provider; several providers may register the same name |
| Version | A positive integer. A provider raises it when the meaning of a field changes; new optional fields do not change it |
| Priority | An integer; providers of one name are tried in ascending order, like command hooks. The host picks the first provider whose declared capabilities fit the request |
| Description | The JSON of §4: what the service does and the schema of its parameters |

**Reserved names.** A plugin cannot register a name that starts with `host.` or `service.`, or equals `host`, `service` or one of the core scheme names `file`, `recycle`, `sys`, `find`, `ws`. The registration is refused with the error code `-32003`.

**Lazy loading.** A plugin that offers services lists their names in the `services` array of `plugin.json`; the host loads such a plugin when a request for one of the names arrives (the same way a plugin is loaded for its scheme). A plugin without the array registers its services only after it was loaded for another reason.

**Turning a provider off.** The plugins that offer services (Everything, ripgrep, the document viewer) have a Settings dialog with the option "Offer this plugin as a provider of JSON-RPC services". When the user clears it (the plugin setting `jsonrpc_provider` = `0`), the plugin registers no service the next time it loads, so the host never calls it. `TServiceProvider.Register` in `uPluginServiceProvider.pas` applies the option, and `uPluginServiceSettings.pas` holds the dialog; a plugin of another kind adds the same dialog with `RegisterServiceSettings`.

---

## 3. Messages

Every message is one UTF-8 JSON object that follows [JSON-RPC 2.0](https://www.jsonrpc.org/specification). Batches (a JSON array of requests) are not used.

- **Request:** `{"jsonrpc":"2.0","id":1,"method":"search.files","params":{...}}`. `id` is an integer or a string unique among the caller's open requests.
- **Response:** `{"jsonrpc":"2.0","id":1,"result":{...}}` or `{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"..."}}`.
- **Notification:** a message without `id`; it gets no response.

The `method` of a request is the name of the service, or `service.describe` / `service.ping` (§4).

### 3.1. Error codes

| Code | Meaning |
|---|---|
| `-32700` | The message is not valid JSON |
| `-32600` | The message is not a valid JSON-RPC object |
| `-32601` | No provider for the method |
| `-32602` | The parameters do not match the schema of the service |
| `-32603` | Internal error of the provider or the host |
| `-32001` | The call was cancelled |
| `-32002` | The provider cannot serve this request (a missing program, an unsupported criterion); the caller falls back to its own way |
| `-32003` | Not allowed: a reserved name, a refused permission |
| `-32004` | Too many open calls for the service |
| `-32005` | The provider did not answer within the time limit |

`message` is a short text for the log; it is not shown to the user as is. Details go into `error.data` (an object).

---

## 4. Common methods

### 4.1. `service.describe`

Request without parameters. The result lists what the provider offers:

```json
{
  "protocolVersion": 1,
  "name": "search.files",
  "version": 1,
  "title": "Everything",
  "description": "Finds files by name with the Everything index",
  "inputSchema": {
    "type": "object",
    "properties": {
      "root":   {"type": "string"},
      "mask":   {"type": "string"},
      "subdirs": {"type": "boolean"},
      "caseSensitive": {"type": "boolean"}
    },
    "required": ["root", "mask"]
  },
  "capabilities": ["name", "mask", "path", "size", "date"]
}
```

- `inputSchema` is a JSON Schema object with the types `object`, `string`, `integer`, `number`, `boolean`, `array`, and the keywords `properties`, `required`, `enum`, `items`. The host checks the parameters of a request against it before the call and answers `-32602` itself.
- `name`, `description` and `inputSchema` have the same shape as an entry of the usual "list of tools" of JSON-RPC tool servers, so an external process can be mapped to a service without changing the data (see §10).
- `capabilities` is the list of strings the host matches against what a request needs. The words for each service are defined in the section of that service (§7).

### 4.2. `service.ping`

Request without parameters; the result is `{}`. The host uses it for a provider that runs in another process; a provider in a library answers at once.

---

## 5. Results, progress and cancellation

**Result of a call.** A provider returns an object:

```json
{
  "content": [{"type": "text", "text": "12 files found"}],
  "structuredContent": {"hits": 12, "truncated": false},
  "isError": false
}
```

- `content` is a text for a person (a list of objects with `type` `text`).
- `structuredContent` is the data for the program; its form is defined by the service (§7).
- `isError` is `true` when the service ran and reported a failure of its own task (for example, an unreadable folder); the protocol-level failures use the `error` object of §3.1.

**Progress.** While a call runs, the provider may send notifications:

```json
{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"1","progress":120,"total":0,"message":"C:\\Work"}}
```

`progressToken` is the `id` of the request; `total` is 0 when unknown. The host shows `message` in the job line. Partial data of a service is sent in service-specific notifications (for `search.files`: `search.hits`, §7).

**Cancellation.** A caller cancels a call with `CancelService` (§6); the host answers the caller with the error `-32001` at once and sends the provider the notification `{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1,"reason":"cancelled"}}`. The provider must stop its work and free what the call holds; whatever it sends for the call afterwards is dropped by the host. A call that ends for another reason (the time limit, the provider unloaded) is closed the same way.

---

## 6. Host API (ABI 11)

The functions are added at the end of the Host API table, so a plugin built against an older ABI keeps working. A plugin that wants them checks `AHostApi^.AbiVersion >= 11` first. Every text is UTF-8; "main thread" means the thread that runs the plugin's other callbacks.

| Function | Purpose |
|---|---|
| `RegisterService(pluginId, name, version, describeJson, handler, userData, priority)` | Offers a service (main thread). 0 = registered, otherwise the error code: `-32003` for a reserved name, `-32602` for a bad argument. Registering a name again from the same plugin replaces it |
| `ServiceReply(call, responseJson)` | Completes a call of the provider; from any thread, once per call. 0 = queued, -1 = not valid |
| `ServiceNotify(call, notificationJson)` | Sends progress or partial data of a running call to its caller; from any thread. 0 = queued, -1 = not valid |
| `CallService(pluginId, name, requestJson, timeoutMs, buf, bufSize, negotiatedSize)` | Synchronous call (main thread). `pluginId` is empty or `NULL` for the first provider. `timeoutMs` is 1..60000. 0 = the response is in `buf`; -2 = `buf` is too small and `negotiatedSize` is the size needed; otherwise the error code of the failure |
| `CallServiceAsync(pluginId, name, requestJson, timeoutMs, onMessage, userData, jobId)` | Asynchronous call (main thread): returns at once; `onMessage` receives the notifications and then the response. 0 = started, otherwise the error code and no message follows |
| `ServiceStatus(jobId, buf, bufSize)` | The state of a call as JSON: `state` (`running`, `done`, `cancelled`, `failed`), `progress`, `total`, `message`. Text result as for the other text functions; -1 = no such call |
| `CancelService(jobId)` | Requests cancellation (§5) (main thread). 0 = cancelled, -1 = the call is not open |

A plugin that is unloaded loses its services and the calls open on them end with `-32603`. The manifest field `"services": ["search.files"]` lists the names a plugin registers; the host loads the plugin the first time a caller asks for one of them. The optional field `"serviceCapabilities": {"search.files": ["name", "list"]}` repeats the capability words of a service, so that the host can offer the provider in a list (the Pipeline dialog) without loading the plugin.

Provider handler: `function(userData: Pointer; call: Int64; requestJson: PAnsiChar): Int64; cdecl;`. It must return quickly: for a request (`call` is not 0) it starts the work, possibly on its own thread, and completes it with `ServiceReply`; for a notification (`call` is 0) it only reads it. The return value is 0 when the message was accepted.

Caller callback: `procedure(userData: Pointer; jobId: Int64; messageJson: PAnsiChar); cdecl;`. The text is valid only during the call.

### 6.1. WASM plugins

A WASM guest reaches the same services through imports of the module `mtn_host` (the full list with the other imports is in the header of `Core/uWasmPluginHost.pas`). All of them run on the main thread; texts are UTF-8 in guest memory.

| Import | Purpose |
|---|---|
| `service_register(name_ptr, name_len, version, describe_ptr, describe_len, export_ptr, export_len, priority)` | Offers a service; an empty description counts as `{}`. 0 = registered, otherwise the error code as for `RegisterService`. The guest export named by `export_*` is `(call, handle, length)` |
| `service_message(handle, out_ptr, out_cap)` | Fetches the text behind a handle that the host gave to a guest export: its length; the text is written only when it fits |
| `service_reply(call, ptr, len)`, `service_notify(call, ptr, len)` | Complete a call of the guest's service or send it a notification. 0 = queued, -1 = not valid; only a call the guest was given can be answered |
| `service_call(plugin_ptr, plugin_len, name_ptr, name_len, request_ptr, request_len, timeout_ms, export_ptr, export_len)` | Starts a call (`timeout_ms` 0..60000, plugin empty = first provider). A positive result is the job number, otherwise the error code. The guest export is `(job, handle, length)`; it hears every notification and the response, and the text is fetched with `service_message` |
| `service_cancel(job)` | Cancels a call the guest started. 0 = cancelled, -1 = not valid |

The host never enters the guest from inside one of its imports: a request for the guest's service, a notification or a response reaches the export from the message queue, a moment after the call that caused it. A `call` of 0 in the provider export is a notification. Calls the guest started end when the plugin is unloaded.

Calling services needs the permission `services.call` (named in the manifest and granted by the user, see §2.6 of [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md)): a service can read files or start programs, which a guest otherwise cannot do. Without it `service_call` returns `-32003`. Providing a service needs no permission.

A complete sample, `samples/plugins/mtn.wasm.services`, provides a service and calls it from a menu item.

---

## 7. Threads, limits, safety

- **Threads.** A provider answers from any thread. The host moves every message for a caller to the main thread before `onMessage` runs, in the order the provider sent them; the response is always the last message of a call. `CallService` waits on the main thread and delivers other messages meanwhile, so it suits fast services only; the host uses `CallServiceAsync` for jobs the user can see.
- **Limits.** One message is at most 4 MiB. At most 8 calls of a service run at once; the next one gets `-32004`. A call has a time limit given by the caller, at most 60 s, counted from the last message of the provider (a notification restarts it); without a limit the call may be silent as long as it takes. A provider that is silent for the limit is answered `-32005` and its call is cancelled.
- **Safety.** A provider is as trusted as its plugin (§1 of [PLUGIN_BOUNDARIES.md](PLUGIN_BOUNDARIES.md)). A provider that starts another program builds its argument list without a shell and never takes a program path from data of a request. Parameters from a request are never put on a command line as one string.
- **Exceptions.** An exception inside a handler is answered with `-32603`; it does not reach the caller as a crash.

---

## 8. Service `search.files`

Finds files and folders. Alt+F7 asks the registered providers before it walks the disk.

### 8.1. Request parameters

| Field | Type | Meaning |
|---|---|---|
| `root` | string | The folder to search in, a local path |
| `mask` | string | One or several masks, separated by `;`; empty means every name |
| `text` | string | The text a file must contain; empty means names only |
| `regex` | boolean | `text` is a regular expression |
| `caseSensitive` | boolean | Match case |
| `wholeWords` | boolean | Match whole words only |
| `subdirs` | boolean | Search the subfolders of `root` |
| `includeFolders` | boolean | Folders may be in the result |
| `hidden` | boolean | Hidden and ignored files may be in the result |
| `encoding` | string | A fixed encoding of the file text; empty means detect |
| `minSize`, `maxSize` | integer | Bytes; absent means no bound |
| `modifiedFrom`, `modifiedTo` | string | ISO 8601 date and time; absent means no bound |
| `maxResults` | integer | The most hits the caller wants |
| `files` | array of strings | Files to look in; the provider checks only these files for `text` and ignores `root`, `mask` and `subdirs` (second stage of the pipeline, §8.5) |

### 8.2. Capabilities

A provider lists the words for what it honors: `name`, `mask`, `path`, `subdirs`, `case`, `words`, `size`, `date`, `folders`, `content`, `regex`, `encoding`, `hidden`, `list`, `files`. `list` means the provider lists files by name without looking into them (it can run the first stage of the pipeline, §8.5); `files` means it accepts the `files` parameter (the second stage). The host uses a provider only when every word the request needs is in the list; the request needs `name` and `mask` always, and `content` when `text` is not empty. A bound the provider does not honor (for example, a lower size bound) is applied by the host to the hits.

### 8.3. Hits and result

While the search runs the provider sends the notification

```json
{"jsonrpc":"2.0","method":"search.hits","params":{"progressToken":"1","hits":[{"path":"C:\\Work\\a.txt","isDir":false,"size":120,"modified":"2026-01-02T03:04:05"}]}}
```

The `hits` array holds at most 500 entries per message; `size`, `modified`, `created`, `accessed` (local ISO 8601) and `attributes` (Windows attribute bits) are optional; what a hit lacks stays empty in the results list. The final response carries the totals:

```json
{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"12 found"}],"structuredContent":{"count":12,"truncated":false}}}
```

`truncated` is `true` when the provider stopped at `maxResults` or at a limit of its own.

### 8.4. Choice of the provider and fallback

The host picks the first provider in priority order whose capabilities fit the request. A request with a condition no provider honors (a byte pattern, files inside archives, attributes, a non-local root) is served by the built-in walk. When the chosen provider answers with `-32002`, `-32005` or any other error before the first hit, the host runs the built-in walk and shows a short note in the status line. After the first hit an error ends the search with the hits found so far.

### 8.5. Pipeline

A search with a text and a mask (or size or date bounds) that leaves files out runs in two stages. The first stage lists the files by name: a provider with `list` (for example Everything), or the built-in walk. The found files go in batches to the second stage, which looks for the text only in them: a provider with `files` (for example ripgrep), or the built-in text check. Documents whose text a `text.extract` provider reads always go to the built-in check. A search with a text and an open mask (`*` or `*.*`) is served by one provider as described in §8.4, because listing every file first would be slower. The Pipeline dialog of the Find dialog chooses the provider of each stage: Auto, Built-in or a provider that has the capability of the stage. A first-stage provider that fails before the first hit hands the stage to the built-in walk; a second-stage provider that fails before the first hit hands it to the built-in check.

---

## 9. Service `text.extract`

Turns a document into plain text. A content search in Alt+F7 asks it for the files whose extension a provider serves, so a `.docx` or `.pdf` is searched by its text instead of its bytes.

### 9.1. Request parameters

| Field | Type | Meaning |
|---|---|---|
| `path` | string | The local path of the document |
| `maxChars` | integer | The most characters of text the caller wants |

### 9.2. Capabilities

A provider lists one word `ext.<extension>` for every extension it reads (lower case, without the dot): `ext.docx`, `ext.pdf`. The host asks a provider only for an extension in its list. When no provider lists the extension, the file is read as it is.

### 9.3. Result

```json
{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"1200 characters"}],"structuredContent":{"text":"...","truncated":false}}}
```

`truncated` is `true` when the text was cut at `maxChars`. A file the provider cannot read is answered with `-32002`, bad parameters with `-32602`; the host then treats the file as not containing the text. A file with no text gives an empty `text`.

### 9.4. Use by the search

The built-in walk reads such a file through the service and looks for the text in the answer. When a `search.files` provider (for example ripgrep) serves the search, the host runs a second pass over the files of the served extensions after the provider has finished, and lists a file that both found once. The Pipeline dialog of the Find dialog chooses the provider of each stage: Auto (the rule above), Built-in (no provider and no text extraction), or one plugin, which is the only provider asked, and the built-in code serves the stage when it cannot.


---

## 10. Compatibility with external processes

The message format (JSON-RPC 2.0), the shape of the description (`name`, `description`, `inputSchema`), the call result (`content`, `structuredContent`, `isError`), and the names and fields of the progress and cancellation notifications follow the conventions of common JSON-RPC tool servers. The `mtn.bridge` plugin starts external programs that speak this protocol over stdin and stdout (one JSON message per line), or contacts HTTP addresses that take one POST per message and answer with a JSON body or an event stream, and registers each tool of a server as the service `bridge.<server>.<tool>`.

### 10.1. Settings

The plugin setting "Servers" is a JSON list. Each entry has `name` (a-z, 0-9, `_`, `-`, up to 32 characters), `command`, and optionally `args`, `cwd`, `env` (an object of strings), `startTimeoutMs` (1000..60000, default 10000) and `allow` (the tools that may be offered; empty means all). At most 16 servers are accepted.

A program is started only after the user approved its command line: when the settings are saved, the plugin shows the whole command (program, arguments, folder, environment) and asks. The approval is tied to this exact command line; a changed command asks again. No program path is taken from data or from a service call.

### 10.2. Behavior

- The tool list is read once and kept in the plugin settings; services are registered while the plugin loads. A server without a kept list is started once at load to read it. Saving the settings clears the lists.
- A server is started when its first service is called, and restarted after a failure up to three times in a row.
- The `params` of a call are passed as the tool arguments. A tool result with `isError` becomes the error `-32603` with the text of the result. A progress notification of the server becomes a progress message of the call. A cancelled call sends a cancel notification to the server and ends with `-32001`.
- Limits: 16 pending calls per server, 200 tools, 4 MB per line, a call time limit of 120 s (`-32005`).
- The program runs in a process group (a job object on Windows) that ends with the host.
- `service.describe` of a registered service is built from the tool description; its capability is `tool`.
- The option "JSON-RPC provider" in the plugin settings stops the plugin from offering the servers.

`samples/echo_server.py` in the plugin folder is a minimal server.

---

## 11. Implementation state

- Described here: the message format, the error codes, `service.describe` and `service.ping`, progress and cancellation, the Host API functions, `search.files`, `text.extract`.
- Implemented: the registry and the router, the checking of parameters against `inputSchema`, the Host API functions of ABI 11, the manifest field `services`, the use in Alt+F7, the providers (Everything and ripgrep for `search.files`, the document viewer for `text.extract`), the `mtn.bridge` plugin, the services of the WASM guest ABI (§6.1).
