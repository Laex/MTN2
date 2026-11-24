unit uPluginSdk;

{ Helpers shared by the native plugins: the host table and the plugin id, text
  calls, settings, dialog declarations, background jobs and worker threads.
  A plugin calls SdkAttach from mtn_plugin_init and SdkDetach from
  mtn_plugin_shutdown; SdkDetach waits for the workers, so a worker can use the
  host table until it ends. }

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, uPluginHostAbi;

var
  GHostApi: THostApiTable;
  GPluginId: string;
  GShutdown: Boolean;

procedure SdkAttach(AHostApi: PHostApiTable; const APluginId: string);
procedure SdkDetach;

/// <summary>Runs AProc on a worker thread that SdkDetach waits for. Exceptions
/// do not leave the thread.</summary>
procedure SdkRunWorker(const AProc: TProc);

/// <summary>Runs ACallback on the main thread; False when the plugin is shutting
/// down or the host has no PostToMain.</summary>
function SdkPostToMain(ACallback: THostMainCallback; AUserData: Pointer = nil): Boolean;

function Tr(const AKey, ADefault: string): string;
procedure Notice(const AText: string; AKind: Int64);
function GetSettingText(const AKey: string): string;
procedure SetSettingText(const AKey, AValue: string);
function HostText(AFn: THostTextOutFn): string;
/// <summary>JSON of the rows of the active panel (PanelList for the active side).</summary>
function HostPanelListText: string;

type
  TPanelRowHandler = reference to procedure(ARow: TJSONObject);

/// <summary>Calls AHandler for each selected row of the active panel in list order,
/// or for the row under the cursor when nothing is selected. ADirUri is the folder
/// of the list. False when the panel cannot be read.</summary>
function ForEachSelectedRow(out ADirUri: string; const AHandler: TPanelRowHandler): Boolean;

procedure JobBeginNow(const AKey, ATitle: string; AOnCancel: THostMainCallback);
procedure JobEndNow(const AKey: string);

{ ---- dialog declarations ---- }

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth, AHeight: Integer; ADefault: Boolean = False; ACancel: Boolean = False);
/// <summary>AddControl with a height of one row.</summary>
procedure AddItem(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth: Integer; ADefault: Boolean = False; ACancel: Boolean = False);
procedure AddField(AChildren: TJSONArray; const AId, AValue: string;
  ACol, ARow, AWidth: Integer);
procedure AddCheck(AChildren: TJSONArray; const AId, AText: string; AChecked: Boolean;
  ACol, ARow, AWidth: Integer);
function NewDialog(const ATitle: string; AWidth, AHeight: Integer;
  out AChildren: TJSONArray): TJSONObject;
function ShowDeclaration(ADecl: TJSONObject; ACallback: THostDialogCommandCallback): Boolean;

implementation

uses
  System.SyncObjs;

const
  cWorkerWaitMs = 15000;

var
  GWorkers: Integer;

procedure SdkAttach(AHostApi: PHostApiTable; const APluginId: string);
begin
  GHostApi := AHostApi^;
  GPluginId := APluginId;
  GShutdown := False;
end;

procedure SdkDetach;
var
  Waited: Integer;
begin
  GShutdown := True;
  Waited := 0;
  while (TInterlocked.CompareExchange(GWorkers, 0, 0) > 0) and (Waited < cWorkerWaitMs) do
  begin
    Sleep(10);
    Inc(Waited, 10);
  end;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

procedure SdkRunWorker(const AProc: TProc);
begin
  TInterlocked.Increment(GWorkers);
  try
    TThread.CreateAnonymousThread(
      procedure
      begin
        try
          try
            AProc();
          except
            // The job reports its own errors; nothing may escape the thread.
          end;
        finally
          TInterlocked.Decrement(GWorkers);
        end;
      end).Start;
  except
    TInterlocked.Decrement(GWorkers);
    raise;
  end;
end;

function SdkPostToMain(ACallback: THostMainCallback; AUserData: Pointer): Boolean;
var
  Id: UTF8String;
begin
  Result := False;
  if GShutdown or not Assigned(GHostApi.PostToMain) then
    Exit;
  Id := UTF8String(GPluginId);
  Result := GHostApi.PostToMain(PAnsiChar(Id), ACallback, AUserData) = 0;
end;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..1023] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(GPluginId);
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
  Plugin := UTF8String(GPluginId);
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
  Plugin := UTF8String(GPluginId);
  Key := UTF8String(AKey);
  Value := UTF8String(AValue);
  GHostApi.SetSetting(PAnsiChar(Plugin), PAnsiChar(Key), PAnsiChar(Value));
