# Everything

The plugin shows the results of a search in the [Everything](https://www.voidtools.com/) program as a panel (`everything:///<query>`). Windows only; Everything must be running.

**Plugins > Everything search...** asks for the query (Everything syntax: `*.log`, `ext:pdf size:>10mb`, `path:"C:\Work" report`) and opens the results in the active panel. The query is stored in the address; a `/` in it is written `%2F`.

The rows are the real files, so F3, F4, F5, F6 and F8 act on them. At most 5000 results are shown. The panel reads the results through the Everything window messages, so the Everything SDK library is not needed.
