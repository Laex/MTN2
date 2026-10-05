library NotesPlugin;

{ Demo plugin in Delphi: quick notes. Ctrl+Alt+F8 ("Note" in the function bar)
  asks for a line of text and appends it, with the time, to mtn2-notes.txt in
  the user's profile folder (or the file chosen under Settings in the Plugins
  dialog); the status line shows how many notes the file has.

  Shows: a plugin command with a key chord and a bar caption, a dialog with an
  input field described as JSON (the answer carries the typed text), and a
  status-line segment, and a settings dialog (the host keeps the value). The host
  table is the Delphi record THostApiTable. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  uPluginHostAbi in '..\..\..\src\Core\uPluginHostAbi.pas';

const
  cPluginId: UTF8String = 'mtn.demo.pas';
  cCommandId: UTF8String = 'demo.pas.note';
  cDialog: UTF8String =
    '{"type":"dialog","version":"2.0","title":"Quick note","width":56,"height":9,' +
    '"children":[' +
    '{"type":"label","text":"Note:","col":2,"row":1,"width":8,"height":1},' +
    '{"type":"input","id":"note","value":"","col":10,"row":1,"width":42,"height":1},' +
    '{"type":"button","id":"ok","text":"  OK  ","default":true,"col":16,"row":5,"width":10,"height":1},' +
    '{"type":"button","id":"cancel","text":"Cancel","cancel":true,"col":29,"row":5,"width":10,"height":1}]}';

var
  GHost: PHostApiTable;
  GCount: Integer;

function NotesFile: string;
var
  Buf: array[0..1023] of AnsiChar;
  Len: Int64;
begin
  Result := '';
  // The notes file chosen in the settings dialog, if any.
  if (GHost <> nil) and Assigned(GHost.GetSetting) then
  begin
    Len := GHost.GetSetting(PAnsiChar(cPluginId), 'file', @Buf[0], SizeOf(Buf));
    if Len > 0 then
      Result := string(UTF8String(PAnsiChar(@Buf[0])));
  end;
  if Result = '' then
    Result := TPath.Combine(GetEnvironmentVariable('USERPROFILE'), 'mtn2-notes.txt');
end;

procedure ShowCount;
var
  Text: UTF8String;
begin
  if (GHost = nil) or not Assigned(GHost.SetStatusSegment) then
    Exit;
  Text := UTF8String(Format('Notes: %d', [GCount]));
  GHost.SetStatusSegment(PAnsiChar(cPluginId), 'count', PAnsiChar(Text));
end;

procedure CountExistingNotes;
begin
  GCount := 0;
  if TFile.Exists(NotesFile) then
    try
      GCount := Length(TFile.ReadAllLines(NotesFile, TEncoding.UTF8));
    except
      GCount := 0;
    end;
end;

procedure AppendNote(const AText: string);
begin
  try
    TFile.AppendAllText(NotesFile,
      FormatDateTime('yyyy-mm-dd hh:nn', Now) + '  ' + AText + sLineBreak, TEncoding.UTF8);
    Inc(GCount);
  except
    // An unwritable profile folder: the count simply does not change.
  end;
end;

procedure OnDialogAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Note: string;
begin
  try
    if string(UTF8String(AControlId)) <> 'ok' then
      Exit;
    Root := TJSONObject.ParseJSONValue(string(UTF8String(AValuesJson)));
    try
      if Root is TJSONObject then
        Note := Trim(TJSONObject(Root).GetValue<string>('note', ''))
      else
        Note := '';
    finally
      Root.Free;
    end;
    if Note <> '' then
    begin
      AppendNote(Note);
      ShowCount;
    end;
  except
    // Never let an exception cross into the host.
  end;
end;

procedure OnSettingsAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  FileName: string;
begin
  try
    if string(UTF8String(AControlId)) <> 'ok' then
      Exit;
    Root := TJSONObject.ParseJSONValue(string(UTF8String(AValuesJson)));
    try
      if Root is TJSONObject then
        FileName := Trim(TJSONObject(Root).GetValue<string>('file', ''))
      else
        FileName := '';
    finally
      Root.Free;
    end;
    GHost.SetSetting(PAnsiChar(cPluginId), 'file', PAnsiChar(UTF8String(FileName)));
    CountExistingNotes;
    ShowCount;
  except
    // Never let an exception cross into the host.
  end;
end;

// "Settings" in the Plugins dialog: ask for the notes file (empty = default).
procedure OnConfigure(AUserData: Pointer); cdecl;
var
  Decl: TJSONObject;
  Children: TJSONArray;
  Child: TJSONObject;
  Json: UTF8String;

  function Control(const AType: string; ACol, ARow, AWidth: Integer): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.AddPair('type', AType);
    Result.AddPair('col', TJSONNumber.Create(ACol));
    Result.AddPair('row', TJSONNumber.Create(ARow));
    Result.AddPair('width', TJSONNumber.Create(AWidth));
    Result.AddPair('height', TJSONNumber.Create(1));
  end;

begin
  Decl := TJSONObject.Create;
  try
    Decl.AddPair('type', 'dialog');
    Decl.AddPair('version', '2.0');
    Decl.AddPair('title', 'Notes settings');
    Decl.AddPair('width', TJSONNumber.Create(64));
    Decl.AddPair('height', TJSONNumber.Create(9));
    Children := TJSONArray.Create;
    Child := Control('label', 2, 1, 40);
    Child.AddPair('text', 'Notes file (empty = mtn2-notes.txt in the profile):');
    Children.Add(Child);
    Child := Control('input', 2, 2, 58);
    Child.AddPair('id', 'file');
    Child.AddPair('value', NotesFile);
    Children.Add(Child);
    Child := Control('button', 20, 5, 10);
    Child.AddPair('id', 'ok');
    Child.AddPair('text', '  OK  ');
    Child.AddPair('default', TJSONTrue.Create);
    Children.Add(Child);
    Child := Control('button', 33, 5, 10);
    Child.AddPair('id', 'cancel');
    Child.AddPair('text', 'Cancel');
    Child.AddPair('cancel', TJSONTrue.Create);
    Children.Add(Child);
    Decl.AddPair('children', Children);
    Json := UTF8String(Decl.ToJSON);
  finally
    Decl.Free;
  end;
  GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(Json), @OnSettingsAnswer, nil);
end;

procedure OnAddNote(AUserData: Pointer); cdecl;
begin
  if (GHost <> nil) and Assigned(GHost.ShowDialog) then
    GHost.ShowDialog(PAnsiChar(cPluginId), PAnsiChar(cDialog), @OnDialogAnswer, nil);
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 2) or
     not Assigned(AHostApi.RegisterCommand) or not Assigned(AHostApi.ShowDialog) or
     not Assigned(AHostApi.GetSetting) or not Assigned(AHostApi.RegisterSettings) then
    Exit(-1);
  GHost := AHostApi;
  CountExistingNotes;
  AHostApi.RegisterCommand(PAnsiChar(cPluginId), PAnsiChar(cCommandId), @OnAddNote, nil);
  AHostApi.RegisterKeyBinding(PAnsiChar(cPluginId), PAnsiChar(cCommandId), 'Ctrl+Alt+F8');
  AHostApi.SetCommandCaption(PAnsiChar(cPluginId), PAnsiChar(cCommandId), 'Note');
  AHostApi.RegisterSettings(PAnsiChar(cPluginId), @OnConfigure, nil);
  ShowCount;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GHost := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
