program TestDisplaySettings;

{$APPTYPE CONSOLE}
{$R '..\..\MTN2.dres'}

{ Stage 55: clamp/index helpers, monospace fallback, session round-trip,
  GShowPanelIcons / PanelIconReserve. Also covers the Language field/picker
  (uStrings.pas) added on top -- needs the embedded STRINGS_RU resource, see
  the $R above (uDisplaySettings.DisplayLanguageItems reads it indirectly
  through uStrings.AvailableLocales). }

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Math,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uPanelColumns in '..\..\Core\uPanelColumns.pas',
  uConfigLocation in '..\..\Core\uConfigLocation.pas',
  uDisplaySettings in '..\..\Core\uDisplaySettings.pas',
  uSession in '..\..\Core\uSession.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestClampAndIndex;
begin
  Writeln('Clamp / index');
  Expect(SameValue(ClampDisplayFontSize(4), cDisplayMinFontSize), 'font size min');
  Expect(SameValue(ClampDisplayFontSize(99), cDisplayMaxFontSize), 'font size max');
  Expect(SameValue(ClampDisplayFontSize(14), 14), 'font size 14');
  Expect(SameValue(ClampDisplayZoom(0.1), cDisplayMinZoom), 'zoom min');
  Expect(SameValue(ClampDisplayZoom(9), cDisplayMaxZoom), 'zoom max');
  Expect(SameValue(ClampDisplayZoom(1), 1.0), 'zoom 100%');
  Expect(ClampDisplayBlinkMs(530) = cDisplayDefaultBlinkMs, 'blink 530');
  Expect(ClampDisplayBlinkMs(400) = 300, 'blink 400 -> 300');
  Expect(ClampDisplayBlinkMs(800) = 1000, 'blink 800 -> 1000');
  Expect(IndexOfDisplayFontSize(14) = 5, '14 pt index');
  Expect(SameValue(DisplayFontSizeAt(5), 14), 'index 5 is 14 pt');
  Expect(IndexOfDisplayZoom(1.0) = 2, '100% zoom index');
  Expect(SameValue(DisplayZoomAt(2), 1.0), 'index 2 is 100%');
  Expect(IndexOfDisplayBlinkMs(530) = 1, '530 ms index');
  Expect(DisplayBlinkMsAt(1) = 530, 'index 1 is 530 ms');
end;

procedure TestFontEnum;
var
  Names: TArray<string>;
  Fallback: string;
begin
  Writeln('Monospace enum / resolve');
  Names := EnumerateMonospaceFontFamilies;
  Expect(Length(Names) >= 1, 'at least one monospace family');
  Fallback := PreferMonoFontFamily;
  Expect(Fallback <> '', 'prefer-mono is non-empty');
  Expect(ResolveMonospaceFontFamily('') = Fallback, 'blank name -> prefer-mono');
  Expect(ResolveMonospaceFontFamily('NoSuchFont_MTN2_Stage55') = Fallback,
    'unknown name -> prefer-mono');
  Expect(ResolveMonospaceFontFamily(Fallback) = Fallback, 'prefer-mono resolves to itself');
end;

function MakeUsableSession: TMtnSession;
var
  Tab: TTab;
begin
  Result := Default(TMtnSession);
  Result.Version := cSessionVersion;
  Result.Zoom := 1.25;
  Result.ConsoleRestartOnExit := True;
  Result.TerminalCloseOnExit := True;
  Result.RestoreWorkspaceOnStart := True;
  Result.CustomColumns := DefaultCustomColumnsConfig;
  Result.FontName := 'Consolas';
  Result.FontSize := 16;
  Result.CursorBlink := False;
  Result.CursorBlinkMs := 300;
  Result.ShowPanelIcons := False;
  Result.Language := 'ru';
  Tab := MakeTab(1, 'C:', 'file:///C:/');
  SetLength(Result.Panels.WorkspaceTabs, 1);
  Result.Panels.WorkspaceTabs[0].Id := 1;
  Result.Panels.WorkspaceTabs[0].Title := 'Workspace';
  Result.Panels.WorkspaceTabs[0].Kind := wkPanels;
  Result.Panels.WorkspaceTabs[0].State.LeftVisible := True;
  Result.Panels.WorkspaceTabs[0].State.RightVisible := True;
  SetLength(Result.Panels.WorkspaceTabs[0].State.LeftPanel.Tabs, 1);
  Result.Panels.WorkspaceTabs[0].State.LeftPanel.Tabs[0] := Tab;
  SetLength(Result.Panels.WorkspaceTabs[0].State.RightPanel.Tabs, 1);
  Result.Panels.WorkspaceTabs[0].State.RightPanel.Tabs[0] := Tab;
