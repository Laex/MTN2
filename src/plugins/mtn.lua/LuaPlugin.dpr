library LuaPlugin;

{ Native MTN2 plugin: macros in Lua. Ctrl+. records the keys the user presses and
  saves them as a macro file in the macros folder of the settings directory;
  every macro file is a command that runs from its own key or the Macros menu,
  in the panels, viewer, editor and terminal. The Macros menu also opens the
  manager (enable and disable, edit, assign a key, reload). See uLuaMacros for
  the engine and the mtn API macros use. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections, System.RegularExpressions, System.Character, System.NetEncoding,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uLuaApi in 'uLuaApi.pas',
  uLuaHostFns in 'uLuaHostFns.pas',
  uLuaMacros in 'uLuaMacros.pas';

const
  cPluginId = 'mtn.lua';
  cRecordCommand = 'macro.record';
  cRecordChord = 'Ctrl+.';
  cPauseCommand = 'macro.pause';
  cPauseChord = 'Ctrl+Shift+.';
  cKeyTopic = 'input.key';
  cMenuPath = 'Macros';
  cSettingDisabled = 'disabled';

type
  /// <summary>Stable user data of a macro command: survives a reload of the macro files.</summary>
  TSlot = class
  public
    Macro: TMacro;
  end;

var
  GHostApi: THostApiTable;
  GMacrosDir: string;
  GLoadError: string;
  GRecording: Boolean;
  GPaused: Boolean;
  GPauseItemShown: Boolean;
  { The key the key dialog shows again after a clash warning, and the macro+key pair already warned about. }
  GKeyDraft, GKeyWarned: string;
  GRecorded: TStringList;
  GRecordArea: string;
  GLastKey: string;
  GSlots: TObjectDictionary<string, TSlot>;
  GBound: TStringList;
  GMenuIds: TStringList;
  GDisabled: TStringList;
  GListIds: TStringList;
  GListTexts: TStringList;
  GListSelected: Integer;
  GPending: TStringList;
  GPendingArea: string;
  GDialogMacro: string;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..511] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHostApi.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure Notice(const AText: string; AKind: Integer = 0);
var
  Raw: UTF8String;
begin
  if not Assigned(GHostApi.ShowMessage) then
    Exit;
  Raw := UTF8String(AText);
  GHostApi.ShowMessage(PAnsiChar(Raw), AKind);
end;

{ Why macros are off, with the way to fix it for this platform. }
function NoLuaText: string;
begin
  {$IFDEF MSWINDOWS}
  Result := Format(Tr('err.noLuaWin', 'Macros need the Lua library (lua55.dll next to the plugin): %s'), [GLoadError]);
  {$ELSE}
  Result := Format(Tr('err.noLuaLinux',
    'Macros need the Lua library: install liblua5.4-0 (Debian, Ubuntu) or lua-libs (Fedora). %s'), [GLoadError]);
  {$ENDIF}
end;

{ What the program already binds the chord to ('' = free). The plugin's own macro commands are
  left to the macro checks, which know which of them are live. }
function KeyOwner(const AChord: string): string;
var
  Chord: UTF8String;
  Buf: array[0..255] of AnsiChar;
begin
  Result := '';
  if (AChord = '') or not Assigned(GHostApi.KeyOwner) then
    Exit;
  Chord := UTF8String(AChord);
  Buf[0] := #0;
  if GHostApi.KeyOwner(PAnsiChar(Chord), @Buf[0], SizeOf(Buf)) > 0 then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
  if Result.StartsWith('macro.run.') then
    Result := '';
end;

function GetSettingText(const AKey: string): string;
var
  Plugin, Key: UTF8String;
  Buf: array[0..1023] of AnsiChar;
begin
  Result := '';
  if not Assigned(GHostApi.GetSetting) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Buf[0] := #0;
  if GHostApi.GetSetting(PAnsiChar(Plugin), PAnsiChar(Key), @Buf[0], SizeOf(Buf)) >= 0 then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure SetSettingText(const AKey, AValue: string);
var
  Plugin, Key, Value: UTF8String;
begin
  if not Assigned(GHostApi.SetSetting) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Value := UTF8String(AValue);
  GHostApi.SetSetting(PAnsiChar(Plugin), PAnsiChar(Key), PAnsiChar(Value));
end;

function PluginFolder: string;
var
  Buf: array[0..MAX_PATH] of Char;
begin
  GetModuleFileName(HInstance, Buf, Length(Buf));
  Result := ExtractFilePath(string(Buf));
end;

function ConfigFolder: string;
var
  Info: string;
  V: TJSONValue;
begin
  Result := '';
  Info := GEngine.HostText(GHostApi.HostInfo);
  if Info = '' then
    Exit;
  V := TJSONObject.ParseJSONValue(Info);
  try
    if V is TJSONObject then
      Result := TJSONObject(V).GetValue<string>('configDir', '');
  finally
    V.Free;
  end;
end;

{ A macro key must be a chord that is not typed text: with Ctrl or Alt, or a function key. }
function IsMacroChord(const AChord: string): Boolean;
var
  U: string;
  I: Integer;
begin
  U := UpperCase(StringReplace(AChord, ' ', '', [rfReplaceAll]));
  if (Pos('CTRL+', U) > 0) or (Pos('ALT+', U) > 0) then
    Exit(True);
  I := LastDelimiter('+', U);
  U := Copy(U, I + 1, MaxInt);
  Result := (Length(U) >= 2) and (U[1] = 'F') and (StrToIntDef(Copy(U, 2, MaxInt), 0) in [1..24]);
end;

{ ---- enabled and disabled macros ---- }

function IsDisabled(const AId: string): Boolean;
begin
  Result := GDisabled.IndexOf(AId) >= 0;
end;

procedure SetDisabled(const AId: string; ADisabled: Boolean);
var
  I: Integer;
begin
  I := GDisabled.IndexOf(AId);
  if ADisabled and (I < 0) then
    GDisabled.Add(AId)
  else if (not ADisabled) and (I >= 0) then
    GDisabled.Delete(I);
  SetSettingText(cSettingDisabled, GDisabled.CommaText);
