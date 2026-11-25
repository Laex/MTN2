# ripgrep

The plugin serves the text search of **Alt+F7** with [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`), which is much faster than the built-in walk on large trees. It needs `rg` in the PATH or next to the plugin; without it the built-in search is used.

It takes the content stage of the search: with a selective mask the Find dialog runs a pipeline (names first, then text), and the **Pipeline** button chooses **Auto**, **Built-in** or this plugin for the stage. Searches inside archives, by hex bytes or by attributes always use the built-in code, and so does a stage the plugin cannot serve.
