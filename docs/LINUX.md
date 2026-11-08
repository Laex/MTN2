# MTN2 in a Linux terminal

**English** | [Русский](LINUX.ru.md)

`mtn2-tui` is the MTN2 version for a Linux text terminal. The windows are the same as in the graphical program: two
panels with tabs, a viewer, an editor, a console, terminals, menus, dialogs and help. Instead of a window the program
takes over the whole terminal: only the changed cells are written to the screen (TrueColor, wide CJK characters take two
columns), and input comes from the terminal keyboard and mouse. It works over SSH, in `tmux`, in containers and on servers without X11.

For building, see [BUILDING.md](BUILDING.md), the section "Building for Linux". The version with a regular SDL2 window (`mtn2-sdl`) is described in the section "The SDL2 window version" below.

## Requirements

Linux x86-64 with glibc 2.34 or newer (Ubuntu 22.04, Debian 12, Fedora 35, RHEL 9 and newer) and `libstdc++`, `libz`.
Installation and launch have been verified on Debian 12, Ubuntu 22.04 and 24.04, Fedora and openSUSE Leap 15.6. The program needs the glibc character set conversion modules (`gconv`): regular installations have them, but trimmed-down openSUSE container images do not, and the program crashes at startup; the `glibc-locale` package fixes this. Distributions with musl (Alpine) are not supported.
No graphics stack is needed: Skia and FireMonkey, on which the Windows version window is built, are not used in the Linux programs (`mtn2-tui` draws with text, `mtn2-sdl` through SDL2 and FreeType). `xdg-open` is used to open files in a graphical environment, and the `sftp` client for SFTP. The "Network connections" plugin (FTP, FTPS, WebDAV, S3) loads the system `libcurl.so.4` (package `libcurl4` or `libcurl4t64`); without it the plugin reports that the library was not found. The "Macros" plugin takes the Lua library from its own folder (`plugins/mtn.lua/liblua5.4.so.0`, it is included in the archive and the packages), and if it is not there, the system one (`liblua5.4.so.0`: package `liblua5.4-0` on Debian and Ubuntu, `lua-libs` on Fedora and RHEL); without either it reports which package to install.

Only English is built into the program. The other languages and the F1 help are in the `resource/<language>/` folder next to the program (it is included in the archive and the package); a new language is added by copying such a folder, see [SDS.md](SDS.md) (the localization section).

## Installation

The release contains `MTN2-<version>-linux-x64.tar.gz` and the packages `MTN2-<version>-linux-x64.deb` and `MTN2-<version>-linux-x64.rpm`.

```bash
tar xzf MTN2-*-linux-x64.tar.gz && ./mtn2/install.sh    # for yourself: ~/.local/opt/mtn2, the command is mtn2
sudo ./mtn2/install.sh                                  # for everyone: /opt/mtn2, the command is mtn2
sudo apt install ./MTN2-*-linux-x64.deb                 # the same as a package (recommends 7zip or p7zip-full and chafa)
sudo dnf install ./MTN2-*-linux-x64.rpm                 # Fedora, RHEL and derivatives (recommends p7zip, chafa, libcurl, SDL2)
./mtn2/install.sh --uninstall                           # remove
```

The folder from the archive does not have to be installed: `mtn2/mtn2-tui` runs from wherever it is.

## Launch

```bash
mtn2-tui [options] [path ...]
```

