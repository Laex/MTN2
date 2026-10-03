## Settings

The **Options** menu (F9):
- **Theme...** – pick the appearance; changes at once. **Customize...** opens the editor of the selected theme: sections (colors of windows, dialogs, buttons, cursor, panels and more, Markdown, text styles, glyphs, frames) with their values; **Enter** on a row edits the value (a color is typed as `#RRGGBB` or picked with **F9** / the **[...]** button), **Inherit** returns the value of the base theme; rows with an asterisk are set by the theme itself. A color is a `#RRGGBB` value, a reference to another role of the theme (`@cursor.bg`) or a name from the palette. The **Bases** section lists the themes this one builds on (several separated by `;`, later ones override earlier ones). Changes show at once. **Save** writes the theme to a file. Built-in themes are read-only: a copy of a built-in theme is saved under a new name (a file in the `themes` folder of the settings folder), your own theme is updated in place by **Save**, and **Save as...** writes it under another name. **New...** makes a theme from scratch ("blank") or from any other one. **Delete** removes your own theme. If the theme of the saved session is not found, the program says so and uses the classic Far theme.
- **Font / Display...** – font, size, zoom, cursor blinking, file icons in the panel, **line spacing** (see below), pop-up notifications, the **window title bar, menu bar, F-key bar and status line** (a hidden row goes to the panels; with the menu bar hidden, F9 shows it over the top row while the menu is open; with the window title bar hidden the **[_] [□] [x]** buttons move to the right end of the menu bar, or of the tab bar when that is hidden too, the window title is shown in the free space of the tab bar, and the window is dragged by the free parts of the menu and tab bars and resized by its edges; a right click on a free spot of the tab bar opens the top menu, like F9), window and button **shadows** (Classic, Soft or None; the dimming behind a dialog is lightened or dropped with them), how **marked files** look (“Text color” – only the letters change colour, as in Far; “Row background” – a background band across the whole row as well) and the **interface language** (English / Русский); everything applies without a restart. The **“Select all also folders”** box in the same dialog makes Shift+Gray + / Shift+Gray − and select by extension take folders too (files only by default, as in Far).
- **Columns...** – the columns of the “Custom” mode.
- **Console...** – the scrollback size of the console and terminals, confirmation of a multi-line paste, removal of trailing spaces on copy and paste (more in the command line help).
- **Export settings... / Import settings...** – the settings as one zip file: the session and display options, keys, user menu, associations, hotlist, SSH connection list, workspaces, own themes; histories are not included. The file name field is an input with a ↓ drop-down of the files used before; by default it is `mtn2-settings.zip` in the folder of the active panel. Before an import the replaced files are saved as `settings-backup.zip` in the settings folder. The new settings take effect after MTN2 restarts.
- **Color coding...** – row colors by name masks; they are stored in the theme, so an edit made with a built-in theme is saved as a new theme (the program asks for its name). **F9** on a color field, or a click on the **[...]** button at its right end (it shows the field's color), opens the color picker (see below).
- **Keymap...** – view and change keys.
- **Plugins...** – installed plugins.
- **External viewer/editor...** – the Alt+F3 / Alt+F4 commands; `%1` is the file path (without `%1` the path is added at the end), e.g. `"C:\Program Files\Notepad++\notepad++.exe" %1`.
- **Markdown colors...** – colors of the Markdown view (F3 on a `.md` file): a foreground and a background (`#RRGGBB`) and a **text style** (the list: Theme, Plain, Bold, Italic, Bold italic, Underline, Strikethrough and combinations) for every element – headings, bold, italic, strikethrough, code, quote, list markers, rules, links, tables. An empty field or **Theme** in the style list keeps the theme's own; **Plain** turns off the style the element has (for example the underline of links); **F9** on a field or a click on its **[...]** button opens the color picker. The **Text / document** row sets the text color and the background of the whole Markdown view (only for Markdown, other files keep the theme colors); elements without a background of their own follow it. **Import from Obsidian...** reads the colors from an Obsidian theme (`theme.css`, for example `<vault>\.obsidian\themes\<theme>\theme.css`); the **Dark** or **Light** palette is picked in the import dialog, and the imported colors and text styles (weight, italic and underline the theme sets for headings, bold, links, quotes and table headers) replace the fields and lists (nothing is saved until OK). **Reset** empties all fields and sets every style to **Theme**, so the theme's own colors and styles apply. The sample next to a row is drawn with its colors and style. Stored in the active theme: with a built-in theme the program asks for the name of a new theme, your own theme is updated in place; the fields hold only what the theme sets itself (the rest is inherited).
- **Zoom**: Ctrl+mouse wheel, **Ctrl+0** – reset.

### Color picker

The picker has a grid of swatches (hues across, light to dark down; the bottom row is gray), sliders **H, S, L** (hue, saturation, lightness) and **R, G, B**, and a **Hex** field next to two swatches: the color **was** when the picker opened and the color **now**. **Up / Down** switch between the grid, the sliders and the hex field; **Left / Right** move along the grid or change a slider by 1 (**Shift** – by 10, **PgUp / PgDn** – by 10, **Home / End** – to the ends). The grid uses the current saturation, so the **S** slider makes it paler or more vivid. A mouse click picks a swatch or sets a slider; a click on the **was** swatch returns to the original color. **Use** takes the color, **Theme color** clears the field so the theme's color applies again.

### Font and line spacing

The **Line spacing (as in a terminal)** checkbox in **Options → Font / Display...** makes rows 15% of the font size taller; the text stays centred in the row, frames and highlights stretch over its whole height. It is off by default: rows are as tall as the font's line, and more of them fit on the screen. For Cascadia Mono 11 pt that is 17 pixels without spacing and 19 with it – the same as in Windows Terminal.

Font size is in typographic points, as in Windows Terminal and the Windows console: 6 to 24 pt, in half-point steps from 8 to 12 pt. At 100% Windows scaling 1 pt = 4/3 pixel: 10.5 pt is 14 pixels (the former default), 11 pt is 14.7 pixels.

Two more options in the same dialog make the text crisper:
- **Snap font size to device pixels** rounds the letter size to whole physical screen pixels. With 125% or 150% Windows scaling and fractional sizes (11 pt) the strokes then have an equal weight. The cell size can change slightly. Off by default.
- **Text contrast** (Off, Low, Medium, High) fills in the faint anti-aliased fringe: thin light text on a dark background reads firmer. Off by default.
- **Cell width** and **Cell height** add 0 to 4 physical pixels to every cell. They help a font whose letters touch or whose rows sit too tight. Letters stay centred in the cell, frames fill it completely. 0 by default.

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
- **Alt+Shift+Ins** / **Ctrl+Shift+Ins** – the path / name copied (or “Nothing to copy”);
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
