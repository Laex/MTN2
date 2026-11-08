# Themes: file format

**English** | [Русский](THEMES.ru.md)

The look of MTN2 is described by a theme file `*.theme.json`. One class (`TDataTheme`) draws any theme; the file sets colors, glyphs and text styles. Where the parts of the widgets sit (the title, the close button, the scroll thumb) is the same for all themes and cannot be changed from the file.

## Where themes live

| What | Where |
|---|---|
| The root theme `NDN` (read-only) | embedded in the exe (`THEME_NDN`, source `src/Assets/themes/NDN.theme.json`) |
| Bundled themes (read-only) | `resource\themes\<Id>.theme.json` next to the exe |
| Your themes | `<settings folder>\themes\<name>.theme.json` (`%APPDATA%\MTN2\themes` or the folder next to the exe in portable mode) |

The bundled themes are kept apart from yours: updating the program replaces `resource\`, while your files stay in the settings folder. If your file has the same name as a built-in or bundled theme (for example `Nord.theme.json`), it is ignored: rename it. To add a theme for all copies of the program, just put the file in `resource\themes\`.

The theme identifier is the file name without `.theme.json`; it is stored in `session.json` (the `"theme"` field). If the theme from the session is not found, the program shows a message and switches to the classic Far theme (`NDN`).

Themes are created and edited in the **Options → Theme...** dialog: "Customize..." (change the selected one), "New..." (from scratch or based on an existing one), "Delete". Built-in themes are not modified: customizing a built-in theme is saved to a new file with the chosen name.

## Inheritance

A file lists only what it sets itself; the rest comes from the themes it extends (`"extends"`). A theme without `extends` extends `NDN`. `extends` is a single identifier or a list: `["Nord", "MyColors"]`. The bases are applied in order, later ones override earlier ones, and the values of the file itself override all the bases; this way a theme can be assembled from parts (the palette from one, file coloring from another, glyphs from a third). A theme shared by two bases is counted once, under both. If a base is not found or the chain is circular, `NDN` is used in its place.

A color role that nobody in the chain has set gets the value of the **fallback role** (the "If not set" column below): a theme that changes only the cursor colors gets consistent colors for focused checkboxes and for the selection in the editor. A value set explicitly by a base theme overrides the fallback role.

## References and palette

A color in the file is one of three things:

- a literal `#RRGGBB` or `#AARRGGBB`;
- a name from `palette`: `"accent"`. Names are inherited – a descendant can use the names of the base theme. A name is bound where it is written: a color named by the base theme stays the base theme's color, even if the descendant defines the same name differently;
- a reference to a role of the same theme `@group.key`, for example `"@cursor.bg"`: the color follows the role and changes together with it (including when the role comes from a fallback). References can be written in roles, in Markdown styles and in the colors of file coloring groups.

A reference that cannot be resolved (no such role or name, a cycle) is treated as not set.

## File

```json
{
  "schema": 2,
  "name": "My theme",
  "extends": ["Nord"],
  "palette": { "accent": "#88C0D0" },
  "colors": {
    "window": { "borderFocus": "accent", "bg": "#101820" },
    "cursor": { "bg": "accent" },
    "status": { "bg": "@cursor.bg" }
  },
  "markdown": { "h1": { "fg": "accent", "attrs": ["bold", "underline"] } },
  "attrs": { "button": ["bold"] },
  "glyphs": { "checkOn": "[x] ", "scrollBlock": "#" },
  "frames": { "window": "rounded", "panelActive": "double" },
  "options": { "doubleActivePanel": true },
  "fileColoring": [ { "name": "Archives", "mask": "*.zip;*.7z", "normal": { "fg": "@cursor.bg" } } ],
  "fileColoringOrder": ["Archives"]
}
```

