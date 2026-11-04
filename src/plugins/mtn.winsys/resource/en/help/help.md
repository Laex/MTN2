# Registry, processes and services

The plugin adds three folders to the Change Drive list (Alt+F1 / Alt+F2): Registry (`reg:///`), Processes (`proc:///`) and Services (`svc:///`).

## Registry

Keys are folders, values are files; the default value of a key is `(Default)`. A `/` in a name is written `%2F`.

| Key | Action |
|---|---|
| F3 | show a value: its type and data |
| F4 | edit a value (REG_SZ, REG_EXPAND_SZ, REG_DWORD, REG_QWORD, REG_MULTI_SZ) |
| Shift+F4 | make a new value (a string unless the text starts with a `Type:` line) |
| F7 | make a key |
| F8 | delete a key with everything in it, or a value |

The text of a value starts with `Type: REG_X` and an empty line. Changing the type name in the first line changes the type when the value is saved. Binary values are shown as a hex dump and cannot be edited.

## Processes

Every process is a file `name.exe (pid)`; its size is the working set and its date the start time. F3 shows the path, parent, memory, handles and times. F8 ends the process at once (the program asks first).

## Services

Every service is a file named by its short name, colored by state: green running, grey stopped, yellow starting or stopping. F3 shows the display name, start type, command line, account and description. The **Plugins** menu starts, stops, restarts, pauses and resumes the service under the cursor.

Starting, stopping and many registry keys need an administrator: start MTN2 elevated when the program answers "access denied".

Columns: in the Custom column mode (**Columns...**) processes show PID (also PPID and thread count) and services show State, PID and Display name; click a header or press Ctrl+F12 to sort by one.