| Option | What it does |
|---|---|
| `path` | a folder opens in a new tab; for a file, its folder opens with the cursor on it. There can be several paths |
| `--view file` | open the file in the viewer |
| `--edit file`, `-e file` | open the file in the editor |
| `--update [stable\|nightly]` | download and install the latest version of the channel without starting the program; the selected channel is remembered (the same one as in "Help – Check for updates..."). For a package installation it only checks: the package manager does the updating |
| `--install-desktop`, `--uninstall-desktop` | write or remove the menu shortcut and the icon in `~/.local/share` (`mtn2-tui` is a shortcut that runs in a terminal) |
| `--no-mouse` | do not ask the terminal for mouse events (selecting and copying are then done by the terminal) |
| `--colors=truecolor\|256\|16` | number of colors; by default it is detected from `COLORTERM` and `TERM` (Windows Terminal is detected by `WT_SESSION`) |
| `--dump [W H]` | draw one screen as plain text to standard output and exit (for checks without a terminal) |
| `--paths`, `--list-commands`, `--list-plugins` | print the program and settings folders, the built-in commands with their keys, the installed plugins |
| `--check-keymap [file]`, `--export-theme [id]` | check `keymap.json`; print a theme as JSON (without an id, the list of themes) |
| `--shell-init bash\|zsh\|fish\|powershell`, `--cd-file file` | the `mtn` function that, after exit, changes the shell to the folder of the active panel: `eval "$(mtn2-tui --shell-init bash)"` in `~/.bashrc` |
| `--version`, `--help` | version, help |

Exit is `F10` or `Alt+X`. Panels, tabs and settings are saved on exit.

## The SDL2 window version

`mtn2-sdl` is the same program in a regular graphical window: the Linux desktop (X11 or Wayland, WSLg on Windows), the system font, mouse and wheel, input in any keyboard layout, the desktop clipboard. The windows, menus, dialogs, plugins and settings are the same as in `mtn2-tui` and live in the same `~/.config/mtn2`. This version is experimental; it is included in the `tar.gz` archive and the `.deb` package (the `mtn2-sdl` command next to `mtn2`), and is built from source with the `-Sdl` switch.

One window per user: `mtn2-sdl <path ...>`, started while a window is already open, passes the paths to that window (new tabs, the window comes to the foreground) and exits; `--view` and `--edit` are passed the same way. The exchange goes through the Unix socket `mtn2-sdl.sock` in `$XDG_RUNTIME_DIR` (without it, in `/tmp` with the user id), accessible only to the owner. `--new-window` opens a separate window. `mtn2-tui` is bound to its own terminal and does not pass folders on.

### Dependencies

| Package | Purpose |
|---|---|
| `libsdl2-2.0-0` | window, events, clipboard (required) |
| `libfreetype6` | glyph rendering (required) |
| `fontconfig`, `fonts-dejavu-core` | font file lookup; at least one monospaced font is needed |
| `libsdl2-image-2.0-0` | PNG, JPEG, GIF, WebP images in Quick View; without it only BMP is shown |

```bash
sudo apt install libsdl2-2.0-0 libfreetype6 fontconfig fonts-dejavu-core libsdl2-image-2.0-0
```

The libraries are loaded at startup, not at build time: without `libsdl2-image` the program starts, and when any of the others is missing it says what is missing. Check: `mtn2-sdl --self-check` prints the libraries found, the font file, the resources and the plugins.

### Building and running

The build is done from Windows with the same compiler as `mtn2-tui`:

```powershell
./src/build-linux.ps1 -Sdl             # -> bin\linux64\mtn2-sdl (together with mtn2-tui)
```

Run it with `./mtn2-sdl [options] [path ...]` next to `plugins/` and `libwasmtime.so`; in WSL with WSLg the window appears on the Windows desktop.

| Option | What it does |
|---|---|
| `path` | a folder opens in a new tab; for a file, its folder opens with the cursor on it. There can be several paths |
| `--view file`, `--edit file` (`-e file`) | open the file in the viewer or in the editor |
| `--update [stable\|nightly]` | the same as in `mtn2-tui` |
| `--install-desktop`, `--uninstall-desktop` | write or remove the menu shortcut and the icon |
| `--font=NAME` | font family (DejaVu Sans Mono by default) |
| `--size=N` | font size in pixels |
| `--cols=N`, `--rows=N` | grid size when the window opens |
| `--snapshot=file.png` | draw one frame to a PNG without a window and exit (for checks without a desktop) |
| `--self-check` | check the libraries, the font, the resources and the plugins |
| `--paths`, `--list-commands`, `--list-plugins`, `--check-keymap`, `--export-theme`, `--shell-init`, `--cd-file` | the same as in `mtn2-tui` |
| `--version`, `--help` | version, help |