| Key | What it is |
|---|---|
| `schema` | format version (currently `2`); a file with a greater version is not loaded |
| `name` | name in the theme list |
| `extends` | identifier of the base theme or a list of identifiers |
| `palette` | named colors; inherited by descendants, only colors remain in the resulting theme |
| `colors` | colors by role: `group` -> `key` -> color (a literal, a name from `palette` or `@role`) |
| `markdown` | style of Markdown elements: `fg`, `bg` and `attrs` (a list of text styles) for `text`, `h1`, `h2`, `h3to6`, `bold`, `italic`, `boldItalic`, `strike`, `inlineCode`, `codeBlock`, `quote`, `listMarker`, `hrule`, `link`, `imageMarker`, `tableBorder`, `tableHeader`. An element without `fg` / `bg` takes the colors of the `text` element (which takes the window colors); without `attrs` it is drawn as plain text: the underline of links, the slant of italics and the strikethrough are set by the theme |
| `attrs` | text styles: `windowTitle`, `dialogTitle`, `button`, `check`, `tab`, `toolbar`, `toolbarKey`, `status`, `menu`, `menuHot`, `clock`, `hot`, `hotFocus`; the value is a list of `bold`, `italic`, `underline`, `strike`, `blink`, `reverse` (an empty list is plain text) |
| `glyphs` | strings and characters (below) |
| `frames` | the frame character set for `window`, `dialog`, `panelActive`, `panelIdle`: `single`, `double`, `ascii`, `rounded`, `heavy` or a name from `frameSets` |
| `frameSets` | custom frame sets: `{ "name": { "tl": "+", "tr": "+", "bl": "+", "br": "+", "h": "-", "v": "|" } }` |
| `options.doubleActivePanel` | draw the active panel with a double frame; without the key – if the frames of the active and inactive panel differ |
| `fileColoring` | only the file coloring groups that the theme adds or changes (a mask and colors for a regular row, a marked row and the row under the cursor); merged with the groups of the bases by the `name` field |
| `fileColoringOrder` | names of the groups that go first, in that order (needed when the order differs from the merge order); written by the editor |

Coloring rules are merged along the `extends` chain by the `name` field: a group with the same name replaces the base one in its place, a new one is added to the beginning. A disabled group (`"enabled": false`) stays in the list but is not applied – this is how a theme "removes" a group of the base. The coloring editor and the Markdown editor write to the theme only the differences from the bases, so new groups of the base theme reach the derived ones too.

### Glyphs (`glyphs`)

| Key | Default | Purpose |
|---|---|---|
| `checkOn`, `checkOff` | `[x] `, `[ ] ` | checkbox mark (before the label) |
| `radioOn`, `radioOff` | `(*) `, `( ) ` | radio button mark |
| `buttonNormal`, `buttonDefault` | `[ {0} ]`, `< {0} >` | label of a button and of the default button; `{0}` is the text |
| `tabWorkspace`, `tabPanel` | `[{0}]`, ` {0} ` | label of a workspace tab and of a panel tab |
| `statusSeparator` | `│` | separator of the status line segments (one character) |
| `closeLeft`, `closeMark`, `closeRight` | `[`, `x`, `]` | window close button (the width is always 3 cells) |
| `desktopFill` | space | desktop fill |
| `scrollUp`, `scrollDown`, `scrollLeft`, `scrollRight` | `▲ ▼ ◄ ►` | scroll bar arrows |
| `scrollShade`, `scrollBlock` | `░`, `█` | scroll bar background and thumb |

## Color roles

A role key is written as `group.key` (`window.bg` is `colors.window.bg`). The "If not set" column is the role whose value is taken when no file in the chain has set the role; "–" means the role must be present in the base theme.


### Desktop (`desktop`)

The background behind all windows.

| Role | If not set |
|---|---|
| `desktop.bg` | – |

### Windows (`window`)

Windows, frames and titles, the close button.

| Role | If not set |
|---|---|
| `window.fg` | – |
| `window.bg` | – |
| `window.borderFocus` | – |
| `window.borderNormal` | – |
| `window.titleFgFocus` | – |
| `window.titleBgFocus` | – |
| `window.titleFgNormal` | – |
| `window.titleBgNormal` | – |
| `window.closeAccent` | – |

### Dialogs (`dialog`)

The body, frame and title of a dialog; list rows in dialogs.

| Role | If not set |
|---|---|
| `dialog.fg` | – |
| `dialog.bg` | – |
| `dialog.border` | – |
| `dialog.hotFg` | – |
| `dialog.titleFg` | `window.titleFgFocus` |
| `dialog.titleBg` | `window.titleBgFocus` |
| `dialog.rowFg` | `dialog.fg` |
| `dialog.rowBg` | `dialog.bg` |
| `dialog.rowCursorFg` | `cursor.fg` |
| `dialog.rowCursorBg` | `cursor.bg` |
| `dialog.listBg` | slightly lighter or darker than `dialog.rowBg`: 10% of the `dialog.rowFg` color is mixed into it |

### Buttons (`button`)

Dialog buttons, regular and focused.

| Role | If not set |
|---|---|
| `button.fg` | – |
| `button.bg` | – |
| `button.focusFg` | – |
| `button.focusBg` | – |
| `button.hotFg` | `dialog.hotFg` |
| `button.hotFocusFg` | `button.focusFg` |

### Checkboxes and radio buttons (`check`)

Labels of checkboxes and radio buttons.

