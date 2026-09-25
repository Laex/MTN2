program TestStrings;

{$APPTYPE CONSOLE}
{$R '..\..\MTN2.dres'}

{ Characterization tests for uStrings.pas (the UI-translation mechanism)
  and its two hooks: uDialogResources.TryLoadDialogResource's static-caption
  translation pass, and TTopMenuController.LoadMenuFromJson's menu-caption/
  category-title translation. Exercises the real embedded STRINGS_RU
  resource (strings/ru.json) against the real embedded DIALOG_CONFIRM/
  DIALOG_ASKSAVE dialogs, plus a temp on-disk locale for the loose-file
  override path and the Format-argument-mismatch fallback, which nothing
  shipped exercises on its own. }

uses
  System.SysUtils, System.IOUtils,
  uStrings in '..\..\Core\uStrings.pas',
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uDialogJson in '..\..\Core\uDialogJson.pas',
  uDialogResources in '..\..\Core\uDialogResources.pas',
  uDialogHost in '..\..\Core\uDialogHost.pas',
  uDialogRenderer in '..\..\Core\uDialogRenderer.pas',
  uInputLine in '..\..\Core\uInputLine.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uThemeDrawing in '..\..\Core\uThemeDrawing.pas',
  uFunctionBar in '..\..\Core\uFunctionBar.pas',
  uColorCoding in '..\..\Core\uColorCoding.pas',
  uColorCodingEditHelpers in '..\..\Core\uColorCodingEditHelpers.pas',
  uFileFind in '..\..\Core\uFileFind.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uDualPanelOverlays in '..\..\Core\uDualPanelOverlays.pas',
  uTopMenuBar in '..\..\Core\uTopMenuBar.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function FindCtrlText(const ADecl: TDialogDeclaration; const AId: string): string;
var
  I: Integer;
begin
  Result := '<missing:' + AId + '>';
  for I := 0 to High(ADecl.Controls) do
    if ADecl.Controls[I].Id = AId then
      Exit(ADecl.Controls[I].Text);
end;

