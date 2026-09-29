unit TestDisplaySettings;

{ Clamp/index helpers, monospace fallback, session round-trip,
  GShowPanelIcons / PanelIconReserve. Also covers the Language field/picker
  (uStrings.pas) added on top -- needs the embedded STRINGS_RU resource, see
  the $R above (uDisplaySettings.DisplayLanguageItems reads it indirectly
  through uStrings.AvailableLocales). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDisplaySettings = class
  public
    [Test] procedure TestClampAndIndex;
    [Test] procedure TestFontEnum;
    [Test] procedure TestSessionRoundTrip;
    [Test] procedure TestSessionMissingKeys;
    [Test] procedure TestLanguagePicker;
    [Test] procedure TestPanelIconFlag;
    [Test] procedure TestShadowStyle;
    [Test] procedure TestDialogShowsMarkedFiles;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Math,
  uVfsTypes,
  uDualPanelTypes,
  uPanelColumns,
  uConfigLocation,
  uDisplaySettings,
  uSession,
  System.UITypes, uTerminalTypes, uThemeTypes, uThemeDrawing,
  uStrings, uDialogTypes, uDialogHost, uNDNTheme;

procedure TestClampAndIndex;
begin
  Assert.IsTrue(SameValue(ClampDisplayFontSize(4), cDisplayMinFontSize), 'font size min');
  Assert.IsTrue(SameValue(ClampDisplayFontSize(99), cDisplayMaxFontSize), 'font size max');
  Assert.IsTrue(SameValue(ClampDisplayFontSize(14), 14), 'font size 14');
  Assert.IsTrue(SameValue(ClampDisplayZoom(0.1), cDisplayMinZoom), 'zoom min');
  Assert.IsTrue(SameValue(ClampDisplayZoom(9), cDisplayMaxZoom), 'zoom max');
  Assert.IsTrue(SameValue(ClampDisplayZoom(1), 1.0), 'zoom 100%');
  Assert.IsTrue(ClampDisplayBlinkMs(530) = cDisplayDefaultBlinkMs, 'blink 530');
  Assert.IsTrue(ClampDisplayBlinkMs(400) = 300, 'blink 400 -> 300');
  Assert.IsTrue(ClampDisplayBlinkMs(800) = 1000, 'blink 800 -> 1000');
  // The list is in points; sizes are pixels (1 pt = 4/3 px).
  Assert.IsTrue(IndexOfDisplayFontSize(14) = 9, '14 px = 10.5 pt, index 9');
  Assert.IsTrue(SameValue(DisplayFontSizeAt(9), 14, 0.001), 'index 9 = 10.5 pt = 14 px');
  Assert.IsTrue(SameValue(DisplayFontSizeAt(10), 11 * 96 / 72, 0.001), 'index 10 = 11 pt = 14.67 px');
  Assert.IsTrue(IndexOfDisplayFontSize(11 * 96 / 72) = 10, '14.67 px back to 11 pt');
  Assert.IsTrue(IndexOfDisplayFontSize(16) = 12, '16 px = 12 pt');
  Assert.IsTrue(SameValue(DisplayFontSizeAt(0), cDisplayMinFontSize, 0.001), 'first item = min size');
  Assert.IsTrue(SameValue(DisplayFontSizeAt(High(DisplayFontSizeItems)), cDisplayMaxFontSize, 0.001),
    'last item = max size');
  Assert.IsTrue(DisplayFontSizeItems[9].StartsWith('10') and DisplayFontSizeItems[9].Contains('5'),
    'half points shown: ' + DisplayFontSizeItems[9]);
  Assert.IsTrue(IndexOfDisplayZoom(1.0) = 2, '100% zoom index');
  Assert.IsTrue(SameValue(DisplayZoomAt(2), 1.0), 'index 2 is 100%');
  Assert.IsTrue(IndexOfDisplayBlinkMs(530) = 1, '530 ms index');
  Assert.IsTrue(DisplayBlinkMsAt(1) = 530, 'index 1 is 530 ms');
end;

procedure TestFontEnum;
var
  Names: TArray<string>;
  Fallback: string;
begin
  Names := EnumerateMonospaceFontFamilies;
  Assert.IsTrue(Length(Names) >= 1, 'at least one monospace family');
  Fallback := PreferMonoFontFamily;
  Assert.IsTrue(Fallback <> '', 'prefer-mono is non-empty');
  Assert.IsTrue(ResolveMonospaceFontFamily('') = Fallback, 'blank name -> prefer-mono');
  Assert.IsTrue(ResolveMonospaceFontFamily('NoSuchFont_MTN2_Stage55') = Fallback,
    'unknown name -> prefer-mono');
  Assert.IsTrue(ResolveMonospaceFontFamily(Fallback) = Fallback, 'prefer-mono resolves to itself');
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
  Result.ShowNotifications := False;
  Result.ShowTitleBar := False;
  Result.ShowMenuBar := False;
  Result.ShowKeyBar := False;
  Result.ShowStatusLine := True;
  Result.ShadowStyle := 'soft';
  Result.LineSpacing := True;
  Result.MarkedRows := 'band';
  Result.SelectFolders := True;
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
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-display-session-test.json');
  Saved := MakeUsableSession;
  Assert.IsTrue(SaveSession(Path, Saved), 'save session');
  try
    Assert.IsTrue(TryLoadSession(Path, Loaded), 'load session');
    Assert.IsTrue(Loaded.FontName = 'Consolas', 'fontName saved');
    Assert.IsTrue(SameValue(Loaded.FontSize, 16), 'fontSize saved');
    Assert.IsTrue(not Loaded.CursorBlink, 'cursorBlink saved');
    Assert.IsTrue(Loaded.CursorBlinkMs = 300, 'cursorBlinkMs saved');
    Assert.IsTrue(not Loaded.ShowPanelIcons, 'showPanelIcons saved');
    Assert.IsTrue(not Loaded.ShowNotifications, 'showNotifications saved');
    Assert.IsTrue(not Loaded.ShowTitleBar, 'showTitleBar saved');
    Assert.IsTrue(not Loaded.ShowMenuBar, 'showMenuBar saved');
    Assert.IsTrue(not Loaded.ShowKeyBar, 'showKeyBar saved');
    Assert.IsTrue(Loaded.ShowStatusLine, 'showStatusLine saved');
    Assert.IsTrue(SameValue(Loaded.Zoom, 1.25), 'zoom still saved');
    Assert.IsTrue(Loaded.Language = 'ru', 'language saved');
    Assert.IsTrue(Loaded.ShadowStyle = 'soft', 'shadowStyle saved');
    Assert.IsTrue(Loaded.LineSpacing, 'lineSpacing saved');
    Assert.IsTrue(Loaded.MarkedRows = 'band', 'markedRows saved');
    Assert.IsTrue(Loaded.SelectFolders, 'selectFolders saved');
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
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-display-session-missing.json');
  Sess := MakeUsableSession;
  Assert.IsTrue(SaveSession(Path, Sess), 'save before stripping keys');
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
    Pair := Root.RemovePair('showNotifications');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('language');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('showTitleBar');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('showMenuBar');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('showKeyBar');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('shadowStyle');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('lineSpacing');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('markedRows');
    if Assigned(Pair) then
      Pair.Free;
    Pair := Root.RemovePair('selectFolders');
    if Assigned(Pair) then
      Pair.Free;
    TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
  finally
    Root.Free;
  end;
  try
    Assert.IsTrue(TryLoadSession(Path, Sess), 'load old session.json');
    Assert.IsTrue(Sess.FontName = '', 'missing fontName defaults empty');
    Assert.IsTrue(SameValue(Sess.FontSize, cDisplayDefaultFontSize), 'missing fontSize -> 14');
    Assert.IsTrue(Sess.CursorBlink, 'missing cursorBlink -> on');
    Assert.IsTrue(Sess.CursorBlinkMs = cDisplayDefaultBlinkMs, 'missing blink ms -> 530');
    Assert.IsTrue(Sess.ShowPanelIcons, 'missing showPanelIcons -> on');
    Assert.IsTrue(Sess.ShowNotifications, 'missing showNotifications -> on');
    Assert.IsTrue(Sess.ShowTitleBar, 'missing showTitleBar -> shown');
    Assert.IsTrue(Sess.ShowMenuBar, 'missing showMenuBar -> shown');
    Assert.IsTrue(Sess.ShowKeyBar, 'missing showKeyBar -> shown');
    Assert.IsTrue(Sess.Language = '', 'missing language -> empty (English)');
    Assert.IsTrue(Sess.ShadowStyle = 'classic', 'missing shadowStyle -> classic');
    Assert.IsTrue(not Sess.LineSpacing, 'missing lineSpacing -> off');
    Assert.IsTrue(Sess.MarkedRows = 'text', 'missing markedRows -> text');
    Assert.IsTrue(not Sess.SelectFolders, 'missing selectFolders -> files only');
  finally
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

procedure TestShadowStyle;
const
  cBg = TAlphaColor($FF0000AA);
var
  Grid: TTerminalGrid;
  Box: TRectI;
  Saved: TShadowStyle;

  // Background of the cell right of the box after DrawDialogShadow.
  function ShadowBg(AStyle: TShadowStyle): TAlphaColor;
  begin
    ClearTerminalGrid(Grid, TAlphaColorRec.White, cBg, ' ');
    GShadowStyle := AStyle;
    DrawDialogShadow(Grid, Box);
    Result := Grid[3][Box.Right + 1].BgColor;
  end;

  function Luma(C: TAlphaColor): Integer;
  begin
    Result := TAlphaColorRec(C).R + TAlphaColorRec(C).G + TAlphaColorRec(C).B;
  end;

begin
  Assert.IsTrue(ShadowStyleFromId('soft') = ssSoft, 'id soft');
  Assert.IsTrue(ShadowStyleFromId('NONE') = ssNone, 'ids ignore case');
  Assert.IsTrue(ShadowStyleFromId('bogus') = ssClassic, 'unknown id -> classic');
  Assert.IsTrue(ShadowStyleFromId(ShadowStyleId(ssSoft)) = ssSoft, 'id round-trip');
  Assert.IsTrue(Length(DisplayShadowItems) = Ord(High(TShadowStyle)) + 1, 'one item per style');
  Assert.IsTrue(MarkedRowStyleFromId('BAND') = mrsBand, 'marked id band, any case');
  Assert.IsTrue(MarkedRowStyleFromId('') = mrsText, 'missing marked id -> text');
  Assert.IsTrue(MarkedRowStyleFromId(MarkedRowStyleId(mrsBand)) = mrsBand, 'marked id round-trip');
  Assert.IsTrue(Length(DisplayMarkedRowItems) = Ord(High(TMarkedRowStyle)) + 1,
    'one marked-files item per style');

  AllocTerminalGrid(Grid, 20, 10);
  Box := TRectI.Make(2, 2, 10, 6);
  Saved := GShadowStyle;
  try
    Assert.IsTrue(ShadowBg(ssNone) = cBg, 'none: nothing darkened');
    Assert.IsTrue(Luma(ShadowBg(ssClassic)) < Luma(ShadowBg(ssSoft)), 'soft lighter than classic');
    Assert.IsTrue(Luma(ShadowBg(ssSoft)) < Luma(cBg), 'soft still darkens');
    Assert.IsTrue(DimCoverFor(ssNone, 96) = 0, 'none: no modal dim');
    Assert.IsTrue(DimCoverFor(ssSoft, 96) = 48, 'soft: half the modal dim');
    Assert.IsTrue(DimCoverFor(ssClassic, 96) = 96, 'classic: modal dim unchanged');
  finally
    GShadowStyle := Saved;
  end;
end;

// The real Font / Display dialog, drawn: the "Marked files" row is on
// screen with the saved choice, in English and in Russian.
procedure TestDialogShowsMarkedFiles;

  function DrawnText: string;
  var
    Host: TDialogHost;
    Grid: TTerminalGrid;
    X, Y: Integer;
  begin
    Host := TDialogHost.Create(TNDNTheme.Create);
    try
      Host.Open(BuildDisplayDialog(['Consolas'], 0, 0, 0, 0, True, True, '',
        ['English'], 0, True, 0, False, Ord(mrsBand)), nil);
      AllocTerminalGrid(Grid, 100, 40);
      ClearTerminalGrid(Grid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
      Host.Draw(Grid, 100, 40);
      Result := '';
      for Y := 0 to High(Grid) do
      begin
        for X := 0 to High(Grid[Y]) do
          Result := Result + Grid[Y][X].CharValue;
        Result := Result + #10;
      end;
    finally
      Host.Free;
    end;
  end;

var
  Text: string;
begin
  try
    SetLocale('');
    Text := DrawnText;
    Assert.IsTrue(Pos('Marked files', Text) > 0, 'label drawn');
    Assert.IsTrue(Pos('Row background', Text) > 0, 'saved style shown');
    SetLocale('ru');
    Text := DrawnText;
    Assert.IsTrue(Pos('Отмеченные файлы', Text) > 0, 'Russian label drawn in full');
    Assert.IsTrue(Pos('Фон строки', Text) > 0, 'Russian style name');
  finally
    SetLocale('');
  end;
end;

procedure TestLanguagePicker;
var
  Codes: TArray<string>;
  I: Integer;
  HasEn, HasRu: Boolean;
begin
  Assert.IsTrue(DefaultDisplaySettings.Language = '', 'default settings: no language pinned (English passthrough)');

  Codes := DisplayLanguageItems;
  HasEn := False;
  HasRu := False;
  for I := 0 to High(Codes) do
  begin
    if SameText(Codes[I], 'en') then HasEn := True;
    if SameText(Codes[I], 'ru') then HasRu := True;
  end;
  Assert.IsTrue(HasEn, 'en is always offered');
  Assert.IsTrue(HasRu, 'ru is offered (embedded STRINGS_RU resource)');

  Assert.IsTrue(DisplayLanguageName('en') = 'English', 'en -> English');
  Assert.IsTrue(DisplayLanguageName('') = 'English', 'blank -> English');
  Assert.IsTrue(DisplayLanguageName('ru') <> 'RU', 'ru has a curated name, not just the uppercased code');
  Assert.IsTrue(DisplayLanguageName('zz') = 'ZZ', 'an unknown code falls back to its own uppercased form');

  // IndexOfFontName is reused (unchanged) as a generic case-insensitive
  // lookup for the language-code array too -- see
  // TSettingsDialogController.OpenDisplay/DispatchDisplayCommand.
  Assert.IsTrue(IndexOfFontName(Codes, 'RU') = IndexOfFontName(Codes, 'ru'),
    'language lookup is case-insensitive, like the font lookup it reuses');
  Assert.IsTrue(IndexOfFontName(Codes, 'no-such-locale') = 0,
    'an unrecognized locale falls back to index 0 (en)');
end;

procedure TestPanelIconFlag;
begin
  GShowPanelIcons := True;
  Assert.IsTrue(PanelIconReserve = 3, 'icons on reserve');
  GShowPanelIcons := False;
  try
    Assert.IsTrue(PanelIconColumnWidth = 0, 'icons off width');
    Assert.IsTrue(PanelIconReserve = 0, 'icons off reserve');
  finally
    GShowPanelIcons := True;
  end;
end;

{ TTestDisplaySettings }

procedure TTestDisplaySettings.TestClampAndIndex;
begin
  TestDisplaySettings.TestClampAndIndex;
end;

procedure TTestDisplaySettings.TestFontEnum;
begin
  TestDisplaySettings.TestFontEnum;
end;

procedure TTestDisplaySettings.TestSessionRoundTrip;
begin
  TestDisplaySettings.TestSessionRoundTrip;
end;

procedure TTestDisplaySettings.TestSessionMissingKeys;
begin
  TestDisplaySettings.TestSessionMissingKeys;
end;

procedure TTestDisplaySettings.TestLanguagePicker;
begin
  TestDisplaySettings.TestLanguagePicker;
end;

procedure TTestDisplaySettings.TestShadowStyle;
begin
  TestDisplaySettings.TestShadowStyle;
end;

procedure TTestDisplaySettings.TestDialogShowsMarkedFiles;
begin
  TestDisplaySettings.TestDialogShowsMarkedFiles;
end;

procedure TTestDisplaySettings.TestPanelIconFlag;
begin
  TestDisplaySettings.TestPanelIconFlag;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDisplaySettings);

end.