In the window the font size changes with `Ctrl` and the wheel, `Ctrl+Plus`, `Ctrl+Minus`; `Ctrl+0` restores the original. The selected size is stored in `sdl.json` in the settings folder; the `--size` option takes precedence over the stored one.

### Things to know

- Typed text comes from text input events, and `Ctrl` and `Alt` combinations come from physical keys, so they work in any keyboard layout. `AltGr` types characters and does not turn on `Alt`.
- A file dropped into the window from a file manager is inserted into the program as a path.
- The Quick View image is drawn in pixels over the grid and stays as long as the view is open.
- Startup and runtime errors are written to `sdl-error.log` in the settings folder.
- Input through an IME (Chinese, Japanese, Korean and others): the system draws the composition and the candidate window at the bottom line of the window (where the command line is); in the window itself the typed text appears after it is confirmed.
- File icons in the panels come from the desktop icon theme: the file type is determined from `/usr/share/mime`, the icon is looked up in the theme from `~/.config/gtk-3.0/settings.ini`, then in Adwaita, Yaru, breeze, Papirus and hicolor (`~/.local/share/icons`, `~/.icons`, `/usr/share/icons`). `libsdl2-image` is needed (without it only BMP is read, and the file type characters remain). The column is turned on by the "Show panel icons" checkbox in "Options – Font / Display...".
- Tabs with a picture that a plugin opens (image and video viewing) are shown as frames over the grid; keys reach the plugin. The mouse in the tab (press, drag, wheel, double click) and the size of the area reach the plugin, as on Windows. Native plugin windows (a window of its own on Windows) are not supported.
- Dragging files out of the window is not supported yet.
- Shortcut and icon: at startup the window writes `~/.local/share/applications/mtn2-sdl.desktop` and the icon `~/.local/share/icons/hicolor/256x256/apps/mtn2.png`, so the taskbar shows the window with its own name and icon rather than the default window manager icon. The window name (`StartupWMClass`, `app_id` on Wayland) is `mtn2-sdl`. A file marked `X-MTN2-Generated` is updated when the program is moved; a foreign file with that name is left alone. Writing is turned off with the environment variable `MTN2_NO_DESKTOP_ENTRY=1`; a program installed from a package does not write the shortcut (the package provides it). The same files are written by `install.sh` for the user and removed by `install.sh --uninstall`.
- In WSL, processes live as long as the distribution is running: a window started without an open WSL console must be started detached (`setsid nohup ./mtn2-sdl &`).

## What the terminal must provide

- UTF-8 and TrueColor (kitty, WezTerm, Alacritty, foot, GNOME Terminal, Konsole, Windows Terminal, iTerm2). In 256-color
  terminals the program picks the nearest colors itself, on 16 colors (the `linux` console) the nearest ones from the ANSI palette.
- An extended keyboard. At startup the program turns on the kitty keyboard protocol; a terminal that knows it
  (kitty, foot, Ghostty, Alacritty 0.13+, WezTerm with `enable_kitty_keyboard`) passes all combinations, including `Ctrl+Shift+...`, `Ctrl+;` and
  `Ctrl+Tab`, and on a non-Latin layout the combinations work by key, as on Windows. In the other terminals
  the xterm `modifyOtherKeys` mode is requested. If that is missing too, some combinations are unavailable: call the commands with
  `Ctrl+Shift` through the menu (`F9`).
- A terminal with the kitty protocol (kitty, foot, WezTerm, Ghostty, Alacritty) also reports the release of `Ctrl` and `Alt`:
  drive selection, quick search and the history list finish at the moment of release, as on Windows. The program turns these
  events on itself if the terminal answers the protocol query; `MTN2_NO_KEY_EVENTS=1` in the environment turns them off. In `mtn2-sdl`
  the release comes from SDL in any case.
- The other terminals do not pass key releases, so what on Windows lives while `Ctrl` or `Alt` is held
  finishes by itself: drive selection with `Ctrl+Left/Right` is applied 0.7 s after the last press, and quick
  search by `Alt` and the history list `Alt+Left/Right` close after 1.5 s or on any key without `Alt`.