end;

{ ---- running and registering ---- }

procedure CmdRunMacro(AUserData: Pointer); cdecl;
var
  Slot: TSlot;
begin
  try
    Slot := TSlot(AUserData);
    if (GEngine = nil) or (Slot = nil) then
      Exit;
    if Slot.Macro = nil then
      Notice(Tr('err.gone', 'The macro file was removed'), 1)
    else if IsDisabled(Slot.Macro.Id) then
      Notice(Format(Tr('err.disabled', 'The macro "%s" is turned off'), [Slot.Macro.Name]), 1)
    else
      GEngine.Run(Slot.Macro);
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

function CommandId(AMacro: TMacro): string;
begin
  Result := 'macro.run.' + AMacro.Id;
end;

procedure RegisterMacro(AMacro: TMacro);
var
  Plugin, Cmd, Chord, Caption, MenuItem, Parent: UTF8String;
  Slot: TSlot;
  BoundKey: string;
begin
  if not GSlots.TryGetValue(AMacro.Id, Slot) then
  begin
    Slot := TSlot.Create;
    GSlots.Add(AMacro.Id, Slot);
  end;
  Slot.Macro := AMacro;
  Plugin := UTF8String(cPluginId);
  Cmd := UTF8String(CommandId(AMacro));
  GHostApi.RegisterCommand(PAnsiChar(Plugin), PAnsiChar(Cmd), @CmdRunMacro, Pointer(Slot));
  if AMacro.Key <> '' then
  begin
    if IsMacroChord(AMacro.Key) and Assigned(GHostApi.RegisterKeyBinding) then
    begin
      // A chord stays bound to the command until the program restarts.
      BoundKey := AMacro.Id + '|' + AMacro.Key;
      if GBound.IndexOf(BoundKey) < 0 then
      begin
        Chord := UTF8String(AMacro.Key);
        GHostApi.RegisterKeyBinding(PAnsiChar(Plugin), PAnsiChar(Cmd), PAnsiChar(Chord));
        GBound.Add(BoundKey);
      end;
    end
    else
      Notice(Format(Tr('err.key', 'Macro "%s": the key %s must use Ctrl or Alt, or be a function key'),
        [AMacro.Name, AMacro.Key]), 1);
  end;
  if AMacro.InMenu and Assigned(GHostApi.RegisterMenuItem) then
  begin
    Parent := UTF8String(cMenuPath);
    MenuItem := UTF8String(CommandId(AMacro));
    Caption := UTF8String(AMacro.Name);
    GHostApi.RegisterMenuItem(PAnsiChar(Plugin), PAnsiChar(Parent), PAnsiChar(MenuItem),
      PAnsiChar(Caption), @CmdRunMacro, Pointer(Slot), 100);
    if GMenuIds.IndexOf(AMacro.Id) < 0 then
      GMenuIds.Add(AMacro.Id);
  end;
end;

procedure RegisterAllMacros;
var
  M: TMacro;
begin
  for M in GEngine.Macros do
    RegisterMacro(M);
end;

{ Menu items cannot be removed one by one; registering an item again with an empty
  caption hides it. }
procedure HideStaleMenuItems;
var
  I: Integer;
  Slot: TSlot;
  Plugin, Parent, Item, Caption: UTF8String;
begin
  if not Assigned(GHostApi.RegisterMenuItem) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Parent := UTF8String(cMenuPath);
  Caption := '';
  for I := GMenuIds.Count - 1 downto 0 do
    if not GSlots.TryGetValue(GMenuIds[I], Slot) or (Slot.Macro = nil) or not Slot.Macro.InMenu then
    begin
      Item := UTF8String('macro.run.' + GMenuIds[I]);
      GHostApi.RegisterMenuItem(PAnsiChar(Plugin), PAnsiChar(Parent), PAnsiChar(Item),
        PAnsiChar(Caption), @CmdRunMacro, nil, 100);
      GMenuIds.Delete(I);
    end;
end;

procedure ReloadMacros;
var
  Slot: TSlot;
begin
  if GEngine.Running <> nil then
  begin
    Notice(Tr('err.busy', 'A macro is already running (Esc stops it)'), 1);
    Exit;
  end;
  for Slot in GSlots.Values do
    Slot.Macro := nil;
  GEngine.LoadFolder(GMacrosDir);
  RegisterAllMacros;
  HideStaleMenuItems;
end;

{ ---- dialogs ---- }

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText, AValue: string;
  ACol, ARow, AWidth: Integer; AChecked: Boolean = False; ADefault: Boolean = False;
  ACancel: Boolean = False; AHeight: Integer = 1);
var
  O: TJSONObject;
  KeyCapture: Boolean;
begin
  // "hotkey" is an input that stores the pressed chord.
  KeyCapture := AType = 'hotkey';
  O := TJSONObject.Create;
  if KeyCapture then
    O.AddPair('type', 'input')
  else
    O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if (AType = 'input') or KeyCapture then
    O.AddPair('value', AValue);
  if KeyCapture then
    O.AddPair('hotkey', TJSONBool.Create(True));
  if AType = 'checkbox' then
    O.AddPair('checked', TJSONBool.Create(AChecked));
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(AHeight));
  AChildren.AddElement(O);
end;

{ A horizontal line across the whole dialog (80 cells wide). }
procedure AddRule(AChildren: TJSONArray; ARow: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'separator');
  O.AddPair('col', TJSONNumber.Create(0));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(78));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

function ShowDialogJson(const AJson: string; ACallback: THostDialogCommandCallback): Boolean;
var
  Plugin, Json: UTF8String;
begin
  Plugin := UTF8String(cPluginId);
  Json := UTF8String(AJson);
  Result := Assigned(GHostApi.ShowDialog) and
    (GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), ACallback, nil) = 0);
  if not Result then
    Notice(Tr('msg.noDialog', 'The dialog cannot be shown now.'), 1);