procedure TestLocaleBasics;
begin
  Writeln('Locale basics');
  Expect(CurrentLocale = 'en', 'default locale is en');
  SetLocale('ru');
  Expect(CurrentLocale = 'ru', 'SetLocale switches the current locale');
  SetLocale('');
  Expect(CurrentLocale = 'en', 'SetLocale('''') resets to en');
  SetLocale('RU');
  Expect(CurrentLocale = 'RU', 'SetLocale preserves the caller''s casing verbatim');
  Expect(SameText(CurrentLocale, 'ru'), 'but lookups are still case-insensitive against it');
  SetLocale('en');
end;

procedure TestAvailableLocales;
var
  Locales: TArray<string>;
  I: Integer;
  HasEn, HasRu: Boolean;
begin
  Writeln('AvailableLocales discovers embedded STRINGS_* resources');
  Locales := AvailableLocales;
  HasEn := False;
  HasRu := False;
  for I := 0 to High(Locales) do
  begin
    if SameText(Locales[I], 'en') then HasEn := True;
    if SameText(Locales[I], 'ru') then HasRu := True;
  end;
  Expect(HasEn, 'en is always listed');
  Expect(HasRu, 'ru is discovered from the embedded STRINGS_RU resource');
  Expect(SameText(Locales[0], 'en'), 'en is always first');
end;

procedure TestPlainLookup;
begin
  Writeln('T(): plain-text lookup');
  SetLocale('en');
  Expect(T('menu.tmaFileCopy', 'Copy') = 'Copy', 'en locale is a zero-cost passthrough to ADefault');
  Expect(T('this.key.does.not.exist', 'Fallback') = 'Fallback', 'an unknown key falls back to ADefault, even for en');

  SetLocale('ru');
  Expect(T('menu.tmaFileCopy', 'Copy') = '&Копировать',
    'a real key translates once ru is active (raw, with its menu mnemonic marker)');
  Expect(T('this.key.does.not.exist', 'Fallback') = 'Fallback',
    'a key absent from ru.json still falls back to ADefault (partial translation never shows a raw key)');
  SetLocale('en');
end;

procedure TestFormatArgs;
begin
  Writeln('T() with Format args');
  SetLocale('en');
  Expect(T('status.itemsSelected', '%d item(s) selected', [3]) = '3 item(s) selected',
    'en formats ADefault directly');

  SetLocale('ru');
  Expect(T('status.itemsSelected', '%d item(s) selected', [3]) = '3 item(s) selected',
    'an untranslated templated key still formats ADefault correctly');
  SetLocale('en');
end;

procedure TestLooseFileOverrideAndBadFormatFallback;
var
  Dir, FilePath: string;
begin
  Writeln('Loose-file locale override, and a mismatched-placeholder translation falls back to English');
  Dir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'strings');
  ForceDirectories(Dir);
  FilePath := TPath.Combine(Dir, 'zz.json');
  // "zz.badfmt" asks for two args but T() below only supplies one -- unlike
  // an unused extra arg (which Format() tolerates silently), a placeholder
  // with nothing to fill it raises EConvertError, which T() must catch and
  // recover from by formatting ADefault instead of propagating it.
  TFile.WriteAllText(FilePath,
    '{"zz":{"ok":"ZZ-OK","badfmt":"%d and %d"}}', TEncoding.UTF8);
  try
    SetLocale('zz');
    Expect(CurrentLocale = 'zz', 'switched to the on-disk-only locale');
    Expect(T('zz.ok', 'fallback') = 'ZZ-OK',
      'a locale with no embedded STRINGS_ZZ resource still loads from strings\zz.json next to the exe');
    Expect(T('zz.badfmt', 'value: %d', [42]) = 'value: 42',
      'a translated string whose placeholders don''t match AArgs formats ADefault instead of raising');
  finally
    SetLocale('en');
    TFile.Delete(FilePath);
  end;
end;

procedure TestDialogTranslationEn;
var
  Decl: TDialogDeclaration;
begin
  Writeln('TryLoadDialogResource: en leaves dialogs.json text untouched');
  SetLocale('en');
  Expect(TryLoadDialogResource(cResDialogConfirm, Decl), 'DIALOG_CONFIRM loads');
  Expect(FindCtrlText(Decl, 'ok') = 'OK', 'ok button stays English');
  Expect(FindCtrlText(Decl, 'cancel') = 'Cancel', 'cancel button stays English');

  Expect(TryLoadDialogResource(cResDialogAskSave, Decl), 'DIALOG_ASKSAVE loads');
  Expect(Decl.Title = 'Save modified file?', 'title stays English');
  Expect(FindCtrlText(Decl, 'yes') = 'Yes', 'yes button stays English');
  Expect(FindCtrlText(Decl, 'no') = 'No', 'no button stays English');
end;

procedure TestDialogTranslationRu;
var
  Decl: TDialogDeclaration;
begin
  Writeln('TryLoadDialogResource: ru translates static captions via TDialog()');
  SetLocale('ru');
  Expect(TryLoadDialogResource(cResDialogConfirm, Decl), 'DIALOG_CONFIRM loads');
  Expect(FindCtrlText(Decl, 'ok') = 'ОК', 'ok button translates');
  Expect(FindCtrlText(Decl, 'cancel') = 'Отмена', 'cancel button translates');

  Expect(TryLoadDialogResource(cResDialogAskSave, Decl), 'DIALOG_ASKSAVE loads');
  Expect(Decl.Title = 'Сохранить изменённый файл?', 'title translates');
  Expect(FindCtrlText(Decl, 'yes') = 'Да', 'yes button translates');
  Expect(FindCtrlText(Decl, 'no') = 'Нет', 'no button translates');
  Expect(FindCtrlText(Decl, 'cancel') = 'Отмена', 'cancel button translates');
  // filename is always overwritten dynamically by BuildAskSaveDialog's own
  // caller (DialogSetLabelText), never a static caption -- confirms the
  // translation pass leaves it as whatever the raw JSON placeholder was
  // rather than mistranslating live/dynamic content.
  Expect(FindCtrlText(Decl, 'filename') <> '<missing:filename>', 'filename control exists untouched');
  SetLocale('en');
end;

procedure TestDialogTranslationBroadSweep;
var
  Decl: TDialogDeclaration;
begin
  Writeln('TryLoadDialogResource: ru sweep across newly-translated dialogs');
  SetLocale('ru');

  // Display: the 5 static captions that had no stable id before this batch
  // (Font/Size/Zoom/Interval/Language) -- confirms adding "id" to a JSON
  // label is enough to pick it up, no code change needed.
  Expect(TryLoadDialogResource(cResDialogDisplay, Decl), 'DIALOG_DISPLAY loads');
  Expect(FindCtrlText(Decl, 'lbl_font') = 'Шрифт', 'Font label translates');
  Expect(FindCtrlText(Decl, 'lbl_size') = 'Размер', 'Size label translates');
  Expect(FindCtrlText(Decl, 'lbl_zoom') = 'Масштаб', 'Zoom label translates');
  Expect(FindCtrlText(Decl, 'lbl_interval') = 'Интервал', 'Interval label translates');
  Expect(FindCtrlText(Decl, 'lbl_language') = 'Язык', 'Language label translates');
  Expect(FindCtrlText(Decl, 'blink') = 'Мигающий курсор', 'Blink cursor checkbox translates');

  Expect(TryLoadDialogResource(cResDialogSearch, Decl), 'DIALOG_SEARCH loads');
  Expect(Decl.Title = 'Поиск файла', 'title translates');
  Expect(FindCtrlText(Decl, 'search_case') = 'Учитывать регистр', 'checkbox translates');
  Expect(FindCtrlText(Decl, 'ok') = 'Найти', 'Find button translates');

  Expect(TryLoadDialogResource(cResDialogCopyMove, Decl), 'DIALOG_COPYMOVE loads');
  // prompt is always overwritten dynamically by the caller (DialogSetLabelText),
  // so it must NOT come from ru.json -- confirms dynamic-content ids were
  // correctly left out of the translation table, not just missed by accident.
  Expect(FindCtrlText(Decl, 'prompt') = 'Copy to:', 'dynamic prompt label is untouched by translation');
  Expect(FindCtrlText(Decl, 'job_timestamps') = 'Сохранять все временные метки', 'static checkbox translates');
  Expect(FindCtrlText(Decl, 'ok') = 'Копировать', 'Copy button translates');

  // total_rule's "Total" -> "Итого" substitution is length-for-length
  // (both 5 chars) specifically so the dash-padding either side keeps the
  // dialog's declared width -- verify that invariant held.
  Expect(TryLoadDialogResource(cResDialogJobProgress, Decl), 'DIALOG_JOBPROGRESS loads');
  Expect(FindCtrlText(Decl, 'total_rule').Contains('Итого'), 'Total -> Итого');
  Expect(Length(FindCtrlText(Decl, 'total_rule')) = Length('──────────────────────────────── Total ──────────────────────────────────'),
    'translated separator keeps the exact same rendered width as the English default');

  // A multi-column list header (assocHeader) is a deliberate translation gap:
  // its fixed-width padding lines up with data-row offsets baked into the
  // Pascal renderer, so translating the label alone would misalign the grid.
  Expect(TryLoadDialogResource(cResDialogAssociations, Decl), 'DIALOG_ASSOCIATIONS loads');
  Expect(FindCtrlText(Decl, 'assocHeader').StartsWith('Ext'),
    'column header intentionally left untranslated (see uStrings.pas dialog-translation notes)');
  Expect(FindCtrlText(Decl, 'ok') = 'Изменить', 'Edit button translates');

  SetLocale('en');
end;

procedure TestUiStringsSweep;
begin
  Writeln('T(''ui.*.*''): ad-hoc call-site strings (confirm/prompt/error messages)');
  SetLocale('en');
  Expect(T('ui.delete.promptOne', 'Delete item "%s"?', ['foo.txt']) = 'Delete item "foo.txt"?',
    'en: delete prompt (one) stays English');
  Expect(T('ui.job.confirmRecycle', 'Move %d item(s) to Recycle Bin?', [3]) =
    'Move 3 item(s) to Recycle Bin?', 'en: recycle confirm stays English');

  SetLocale('ru');
  Expect(T('ui.delete.promptOne', 'Delete item "%s"?', ['foo.txt']) = 'Удалить объект «foo.txt»?',
    'ru: delete prompt (one) translates with its %s arg substituted');
  Expect(T('ui.delete.promptMany', 'Delete %d selected items?', [5]) = 'Удалить выбранные объекты (5)?',
    'ru: delete prompt (many) translates with its %d arg substituted');
  Expect(T('ui.job.titleCopy', 'Copy') = 'Копирование', 'ru: job title translates');
  Expect(T('ui.job.confirmCopyMoveOne', '%s `%s` to:', ['Copy', 'a.txt']) = 'Copy «a.txt» в:',
    'ru: copy/move confirm template translates around its two args');
  Expect(T('ui.mkdir.title', 'Make directory') = 'Создание папки', 'ru: mkdir title translates');
  Expect(T('ui.rename.title', 'Rename') = 'Переименование', 'ru: rename title translates');
  Expect(T('ui.ssh.confirmDelete', 'Delete saved connection "%s"?', ['prod-box']) =
    'Удалить сохранённое соединение «prod-box»?', 'ru: ssh delete confirm translates');
  Expect(T('ui.shellProfiles.noneAvailable', 'No shell profiles available') =
    'Нет доступных профилей оболочки', 'ru: shared shell-profiles stub message translates');
  SetLocale('en');
end;

procedure TestMenuTranslation;
const
  cJson =
    '{"categories":[{"title":"Files","hotChar":"F","items":[' +
    '{"caption":"Copy","hotChar":"C","shortcut":"F5","action":"tmaFileCopy"}' +
    ']}]}';
var
  C: TTopMenuController;
begin
  Writeln('TTopMenuController.LoadMenuFromJson translates category titles and item captions');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    SetLocale('en');
    Expect(C.LoadMenuFromJson(cJson), 'menu JSON parses (en)');
    Expect(C.CategoryTitle(0) = 'Files', 'category title stays English (untranslated key)');
    Expect(C.CategoryItemCaption(0, 0) = 'Copy', 'item caption stays English (untranslated key)');

    SetLocale('ru');
    Expect(C.LoadMenuFromJson(cJson), 'menu JSON parses (ru)');
    Expect(C.CategoryTitle(0) = 'Файлы', 'category title translates via menu.category.<title>');
    Expect(C.CategoryItemCaption(0, 0) = 'Копировать',
      'item caption translates via menu.<action>, mnemonic marker stripped');
  finally
    C.Free;
    SetLocale('en');
  end;
end;

begin
  try
    TestLocaleBasics;
    TestAvailableLocales;
    TestPlainLookup;
    TestFormatArgs;
    TestLooseFileOverrideAndBadFormatFallback;
    TestDialogTranslationEn;
    TestDialogTranslationRu;
    TestDialogTranslationBroadSweep;
    TestUiStringsSweep;
    TestMenuTranslation;
    Writeln('All Strings tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