- Mouse: presses, dragging and the wheel (SGR 1006 protocol). To select text with the terminal's own means, hold
  `Shift`.
- Clipboard: copying is sent to the terminal with the OSC 52 sequence. It is understood by Windows Terminal, mintty,
  WezTerm, kitty, iTerm2, Alacritty and most modern terminals; in `tmux` turn on `set -g set-clipboard on`.
  PuTTY does not handle the OSC 52 sequence: text selected in the program console does not reach the clipboard in it;
  hold `Shift` and select with PuTTY's own means (the window frames then end up in the selection) or turn off the
  program mouse with `Ctrl+Shift+M`: then the terminal itself selects and copies text. Without OSC 52 there is no fallback
  on the remote side: `tmux`, `wl-copy` and `xclip` help only where they exist and have somewhere to write
  (a `tmux` session or a graphical session). Text selected in the program
  console is copied with `Ctrl+Ins` or `Ctrl+C`. Paste is the regular terminal paste (`Ctrl+Shift+V`), it
  reaches the program as a "bracketed paste".
- Copying files: `Ctrl+C` and `Ctrl+X` on a panel put the list of files into the desktop clipboard through `wl-copy`
  (Wayland) or `xclip` (X11), so they can be pasted into Nautilus, Dolphin, Thunar and other file managers, and
  files copied there are pasted into a panel with `Ctrl+V`. Packages: `wl-clipboard` or `xclip`. Without them (and over
  SSH without a graphical environment) the list is passed only inside the program.

## What works

- Panels, tabs and workspaces, quick search, filter, selection by mask, directory comparison,
  synchronization, history and favorite folders.
- Mouse dragging from one panel to the other (in `mtn2-tui` and `mtn2-sdl`): a file row or the selection, highlighting of the panel or folder under the pointer, and on release the regular copy dialog opens; with `Shift` the move dialog. Dragging onto the same folder does nothing. Files can be dragged from archives and from servers too.
- Copying, moving, deleting, creating folders and links (symbolic and hard), checksums, file search.
- The "Attr" column shows permissions (`rwxr-xr-x`); files whose name starts with a dot are considered hidden.
- The "File attributes" command (`Ctrl+A`) opens the permissions dialog: the mode in octal notation (`0644`, `4755`) with a hint of the form `rw-r--r--`, owner and group, "Process subfolders". Only the changed fields go into the plan; changing the owner requires root rights. The same dialog has three file system flags, like `chattr`: immutable (`i`), append only (`a`) and do not back up (`d`); `i` and `a` require root rights, and a file system without flags (for example `tmpfs`) does not accept them.
- Drives: mount points from `/proc/self/mountinfo` (`F4` on a drive in the list shows the device, file system, size and mount options); quick folders: home, the XDG user directories,
  `/`, `/etc`, `/usr`, `/var`, `/opt`, `/tmp`, `/media`, `/mnt`.
- Trash according to the freedesktop.org specification: `~/.local/share/Trash` (`files` and `info`).
- Viewer, editor, Quick View, Markdown. The list refreshes when a directory changes, through inotify.
- The console folder carries over to the panel, and a command from the command line returns to the panels when it finishes (the "Always return to the panels when a command ends" option): the program reads the shell folder from `/proc`, and detects the end of the command by the shell being in the foreground again and the output going quiet.
- The console under the panels (`Ctrl+O`) and the terminals in tabs run on a real pseudo-terminal: bash, zsh, fish,
  `ssh` profiles. Shells are taken from `/etc/shells` and `$SHELL`; `Enter` on an executable file runs it in the console.
- Zip archives as folders, SFTP (the `sftp` client is needed).
- Plugins from the `plugins/` folder: `.so` libraries and WebAssembly modules (`libwasmtime.so` is needed, it sits next to the program).
  The `mtn.7z` plugin opens 7z, RAR, TAR, ISO and other archives as folders and packs into 7z through the 7-Zip program:
  install the `7zip` package (the `7zz` command) or `p7zip-full` (the `7z` command); without it the plugin reports that it
  cannot open archives.