end;

function DialogHeader(const ATitle: string; AWidth, AHeight: Integer; out AKids: TJSONArray): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'dialog');
  Result.AddPair('version', '2.0');
  Result.AddPair('title', ATitle);
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(AHeight));
  AKids := TJSONArray.Create;
  Result.AddPair('children', AKids);
end;

function ValueOf(const AValuesJson, AName: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  V := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if V is TJSONObject then
      Result := TJSONObject(V).GetValue<string>(AName, '');
  finally
    V.Free;
  end;
end;

function BoolValueOf(const AValuesJson, AName: string): Boolean;
var
  V: TJSONValue;
  B: TJSONValue;
begin
  Result := False;
  V := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if V is TJSONObject then
    begin
      B := TJSONObject(V).GetValue(AName);
      Result := (B is TJSONBool) and TJSONBool(B).AsBoolean;
    end;
  finally
    V.Free;
  end;
end;

{ ---- macro files ---- }

function MacroSource(const AName, AArea, AKey: string; AMenu: Boolean; const AKeys: TStrings): string;
var
  Body: TStringList;
  I: Integer;
  Text: string;

  procedure FlushText;
  begin
    if Text <> '' then
      Body.Add('    mtn.text(' + LuaQuote(Text) + ')');
    Text := '';
  end;

begin
  Body := TStringList.Create;
  try
    Text := '';
    for I := 0 to AKeys.Count - 1 do
      if Length(AKeys[I]) = 1 then
        Text := Text + AKeys[I]
      else
      begin
        FlushText;
        Body.Add('    mtn.key(' + LuaQuote(AKeys[I]) + ')');
      end;
    FlushText;
    Result := 'macro {' + sLineBreak +
      '  name = ' + LuaQuote(AName) + ',' + sLineBreak;
    if AArea <> '' then
      Result := Result + '  area = ' + LuaQuote(AArea) + ',' + sLineBreak;
    if AKey <> '' then
      Result := Result + '  key = ' + LuaQuote(AKey) + ',' + sLineBreak;
    if AMenu then
      Result := Result + '  menu = true,' + sLineBreak;
    Result := Result + '  run = function()' + sLineBreak + Body.Text + '  end,' + sLineBreak + '}' + sLineBreak;
  finally
    Body.Free;
  end;
end;

function FileSlug(const AName: string): string;
var
  C: Char;
begin
  Result := '';
  for C in LowerCase(AName) do
    if C.IsLetterOrDigit then
      Result := Result + C
    else if (Result <> '') and (Result[Length(Result)] <> '-') then
      Result := Result + '-';
  Result := Result.Trim(['-']);
  if Result = '' then
    Result := 'macro';
end;

function MacroWithKey(const AKey: string; AExceptId: string): TMacro;
var
  M: TMacro;
begin
  Result := nil;
  if AKey = '' then
    Exit;
  for M in GEngine.Macros do
    if (M.Id <> AExceptId) and SameText(StringReplace(M.Key, ' ', '', [rfReplaceAll]),
         StringReplace(AKey, ' ', '', [rfReplaceAll])) then
      Exit(M);
end;

{ Sets the key field in the header of a macro file (the part before run). }
procedure SetKeyInFile(const APath, AKey: string);
var
  Text, Head, Tail, Field: string;
  RunAt: TMatch;
  Rx: TRegEx;
begin
  Text := TFile.ReadAllText(APath, TEncoding.UTF8);
  Field := 'key = ' + LuaQuote(AKey);
  RunAt := TRegEx.Match(Text, '(?<![\w.])run\s*=');
  if RunAt.Success then
  begin
    Head := Copy(Text, 1, RunAt.Index - 1);
    Tail := Copy(Text, RunAt.Index, MaxInt);
  end
  else
  begin
    Head := Text;
    Tail := '';
  end;
  Rx := TRegEx.Create('(?<![\w.])key\s*=\s*"[^"]*"');
  if Rx.IsMatch(Head) then
    Head := Rx.Replace(Head, Field)
  else
    Head := TRegEx.Replace(Head, 'macro\s*\{', 'macro {' + sLineBreak + '  ' + Field + ',');
  TFile.WriteAllText(APath, Head + Tail, TUTF8Encoding.Create(False));
end;

{ ---- recording ---- }

function SaveMacroFile(const AName, AKey: string; AMenu: Boolean): TMacro;
var
  Path, Slug: string;
begin
  TDirectory.CreateDirectory(GMacrosDir);
  Slug := FileSlug(AName);
  Path := TPath.Combine(GMacrosDir, Slug + '.lua');
  if TFile.Exists(Path) then
    Path := TPath.Combine(GMacrosDir, Slug + '-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.lua');
  TFile.WriteAllText(Path, MacroSource(AName, GPendingArea, AKey, AMenu, GPending),
    TUTF8Encoding.Create(False));
  Result := GEngine.LoadFile(Path);
  if Result <> nil then
  begin
    RegisterMacro(Result);
    Notice(Format(Tr('msg.saved', 'Macro saved: %s'), [TPath.GetFileName(Path)]));
  end;
end;

procedure OnSaveDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Name, Key, Values: string;
begin
  try
    if not SameText(string(AControlId), 'ok') then
    begin
      Notice(Tr('msg.discarded', 'The recording was discarded'));
      Exit;
    end;
    Values := UTF8ToString(AValuesJson);
    Name := Trim(ValueOf(Values, 'name'));
    Key := Trim(ValueOf(Values, 'key'));
    if Name = '' then
      Name := 'Macro ' + FormatDateTime('yyyymmdd-hhnnss', Now);
    if (Key <> '') and not IsMacroChord(Key) then
    begin
      Notice(Format(Tr('err.key', 'Macro "%s": the key %s must use Ctrl or Alt, or be a function key'),
        [Name, Key]), 1);
      Key := '';
    end
    else if MacroWithKey(Key, '') <> nil then
    begin
      Notice(Format(Tr('err.keyTaken', 'The key %s is already used by the macro "%s"'),
        [Key, MacroWithKey(Key, '').Name]), 1);
      Key := '';
    end
    else if (Key <> '') and (KeyOwner(Key) <> '') then
    begin
      Notice(Format(Tr('err.keyOwnedSaved', 'The key %s is already used by "%s"; the macro is saved without a key'),
        [Key, KeyOwner(Key)]), 1);
      Key := '';
    end;
    SaveMacroFile(Name, Key, BoolValueOf(Values, 'menu'));
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

procedure SaveRecording;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
begin
  if GRecorded.Count = 0 then
  begin
    Notice(Tr('msg.emptyRecording', 'Nothing was recorded'), 1);
    Exit;
  end;
  GPending.Assign(GRecorded);
  GPendingArea := GRecordArea;
  Decl := DialogHeader(Tr('dlg.saveTitle', 'Save macro'), 60, 13, Kids);
  try
    AddControl(Kids, 'label', '', Tr('dlg.name', 'Name:'), '', 2, 1, 54);
    AddControl(Kids, 'input', 'name', '', 'Macro ' + FormatDateTime('yyyymmdd-hhnnss', Now), 2, 2, 54);
    AddControl(Kids, 'label', '', Tr('dlg.keyHint', 'Key (Ctrl+..., Alt+... or F2..F12; may stay empty):'),
      '', 2, 4, 54);
    AddControl(Kids, 'input', 'key', '', '', 2, 5, 54);
    AddControl(Kids, 'checkbox', 'menu', Tr('dlg.menu', 'Show in the &Macros menu'), '', 2, 7, 54, True);
    AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), '', 16, 9, 12, False, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), '', 31, 9, 12, False, False, True);
    if not ShowDialogJson(Decl.ToJSON, OnSaveDialog) then
    begin
      // No dialog now: keep the recording under a time-stamped name.
      GPendingArea := GRecordArea;
      SaveMacroFile('Recorded ' + FormatDateTime('yyyymmdd-hhnnss', Now), '', True);
    end;
  finally
    Decl.Free;
  end;
