unit TestStrings;

{ Characterization tests for uStrings.pas (the UI-translation mechanism)
  and its two hooks: uDialogResources.TryLoadDialogResource's static-caption
  translation pass, and TTopMenuController.LoadMenuFromJson's menu-caption/
  category-title translation. Exercises the real embedded STRINGS_RU
  resource (strings/ru.json) against the real embedded DIALOG_CONFIRM/
  DIALOG_ASKSAVE dialogs, plus a temp on-disk locale for the loose-file
  override path and the Format-argument-mismatch fallback, which nothing
  shipped exercises on its own. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStrings = class
  public
    [Test] procedure TestLocaleBasics;
    [Test] procedure TestAvailableLocales;
    [Test] procedure TestPlainLookup;
    [Test] procedure TestFormatArgs;
    [Test] procedure TestLooseFileOverrideAndBadFormatFallback;
    [Test] procedure TestLooseFileLayersOverEmbedded;
    [Test] procedure TestDialogTranslationEn;
    [Test] procedure TestDialogTranslationRu;
    [Test] procedure TestDialogTranslationBroadSweep;
    [Test] procedure TestUiStringsSweep;
    [Test] procedure TestMenuTranslation;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uStrings,
  uDialogTypes,
  uDialogJson,
  uDialogResources,
  uDialogHost,
  uDialogRenderer,
  uInputLine,
  uTerminalTypes,
  uThemeTypes,
  uThemeDrawing,
  uFunctionBar,
  uColorCoding,
  uColorCodingEditHelpers,
  uFileFind,
  uDualPanelTypes,
  uDualPanelOverlays,
  uTopMenuBar;

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
  Assert.IsTrue(CurrentLocale = 'en', 'default locale is en');
  SetLocale('ru');
  Assert.IsTrue(CurrentLocale = 'ru', 'SetLocale switches the current locale');
  SetLocale('');
  Assert.IsTrue(CurrentLocale = 'en', 'SetLocale('''') resets to en');
  SetLocale('RU');
  Assert.IsTrue(CurrentLocale = 'RU', 'SetLocale preserves the caller''s casing verbatim');
  Assert.IsTrue(SameText(CurrentLocale, 'ru'), 'but lookups are still case-insensitive against it');
  SetLocale('en');
end;

procedure TestAvailableLocales;
var
  Locales: TArray<string>;
  I: Integer;
  HasEn, HasRu: Boolean;
begin
  Locales := AvailableLocales;
  HasEn := False;
  HasRu := False;
  for I := 0 to High(Locales) do
  begin
    if SameText(Locales[I], 'en') then HasEn := True;
    if SameText(Locales[I], 'ru') then HasRu := True;
  end;
  Assert.IsTrue(HasEn, 'en is always listed');
  Assert.IsTrue(HasRu, 'ru is discovered from the embedded STRINGS_RU resource');
  Assert.IsTrue(SameText(Locales[0], 'en'), 'en is always first');
end;

procedure TestPlainLookup;
begin
  SetLocale('en');
  Assert.IsTrue(T('menu.tmaFileCopy', 'Copy') = 'Copy', 'en locale is a zero-cost passthrough to ADefault');
  Assert.IsTrue(T('this.key.does.not.exist', 'Fallback') = 'Fallback', 'an unknown key falls back to ADefault, even for en');

  SetLocale('ru');
  Assert.IsTrue(T('menu.tmaFileCopy', 'Copy') = '&Копировать',
    'a real key translates once ru is active (raw, with its menu mnemonic marker)');
  Assert.IsTrue(T('this.key.does.not.exist', 'Fallback') = 'Fallback',
    'a key absent from ru.json still falls back to ADefault (partial translation never shows a raw key)');
  SetLocale('en');
end;

procedure TestFormatArgs;
begin
  SetLocale('en');
  Assert.IsTrue(T('status.itemsSelected', '%d item(s) selected', [3]) = '3 item(s) selected',
    'en formats ADefault directly');

  SetLocale('ru');
  Assert.IsTrue(T('status.itemsSelected', '%d item(s) selected', [3]) = '3 item(s) selected',
    'an untranslated templated key still formats ADefault correctly');
  SetLocale('en');
end;

procedure TestLooseFileOverrideAndBadFormatFallback;
var
  Dir, FilePath: string;
begin
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
    Assert.IsTrue(CurrentLocale = 'zz', 'switched to the on-disk-only locale');
    Assert.IsTrue(T('zz.ok', 'fallback') = 'ZZ-OK',
      'a locale with no embedded STRINGS_ZZ resource still loads from strings\zz.json next to the exe');
    Assert.IsTrue(T('zz.badfmt', 'value: %d', [42]) = 'value: 42',
      'a translated string whose placeholders don''t match AArgs formats ADefault instead of raising');
  finally
    SetLocale('en');
    TFile.Delete(FilePath);
  end;
end;

procedure TestLooseFileLayersOverEmbedded;
var
  Dir, FilePath: string;
begin
  Dir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'strings');
  ForceDirectories(Dir);
  FilePath := TPath.Combine(Dir, 'ru.json');
  Assert.IsFalse(TFile.Exists(FilePath), 'no stray strings\ru.json next to the test exe');
  TFile.WriteAllText(FilePath,
    '{"menu":{"tmaFileCopy":"COPY-FIX"},"zz":{"extra":"ZZ-EXTRA"}}', TEncoding.UTF8);
  try
    SetLocale('ru');
    Assert.IsTrue(T('menu.tmaFileCopy', 'Copy') = 'COPY-FIX',
      'a key in the loose strings\ru.json overrides the embedded STRINGS_RU text');
    Assert.IsTrue(T('menu.tmaFileMove', 'Move') = 'П&ереместить',
      'a key the loose file lacks keeps the embedded translation, not English');
    Assert.IsTrue(T('zz.extra', 'fallback') = 'ZZ-EXTRA',
      'a key only the loose file has is added');
  finally
    SetLocale('en');
    TFile.Delete(FilePath);
  end;
end;

procedure TestDialogTranslationEn;
var
  Decl: TDialogDeclaration;
begin
  SetLocale('en');
  Assert.IsTrue(TryLoadDialogResource(cResDialogConfirm, Decl), 'DIALOG_CONFIRM loads');
  Assert.IsTrue(FindCtrlText(Decl, 'ok') = 'OK', 'ok button stays English');
  Assert.IsTrue(FindCtrlText(Decl, 'cancel') = 'Cancel', 'cancel button stays English');

  Assert.IsTrue(TryLoadDialogResource(cResDialogAskSave, Decl), 'DIALOG_ASKSAVE loads');
  Assert.IsTrue(Decl.Title = 'Save modified file?', 'title stays English');
  Assert.IsTrue(FindCtrlText(Decl, 'yes') = 'Yes', 'yes button stays English');
  Assert.IsTrue(FindCtrlText(Decl, 'no') = '&No', 'no button stays English');
end;

procedure TestDialogTranslationRu;
var
  Decl: TDialogDeclaration;
begin
  SetLocale('ru');
  Assert.IsTrue(TryLoadDialogResource(cResDialogConfirm, Decl), 'DIALOG_CONFIRM loads');
  Assert.IsTrue(FindCtrlText(Decl, 'ok') = 'ОК', 'ok button translates');
  Assert.IsTrue(FindCtrlText(Decl, 'cancel') = 'Отмена', 'cancel button translates');

  Assert.IsTrue(TryLoadDialogResource(cResDialogAskSave, Decl), 'DIALOG_ASKSAVE loads');
  Assert.IsTrue(Decl.Title = 'Сохранить изменённый файл?', 'title translates');
  Assert.IsTrue(FindCtrlText(Decl, 'yes') = 'Да', 'yes button translates');
  Assert.IsTrue(FindCtrlText(Decl, 'no') = '&Нет', 'no button translates');
  Assert.IsTrue(FindCtrlText(Decl, 'cancel') = 'Отмена', 'cancel button translates');
  // filename is always overwritten dynamically by BuildAskSaveDialog's own
  // caller (DialogSetLabelText), never a static caption -- confirms the
  // translation pass leaves it as whatever the raw JSON placeholder was
  // rather than mistranslating live/dynamic content.
  Assert.IsTrue(FindCtrlText(Decl, 'filename') <> '<missing:filename>', 'filename control exists untouched');

  // The delete-error dialog fills its button and question in code: they
  // follow the locale too, and the translated title stays.
  Decl := BuildDeleteErrorDialog('h', 'p', '', 'e', True);
  Assert.AreEqual('Ошибка', Decl.Title, 'delete error: title translates');
  Assert.AreEqual('Удалить', FindCtrlText(Decl, cDlgCmdDelete), 'delete error: Delete translates');
  Decl := BuildDeleteErrorDialog('h', 'p', '', 'e', False);
  Assert.AreEqual('Повторить', FindCtrlText(Decl, cDlgCmdDelete), 'delete error: Retry translates');
  Assert.AreEqual('Повторить удаление без корзины?', FindCtrlText(Decl, 'question'),
    'delete error: the retry question translates');

  // The administrator button of the error prompts exists only when offered
  // and takes the locale.
  Decl := BuildIOErrorDialog('h', 'p', 'e');
  Assert.AreEqual('<missing:elevate>', FindCtrlText(Decl, cDlgCmdElevate),
    'io error: no Elevate button unless offered');
  Decl := BuildIOErrorDialog('h', 'p', 'e', True);
  Assert.AreEqual('&Админ', FindCtrlText(Decl, cDlgCmdElevate),
    'io error: Elevate translates');
  Decl := BuildDeleteErrorDialog('h', 'p', '', 'e', True, True);
  Assert.AreEqual('&Админ', FindCtrlText(Decl, cDlgCmdElevate),
    'delete error: Elevate translates');
  SetLocale('en');
end;

/// <summary>Start offsets of the words in a column header, e.g. '0,13,27,'.</summary>
function ColumnStarts(const AText: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AText) do
    if (AText[I] <> ' ') and ((I = 1) or (AText[I - 1] = ' ')) then
      Result := Result + IntToStr(I - 1) + ',';
end;

procedure TestDialogTranslationBroadSweep;
var
  Decl: TDialogDeclaration;
begin
  SetLocale('ru');

  // Display: the static captions with a stable id
  // (Font/Size/Zoom/Interval/Language) -- confirms adding "id" to a JSON
  // label is enough to pick it up, no code change needed.
  Assert.IsTrue(TryLoadDialogResource(cResDialogDisplay, Decl), 'DIALOG_DISPLAY loads');
  Assert.IsTrue(FindCtrlText(Decl, 'lbl_font') = 'Шрифт', 'Font label translates');
  Assert.IsTrue(FindCtrlText(Decl, 'lbl_size') = 'Размер', 'Size label translates');
  Assert.IsTrue(FindCtrlText(Decl, 'lbl_zoom') = 'Масштаб', 'Zoom label translates');
  Assert.IsTrue(FindCtrlText(Decl, 'lbl_interval') = 'Интервал', 'Interval label translates');
  Assert.IsTrue(FindCtrlText(Decl, 'lbl_language') = 'Язык', 'Language label translates');
  Assert.IsTrue(FindCtrlText(Decl, 'blink') = 'Мигающий &курсор', 'Blink cursor checkbox translates');

  Assert.IsTrue(TryLoadDialogResource(cResDialogSearch, Decl), 'DIALOG_SEARCH loads');
  Assert.IsTrue(Decl.Title = 'Поиск файла', 'title translates');
  Assert.IsTrue(FindCtrlText(Decl, 'search_case') = '&Учитывать регистр', 'checkbox translates');
  Assert.IsTrue(FindCtrlText(Decl, 'ok') = 'Найти', 'Find button translates');

  Assert.IsTrue(TryLoadDialogResource(cResDialogCopyMove, Decl), 'DIALOG_COPYMOVE loads');
  // prompt is always overwritten dynamically by the caller (DialogSetLabelText),
  // so it must NOT come from ru.json -- confirms dynamic-content ids were
  // correctly left out of the translation table, not just missed by accident.
  Assert.IsTrue(FindCtrlText(Decl, 'prompt') = 'Copy to:', 'dynamic prompt label is untouched by translation');
  Assert.IsTrue(FindCtrlText(Decl, 'job_timestamps') = '&Сохранять все временные метки', 'static checkbox translates');
  Assert.IsTrue(FindCtrlText(Decl, 'ok') = 'Копировать', 'Copy button translates');

  // total_rule's "Total" -> "Итого" substitution is length-for-length
  // (both 5 chars) specifically so the dash-padding either side keeps the
  // dialog's declared width -- verify that invariant held.
  Assert.IsTrue(TryLoadDialogResource(cResDialogJobProgress, Decl), 'DIALOG_JOBPROGRESS loads');
  Assert.IsTrue(FindCtrlText(Decl, 'total_rule').Contains('Итого'), 'Total -> Итого');
  Assert.IsTrue(Length(FindCtrlText(Decl, 'total_rule')) = Length('──────────────────────────────── Total ──────────────────────────────────'),
    'translated separator keeps the exact same rendered width as the English default');

  // A multi-column list header (assocHeader) is padded to line up with
  // data-row offsets baked into the Pascal renderer, so its translation must
  // start every column exactly where the English one does.
  Assert.IsTrue(TryLoadDialogResource(cResDialogAssociations, Decl), 'DIALOG_ASSOCIATIONS loads');
  Assert.IsTrue(FindCtrlText(Decl, 'assocHeader').StartsWith('Расш.'), 'column header translates');
  Assert.IsTrue(ColumnStarts(FindCtrlText(Decl, 'assocHeader')) =
    ColumnStarts('Ext          Action        Command'),
    'translated column header keeps every column where the English one starts it');
  Assert.IsTrue(FindCtrlText(Decl, 'ok') = 'Изменить', 'Edit button translates');

  SetLocale('en');
end;

procedure TestUiStringsSweep;
begin
  SetLocale('en');
  Assert.IsTrue(T('ui.delete.promptOne', 'Delete item "%s"?', ['foo.txt']) = 'Delete item "foo.txt"?',
    'en: delete prompt (one) stays English');
  Assert.IsTrue(T('ui.job.confirmRecycle', 'Move %d item(s) to Recycle Bin?', [3]) =
    'Move 3 item(s) to Recycle Bin?', 'en: recycle confirm stays English');

  SetLocale('ru');
  Assert.IsTrue(T('ui.delete.promptOne', 'Delete item "%s"?', ['foo.txt']) = 'Удалить объект «foo.txt»?',
    'ru: delete prompt (one) translates with its %s arg substituted');
  Assert.IsTrue(T('ui.delete.promptMany', 'Delete %d selected items?', [5]) = 'Удалить выбранные объекты (5)?',
    'ru: delete prompt (many) translates with its %d arg substituted');
  Assert.IsTrue(T('ui.job.titleCopy', 'Copy') = 'Копирование', 'ru: job title translates');
  Assert.IsTrue(T('ui.job.confirmCopyMoveOne', '%s `%s` to:', ['Copy', 'a.txt']) = 'Copy «a.txt» в:',
    'ru: copy/move confirm template translates around its two args');
  Assert.IsTrue(T('ui.mkdir.title', 'Make directory') = 'Создание папки', 'ru: mkdir title translates');
  Assert.IsTrue(T('ui.rename.title', 'Rename') = 'Переименование', 'ru: rename title translates');
  Assert.IsTrue(T('ui.ssh.confirmDelete', 'Delete saved connection "%s"?', ['prod-box']) =
    'Удалить сохранённое соединение «prod-box»?', 'ru: ssh delete confirm translates');
  Assert.IsTrue(T('ui.shellProfiles.noneAvailable', 'No shell profiles available') =
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
  C := TTopMenuController.Create(nil, nil, nil);
  try
    SetLocale('en');
    Assert.IsTrue(C.LoadMenuFromJson(cJson), 'menu JSON parses (en)');
    Assert.IsTrue(C.CategoryTitle(0) = 'Files', 'category title stays English (untranslated key)');
    Assert.IsTrue(C.CategoryItemCaption(0, 0) = 'Copy', 'item caption stays English (untranslated key)');

    SetLocale('ru');
    Assert.IsTrue(C.LoadMenuFromJson(cJson), 'menu JSON parses (ru)');
    Assert.IsTrue(C.CategoryTitle(0) = 'Файлы', 'category title translates via menu.category.<title>');
    Assert.IsTrue(C.CategoryItemCaption(0, 0) = 'Копировать',
      'item caption translates via menu.<action>, mnemonic marker stripped');
  finally
    C.Free;
    SetLocale('en');
  end;
end;

{ TTestStrings }

procedure TTestStrings.TestLocaleBasics;
begin
  TestStrings.TestLocaleBasics;
end;

procedure TTestStrings.TestAvailableLocales;
begin
  TestStrings.TestAvailableLocales;
end;

procedure TTestStrings.TestPlainLookup;
begin
  TestStrings.TestPlainLookup;
end;

procedure TTestStrings.TestFormatArgs;
begin
  TestStrings.TestFormatArgs;
end;

procedure TTestStrings.TestLooseFileOverrideAndBadFormatFallback;
begin
  TestStrings.TestLooseFileOverrideAndBadFormatFallback;
end;

procedure TTestStrings.TestLooseFileLayersOverEmbedded;
begin
  TestStrings.TestLooseFileLayersOverEmbedded;
end;

procedure TTestStrings.TestDialogTranslationEn;
begin
  TestStrings.TestDialogTranslationEn;
end;

procedure TTestStrings.TestDialogTranslationRu;
begin
  TestStrings.TestDialogTranslationRu;
end;

procedure TTestStrings.TestDialogTranslationBroadSweep;
begin
  TestStrings.TestDialogTranslationBroadSweep;
end;

procedure TTestStrings.TestUiStringsSweep;
begin
  TestStrings.TestUiStringsSweep;
end;

procedure TTestStrings.TestMenuTranslation;
begin
  TestStrings.TestMenuTranslation;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStrings);

end.
