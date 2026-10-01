# Темы: формат файла

Внешний вид MTN2 описывает файл темы `*.theme.json`. Один класс (`TDataTheme`) рисует любую тему; файл задаёт цвета, символы и начертания. Где стоят части виджетов (заголовок, кнопка закрытия, ползунок) – одинаково для всех тем и из файла не меняется.

## Где лежат темы

| Что | Где |
|---|---|
| Встроенные темы (только для чтения) | `src/Assets/themes/*.theme.json`, вшиты в exe (`THEME_<ID>`, `MTN2Resource.rc`) |
| Ваши темы | `<каталог настроек>\themes\<имя>.theme.json` (`%APPDATA%\MTN2\themes` или папка рядом с exe в портативном режиме) |

Идентификатор темы – имя файла без `.theme.json`; он хранится в `session.json` (поле `"theme"`). Если тема из сессии не найдена, программа показывает сообщение и включает классическую тему Far (`NDN`).

Темы создаются и правятся в диалоге **Настройки → Тема...**: «Настроить...» (изменить выбранную), «Создать...» (с нуля или на основе существующей), «Удалить». Встроенные темы не изменяются: настройка встроенной темы сохраняется в новый файл с выбранным именем.

## Наследование

Файл перечисляет только то, что задаёт сам; остальное берётся из тем, которые он расширяет (`"extends"`). Тема без `extends` расширяет `NDN`. `extends` – один идентификатор или список: `["Nord", "МояРаскраска"]`. Базы применяются по порядку, поздние перекрывают ранние, а значения самого файла – все базы; так тему можно собрать из частей (палитра из одной, раскраска файлов из другой, символы из третьей). Общая для двух баз тема учитывается один раз, под обеими. Если база не найдена или цепочка зациклена, вместо неё берётся `NDN`.

Роль цвета, которую не задал никто в цепочке, получает значение **роли-запасной** (столбец «Если не задано» ниже): тема, меняющая только цвета курсора, получает согласованные цвета флажков в фокусе и выделения в редакторе. Значение, заданное базовой темой явно, запасную роль перебивает.

## Ссылки и палитра

Цвет в файле – одно из трёх:

- литерал `#RRGGBB` или `#AARRGGBB`;
- имя из `palette`: `"accent"`. Имена наследуются – потомок может использовать имена базовой темы. Имя привязывается там, где записано: цвет, который назвала базовая тема, остаётся её цветом, даже если потомок определяет то же имя иначе;
- ссылка на роль той же темы `@группа.ключ`, например `"@cursor.bg"`: цвет следует за ролью и меняется вместе с ней (в том числе если роль берётся из запасной). Ссылки можно писать в ролях, в стилях Markdown и в цветах групп раскраски файлов.

Ссылка, которую нельзя разрешить (нет такой роли или имени, цикл), считается незаданной.

## Файл

