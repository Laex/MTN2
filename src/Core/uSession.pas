unit uSession;

{ Persist Dual Panel session + zoom as JSON (Stage 12). Corrupt/missing files
  fall back to the built-in default session without blocking startup. }

interface

uses
  System.SysUtils,
  uDualPanelTypes, uPanelColumns;

const
  cSessionVersion = 1;

type
  TMtnWindowBounds = record
    Left: Single;
    Top: Single;
    Width: Single;
    Height: Single;
    Maximized: Boolean;
    Valid: Boolean; // False = omit / ignore (old sessions)
    /// <summary>Windows monitor device name (e.g. '\\.\DISPLAY1') the window
    /// was on when saved; '' = unknown (old sessions) — falls back to the
    /// primary-monitor clamp in TMainForm.ApplySessionWindow.</summary>
    Display: string;
  end;

  TMtnSession = record
    Version: Integer;
    Zoom: Single;
    Window: TMtnWindowBounds;
    Panels: TDualPanelWindowState;
    BackgroundConsoleProfile: string; // profile for Ctrl+O background console
    ConsoleRestartOnExit: Boolean; // auto-restart the Ctrl+O background console's shell when it exits
    TerminalCloseOnExit: Boolean;  // close a Ctrl+Shift+N terminal tab when its shell exits
    AutoSyncConsoleCwd: Boolean;   // auto-cd the background console whenever the active panel navigates
    /// <summary>When True, FormCreate starts the Ctrl+O shell immediately.
    /// When False (default), the shell starts on the first Ctrl+O or the
    /// first command submitted from the Dual Panel command line.</summary>
    ConsoleStartOnLaunch: Boolean;
    /// <summary>IThemeRenderer implementation to instantiate (e.g. 'NDN').
    /// '' = unspecified — caller falls back to the default theme.</summary>
    ThemeName: string;
    /// <summary>Theme JSON file (in the config dir, uColorCoding's active
    /// theme file — see SetActiveThemeFileName) whose "fileColoring" (and,
    /// eventually, palette/roles) overrides ThemeName's embedded defaults.
    /// Independent of ThemeName on purpose: lets a JSON-only reskin (e.g.
    /// 'FARtheme.json') run through the existing IThemeRenderer before a
    /// dedicated Pascal class exists for it. '' = unspecified — caller
    /// falls back to 'NDNtheme.json'.</summary>
    ThemeFile: string;
    /// <summary>Options > Columns... selection — which fields pcmCustom
    /// shows. App-wide, like ThemeName/Zoom (not per-panel).</summary>
    CustomColumns: TCustomColumnsConfig;
    /// <summary>Id of the last saved/restored ws:/// snapshot. '' = none.</summary>
    LastWorkspaceId: string;
    /// <summary>On startup, load LastWorkspaceId into the live ws:/// store.</summary>
    RestoreWorkspaceOnStart: Boolean;
    /// <summary>Stage 55: display font family. '' = PreferMonoFontFamily.</summary>
    FontName: string;
    FontSize: Single;
    CursorBlink: Boolean;
    CursorBlinkMs: Integer;
    ShowPanelIcons: Boolean;
    /// <summary>uStrings.pas locale code. '' = English.</summary>
    Language: string;
  end;

function DefaultSessionFilePath: string;
function TryLoadSession(const APath: string; out ASession: TMtnSession): Boolean;
function SaveSession(const APath: string; const ASession: TMtnSession): Boolean;
function SessionIsUsable(const ASession: TMtnSession): Boolean;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON,
  System.Math, uConfigLocation, uDisplaySettings;

function DefaultSessionFilePath: string;
begin
  Result := GetConfigFilePath('session.json');
end;

function JsonStr(O: TJSONObject; const AName, ADefault: string): string;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if O = nil then
    Exit;
  V := O.GetValue(AName);
  if V is TJSONString then
    Result := TJSONString(V).Value;
end;

