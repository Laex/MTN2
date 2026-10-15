# Operation counter (C++)

The plugin counts the Copy (F5), Move (F6) and Delete (F8) commands, however they were started (the key or the menu), and shows the total as **Ops: N** at the end of the status line. It only watches: the commands run as usual.

## Use

- Work as usual; the number grows by one for every command.
- **Ctrl+Alt+F10** (shown as *Stats* in the function bar with Ctrl+Alt held) opens a dialog with the three counters.
- The counters start from zero each time MTN2 starts.

## For authors

Source: `samples/plugins/mtn.demo.cpp/plugin.cpp`. It shows command hooks that answer 0 (do not cancel the command), a status segment, a plugin command with a key and a bar label, and a dialog written as JSON.
