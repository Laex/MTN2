library LogFilterPlugin;

{ Native MTN2 plugin: Ctrl+Shift+J in the viewer or editor asks for a text or a
  regular expression and opens the lines of the document that match it (or, for
  an inverted filter, do not) in a new viewer tab, each with its number in the
  original text. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uLogFilter in 'uLogFilter.pas';

const
  cPluginId = 'mtn.logfilter';
  cCommandId = 'logfilter.filter';
  cKeyChord = 'Ctrl+Shift+J';
  cSettingPattern = 'lastPattern';
  cSettingFlags = 'lastFlags';
  cMaxLines = 3000000;
  cTempFolder = 'mtn2-filter';
  cKeepDays = 1;

var
  GHostApi: THostApiTable;
  GDocPath: string;
  GTempFiles: TArray<string>;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..255] of AnsiChar;
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

procedure Notice(const AText: string; AKind: Int64);
var
  Text: UTF8String;
begin
  if not Assigned(GHostApi.ShowMessage) then
    Exit;
  Text := UTF8String(AText);
  GHostApi.ShowMessage(PAnsiChar(Text), AKind);
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

{ A text result of the host (DocInfo and the like): '' when it is not available. }
function HostText(AFn: THostTextOutFn): string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if not Assigned(AFn) then
    Exit;
  Len := AFn(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := AFn(PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

function DocumentText: string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  Len := GHostApi.DocGetText(1, nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.DocGetText(1, PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

function TempFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, cTempFolder);
end;

{ Filter files of earlier runs that are still lying around are removed. }
procedure RemoveOldTempFiles;
var
  F: string;
begin
  try
    if not TDirectory.Exists(TempFolder) then
      Exit;
    for F in TDirectory.GetFiles(TempFolder) do
      if Now - TFile.GetLastWriteTime(F) > cKeepDays then
        TFile.Delete(F);
  except
    // A file another program holds open stays for the next time.
  end;
end;

function FlagsToText(const AOptions: TLogFilterOptions): string;
begin
  Result := '';
  if AOptions.MatchCase then
    Result := Result + 'c';
  if AOptions.Regex then
    Result := Result + 'r';
  if AOptions.Invert then
    Result := Result + 'i';
  if AOptions.LineNumbers then
    Result := Result + 'n';
end;

procedure TextToFlags(const AText: string; var AOptions: TLogFilterOptions);
begin
  AOptions.MatchCase := Pos('c', AText) > 0;
  AOptions.Regex := Pos('r', AText) > 0;
  AOptions.Invert := Pos('i', AText) > 0;
  AOptions.LineNumbers := Pos('n', AText) > 0;
end;

function JsonBool(ARoot: TJSONObject; const AKey: string): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  V := ARoot.GetValue(AKey);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else if V <> nil then
    Result := SameText(V.Value, 'true') or (V.Value = '1');
end;

{ The temporary file for the lines kept from ASourcePath, named after it so the
  new tab shows where they came from. }
function WriteResult(const ASourcePath, AText: string): string;
var
  Base, Ext: string;
begin
  TDirectory.CreateDirectory(TempFolder);
  Base := TPath.GetFileNameWithoutExtension(ASourcePath);
  Ext := TPath.GetExtension(ASourcePath);
  if Base = '' then
    Base := 'document';
  Result := TPath.Combine(TempFolder,
    Format('%s.filter-%s%s', [Base, FormatDateTime('hhnnsszzz', Now), Ext]));
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
  SetLength(GTempFiles, Length(GTempFiles) + 1);
  GTempFiles[High(GTempFiles)] := Result;
end;

procedure RunFilter(const AOptions: TLogFilterOptions);
var
  Text, Err, Output, Path, Uri: string;
  Matched, Total: Integer;
  UriUtf8: UTF8String;
begin
  Text := DocumentText;
  if Text = '' then
  begin
    Notice(Tr('msg.noText', 'Open a text document in the viewer or editor first.'), 1);
    Exit;
  end;
  Output := FilterLines(Text, AOptions, Matched, Total, Err);
  if Err <> '' then
  begin
    Notice(Format(Tr('msg.badPattern', 'The pattern cannot be used: %s'), [Err]), 1);
    Exit;
  end;
  if Matched = 0 then
  begin
    Notice(Format(Tr('msg.nothing', 'No line matches (%d lines checked).'), [Total]), 0);
    Exit;
  end;
  Path := WriteResult(GDocPath, Output);
  Uri := PathToFileUri(Path);
  UriUtf8 := UTF8String(Uri);
  if GHostApi.OpenDocument(PAnsiChar(UriUtf8), 0) <> 0 then
    Notice(Tr('msg.cannotOpen', 'The result cannot be shown now.'), 1)
  else
    Notice(Format(Tr('msg.done', 'Kept %d of %d lines.'), [Matched, Total]), 0);
end;

procedure OnFilterDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Options: TLogFilterOptions;
begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    Options := Default(TLogFilterOptions);
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) then
        Exit;
      Root.TryGetValue<string>('pattern', Options.Pattern);
      Options.MatchCase := JsonBool(TJSONObject(Root), 'case');
      Options.Regex := JsonBool(TJSONObject(Root), 'regex');
      Options.Invert := JsonBool(TJSONObject(Root), 'invert');
      Options.LineNumbers := JsonBool(TJSONObject(Root), 'numbers');
    finally
      Root.Free;
    end;
    if Options.Pattern = '' then
      Exit;
    SetSettingText(cSettingPattern, Options.Pattern);
    SetSettingText(cSettingFlags, FlagsToText(Options));
    RunFilter(Options);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText, AValue: string;
  ACol, ARow, AWidth: Integer; AChecked: Boolean = False; ADefault: Boolean = False;
  ACancel: Boolean = False);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if AType = 'input' then
    O.AddPair('value', AValue);
  if AType = 'checkbox' then
    O.AddPair('checked', TJSONBool.Create(AChecked));
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

procedure ShowFilterDialog;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Json, Plugin: UTF8String;
  Options: TLogFilterOptions;
  Flags: string;
begin
  Options := Default(TLogFilterOptions);
  Options.LineNumbers := True;
  Flags := GetSettingText(cSettingFlags);
  if (Flags <> '') or (GetSettingText(cSettingPattern) <> '') then
    TextToFlags(Flags, Options);
  Decl := TJSONObject.Create;
  try
    Decl.AddPair('type', 'dialog');
    Decl.AddPair('version', '2.0');
    Decl.AddPair('title', Tr('dlg.title', 'Filter lines'));
    Decl.AddPair('width', TJSONNumber.Create(60));
    Decl.AddPair('height', TJSONNumber.Create(13));
    Kids := TJSONArray.Create;
    Decl.AddPair('children', Kids);
    AddControl(Kids, 'label', '', Tr('dlg.hint', 'Keep the lines that contain:'), '', 2, 1, 54);
    AddControl(Kids, 'input', 'pattern', '', GetSettingText(cSettingPattern), 2, 2, 54);
    AddControl(Kids, 'checkbox', 'case', Tr('dlg.case', '&Match case'), '', 3, 4, 50,
      Options.MatchCase);
    AddControl(Kids, 'checkbox', 'regex', Tr('dlg.regex', '&Regular expression'), '', 3, 5, 50,
      Options.Regex);
    AddControl(Kids, 'checkbox', 'invert', Tr('dlg.invert', '&Invert (lines that do not match)'),
      '', 3, 6, 50, Options.Invert);
    AddControl(Kids, 'checkbox', 'numbers', Tr('dlg.numbers', 'Original line &numbers'), '',
      3, 7, 50, Options.LineNumbers);
    AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), '', 16, 10, 12, False, True);
    AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), '', 31, 10, 12, False,
      False, True);
    Json := UTF8String(Decl.ToJSON);
  finally
    Decl.Free;
  end;
  Plugin := UTF8String(cPluginId);
  if GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), @OnFilterDialog, nil) <> 0 then
    Notice(Tr('msg.noDialog', 'The dialog cannot be shown now.'), 1);