end;

{ While recording, the status line of the panels and a chip in the tab row show the
  state; the chip's window stops the recording, Ctrl+Shift+. pauses it. }
{ The pause item is greyed out until a recording runs. }
procedure SyncPauseMenuItem;
var
  Plugin, Item: UTF8String;
begin
  if GPauseItemShown = GRecording then
    Exit;
  GPauseItemShown := GRecording;
  if not Assigned(GHostApi.SetMenuItemEnabled) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Item := UTF8String(cPauseCommand);
  GHostApi.SetMenuItemEnabled(PAnsiChar(Plugin), PAnsiChar(Item), Ord(GRecording));
end;

procedure UpdateRecIndicator;
var
  Plugin, Id, Json: UTF8String;
  Arr: TJSONArray;
  Part: TJSONObject;
  Head, Info: string;
begin
  SyncPauseMenuItem;
  if GRecording then
  begin
    if GPaused then
      Head := Tr('rec.paused', 'PAUSED')
    else
      Head := Tr('rec.recording', 'REC');
    Info := Format(Tr('rec.keys', '%d keys'), [GRecorded.Count]) + '  ' +
      Tr('rec.hint', 'Ctrl+. stop, Ctrl+Shift+. pause');
  end;
  Plugin := UTF8String(cPluginId);
  Id := 'rec';
  if not GRecording then
  begin
    if Assigned(GHostApi.SetStatusSegmentStyled) then
      GHostApi.SetStatusSegmentStyled(PAnsiChar(Plugin), PAnsiChar(Id), nil);
    Exit;
  end;
  if Assigned(GHostApi.SetStatusSegmentStyled) then
  begin
    Arr := TJSONArray.Create;
    try
      Part := TJSONObject.Create;
      Part.AddPair('t', ' ' + Head + ' ');
      if GPaused then
        Part.AddPair('role', 'warn')
      else
        Part.AddPair('role', 'error');
      Part.AddPair('b', TJSONBool.Create(True));
      // A click on the badge stops the recording.
      Part.AddPair('c', cRecordCommand);
      // Compact forms for the host's tab bar when its status line is hidden.
      if GPaused then
        Part.AddPair('s', ' PAUSE ')
      else
        Part.AddPair('s', ' REC ');
      Arr.AddElement(Part);
      Part := TJSONObject.Create;
      Part.AddPair('t', ' ' + Info);
      Part.AddPair('role', 'info');
      Part.AddPair('s', ' ' + IntToStr(GRecorded.Count) + ' ');
      Arr.AddElement(Part);
      Json := UTF8String(Arr.ToJSON);
    finally
      Arr.Free;
    end;
    GHostApi.SetStatusSegmentStyled(PAnsiChar(Plugin), PAnsiChar(Id), PAnsiChar(Json));
  end;
end;

procedure FinishRecording(ATrimStopKey: Boolean);
begin
  GRecording := False;
  GPaused := False;
  UpdateRecIndicator;
  // The key that stops the recording arrived just before the command; a click
  // or a menu choice leaves the last recorded key alone.
  if ATrimStopKey and (GRecorded.Count > 0) and (GRecorded[GRecorded.Count - 1] = GLastKey) and
     SameText(GLastKey, cRecordChord) then
    GRecorded.Delete(GRecorded.Count - 1);
  SaveRecording;
end;

procedure StartRecording;
begin
  GRecorded.Clear;
  GRecordArea := GEngine.CurrentArea;
  GRecording := True;
  GPaused := False;
  UpdateRecIndicator;
  Notice(Tr('msg.recording', 'Recording a macro: Ctrl+. stops, Ctrl+Shift+. pauses'));
end;

procedure CmdRecord(AUserData: Pointer); cdecl;
begin
  try
    if GEngine = nil then
    begin
      Notice(NoLuaText, 1);
      Exit;
    end;
    if not GRecording then
      StartRecording
    else
      FinishRecording(True);
  except
    on E: Exception do
    begin
      GRecording := False;
      GPaused := False;
      UpdateRecIndicator;
      Notice(E.Message, 1);
    end;
  end;
end;

procedure CmdPause(AUserData: Pointer); cdecl;
begin
  try
    if not GRecording then
      Exit;
    // The pause chord itself is not part of the macro.
    if (GRecorded.Count > 0) and (GRecorded[GRecorded.Count - 1] = GLastKey) and
       (Pos('Ctrl+', GLastKey) = 1) and not GPaused then
      GRecorded.Delete(GRecorded.Count - 1);
    GPaused := not GPaused;
    UpdateRecIndicator;
    if GPaused then
      Notice(Tr('msg.paused', 'Recording paused: Ctrl+Shift+. resumes'))
    else
      Notice(Tr('msg.resumed', 'Recording resumed'));
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

{ ---- the manager ---- }

procedure ShowManager(ASelected: Integer); forward;

procedure ReopenManager(AUserData: Pointer); cdecl;
begin
  try
    ShowManager(GListSelected);
  except
    // The dialog is only a convenience; a failure leaves the program as it was.
  end;
end;

procedure ReopenLater;
var
  Plugin: UTF8String;
begin
  Plugin := UTF8String(cPluginId);
  if Assigned(GHostApi.PostToMain) then
    GHostApi.PostToMain(PAnsiChar(Plugin), @ReopenManager, nil)
  else
    ReopenManager(nil);
end;

procedure ShowKeyDialog(AMacro: TMacro); forward;

procedure ReopenKeyDialog(AUserData: Pointer); cdecl;
var
  M: TMacro;
begin
  try
    for M in GEngine.Macros do
      if M.Id = GDialogMacro then
      begin
        ShowKeyDialog(M);
        Exit;
      end;
  except
    // The dialog is only a convenience.
  end;
end;

procedure OnKeyDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Key: string;
  M: TMacro;
  Taken: TMacro;
  Plugin: UTF8String;
begin
  try
    if SameText(string(AControlId), 'ok') then
    begin
      Key := Trim(ValueOf(UTF8ToString(AValuesJson), 'key'));
      M := nil;
      for Taken in GEngine.Macros do
        if Taken.Id = GDialogMacro then
          M := Taken;
      if M <> nil then
      begin
        if (Key <> '') and not IsMacroChord(Key) then
          Notice(Format(Tr('err.key', 'Macro "%s": the key %s must use Ctrl or Alt, or be a function key'),
            [M.Name, Key]), 1)
        else
        begin
          Taken := MacroWithKey(Key, M.Id);
          if Taken <> nil then
            Notice(Format(Tr('err.keyTaken', 'The key %s is already used by the macro "%s"'),
              [Key, Taken.Name]), 1)
          else if (Key <> '') and not SameText(Key, M.Key) and (KeyOwner(Key) <> '') and
                  (GKeyWarned <> M.Id + '|' + Key) then
          begin
            // The first OK only warns; the same key confirmed again is assigned.
            GKeyWarned := M.Id + '|' + Key;
            GKeyDraft := Key;
            Notice(Format(Tr('err.keyOwned', 'The key %s is already used by "%s". OK again assigns it to the macro anyway'),
              [Key, KeyOwner(Key)]), 1);
            if Assigned(GHostApi.PostToMain) then
            begin
              Plugin := UTF8String(cPluginId);
              GHostApi.PostToMain(PAnsiChar(Plugin), @ReopenKeyDialog, nil);
            end;
            Exit;
          end
          else
          begin
            SetKeyInFile(M.Path, Key);
            ReloadMacros;
            Notice(Tr('msg.keyChanged', 'Key saved. A key replaced by another one stops working after the program restarts.'));
          end;
        end;
      end;
    end;
    ReopenLater;
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

procedure ShowKeyDialog(AMacro: TMacro);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
begin
  GDialogMacro := AMacro.Id;
  Decl := DialogHeader(Tr('dlg.keyTitle', 'Macro key'), 60, 11, Kids);
  try
    AddControl(Kids, 'label', '', Format(Tr('dlg.keyFor', 'Key for "%s":'), [AMacro.Name]), '', 2, 1, 54);
    if GKeyDraft <> '' then
      AddControl(Kids, 'hotkey', 'key', '', GKeyDraft, 2, 2, 54)
    else
      AddControl(Kids, 'hotkey', 'key', '', AMacro.Key, 2, 2, 54);
    GKeyDraft := '';
    AddControl(Kids, 'label', '', Tr('dlg.keyRule', 'Press the key combination; Backspace removes the key.'),
      '', 2, 4, 54);
    AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), '', 16, 7, 12, False, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), '', 31, 7, 12, False, False, True);
    ShowDialogJson(Decl.ToJSON, OnKeyDialog);
  finally
    Decl.Free;
  end;
