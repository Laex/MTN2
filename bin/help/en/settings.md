## Settings

The **Options** menu (F9):
- **Theme...** – appearance; changes at once.
- **Font / Display...** – font, size, zoom, cursor blinking, file icons in the panel, **line spacing** (see below), pop-up notifications, window and button **shadows** (Classic, Soft or None; the dimming behind a dialog is lightened or dropped with them), how **marked files** look (“Text color” – only the letters change colour, as in Far; “Row background” – a background band across the whole row as well) and the **interface language** (English / Русский); everything applies without a restart.
- **Columns...** – the columns of the “Custom” mode.
- **Color coding...** – row colors by name masks.
- **Keymap...** – view and change keys.
- **Plugins...** – installed plugins.
- **External viewer/editor...** – the Alt+F3 / Alt+F4 commands; `%1` is the file path (without `%1` the path is added at the end), e.g. `"C:\Program Files\Notepad++\notepad++.exe" %1`.
- **Zoom**: Ctrl+mouse wheel, **Ctrl+0** – reset.

### Font and line spacing

The **Line spacing (as in a terminal)** checkbox in **Options → Font / Display...** makes rows 15% of the font size taller; the text stays centred in the row, frames and highlights stretch over its whole height. It is off by default: rows are as tall as the font's line, and more of them fit on the screen. For Cascadia Mono 11 pt that is 17 pixels without spacing and 19 with it – the same as in Windows Terminal.

Font size is in typographic points, as in Windows Terminal and the Windows console: 6 to 24 pt, in half-point steps from 8 to 12 pt. At 100% Windows scaling 1 pt = 4/3 pixel: 10.5 pt is 14 pixels (the former default), 11 pt is 14.7 pixels.

#### Why text looks different from Far

Far does not draw its text itself: the console window it runs in does – Windows Terminal or the classic Windows console – with its own font and rules. Compared with the same font, size and colours, MTN2 and Far draw the same letters: stroke weight and antialiasing match. The differences come from settings:
- **Font and size.** Windows Terminal defaults to Cascadia Mono 11 pt. MTN2 uses the font and size from Font / Display (Cascadia Mono if installed, otherwise Consolas; 10.5 pt). Narrow, light fonts such as Ubuntu Mono look thinner and paler, especially on blue.
- **Row height.** Windows Terminal adds about 15% of the font size to the font's line. In MTN2 that is the Line spacing checkbox; without it rows are tighter. The classic Windows console takes the row height from the font's Windows metrics, which can be another 1–3 pixels taller (Cascadia Mono 11 pt – 20 pixels).
- **Colours.** MTN2's colours come from its theme; Far's from its own highlighting and the terminal's colour scheme. In the default theme plain files are light grey; in Far they are usually cyan, with twice the contrast on blue, so the text looks bolder.
- **Antialiasing.** MTN2 uses greyscale antialiasing. So does Windows Terminal when the profile's `antialiasingMode` is `grayscale` (the default); with `cleartype` letters get coloured fringes. The classic Windows console uses ClearType when it is on in Windows.
- **Windows scaling.** Both draw text in physical screen pixels, so it is equally sharp at 125% and 150%.

#### When they match

MTN2 matches Far in Windows Terminal in cell size, stroke weight and row height when:
- the font is the same (Windows Terminal's default is Cascadia Mono);
- the size is the same (Windows Terminal's default is 11 pt);
- Line spacing (as in a terminal) is on;
- the Windows Terminal profile uses `grayscale` antialiasing;
- MTN2's theme and Far use similar colours.

With the classic Windows console (Far without Windows Terminal) they will not match exactly: its row height and ClearType are its own.

### Notifications

Commands that change nothing on screen confirm themselves with a short notice in the bottom right corner; it disappears after a few seconds and does not take keys. Notices appear for:
- **Ctrl+Alt+Ins** / **Alt+Shift+Ins** – the path / name copied (or “Nothing to copy”);
- **Ctrl+C** / **Ctrl+X** (**Ctrl+Ins** / **Ctrl+Del**) on the panel – the files placed on the clipboard;
- copying text in the viewer / editor (without a selection – the current line), in the command line and in a terminal;
- **Ctrl+R** – the panel refreshed;
- **Ctrl+Shift+O** – the folder the console went to;
- **Ctrl+Alt+R** – the item restored from the Recycle Bin;
- **Ctrl+Alt+D** – the folder added to the hotlist;
- selection by mask (**Gray +/−**, **Ctrl+Gray +/−**, **Alt+Gray +/−**) that changed nothing – shown in red.

Notices are turned off in **Options → Font / Display...** (“Show pop-up notifications”). The update-check notice is the exception: it has its own checkbox (see [Updates](updates.md)).

### Updates

Checking for and installing new versions, their settings and what goes over the network are on the [Updates](updates.md) page.

---

[Contents](index.md)