end;

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

function HostPanelListText: string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if not Assigned(GHostApi.PanelList) then
    Exit;
  Len := GHostApi.PanelList(-1, nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelList(-1, PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

function ForEachSelectedRow(out ADirUri: string; const AHandler: TPanelRowHandler): Boolean;
var
  List, Info, Side: TJSONValue;
  Rows, Selected: TJSONArray;
  Row: TJSONValue;
  Sel: TArray<string>;
  Uri, ActiveSide: string;
  Cursor, I: Integer;
begin
  Result := False;
  ADirUri := '';
  List := TJSONObject.ParseJSONValue(HostPanelListText);
  Info := TJSONObject.ParseJSONValue(HostText(GHostApi.PanelInfo));
  try
    if not (List is TJSONObject) or not (Info is TJSONObject) or
       not TJSONObject(List).TryGetValue<string>('uri', ADirUri) or
       not TJSONObject(List).TryGetValue<TJSONArray>('rows', Rows) then
      Exit;
    if TJSONObject(Info).TryGetValue<string>('active', ActiveSide) then
    begin
      Side := TJSONObject(Info).GetValue(ActiveSide);
      if (Side is TJSONObject) and TJSONObject(Side).TryGetValue<TJSONArray>('selected', Selected) then
        for I := 0 to Selected.Count - 1 do
          Sel := Sel + [Selected.Items[I].Value];
    end;
    if Length(Sel) > 0 then
    begin
      for Row in Rows do
        if (Row is TJSONObject) and TJSONObject(Row).TryGetValue<string>('uri', Uri) then
          for I := 0 to High(Sel) do
            if Sel[I] = Uri then
            begin
              AHandler(TJSONObject(Row));
              Break;
            end;
    end
    else if TJSONObject(List).TryGetValue<Integer>('cursor', Cursor) and
            (Cursor >= 0) and (Cursor < Rows.Count) and (Rows.Items[Cursor] is TJSONObject) then
      AHandler(TJSONObject(Rows.Items[Cursor]));
    Result := True;
  finally
    List.Free;
    Info.Free;
  end;
end;

procedure JobBeginNow(const AKey, ATitle: string; AOnCancel: THostMainCallback);
var
  Plugin, Key, Title: UTF8String;
begin
  if not Assigned(GHostApi.JobBegin) then
    Exit;
  Plugin := UTF8String(GPluginId);
  Key := UTF8String(AKey);
  Title := UTF8String(ATitle);
  GHostApi.JobBegin(PAnsiChar(Plugin), PAnsiChar(Key), PAnsiChar(Title), AOnCancel, nil);
end;

procedure JobEndNow(const AKey: string);
var
  Plugin, Key: UTF8String;
begin
  if not Assigned(GHostApi.JobEnd) then
    Exit;
  Plugin := UTF8String(GPluginId);
  Key := UTF8String(AKey);
  GHostApi.JobEnd(PAnsiChar(Plugin), PAnsiChar(Key));
end;

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth, AHeight: Integer; ADefault: Boolean; ACancel: Boolean);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
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

procedure AddItem(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth: Integer; ADefault: Boolean; ACancel: Boolean);
begin
  AddControl(AChildren, AType, AId, AText, ACol, ARow, AWidth, 1, ADefault, ACancel);
end;

procedure AddField(AChildren: TJSONArray; const AId, AValue: string;
  ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'input');
  O.AddPair('id', AId);
  O.AddPair('value', AValue);
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

procedure AddCheck(AChildren: TJSONArray; const AId, AText: string; AChecked: Boolean;
  ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'checkbox');
  O.AddPair('id', AId);
  O.AddPair('text', AText);
  O.AddPair('checked', TJSONBool.Create(AChecked));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

function NewDialog(const ATitle: string; AWidth, AHeight: Integer;
  out AChildren: TJSONArray): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'dialog');
  Result.AddPair('version', '2.0');
  Result.AddPair('title', ATitle);
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(AHeight));
  AChildren := TJSONArray.Create;
  Result.AddPair('children', AChildren);
end;

function ShowDeclaration(ADecl: TJSONObject; ACallback: THostDialogCommandCallback): Boolean;
var
  Json, Plugin: UTF8String;
begin
  Result := False;
  if not Assigned(GHostApi.ShowDialog) then
    Exit;
  Json := UTF8String(ADecl.ToJSON);
  Plugin := UTF8String(GPluginId);
  Result := GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), ACallback, nil) = 0;
end;

end.
