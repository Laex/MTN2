# Language packs

**English** | [Русский](LANGUAGE_PACKS.ru.md)

Only English is built into `MTN2.exe`. Every other interface language is a folder (a language pack) next to the program, so a language can be added, replaced or removed without rebuilding. A pack does not have to be part of the repository or of a release: unpack it into `resource\` and it is picked up.

## Layout

```
MTN2.exe
resource\
  uk\                  <- the language pack, the folder name is the language code
    locale.json        <- required: pack version and display name
    strings.json       <- required: key -> translated text
    help\              <- optional: F1 topics (Markdown)
      index.md
      ...
```

On Linux the same folder is `resource/<code>/` next to the program.

## Folder name

- Lower case, the language code in the BCP 47 style: `uk`, `pl`, `pt-br`. The program lower-cases the name it looks up, so on Linux a folder with capital letters is not found.
- On the first start the language is taken from the OS interface language: `uk-UA` is tried as is, then shortened to `uk`. A folder named `ua` (a country code, not a language code) is a valid pack but is never selected automatically.

## locale.json

```json
{
  "version": 1,
  "name": "Українська"
}
```

- `version` – required, a JSON **number** (`1`, not `"1"`): the revision of the key set the pack was written for. Take it from the packs shipped with the program (`resource\de\locale.json`); the repository keeps the current value in `src/resource.version`.
  - equal to the program's value – the pack is applied;
  - lower – the pack is applied, keys it lacks show English text;
  - higher – the pack is ignored and not offered in the language list.
- `name` – the name shown in the language list. Without it the list shows the upper-cased folder name (`UK`).

A pack with a missing or unreadable `locale.json` is ignored.

## strings.json

A UTF-8 file (a BOM is allowed). Keys are the same as in the template [`src/strings/en.json`](../src/strings/en.json) (every key next to its English text; copy it and translate the values). Two equivalent forms:

```json
{ "dialogs": { "DIALOG_ABOUT": { "$title": "Про MTN2" } } }
```

```json
{ "dialogs.DIALOG_ABOUT.$title": "Про MTN2" }
```

Rules:

- A key that is missing stays English; a partial translation is fine. Unknown keys and values that are not strings are skipped.
- A file that is not valid JSON does not stop the program: the pack is listed, but every text stays English. Check the syntax in an editor or with `python -m json.tool strings.json`.
- Keep the placeholders (`%s`, `%d`, `%1`, `{0}`) in the same number as in the English text; a translation whose placeholders do not fit is replaced by the English text.
- The `&` before a letter marks the hotkey of a menu item and works in any keyboard layout; keep one in translations of menu entries.
- Multi-column list headers (the `*Header` and `header` keys) are aligned with data rows that the program positions itself: start every column at the same offset as in English and fit before the next one.
- Optional `menu.alias.<action>` keys add search words in your language to the command palette (Shift+F9).
- Keys starting with `//` are free-form comments.

## help\

The F1 topics are Markdown files; the layout is [`bin/win64/resource/en/help`](../bin/win64/resource/en/help) (`index.md` is the title page with the table of contents). If the pack has no `help\index.md`, F1 shows the whole help in English. The help is optional, so a pack can be released with the interface strings only and get its help later.

## Installing and checking

1. Copy the folder (for example `uk`) into `resource\` next to `MTN2.exe`.
2. Choose the language in the settings; the change is applied without a restart. A newly copied folder is found the next time the language list opens.
3. `MTN2.exe --self-check` prints one line per pack file: `OK` for a usable pack, `WARN` for an older `version`, `FAIL` for a missing or invalid `locale.json`, a newer `version` or a missing `strings.json`. Without `help\index.md` it also prints `FAIL`: that line only means "no translated help", the pack itself works. The check does not parse `strings.json`.

## Distributing a pack

An archive with the pack folder (`uk\locale.json`, `uk\strings.json`, optionally `uk\help\`) is enough: the recipient unpacks it into `resource\`. Plugins are translated separately, with `plugins\<id>\resource\<code>\` packs of the same layout ([PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md)).

## Installing a pack by hand

1. No restart is needed. Unpack the archive (or copy the folder) so that the pack lands next to `MTN2.exe`:
   - the program's own strings: `resource\<code>\`;
   - a plugin's strings, one folder per plugin that should be translated: `plugins\<id>\resource\<code>\` (for example `plugins\mtn.git\resource\uk\`). A plugin without a pack in the chosen language stays in English.
2. Open the language list in the settings (it is read each time it opens) and choose the new language.
3. Check the result with `MTN2.exe --self-check`.

To remove a language, delete its folders from `resource\` and from the plugin folders; if it was the current language, the program falls back to English.

In Linux the same folders are `resource/<code>/` and `plugins/<id>/resource/<code>/` next to the program.

A pack can also be added to the repository (`bin/win64/resource/<code>/`) and then ships with the program; agree on the language in the issue first so the work is not duplicated.