function JsonInt(O: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if O = nil then
    Exit;
  V := O.GetValue(AName);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt
  else if V is TJSONString then
    Result := StrToIntDef(TJSONString(V).Value, ADefault);
end;

function JsonFloat(O: TJSONObject; const AName: string; ADefault: Single): Single;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if O = nil then
    Exit;
  V := O.GetValue(AName);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsDouble
  else if V is TJSONString then
    Result := StrToFloatDef(TJSONString(V).Value, ADefault);
end;

function JsonBool(O: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
  S: string;
begin
  Result := ADefault;
  if O = nil then
    Exit;
  V := O.GetValue(AName);
  if V is TJSONTrue then
    Result := True
  else if V is TJSONFalse then
    Result := False
  else if V is TJSONString then
  begin
    S := LowerCase(TJSONString(V).Value);
    if (S = '1') or (S = 'true') or (S = 'yes') then
      Result := True
    else if (S = '0') or (S = 'false') or (S = 'no') then
      Result := False;
  end
  else if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt <> 0;
end;

function TabToJson(const ATab: TTab): TJSONObject;
var
  Hist, Sel: TJSONArray;
  S: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(ATab.Id));
  Result.AddPair('title', ATab.Title);
  Result.AddPair('uri', ATab.CurrentURI);
  Result.AddPair('cursor', TJSONNumber.Create(ATab.CursorIndex));
  Result.AddPair('scroll', TJSONNumber.Create(ATab.ScrollOffset));
  Result.AddPair('historyIndex', TJSONNumber.Create(ATab.HistoryIndex));
  Hist := TJSONArray.Create;
  for S in ATab.History do
    Hist.Add(S);
  Result.AddPair('history', Hist);
  Sel := TJSONArray.Create;
  for S in ATab.SelectedURIs do
    Sel.Add(S);
  Result.AddPair('selected', Sel);
end;

function PanelToJson(const APanel: TPanelState): TJSONObject;
var
  Tabs: TJSONArray;
  Dirs: TJSONObject;
  I: Integer;
  L: Char;
begin
  Result := TJSONObject.Create;
  Result.AddPair('activeTab', TJSONNumber.Create(APanel.ActiveTabIndex));
  Result.AddPair('columnMode', PanelColumnModeName(APanel.ColumnMode));
  Result.AddPair('sortColumn', PanelSortColumnName(APanel.SortColumn));
  Result.AddPair('sortDescending', TJSONBool.Create(APanel.SortDescending));
  Result.AddPair('showHidden', TJSONBool.Create(APanel.ShowHiddenFiles));
  if APanel.ViewKind = pvkInfo then
    Result.AddPair('viewKind', 'info')
  else
    Result.AddPair('viewKind', 'files');
  Tabs := TJSONArray.Create;
  for I := 0 to High(APanel.Tabs) do
    Tabs.Add(TabToJson(APanel.Tabs[I]));
  Result.AddPair('tabs', Tabs);
  Dirs := TJSONObject.Create;
  for L := 'A' to 'Z' do
    if APanel.DriveDirs[L] <> '' then
      Dirs.AddPair(string(L), APanel.DriveDirs[L]);
  Result.AddPair('driveDirs', Dirs);
end;

function WorkspaceToJson(const AWs: TDualPanelWorkspaceTab): TJSONObject;
var
  Side: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(AWs.Id));
  Result.AddPair('title', AWs.Title);
  if AWs.State.ActiveSide = psRight then
    Side := 'right'
  else
    Side := 'left';
  Result.AddPair('activeSide', Side);
  Result.AddPair('leftVisible', TJSONBool.Create(AWs.State.LeftVisible));
  Result.AddPair('rightVisible', TJSONBool.Create(AWs.State.RightVisible));
  Result.AddPair('left', PanelToJson(AWs.State.LeftPanel));
  Result.AddPair('right', PanelToJson(AWs.State.RightPanel));
end;

function TabFromJson(O: TJSONObject): TTab;
var
  Arr: TJSONArray;
  I: Integer;
  V: TJSONValue;