end;

function SelectedMacro(const AValuesJson: string): TMacro;
var
  Text: string;
  I: Integer;
  M: TMacro;
begin
  Result := nil;
  Text := ValueOf(AValuesJson, 'macros');
  I := GListTexts.IndexOf(Text);
  if I < 0 then
    Exit;
  GListSelected := I;
  for M in GEngine.Macros do
    if M.Id = GListIds[I] then
      Exit(M);
end;

procedure OnDeleteDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  M: TMacro;
  Path: string;
begin
  try
    if SameText(string(AControlId), 'ok') then
    begin
      Path := '';
      for M in GEngine.Macros do
        if M.Id = GDialogMacro then
          Path := M.Path;
      if (Path <> '') and TFile.Exists(Path) then
      begin
        TFile.Delete(Path);
        ReloadMacros;
        Notice(Tr('msg.deleted', 'Macro file deleted. Its menu item and key stop working after the program restarts.'));
      end;
    end;
    ReopenLater;
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

procedure ShowDeleteDialog(AMacro: TMacro);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
begin
  GDialogMacro := AMacro.Id;
  Decl := DialogHeader(Tr('dlg.deleteTitle', 'Delete macro'), 60, 10, Kids);
  try
    AddControl(Kids, 'label', '', Format(Tr('dlg.deleteAsk', 'Delete the macro "%s"?'), [AMacro.Name]), '', 2, 1, 54);
    AddControl(Kids, 'label', '', Format(Tr('dlg.deleteFile', 'The file %s will be removed.'),
      [TPath.GetFileName(AMacro.Path)]), '', 2, 2, 54);
    AddControl(Kids, 'button', 'ok', Tr('dlg.delete', '&Delete'), '', 16, 6, 12, False, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), '', 31, 6, 12, False, False, True);
    ShowDialogJson(Decl.ToJSON, OnDeleteDialog);
  finally
    Decl.Free;
  end;