| Role | If not set |
|---|---|
| `check.fg` | `dialog.fg` |
| `check.bg` | `dialog.bg` |
| `check.hotFg` | `dialog.hotFg` |
| `check.focusFg` | `cursor.fg` |
| `check.focusBg` | `cursor.bg` |
| `check.focusHotFg` | `cursor.hotFg` |

### Cursor (`cursor`)

The row under the cursor in a panel and in lists.

| Role | If not set |
|---|---|
| `cursor.fg` | – |
| `cursor.bg` | – |
| `cursor.idleBg` | – |
| `cursor.hotFg` | `cursor.fg` |
| `cursor.markedFg` | `cursor.fg` |
| `cursor.markedBg` | `cursor.bg` |

### Marked files (`mark`)

The color of marked rows and the background band.

| Role | If not set |
|---|---|
| `mark.fg` | – |
| `mark.bg` | `window.bg` |
| `mark.bandFg` | `mark.fg` |
| `mark.bandBg` | – |

### File types (`file`)

Name colors by type; `hidden*` are hidden files.

| Role | If not set |
|---|---|
| `file.dir` | – |
| `file.archive` | – |
| `file.executable` | – |
| `file.media` | – |
| `file.plain` | `window.fg` |
| `file.hidden` | – |
| `file.hiddenDir` | `file.hidden` |
| `file.hiddenArchive` | `file.hidden` |
| `file.hiddenExecutable` | `file.hidden` |
| `file.hiddenMedia` | `file.hidden` |
| `file.hiddenPlain` | `file.hidden` |

### Status line (`status`)

The status line at the bottom of the window and the segment separator.

| Role | If not set |
|---|---|
| `status.fg` | – |
| `status.bg` | – |
| `status.separator` | `status.fg` |

### Key bar (`toolbar`)

The bottom row F1..F10.

| Role | If not set |
|---|---|
| `toolbar.fg` | – |
| `toolbar.bg` | – |
| `toolbar.keyFg` | – |

### Menu bar (`menu`)

The top menu row and the clock.

| Role | If not set |
|---|---|
| `menu.fg` | `status.fg` |
| `menu.bg` | `status.bg` |
| `menu.hotFg` | `toolbar.keyFg` |
| `menu.clockFg` | `menu.fg` |

### Workspace tabs (`tab`)

Workspace tabs.

| Role | If not set |
|---|---|
| `tab.activeFg` | – |
| `tab.activeBg` | – |
| `tab.normalFg` | – |
| `tab.normalBg` | – |

### Panels (`panel`)

Panel tabs, the column header, marks, the letter of the current drive in the bottom frame of a panel.

| Role | If not set |
|---|---|
| `panel.tabBarBg` | `window.bg` |
| `panel.tabActiveFg` | – |
| `panel.tabActiveBg` | – |
| `panel.tabNormalFg` | – |
| `panel.headerFg` | – |
| `panel.headerBg` | `window.bg` |
| `panel.hotMark` | `toolbar.keyFg` |
| `panel.closeMark` | `window.closeAccent` |
| `panel.driveCurFg` | `panel.tabActiveFg` |
| `panel.driveCurBg` | `panel.tabActiveBg` |

### Scroll bars (`scroll`)

Scroll bars.

| Role | If not set |
|---|---|
| `scroll.fg` | – |
| `scroll.thumb` | – |

### Viewer and editor (`editor`)

The body of the viewer and editor (F3 / F4).

| Role | If not set |
|---|---|
| `editor.bodyFg` | `window.fg` |
| `editor.bodyBg` | `window.bg` |
| `editor.cursorFg` | `cursor.fg` |
| `editor.cursorBg` | `cursor.bg` |
| `editor.selFg` | `cursor.fg` |
| `editor.selBg` | `cursor.bg` |
| `editor.hintFg` | `toolbar.keyFg` |
| `editor.statusFg` | `status.fg` |
| `editor.statusBg` | `status.bg` |
| `editor.frameFocus` | `window.borderFocus` |
| `editor.frameIdle` | `window.borderNormal` |
| `editor.scrollFg` | `scroll.fg` |
| `editor.scrollThumb` | `scroll.thumb` |
| `editor.matchFg` | `cursor.fg` |
| `editor.matchBg` | `cursor.bg` |
| `editor.lineBg` | `editor.bodyBg` |

## How it is built in code

- `uThemeSpec.pas` – the file model (`TThemeDoc`), JSON parsing and writing, expanding the chain into a complete theme (`TThemeSpec`).
- `uThemeRegistry.pas` – the theme list, loading the `extends` chain, saving and deleting user themes.
- `uDataTheme.pas` – `TDataTheme`, the `IThemeRenderer` implementation over `TThemeSpec`.
- `uDualPanelThemeDialogs.pas` – the dialogs for choosing and editing themes.