```json
{
  "schema": 2,
  "name": "Моя тема",
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

| Ключ | Что это |
|---|---|
| `schema` | версия формата (сейчас `2`); файл с большей версией не загружается |
| `name` | название в списке тем |
| `extends` | идентификатор базовой темы или список идентификаторов |
| `palette` | именованные цвета; наследуются потомками, в итоговой теме остаются только цвета |
| `colors` | цвета по ролям: `группа` -> `ключ` -> цвет (литерал, имя из `palette` или `@роль`) |
| `markdown` | стиль элементов Markdown: `fg`, `bg` и `attrs` (список начертаний) для `text`, `h1`, `h2`, `h3to6`, `bold`, `italic`, `boldItalic`, `strike`, `inlineCode`, `codeBlock`, `quote`, `listMarker`, `hrule`, `link`, `imageMarker`, `tableBorder`, `tableHeader`. Элемент без `fg` / `bg` берёт цвета элемента `text` (а он – цвета окна); без `attrs` рисуется обычным текстом: подчёркивание ссылок, наклон курсива и зачёркивание задаёт тема |
| `attrs` | начертания: `windowTitle`, `dialogTitle`, `button`, `check`, `tab`, `toolbar`, `toolbarKey`, `status`, `menu`, `menuHot`, `clock`, `hot`, `hotFocus`; значение – список из `bold`, `italic`, `underline`, `strike`, `blink`, `reverse` (пустой список – обычный текст) |
| `glyphs` | строки и символы (ниже) |
| `frames` | набор символов рамки для `window`, `dialog`, `panelActive`, `panelIdle`: `single`, `double`, `ascii`, `rounded`, `heavy` или имя из `frameSets` |
| `frameSets` | свои наборы рамок: `{ "имя": { "tl": "+", "tr": "+", "bl": "+", "br": "+", "h": "-", "v": "|" } }` |
| `options.doubleActivePanel` | рисовать активную панель двойной рамкой; без ключа – если рамки активной и неактивной панели различаются |
| `fileColoring` | только те группы раскраски файлов, которые тема добавляет или меняет (маска и цвета для обычной строки, отмеченной и под курсором); сливаются с группами баз по полю `name` |
| `fileColoringOrder` | имена групп, которые идут первыми, в таком порядке (нужен, когда порядок отличается от порядка слияния); пишется редактором |

Правила раскраски сливаются по цепочке `extends` по полю `name`: группа с тем же именем заменяет базовую на её месте, новая добавляется в начало. Отключённая группа (`"enabled": false`) остаётся в списке, но не применяется – так тема «убирает» группу базовой. Редактор раскраски и редактор Markdown записывают в тему только отличия от баз, поэтому новые группы базовой темы доходят и до производных.

### Символы (`glyphs`)

| Ключ | Значение по умолчанию | Назначение |
|---|---|---|
| `checkOn`, `checkOff` | `[x] `, `[ ] ` | метка флажка (перед подписью) |
| `radioOn`, `radioOff` | `(*) `, `( ) ` | метка переключателя |
| `buttonNormal`, `buttonDefault` | `[ {0} ]`, `< {0} >` | подпись кнопки и кнопки по умолчанию; `{0}` – текст |
| `tabWorkspace`, `tabPanel` | `[{0}]`, ` {0} ` | подпись вкладки рабочей области и панели |
| `statusSeparator` | `│` | разделитель сегментов строки состояния (один символ) |
| `closeLeft`, `closeMark`, `closeRight` | `[`, `x`, `]` | кнопка закрытия окна (ширина всегда 3 клетки) |
| `desktopFill` | пробел | заполнение рабочего стола |
| `scrollUp`, `scrollDown`, `scrollLeft`, `scrollRight` | `▲ ▼ ◄ ►` | стрелки полосы прокрутки |
| `scrollShade`, `scrollBlock` | `░`, `█` | фон полосы и ползунок |

## Роли цветов

Ключ роли записывается как `группа.ключ` (`window.bg` – `colors.window.bg`). Столбец «Если не задано» – роль, значение которой берётся, когда ни один файл цепочки роль не задал; «–» означает, что роль обязана быть в базовой теме.


### Рабочий стол (`desktop`)

Фон за всеми окнами.

| Роль | Если не задано |
|---|---|
| `desktop.bg` | – |

### Окна (`window`)

Окна, рамки и заголовки, кнопка закрытия.

| Роль | Если не задано |
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

### Диалоги (`dialog`)

Тело, рамка и заголовок диалога; строки списков в диалогах.

| Роль | Если не задано |
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

### Кнопки (`button`)

Кнопки диалогов, обычные и в фокусе.

| Роль | Если не задано |
|---|---|
| `button.fg` | – |
| `button.bg` | – |
| `button.focusFg` | – |
| `button.focusBg` | – |
| `button.hotFg` | `dialog.hotFg` |
| `button.hotFocusFg` | `button.focusFg` |

### Флажки и переключатели (`check`)

Подписи флажков и переключателей.

| Роль | Если не задано |
|---|---|
| `check.fg` | `dialog.fg` |
| `check.bg` | `dialog.bg` |
| `check.hotFg` | `dialog.hotFg` |
| `check.focusFg` | `cursor.fg` |
| `check.focusBg` | `cursor.bg` |
| `check.focusHotFg` | `cursor.hotFg` |

### Курсор (`cursor`)

Строка под курсором в панели и в списках.

| Роль | Если не задано |
|---|---|
| `cursor.fg` | – |
| `cursor.bg` | – |
| `cursor.idleBg` | – |
| `cursor.hotFg` | `cursor.fg` |
| `cursor.markedFg` | `cursor.fg` |
| `cursor.markedBg` | `cursor.bg` |

### Отмеченные файлы (`mark`)

Цвет отмеченных строк и полоса фона.

| Роль | Если не задано |
|---|---|
| `mark.fg` | – |
| `mark.bg` | `window.bg` |
| `mark.bandFg` | `mark.fg` |
| `mark.bandBg` | – |

### Типы файлов (`file`)

Цвета имён по типу; `hidden*` – скрытые файлы.

| Роль | Если не задано |
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

### Строка состояния (`status`)

Строка состояния внизу окна и разделитель сегментов.

| Роль | Если не задано |
|---|---|
| `status.fg` | – |
| `status.bg` | – |
| `status.separator` | `status.fg` |

### Панель клавиш (`toolbar`)

Нижняя строка F1..F10.

| Роль | Если не задано |
|---|---|
| `toolbar.fg` | – |
| `toolbar.bg` | – |
| `toolbar.keyFg` | – |

### Строка меню (`menu`)

Верхняя строка меню и часы.

| Роль | Если не задано |
|---|---|
| `menu.fg` | `status.fg` |
| `menu.bg` | `status.bg` |
| `menu.hotFg` | `toolbar.keyFg` |
| `menu.clockFg` | `menu.fg` |

### Вкладки рабочих областей (`tab`)

Вкладки рабочих областей.

| Роль | Если не задано |
|---|---|
| `tab.activeFg` | – |
| `tab.activeBg` | – |
| `tab.normalFg` | – |
| `tab.normalBg` | – |

### Панели (`panel`)

Вкладки панелей, шапка колонок, метки.

| Роль | Если не задано |
|---|---|
| `panel.tabBarBg` | `window.bg` |
| `panel.tabActiveFg` | – |
| `panel.tabActiveBg` | – |
| `panel.tabNormalFg` | – |
| `panel.headerFg` | – |
| `panel.headerBg` | `window.bg` |
| `panel.hotMark` | `toolbar.keyFg` |
| `panel.closeMark` | `window.closeAccent` |

### Полосы прокрутки (`scroll`)

Полосы прокрутки.

| Роль | Если не задано |
|---|---|
| `scroll.fg` | – |
| `scroll.thumb` | – |

### Просмотр и редактор (`editor`)

Тело просмотрщика и редактора (F3 / F4).

| Роль | Если не задано |
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

## Как это устроено в коде

- `uThemeSpec.pas` – модель файла (`TThemeDoc`), разбор и запись JSON, разворачивание цепочки в полную тему (`TThemeSpec`).
- `uThemeRegistry.pas` – список тем, загрузка цепочки `extends`, сохранение и удаление пользовательских тем.
- `uDataTheme.pas` – `TDataTheme`, реализация `IThemeRenderer` по `TThemeSpec`.
- `uDualPanelThemeDialogs.pas` – диалоги выбора и редактирования тем.