end;

{ ---- import and export ---- }

function CleanPath(const AText: string): string;
begin
  Result := Trim(AText).DeQuotedString('"');
end;

function LooksLikeMacro(const APath: string): Boolean;
begin
  try
    Result := TRegEx.IsMatch(TFile.ReadAllText(APath, TEncoding.UTF8), '(?<![\w.])macro\s*[\{\(]');
  except
    Result := False;
  end;
end;

{ Copies one macro file into the macros folder under a name that is not taken. }
function ImportFile(const ASource: string): Boolean;
var
  Dest, Base: string;
  N: Integer;
begin
  Result := False;
  if not LooksLikeMacro(ASource) then
    Exit;
  TDirectory.CreateDirectory(GMacrosDir);
  Base := TPath.GetFileNameWithoutExtension(ASource);
  Dest := TPath.Combine(GMacrosDir, Base + '.lua');
  N := 1;
  while TFile.Exists(Dest) do
  begin
    Inc(N);
    Dest := TPath.Combine(GMacrosDir, Base + '-' + IntToStr(N) + '.lua');
  end;
  TFile.Copy(ASource, Dest);
  Result := True;
end;

procedure OnImportDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Path, F: string;
  Done, Skipped: Integer;
  Files: TArray<string>;
begin
  try
    if SameText(string(AControlId), 'ok') then
    begin
      Path := CleanPath(ValueOf(UTF8ToString(AValuesJson), 'path'));
      Files := nil;
      if TDirectory.Exists(Path) then
        Files := TDirectory.GetFiles(Path, '*.lua')
      else if TFile.Exists(Path) then
        Files := [Path]
      else
        Notice(Format(Tr('err.noPath', 'Not found: %s'), [Path]), 1);
      Done := 0;
      Skipped := 0;
      for F in Files do
        if ImportFile(F) then
          Inc(Done)
        else
          Inc(Skipped);
      if Length(Files) > 0 then
      begin
        SetSettingText('importPath', Path);
        ReloadMacros;
        Notice(Format(Tr('msg.imported', 'Imported macros: %d, skipped files that are not macros: %d'),
          [Done, Skipped]), Ord(Done = 0));
      end;
    end;
    ReopenLater;
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

procedure OnExportDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Path, F: string;
  Count: Integer;
begin
  try
    if SameText(string(AControlId), 'ok') then
    begin
      Path := CleanPath(ValueOf(UTF8ToString(AValuesJson), 'path'));
      if Path <> '' then
      begin
        TDirectory.CreateDirectory(Path);
        Count := 0;
        if TDirectory.Exists(GMacrosDir) then
          for F in TDirectory.GetFiles(GMacrosDir, '*.lua') do
          begin
            TFile.Copy(F, TPath.Combine(Path, TPath.GetFileName(F)), True);
            Inc(Count);
          end;
        SetSettingText('exportPath', Path);
        Notice(Format(Tr('msg.exported', 'Exported macros: %d'), [Count]));
      end;
    end;
    ReopenLater;
  except
    on E: Exception do
    begin
      Notice(E.Message, 1);
      ReopenLater;
    end;
  end;
end;

procedure ShowPathDialog(AImport: Boolean);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Start, Title, Hint: string;
begin
  if AImport then
  begin
    Title := Tr('dlg.importTitle', 'Import macros');
    Hint := Tr('dlg.importHint', 'A macro file or a folder with macro files:');
    Start := GetSettingText('importPath');
  end
  else
  begin
    Title := Tr('dlg.exportTitle', 'Export macros');
    Hint := Tr('dlg.exportHint', 'Folder to copy all macro files to:');
    Start := GetSettingText('exportPath');
    if Start = '' then
      Start := TPath.Combine(TPath.GetDocumentsPath, 'MTN2 macros');
  end;
  Decl := DialogHeader(Title, 70, 10, Kids);
  try
    AddControl(Kids, 'label', '', Hint, '', 2, 1, 64);
    AddControl(Kids, 'input', 'path', '', Start, 2, 2, 64);
    AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), '', 21, 6, 12, False, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), '', 36, 6, 12, False, False, True);
    if AImport then
      ShowDialogJson(Decl.ToJSON, OnImportDialog)
    else
      ShowDialogJson(Decl.ToJSON, OnExportDialog);
  finally
    Decl.Free;
  end;
end;

procedure OnManagerDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Cmd, Values, Uri: string;
  M: TMacro;
  UriUtf8: UTF8String;
begin
  try
    Cmd := LowerCase(string(AControlId));
    if (Cmd = 'cancel') or (GEngine = nil) then
      Exit;
    Values := UTF8ToString(AValuesJson);
    M := SelectedMacro(Values);
    if Cmd = 'import' then
      ShowPathDialog(True)
    else if Cmd = 'export' then
      ShowPathDialog(False)
    else if (Cmd = 'reload') or (Cmd = 'f5') then
    begin
      ReloadMacros;
      GListSelected := 0;
      ReopenLater;
    end
    else if M = nil then
      ReopenLater
    else if Cmd = 'run' then
      GEngine.Run(M)
    else if (Cmd = 'toggle') or (Cmd = 'ok') then
    begin
      SetDisabled(M.Id, not IsDisabled(M.Id));
      ReopenLater;
    end
    else if (Cmd = 'edit') or (Cmd = 'f4') then
    begin
      Uri := PathToFileUri(M.Path);
      UriUtf8 := UTF8String(Uri);
      if GHostApi.OpenDocument(PAnsiChar(UriUtf8), 1) <> 0 then
        Notice(Tr('msg.cannotOpen', 'The macro cannot be opened now.'), 1);
    end
    else if (Cmd = 'key') or (Cmd = 'f2') then
      ShowKeyDialog(M)
    else if Cmd = 'delete' then
      ShowDeleteDialog(M)
    else
      ReopenLater;
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