end;

procedure CmdFilter(AUserData: Pointer); cdecl;
var
  Info: string;
  Root: TJSONValue;
  Lines: Integer;
  Hex: Boolean;
begin
  try
    GDocPath := '';
    Lines := 0;
    Hex := False;
    Info := HostText(GHostApi.DocInfo);
    if Info <> '' then
    begin
      Root := TJSONObject.ParseJSONValue(Info);
      try
        if Root is TJSONObject then
        begin
          Root.TryGetValue<string>('path', GDocPath);
          Root.TryGetValue<Integer>('lines', Lines);
          Root.TryGetValue<Boolean>('hex', Hex);
        end;
      finally
        Root.Free;
      end;
    end;
    if (Info = '') or Hex then
    begin
      Notice(Tr('msg.noText', 'Open a text document in the viewer or editor first.'), 1);
      Exit;
    end;
    if Lines > cMaxLines then
    begin
      Notice(Format(Tr('msg.tooBig', 'The document has more than %d lines: use grep or the search.'),
        [cMaxLines]), 1);
      Exit;
    end;
    ShowFilterDialog;
  except
    // Never let an exception cross into the host.
  end;
end;

procedure MenuFilter(AUserData: Pointer); cdecl;
begin
  CmdFilter(AUserData);
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  PluginId, CommandId, Chord: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 6) or not Assigned(AHostApi.DocGetText) or
     not Assigned(AHostApi.OpenDocument) or not Assigned(AHostApi.ShowDialog) or
     not Assigned(AHostApi.RegisterCommand) then
    Exit(-1);
  GHostApi := AHostApi^;
  RemoveOldTempFiles;
  PluginId := UTF8String(cPluginId);
  CommandId := UTF8String(cCommandId);
  Chord := UTF8String(cKeyChord);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(CommandId), @CmdFilter, nil);
  if Assigned(GHostApi.RegisterKeyBinding) then
    GHostApi.RegisterKeyBinding(PAnsiChar(PluginId), PAnsiChar(CommandId), PAnsiChar(Chord));
  if Assigned(GHostApi.RegisterMenuItem) then
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Plugins', PAnsiChar(CommandId),
      PAnsiChar(UTF8String(Tr('menu.filter', 'Filter lines...'))), @MenuFilter, nil, 50);
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
var
  F: string;
begin
  for F in GTempFiles do
    try
      TFile.Delete(F);
    except
      // Still open in a tab: removed by the next start.
    end;
  GTempFiles := nil;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