begin
  Result := MakeTab(
    Cardinal(Max(JsonInt(O, 'id', 0), 0)),
    JsonStr(O, 'title', 'tab'),
    JsonStr(O, 'uri', ''));
  Result.CursorIndex := Max(JsonInt(O, 'cursor', 0), 0);
  Result.ScrollOffset := Max(JsonInt(O, 'scroll', 0), 0);
  Result.HistoryIndex := Max(JsonInt(O, 'historyIndex', 0), 0);

  SetLength(Result.History, 0);
  V := O.GetValue('history');
  if V is TJSONArray then
  begin
    Arr := TJSONArray(V);
    SetLength(Result.History, Arr.Count);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONString then
        Result.History[I] := TJSONString(Arr.Items[I]).Value
      else
        Result.History[I] := '';
  end;
  if Length(Result.History) = 0 then
  begin
    SetLength(Result.History, 1);
    Result.History[0] := Result.CurrentURI;
    Result.HistoryIndex := 0;
  end
  else if Result.HistoryIndex > High(Result.History) then
    Result.HistoryIndex := High(Result.History);

  if Result.CurrentURI = '' then
    Result.CurrentURI := Result.History[Result.HistoryIndex];

  SetLength(Result.SelectedURIs, 0);
  V := O.GetValue('selected');
  if V is TJSONArray then
  begin
    Arr := TJSONArray(V);
    SetLength(Result.SelectedURIs, Arr.Count);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONString then
        Result.SelectedURIs[I] := TJSONString(Arr.Items[I]).Value
      else
        Result.SelectedURIs[I] := '';
  end;
end;

function PanelFromJson(O: TJSONObject): TPanelState;
var
  V: TJSONValue;
  Arr: TJSONArray;
  Dirs: TJSONObject;
  I: Integer;
  L: Char;
  Key, Val: string;
begin
  Result.ActiveTabIndex := 0;
  Result.ColumnMode := pcmFull;
  Result.SortColumn := pscNone;
  Result.SortDescending := False;
  Result.ViewKind := pvkFiles;
  Result.ShowHiddenFiles := True;
  SetLength(Result.Tabs, 0);
  ClearPanelDriveDirs(Result.DriveDirs);
  if O = nil then
    Exit;
  Result.ActiveTabIndex := Max(JsonInt(O, 'activeTab', 0), 0);
  if not TryPanelColumnModeFromName(JsonStr(O, 'columnMode', 'Full'), Result.ColumnMode) then
    Result.ColumnMode := pcmFull;
  if not TryPanelSortColumnFromName(JsonStr(O, 'sortColumn', 'None'), Result.SortColumn) then
    Result.SortColumn := pscNone;
  Result.SortDescending := JsonBool(O, 'sortDescending', False);
  if Result.SortColumn = pscNone then
    Result.SortDescending := False;
  if SameText(JsonStr(O, 'viewKind', 'files'), 'info') then
    Result.ViewKind := pvkInfo
  else
    Result.ViewKind := pvkFiles;
  Result.ShowHiddenFiles := JsonBool(O, 'showHidden', True);
  V := O.GetValue('tabs');
  if not (V is TJSONArray) then
    Exit;
  Arr := TJSONArray(V);
  SetLength(Result.Tabs, Arr.Count);
  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONObject then
      Result.Tabs[I] := TabFromJson(TJSONObject(Arr.Items[I]))
    else
      Result.Tabs[I] := MakeTab(0, 'tab', '');
  if Length(Result.Tabs) = 0 then
    Exit;
  if Result.ActiveTabIndex > High(Result.Tabs) then
    Result.ActiveTabIndex := 0;
  V := O.GetValue('driveDirs');
  if V is TJSONObject then
  begin
    Dirs := TJSONObject(V);
    for I := 0 to Dirs.Count - 1 do
    begin
      Key := Dirs.Pairs[I].JsonString.Value;
      if (Length(Key) = 1) and (UpCase(Key[1]) >= 'A') and (UpCase(Key[1]) <= 'Z') then
      begin
        L := UpCase(Key[1]);
        if Dirs.Pairs[I].JsonValue is TJSONString then
          Val := TJSONString(Dirs.Pairs[I].JsonValue).Value
        else
          Val := '';
        if Val <> '' then
          Result.DriveDirs[L] := Val;
      end;
    end;
  end;
  SeedPanelDriveDirs(Result);
end;

function WorkspaceFromJson(O: TJSONObject): TDualPanelWorkspaceTab;
var
  Side: string;
  V: TJSONValue;