const
  cNameWidth = 26;
  cKeyWidth = 12;
  cAreaWidth = 8;

{ A table cell: the text cut to AWidth cells or padded with spaces to it. }
function Cell(const AText: string; AWidth: Integer): string;
begin
  if Length(AText) > AWidth then
    Result := Copy(AText, 1, AWidth - 3) + '...'
  else
    Result := AText + StringOfChar(' ', AWidth - Length(AText));
end;

procedure ShowManager(ASelected: Integer);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  List: TJSONObject;
  Items: TJSONArray;
  M: TMacro;
  Mark, KeyText, AreaText, Line: string;
begin
  if GEngine = nil then
  begin
    Notice(NoLuaText, 1);
    Exit;
  end;
  GListIds.Clear;
  GListTexts.Clear;
  Items := TJSONArray.Create;
  for M in GEngine.Macros do
  begin
    if IsDisabled(M.Id) then
      Mark := '[ ]'
    else
      Mark := '[x]';
    KeyText := M.Key;
    if KeyText = '' then
      KeyText := '-';
    AreaText := M.Areas;
    if AreaText = '' then
      AreaText := Tr('dlg.anywhere', 'any');
    Line := Mark + ' ' + Cell(M.Name, cNameWidth) + ' ' + Cell(KeyText, cKeyWidth) + ' ' +
      Cell(AreaText, cAreaWidth) + ' ' + TPath.GetFileName(M.Path);
    GListIds.Add(M.Id);
    GListTexts.Add(Line);
    Items.Add(Line);
  end;
  if GListTexts.Count = 0 then
  begin
    Items.Free;
    Notice(Format(Tr('msg.noMacros', 'No macros yet. Ctrl+. records one; files go to %s'), [GMacrosDir]));
    Exit;
  end;
  if (ASelected < 0) or (ASelected >= GListTexts.Count) then
    ASelected := 0;
  GListSelected := ASelected;
  Decl := DialogHeader(Tr('dlg.managerTitle', 'Macros'), 80, 19, Kids);
  try
    AddControl(Kids, 'label', '', Tr('dlg.managerHint', 'Macros in the macros folder of the settings:'), '', 2, 0, 74);
    AddControl(Kids, 'label', '', '    ' + Cell(Tr('dlg.colName', 'Name'), cNameWidth) + ' ' +
      Cell(Tr('dlg.colKey', 'Key'), cKeyWidth) + ' ' + Cell(Tr('dlg.colArea', 'Area'), cAreaWidth) + ' ' +
      Tr('dlg.colFile', 'File'), '', 2, 1, 74);
    List := TJSONObject.Create;
    List.AddPair('type', 'list');
    List.AddPair('id', 'macros');
    List.AddPair('items', Items);
    List.AddPair('selected', TJSONNumber.Create(ASelected));
    List.AddPair('keycommands', TJSONBool.Create(True));
    List.AddPair('col', TJSONNumber.Create(2));
    List.AddPair('row', TJSONNumber.Create(2));
    List.AddPair('width', TJSONNumber.Create(74));
    List.AddPair('height', TJSONNumber.Create(8));
    Kids.AddElement(List);
    AddRule(Kids, 10);
    AddControl(Kids, 'label', '', Tr('dlg.hint1', 'Enter - run   Space - on/off   F2 - key   F4 - edit'), '', 2, 11, 74);
    AddControl(Kids, 'label', '', Tr('dlg.hint2', 'Del - delete   F5 - reload   Esc - close'), '', 2, 12, 74);
    AddRule(Kids, 13);
    AddControl(Kids, 'button', 'run', Tr('dlg.run', '&Run'), '', 8, 15, 14, False, True);
    AddControl(Kids, 'button', 'import', Tr('dlg.import', '&Import...'), '', 24, 15, 14);
    AddControl(Kids, 'button', 'export', Tr('dlg.export', 'E&xport...'), '', 40, 15, 14);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.close', 'Close'), '', 56, 15, 14, False, False, True);
    ShowDialogJson(Decl.ToJSON, OnManagerDialog);
  finally
    Decl.Free;
  end;
end;

procedure CmdManage(AUserData: Pointer); cdecl;
begin
  try
    // Opening the manager re-reads the folder, so a macro edited meanwhile shows its new header.
    if (GEngine <> nil) and (GEngine.Running = nil) then
      ReloadMacros;
    ShowManager(0);
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

procedure CmdReload(AUserData: Pointer); cdecl;
begin
  try
    if GEngine = nil then
      Exit;
    ReloadMacros;
    Notice(Format(Tr('msg.reloaded', 'Macros loaded: %d'), [GEngine.Macros.Count]));
  except
    on E: Exception do
      Notice(E.Message, 1);
  end;
end;

procedure OnKeyEvent(AUserData: Pointer; ATopic, APayloadJson: PAnsiChar); cdecl;
var
  V: TJSONValue;
  Key: string;
begin
  try
    if (GEngine = nil) or (APayloadJson = nil) then
      Exit;
    V := TJSONObject.ParseJSONValue(UTF8ToString(APayloadJson));
    try
      if not (V is TJSONObject) then
        Exit;
      Key := TJSONObject(V).GetValue<string>('key', '');
    finally
      V.Free;
    end;
    if Key = '' then
      Exit;
    GLastKey := Key;
    if GEngine.Running <> nil then
    begin
      if SameText(Key, 'Esc') or SameText(Key, 'Escape') then
        GEngine.RequestAbort;
    end
    else if GRecording and not GPaused then
    begin
      GRecorded.Add(Key);
      UpdateRecIndicator;
    end;
  except
    // A malformed event is dropped.
  end;