end;

procedure TestSessionRoundTrip;
var
  Path: string;
  Saved, Loaded: TMtnSession;
begin
  Writeln('Session round-trip');
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-display-session-test.json');
  Saved := MakeUsableSession;
  Expect(SaveSession(Path, Saved), 'save session');
  try
    Expect(TryLoadSession(Path, Loaded), 'load session');
    Expect(Loaded.FontName = 'Consolas', 'fontName saved');
    Expect(SameValue(Loaded.FontSize, 16), 'fontSize saved');
    Expect(not Loaded.CursorBlink, 'cursorBlink saved');
    Expect(Loaded.CursorBlinkMs = 300, 'cursorBlinkMs saved');
    Expect(not Loaded.ShowPanelIcons, 'showPanelIcons saved');
    Expect(SameValue(Loaded.Zoom, 1.25), 'zoom still saved');
    Expect(Loaded.Language = 'ru', 'language saved');
  finally
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

procedure TestSessionMissingKeys;
var
  Path: string;
  Root: TJSONObject;
  Pair: TJSONPair;
  Sess: TMtnSession;
begin
  Writeln('Session missing display keys');
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-display-session-missing.json');
  Sess := MakeUsableSession;
  Expect(SaveSession(Path, Sess), 'save before stripping keys');
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
  try
    Pair := Root.RemovePair('fontName');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('fontSize');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('cursorBlink');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('cursorBlinkMs');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('showPanelIcons');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('language');
    if Assigned(Pair) then
      Pair.Free;
    TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
  finally
    Root.Free;
  end;
  try
    Expect(TryLoadSession(Path, Sess), 'load old session.json');
    Expect(Sess.FontName = '', 'missing fontName defaults empty');
    Expect(SameValue(Sess.FontSize, cDisplayDefaultFontSize), 'missing fontSize -> 14');
    Expect(Sess.CursorBlink, 'missing cursorBlink -> on');
    Expect(Sess.CursorBlinkMs = cDisplayDefaultBlinkMs, 'missing blink ms -> 530');
    Expect(Sess.ShowPanelIcons, 'missing showPanelIcons -> on');
    Expect(Sess.Language = '', 'missing language -> empty (English)');
  finally
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

procedure TestLanguagePicker;
var
  Codes: TArray<string>;
  I: Integer;
  HasEn, HasRu: Boolean;
begin
  Writeln('Language picker (uDisplaySettings <-> uStrings)');
  Expect(DefaultDisplaySettings.Language = '', 'default settings: no language pinned (English passthrough)');

  Codes := DisplayLanguageItems;
  HasEn := False;
  HasRu := False;
  for I := 0 to High(Codes) do
  begin
    if SameText(Codes[I], 'en') then HasEn := True;
    if SameText(Codes[I], 'ru') then HasRu := True;
  end;
  Expect(HasEn, 'en is always offered');
  Expect(HasRu, 'ru is offered (embedded STRINGS_RU resource)');

  Expect(DisplayLanguageName('en') = 'English', 'en -> English');
  Expect(DisplayLanguageName('') = 'English', 'blank -> English');
  Expect(DisplayLanguageName('ru') <> 'RU', 'ru has a curated name, not just the uppercased code');
  Expect(DisplayLanguageName('zz') = 'ZZ', 'an unknown code falls back to its own uppercased form');

  // IndexOfFontName is reused (unchanged) as a generic case-insensitive
  // lookup for the language-code array too -- see
  // TSettingsDialogController.OpenDisplay/DispatchDisplayCommand.
  Expect(IndexOfFontName(Codes, 'RU') = IndexOfFontName(Codes, 'ru'),
    'language lookup is case-insensitive, like the font lookup it reuses');
  Expect(IndexOfFontName(Codes, 'no-such-locale') = 0,
    'an unrecognized locale falls back to index 0 (en)');
end;

procedure TestPanelIconFlag;
begin
  Writeln('Panel icon flag');
  GShowPanelIcons := True;
  Expect(PanelIconReserve = 3, 'icons on reserve');
  GShowPanelIcons := False;
  try
    Expect(PanelIconColumnWidth = 0, 'icons off width');
    Expect(PanelIconReserve = 0, 'icons off reserve');
  finally
    GShowPanelIcons := True;
  end;
end;

begin
  try
    TestClampAndIndex;
    TestFontEnum;
    TestSessionRoundTrip;
    TestSessionMissingKeys;
    TestLanguagePicker;
    TestPanelIconFlag;
    Writeln('All DisplaySettings tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