begin
  Result.Id := Cardinal(Max(JsonInt(O, 'id', 0), 0));
  Result.Title := JsonStr(O, 'title', 'Workspace');
  Result.Kind := wkPanels;
  Result.DocURI := '';
  Result.ViewOnly := False;
  Result.OriginWorkspaceId := Cardinal(Max(JsonInt(O, 'originWorkspaceId', 0), 0));
  Side := LowerCase(JsonStr(O, 'activeSide', 'left'));
  if Side = 'right' then
    Result.State.ActiveSide := psRight
  else
    Result.State.ActiveSide := psLeft;
  Result.State.LeftVisible := JsonBool(O, 'leftVisible', True);
  Result.State.RightVisible := JsonBool(O, 'rightVisible', True);
  if not Result.State.LeftVisible and not Result.State.RightVisible then
  begin
    Result.State.LeftVisible := True;
    Result.State.RightVisible := True;
  end;
  V := O.GetValue('left');
  if V is TJSONObject then
    Result.State.LeftPanel := PanelFromJson(TJSONObject(V))
  else
  begin
    Result.State.LeftPanel.ActiveTabIndex := 0;
    SetLength(Result.State.LeftPanel.Tabs, 0);
  end;
  V := O.GetValue('right');
  if V is TJSONObject then
    Result.State.RightPanel := PanelFromJson(TJSONObject(V))
  else
  begin
    Result.State.RightPanel.ActiveTabIndex := 0;
    SetLength(Result.State.RightPanel.Tabs, 0);
  end;
end;

function SessionIsUsable(const ASession: TMtnSession): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Result := False;
  if ASession.Version < 1 then
    Exit;
  if Length(ASession.Panels.WorkspaceTabs) = 0 then
    Exit;
  if (ASession.Panels.ActiveWorkspaceIndex < 0) or
     (ASession.Panels.ActiveWorkspaceIndex > High(ASession.Panels.WorkspaceTabs)) then
    Exit;
  for Ws in ASession.Panels.WorkspaceTabs do
  begin
    if Length(Ws.State.LeftPanel.Tabs) = 0 then
      Exit;
    if Length(Ws.State.RightPanel.Tabs) = 0 then
      Exit;
    if ActiveTab(Ws.State.LeftPanel).CurrentURI = '' then
      Exit;
    if ActiveTab(Ws.State.RightPanel).CurrentURI = '' then
      Exit;
  end;
  Result := True;
end;

function CustomColumnsToJson(const AConfig: TCustomColumnsConfig): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('ext', TJSONBool.Create(AConfig.ShowExt));
  Result.AddPair('size', TJSONBool.Create(AConfig.ShowSize));
  Result.AddPair('modified', TJSONBool.Create(AConfig.ShowModified));
  Result.AddPair('created', TJSONBool.Create(AConfig.ShowCreated));
  Result.AddPair('accessed', TJSONBool.Create(AConfig.ShowAccessed));
  Result.AddPair('type', TJSONBool.Create(AConfig.ShowType));
  Result.AddPair('attr', TJSONBool.Create(AConfig.ShowAttr));
end;

function CustomColumnsFromJson(O: TJSONObject): TCustomColumnsConfig;
begin
  Result := DefaultCustomColumnsConfig;
  if O = nil then
    Exit;
  Result.ShowExt := JsonBool(O, 'ext', Result.ShowExt);
  Result.ShowSize := JsonBool(O, 'size', Result.ShowSize);
  Result.ShowModified := JsonBool(O, 'modified', Result.ShowModified);
  Result.ShowCreated := JsonBool(O, 'created', Result.ShowCreated);
  Result.ShowAccessed := JsonBool(O, 'accessed', Result.ShowAccessed);
  Result.ShowType := JsonBool(O, 'type', Result.ShowType);
  Result.ShowAttr := JsonBool(O, 'attr', Result.ShowAttr);
end;

function WindowToJson(const AWindow: TMtnWindowBounds): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('left', TJSONNumber.Create(AWindow.Left));
  Result.AddPair('top', TJSONNumber.Create(AWindow.Top));
  Result.AddPair('width', TJSONNumber.Create(AWindow.Width));
  Result.AddPair('height', TJSONNumber.Create(AWindow.Height));
  Result.AddPair('maximized', TJSONBool.Create(AWindow.Maximized));
  if AWindow.Display <> '' then
    Result.AddPair('display', AWindow.Display);
end;

function WindowFromJson(O: TJSONObject): TMtnWindowBounds;
var
  V: TJSONValue;