end;

{ A macro file saved in the editor is loaded again, so the change applies at once. }
procedure ReloadIfMacroSaved(APayloadJson: PAnsiChar);
var
  V: TJSONValue;
  Uri, Path, Dir: string;
begin
  try
    if (GEngine = nil) or (APayloadJson = nil) or (GMacrosDir = '') then
      Exit;
    Uri := '';
    V := TJSONObject.ParseJSONValue(UTF8ToString(APayloadJson));
    try
      if V is TJSONObject then
        Uri := TJSONObject(V).GetValue<string>('uri', '');
    finally
      V.Free;
    end;
    if not Uri.StartsWith('file:///', True) then
      Exit;
    Path := FileUriToPath(Uri);
    Dir := IncludeTrailingPathDelimiter(GMacrosDir);
    if SameText(ExtractFileExt(Path), '.lua') and SameText(Copy(Path, 1, Length(Dir)), Dir) then
    begin
      ReloadMacros;
      Notice(Format(Tr('msg.reloaded', 'Macros loaded: %d'), [GEngine.Macros.Count]));
    end;
  except
    // A malformed event is dropped.
  end;
end;

procedure OnDocSaved(AUserData: Pointer; ATopic, APayloadJson: PAnsiChar); cdecl;
begin
  ReloadIfMacroSaved(APayloadJson);
  try
    if (GEngine <> nil) and (APayloadJson <> nil) then
      GEngine.DispatchEvent('doc.saved', UTF8ToString(APayloadJson));
  except
    // A handler's failure never reaches the host.
  end;
end;

procedure AddMenu(const AItemId, ACaption: string; AOnClick: THostRegisterMenuItemCallback;
  APriority: Integer);
var
  Plugin, Parent, Item, Caption: UTF8String;
begin
  if not Assigned(GHostApi.RegisterMenuItem) then
    Exit;
  Plugin := UTF8String(cPluginId);
  Parent := UTF8String(cMenuPath);
  Item := UTF8String(AItemId);
  Caption := UTF8String(ACaption);
  GHostApi.RegisterMenuItem(PAnsiChar(Plugin), PAnsiChar(Parent), PAnsiChar(Item),
    PAnsiChar(Caption), AOnClick, nil, APriority);
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  Plugin, Cmd, Chord, Topic: UTF8String;
  Engine: TMacroEngine;
  Err: string;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 8) or not Assigned(AHostApi.RegisterCommand) or
     not Assigned(AHostApi.SendKey) or not Assigned(AHostApi.Subscribe) then
    Exit(-1);
  GHostApi := AHostApi^;
  GRecorded := TStringList.Create;
  GPending := TStringList.Create;
  GListIds := TStringList.Create;
  GListTexts := TStringList.Create;
  GBound := TStringList.Create;
  GMenuIds := TStringList.Create;
  GDisabled := TStringList.Create;
  GDisabled.CommaText := GetSettingText(cSettingDisabled);
  GSlots := TObjectDictionary<string, TSlot>.Create([doOwnsValues]);
  Plugin := UTF8String(cPluginId);
  Engine := TMacroEngine.Create(@GHostApi, cPluginId, Tr);
  if Engine.Open(PluginFolder, Err) then
  begin
    GEngine := Engine;
    GMacrosDir := TPath.Combine(ConfigFolder, 'macros');
    Cmd := UTF8String(cRecordCommand);
    GHostApi.RegisterCommand(PAnsiChar(Plugin), PAnsiChar(Cmd), @CmdRecord, nil);
    Chord := UTF8String(cRecordChord);
    GHostApi.RegisterKeyBinding(PAnsiChar(Plugin), PAnsiChar(Cmd), PAnsiChar(Chord));
    Cmd := UTF8String(cPauseCommand);
    GHostApi.RegisterCommand(PAnsiChar(Plugin), PAnsiChar(Cmd), @CmdPause, nil);
    Chord := UTF8String(cPauseChord);
    GHostApi.RegisterKeyBinding(PAnsiChar(Plugin), PAnsiChar(Cmd), PAnsiChar(Chord));
    Topic := UTF8String(cKeyTopic);
    GHostApi.Subscribe(PAnsiChar(Plugin), PAnsiChar(Topic), @OnKeyEvent, nil);
    Topic := 'doc.saved';
    GHostApi.Subscribe(PAnsiChar(Plugin), PAnsiChar(Topic), @OnDocSaved, nil);
    AddMenu('macro.manage', Tr('menu.manage', '&Manage macros...'), @CmdManage, 10);
    AddMenu(cRecordCommand, Tr('menu.record', '&Record / stop recording'), @CmdRecord, 20);
    AddMenu(cPauseCommand, Tr('menu.pause', '&Pause / resume recording'), @CmdPause, 25);
    GPauseItemShown := True;
    SyncPauseMenuItem;
    AddMenu('macro.reload', Tr('menu.reload', 'Re&load macros'), @CmdReload, 30);
    GEngine.LoadFolder(GMacrosDir);
    RegisterAllMacros;
  end
  else
  begin
    GLoadError := Err;
    Engine.Free;
    // The record key still answers, with the reason macros are off.
    Cmd := UTF8String(cRecordCommand);
    GHostApi.RegisterCommand(PAnsiChar(Plugin), PAnsiChar(Cmd), @CmdRecord, nil);
    AddMenu('macro.manage', Tr('menu.manage', '&Manage macros...'), @CmdManage, 10);
  end;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GRecording := False;
  FreeAndNil(GEngine);
  FreeAndNil(GSlots);
  FreeAndNil(GRecorded);
  FreeAndNil(GPending);
  FreeAndNil(GListIds);
  FreeAndNil(GListTexts);
  FreeAndNil(GBound);
  FreeAndNil(GMenuIds);
  FreeAndNil(GDisabled);
  LuaUnload;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