- Lua macros (the `mtn.lua` plugin): key recording (`Ctrl+.`), running a macro by key or from the "Macros" menu, macro management. The Lua library is included in the archive and the packages; when building yourself the system one is needed (see "Requirements"). A macro sees only the keys the terminal passes (see "What the terminal must provide"): combinations the terminal does not distinguish cannot be recorded or assigned.
- Docker and Kubernetes (the `mtn.docker` plugin): containers, images and pods as `docker:///` folders with copying files back and forth, viewing logs and starting/stopping containers from the "Plugins" menu. The `docker` program (and `kubectl` for pods) must be in `PATH`.
- Metadata of the file under the cursor in the status line (the `mtn.meta` plugin): images, MP3. Executable file versions are Windows only.
- Document viewing (the `mtn.docview` plugin: docx, xlsx, pptx, svg, SQLite), CSV tables (the `mtn.csv` plugin) and PDF (the `mtn.pdf` plugin): F3 and Quick View. PDF is rendered by the PDFium library (`plugins/mtn.pdf/libpdfium.so` is included in the archive and the packages; when building yourself it is placed by `src/tools/fetch-pdfium.ps1 -Linux`). Without the library the PDF plugin gives way to the text view of the documents plugin.
- The Windows registry, processes and services (the `mtn.winsys` plugin) are not built on Linux.
- Images (png, jpeg, gif, bmp, webp and others that `chafa` understands) are shown in Quick View as colored blocks:
  the program calls `chafa --format=symbols` and outputs the result into the panel cells. The `chafa` package is needed; without it a hint
  appears in place of the image. An image from an archive or from a server (SFTP and others) is first copied to a temporary file (up to 32 MB).
- A file that has nothing to open it with in an environment without a desktop is opened in the built-in viewer; with
  a desktop (`DISPLAY` or `WAYLAND_DISPLAY`) through `xdg-open`.

## What is missing

- Native plugins written for Windows (`.dll`): on Linux the `.so` plugin libraries built for Linux work.
- File icons in the panels in `mtn2-tui` (a terminal has nothing to show them with; `mtn2-sdl` has them), dragging files into other programs, pictures and video
  that a plugin shows in a tab (they exist in `mtn2-sdl`), and plugin windows that the plugins draw themselves.
- Changing the font and scale (that is up to the terminal).
- Windows attributes (hidden, system, archive, creation date): the permissions dialog changes the mode, owner and group.

## Updating

"Help – Check for updates..." and the quiet check after startup work as on Windows: the package
`MTN2-<version>-linux-x64.tar.gz` of the latest release is taken, the checksum is verified, it is unpacked next to the program
and installed. Write access to the program folder and `tar` are needed. After installation the program restarts in the same
terminal. The version is taken from the `version` file next to the program.

In the `.deb` and `.rpm` packages self-update is turned off: an empty `no-self-update` file lies next to the program, the program does not contact GitHub at startup, and the "Check for updates..." command suggests updating the package with the package manager (`apt`, `dnf`) or installing a new package. To restore self-update, delete this file (the `/opt/mtn2` folder belongs to root, so `sudo` is needed; the package manager may later replace the updated files).

## Administrator rights

If an operation (copy, move, delete, create a folder, save a file) ends with an access denied error,
the program offers to repeat it as administrator. The password is asked for in the program window and passed to the command
`sudo -S -v`; the password itself is not stored, the `sudo` cache does the rest, and it also decides when the rights expire (then the password
is asked for again). Each operation is one `sudo` command (`rm`, `mkdir`, `cp`, `mv`, `cat`). `sudo` must be
installed and the account must be allowed to use it; as root there is no offer.

## Files

Settings are in `$XDG_CONFIG_HOME/mtn2` (by default `~/.config/mtn2`): `session.json`, `keymap.json`,
`themes/`, histories. Interface errors that did not stop the program are written to `tui-error.log` in the same place.