begin
  Result.Valid := False;
  Result.Left := 0;
  Result.Top := 0;
  Result.Width := 0;
  Result.Height := 0;
  Result.Maximized := False;
  Result.Display := '';
  if O = nil then
    Exit;
  Result.Left := JsonFloat(O, 'left', 0);
  Result.Top := JsonFloat(O, 'top', 0);
  Result.Width := JsonFloat(O, 'width', 0);
  Result.Height := JsonFloat(O, 'height', 0);
  Result.Display := JsonStr(O, 'display', '');
  V := O.GetValue('maximized');
  if V is TJSONBool then
    Result.Maximized := TJSONBool(V).AsBoolean
  else
    Result.Maximized := JsonInt(O, 'maximized', 0) <> 0;
  Result.Valid := (Result.Width >= 200) and (Result.Height >= 160);
end;

function SaveSession(const APath: string; const ASession: TMtnSession): Boolean;
var
  Root: TJSONObject;
  Workspaces: TJSONArray;
  I: Integer;
  Dir, Text: string;
begin
  Result := False;
  Root := TJSONObject.Create;
  try
    try
      Root.AddPair('version', TJSONNumber.Create(cSessionVersion));
      Root.AddPair('zoom', TJSONNumber.Create(ASession.Zoom));
      if ASession.Window.Valid then
        Root.AddPair('window', WindowToJson(ASession.Window));
      Root.AddPair('activeWorkspace',
        TJSONNumber.Create(ASession.Panels.ActiveWorkspaceIndex));
      Workspaces := TJSONArray.Create;
      for I := 0 to High(ASession.Panels.WorkspaceTabs) do
        Workspaces.Add(WorkspaceToJson(ASession.Panels.WorkspaceTabs[I]));
      Root.AddPair('workspaces', Workspaces);
      if ASession.BackgroundConsoleProfile <> '' then
        Root.AddPair('backgroundConsoleProfile', ASession.BackgroundConsoleProfile);
      Root.AddPair('consoleRestartOnExit', TJSONBool.Create(ASession.ConsoleRestartOnExit));
      Root.AddPair('terminalCloseOnExit', TJSONBool.Create(ASession.TerminalCloseOnExit));
      Root.AddPair('autoSyncConsoleCwd', TJSONBool.Create(ASession.AutoSyncConsoleCwd));
      Root.AddPair('consoleStartOnLaunch', TJSONBool.Create(ASession.ConsoleStartOnLaunch));
      if ASession.ThemeName <> '' then
        Root.AddPair('theme', ASession.ThemeName);
      if ASession.ThemeFile <> '' then
        Root.AddPair('themeFile', ASession.ThemeFile);
      Root.AddPair('customColumns', CustomColumnsToJson(ASession.CustomColumns));
      if ASession.LastWorkspaceId <> '' then
        Root.AddPair('lastWorkspaceId', ASession.LastWorkspaceId);
      Root.AddPair('restoreWorkspaceOnStart', TJSONBool.Create(ASession.RestoreWorkspaceOnStart));
      if ASession.FontName <> '' then
        Root.AddPair('fontName', ASession.FontName);
      Root.AddPair('fontSize', TJSONNumber.Create(ASession.FontSize));
      Root.AddPair('cursorBlink', TJSONBool.Create(ASession.CursorBlink));
      Root.AddPair('cursorBlinkMs', TJSONNumber.Create(ASession.CursorBlinkMs));
      Root.AddPair('showPanelIcons', TJSONBool.Create(ASession.ShowPanelIcons));
      if ASession.Language <> '' then
        Root.AddPair('language', ASession.Language);
      Dir := ExtractFilePath(APath);
      if Dir <> '' then
        ForceDirectories(Dir);
      Text := Root.ToJSON;
      TFile.WriteAllText(APath, Text, TEncoding.UTF8);
      Result := True;
    except
      { leave Result = False }
    end;
  finally
    Root.Free;
  end;
end;

function TryLoadSession(const APath: string; out ASession: TMtnSession): Boolean;
var
  Text: string;
  RootVal: TJSONValue;
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  V: TJSONValue;
begin
  Result := False;
  ASession.Version := 0;
  ASession.Zoom := 1.0;
  ASession.Window.Valid := False;
  ASession.Panels.ActiveWorkspaceIndex := 0;
  SetLength(ASession.Panels.WorkspaceTabs, 0);
  ASession.BackgroundConsoleProfile := '';
  ASession.ConsoleRestartOnExit := True;
  ASession.TerminalCloseOnExit := True;
  ASession.AutoSyncConsoleCwd := False;
  ASession.ConsoleStartOnLaunch := False;
  ASession.ThemeName := '';
  ASession.ThemeFile := '';
  ASession.CustomColumns := DefaultCustomColumnsConfig;
  ASession.LastWorkspaceId := '';
  ASession.RestoreWorkspaceOnStart := True;
  ASession.FontName := '';
  ASession.FontSize := cDisplayDefaultFontSize;
  ASession.CursorBlink := True;
  ASession.CursorBlinkMs := cDisplayDefaultBlinkMs;
  ASession.ShowPanelIcons := True;
  ASession.Language := '';

  if not TFile.Exists(APath) then
    Exit;
  try
    Text := TFile.ReadAllText(APath, TEncoding.UTF8);
    RootVal := TJSONObject.ParseJSONValue(Text);
    if not (RootVal is TJSONObject) then
    begin
      RootVal.Free;
      Exit;
    end;
    Root := TJSONObject(RootVal);
    try
      ASession.Version := JsonInt(Root, 'version', 0);
      ASession.Zoom := EnsureRange(JsonFloat(Root, 'zoom', 1.0), 0.5, 3.0);
      V := Root.GetValue('window');
      if V is TJSONObject then
        ASession.Window := WindowFromJson(TJSONObject(V));
      ASession.Panels.ActiveWorkspaceIndex :=
        Max(JsonInt(Root, 'activeWorkspace', 0), 0);
      V := Root.GetValue('workspaces');
      if not (V is TJSONArray) then
        Exit;
      Arr := TJSONArray(V);
      SetLength(ASession.Panels.WorkspaceTabs, Arr.Count);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
          ASession.Panels.WorkspaceTabs[I] :=
            WorkspaceFromJson(TJSONObject(Arr.Items[I]))
        else
          Exit;
      if ASession.Panels.ActiveWorkspaceIndex >
         High(ASession.Panels.WorkspaceTabs) then
        ASession.Panels.ActiveWorkspaceIndex := 0;
      ASession.BackgroundConsoleProfile :=
        JsonStr(Root, 'backgroundConsoleProfile', '');
      ASession.ConsoleRestartOnExit :=
        JsonBool(Root, 'consoleRestartOnExit', True);
      ASession.TerminalCloseOnExit :=
        JsonBool(Root, 'terminalCloseOnExit', True);
      ASession.AutoSyncConsoleCwd :=
        JsonBool(Root, 'autoSyncConsoleCwd', False);
      ASession.ConsoleStartOnLaunch :=
        JsonBool(Root, 'consoleStartOnLaunch', False);
      ASession.ThemeName := JsonStr(Root, 'theme', '');
      ASession.ThemeFile := JsonStr(Root, 'themeFile', '');
      V := Root.GetValue('customColumns');
      if V is TJSONObject then
        ASession.CustomColumns := CustomColumnsFromJson(TJSONObject(V));
      ASession.LastWorkspaceId := JsonStr(Root, 'lastWorkspaceId', '');
      ASession.RestoreWorkspaceOnStart :=
        JsonBool(Root, 'restoreWorkspaceOnStart', True);
      ASession.FontName := JsonStr(Root, 'fontName', '');
      ASession.FontSize :=
        ClampDisplayFontSize(JsonFloat(Root, 'fontSize', cDisplayDefaultFontSize));
      ASession.CursorBlink := JsonBool(Root, 'cursorBlink', True);
      ASession.CursorBlinkMs :=
        ClampDisplayBlinkMs(JsonInt(Root, 'cursorBlinkMs', cDisplayDefaultBlinkMs));
      ASession.ShowPanelIcons := JsonBool(Root, 'showPanelIcons', True);
      ASession.Language := JsonStr(Root, 'language', '');
      Result := SessionIsUsable(ASession);
      if not Result then
      begin
        SetLength(ASession.Panels.WorkspaceTabs, 0);
        ASession.Version := 0;
        ASession.Window.Valid := False;
      end;
    finally
      Root.Free;
    end;
  except
    Result := False;
    SetLength(ASession.Panels.WorkspaceTabs, 0);
    ASession.Version := 0;
    ASession.Window.Valid := False;
  end;
end;

end.
