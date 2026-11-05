unit uLuaHostFns;

{ The part of the mtn API of macros that reads and changes the program: the
  document of the editor and viewer, the panels, the clipboard, dialogs and
  external programs. The functions are registered as raw globals (mtn_doc_text,
  ...); the Lua prelude of uLuaMacros wraps them, adds the yields and removes
  the raw names. None of them raises a Lua error: a failure is a nil or false
  result.

  Programs start without a shell, one at a time, from a worker thread that the
  macro polls (so Esc still works), and only when the running macro lists the
  program name in its exec field. }

interface

uses
  System.SysUtils, uLuaApi, uPluginHostAbi;

type
  /// <summary>Text for the user; the plugin glue supplies the translation.</summary>
  TLuaText = reference to function(const AKey, ADefault: string): string;

var
  /// <summary>Program names the running macro may start, comma separated.</summary>
  GExecAllowed: string;

/// <summary>Registers the raw functions as globals of the Lua state.</summary>
procedure LuaHostRegister(L: PLuaState; AApi: PHostApiTable; const APluginId: string;
  ATr: TLuaText);

/// <summary>Pushes the JSON text as a Lua value (objects and arrays become
/// tables); nil when it is not JSON.</summary>
procedure LuaPushJson(L: PLuaState; const AJson: string);

/// <summary>Stops a program that is still running and forgets an open dialog's answer.</summary>
procedure LuaHostReset;

/// <summary>True when AProgram is a bare program name that AAllowed lists.</summary>
function ExecAllowed(const AProgram, AAllowed: string): Boolean;

implementation

uses
  System.Classes, System.Math, System.StrUtils, System.JSON, System.SyncObjs, uVfsTypes, uPlatformProcess;

const
  cDefaultExecSeconds = 10;
  cMaxExecSeconds = 60;
  cMaxOutputChars = 1024 * 1024;
  cDialogWidth = 64;
  cMaxListRows = 12;
  cMaxTextLines = 6;

type
  TCancelToken = class(TInterfacedObject, IJobCancelToken)
  private
    FCancelled: Integer;
  public
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

  TExecJob = class(TThread)
  private
    FExe: string;
    FArgs: TArray<string>;
    FStdIn: string;
    FTimeoutMs: Cardinal;
    FToken: IJobCancelToken;
    FDone: Integer;
  protected
    procedure Execute; override;
  public
    Output: string;
    ExitCode: Cardinal;
    Failure: string;
    constructor Create(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
      ATimeoutMs: Cardinal);
    procedure Abort;
    function Finished: Boolean;
  end;

var
  GApi: PHostApiTable;
  GPlugin: UTF8String;
  GTr: TLuaText;
  GJob: TExecJob;
  GDlgSerial: Integer;
  GDlgPending: Boolean;
  GDlgKind: string;
  GDlgItems: TArray<string>;
  GDlgId, GDlgValues: string;

{ ---- helpers ---- }

function LocalText(const AKey, ADefault: string): string;
begin
  if Assigned(GTr) then
    Result := GTr(AKey, ADefault)
  else
    Result := ADefault;
end;

// Reads host text with the measure-then-fetch convention; False when the host
// has none (-1).
function ReadHostText(const AFetch: TFunc<PAnsiChar, Int64, Int64>; out AText: string): Boolean;
var
  Len: Int64;
  Raw: UTF8String;
begin
  AText := '';
  Len := AFetch(nil, 0);
  if Len < 0 then
    Exit(False);
  if Len > 0 then
  begin
    SetLength(Raw, Len + 1);
    if AFetch(PAnsiChar(Raw), Len + 1) <> Len then
      Exit(False);
    AText := UTF8ToString(Copy(Raw, 1, Len));
  end;
  Result := True;
end;

function SideArg(L: PLuaState; AIndex: Integer): Int64;
var
  S: string;
begin
  S := LowerCase(lua_tostr(L, AIndex));
  if S = 'left' then
    Result := 0
  else if S = 'right' then
    Result := 1
  else
    Result := -1;
end;

function PushBool(L: PLuaState; AValue: Boolean): Integer;
begin
  lua_pushboolean(L, Ord(AValue));
  Result := 1;
end;

function PushText(L: PLuaState; AOk: Boolean; const AText: string): Integer;
begin
  if AOk then
    lua_pushstr(L, AText)
  else
    lua_pushnil(L);
  Result := 1;
end;

procedure PushValue(L: PLuaState; AValue: TJSONValue);
var
  I: Integer;
  Pair: TJSONPair;
  S: string;
  Name: UTF8String;
begin
  if AValue is TJSONObject then
  begin
    lua_createtable(L, 0, TJSONObject(AValue).Count);
    for Pair in TJSONObject(AValue) do
    begin
      PushValue(L, Pair.JsonValue);
      Name := UTF8String(Pair.JsonString.Value);
      lua_setfield(L, -2, PAnsiChar(Name));
    end;
  end
  else if AValue is TJSONArray then
  begin
    lua_createtable(L, TJSONArray(AValue).Count, 0);
    for I := 0 to TJSONArray(AValue).Count - 1 do
    begin
      PushValue(L, TJSONArray(AValue).Items[I]);
      lua_seti(L, -2, I + 1);
    end;
  end
  else if AValue is TJSONBool then
    lua_pushboolean(L, Ord(TJSONBool(AValue).AsBoolean))
  else if AValue is TJSONNumber then
  begin
    S := AValue.Value;
    if S.IndexOfAny(['.', 'e', 'E']) < 0 then
      lua_pushinteger(L, StrToInt64Def(S, 0))
    else
      lua_pushnumber(L, StrToFloatDef(S, 0, TFormatSettings.Invariant));
  end
  else if AValue is TJSONNull then
    lua_pushnil(L)
  else
    lua_pushstr(L, AValue.Value);
end;

procedure LuaPushJson(L: PLuaState; const AJson: string);
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if V = nil then
      lua_pushnil(L)
    else
      PushValue(L, V);
  finally
    V.Free;
  end;
end;

{ ---- document ---- }

function LDocInfo(L: PLuaState): Integer; cdecl;
var
  Json: string;
begin
  if Assigned(GApi.DocInfo) and
     ReadHostText(function(ABuf: PAnsiChar; ASize: Int64): Int64 begin Result := GApi.DocInfo(ABuf, ASize); end, Json) then
    LuaPushJson(L, Json)
  else
    lua_pushnil(L);
  Result := 1;
end;

function LDocText(L: PLuaState): Integer; cdecl;
var
  What: Int64;
  Value: string;
  Ok: Boolean;
begin
  What := lua_tointeger(L, 1);
  Ok := Assigned(GApi.DocGetText) and
    ReadHostText(function(ABuf: PAnsiChar; ASize: Int64): Int64 begin Result := GApi.DocGetText(What, ABuf, ASize); end, Value);
  Result := PushText(L, Ok, Value);
end;

function LDocLine(L: PLuaState): Integer; cdecl;
var
  Index: Int64;
  Value: string;
  Ok: Boolean;
begin
  Index := lua_tointeger(L, 1) - 1;
  Ok := Assigned(GApi.DocLine) and (Index >= 0) and
    ReadHostText(function(ABuf: PAnsiChar; ASize: Int64): Int64 begin Result := GApi.DocLine(Index, ABuf, ASize); end, Value);
  Result := PushText(L, Ok, Value);
end;

function LDocReplace(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 2));
  Result := PushBool(L, Assigned(GApi.DocReplace) and (GApi.DocReplace(lua_tointeger(L, 1), PAnsiChar(Raw)) = 0));
end;

function LDocCursor(L: PLuaState): Integer; cdecl;
begin
  Result := PushBool(L, Assigned(GApi.DocSetCursor) and
    (GApi.DocSetCursor(lua_tointeger(L, 1) - 1, lua_tointeger(L, 2) - 1) = 0));
end;

function LDocSelect(L: PLuaState): Integer; cdecl;
begin
  Result := PushBool(L, Assigned(GApi.DocSetSelection) and
    (GApi.DocSetSelection(lua_tointeger(L, 1) - 1, lua_tointeger(L, 2) - 1,
      lua_tointeger(L, 3) - 1, lua_tointeger(L, 4) - 1) = 0));
end;

{ ---- panels and clipboard ---- }

function LPanelList(L: PLuaState): Integer; cdecl;
var
  Json: string;
  Side: Int64;
begin
  Side := SideArg(L, 1);
  if Assigned(GApi.PanelList) and
     ReadHostText(function(ABuf: PAnsiChar; ASize: Int64): Int64 begin Result := GApi.PanelList(Side, ABuf, ASize); end, Json) then
    LuaPushJson(L, Json)
  else
    lua_pushnil(L);
  Result := 1;
end;

function LPanelGoto(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 2));
  Result := PushBool(L, Assigned(GApi.PanelGoto) and (Raw <> '') and
    (GApi.PanelGoto(SideArg(L, 1), PAnsiChar(Raw)) = 0));
end;

function LPanelCursor(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 2));
  Result := PushBool(L, Assigned(GApi.PanelSetCursor) and (Raw <> '') and
    (GApi.PanelSetCursor(SideArg(L, 1), PAnsiChar(Raw)) = 0));
end;

function LPanelSelect(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 3));
  Result := PushBool(L, Assigned(GApi.PanelSelect) and
    (GApi.PanelSelect(SideArg(L, 1), lua_tointeger(L, 2), PAnsiChar(Raw)) = 0));
end;

function LPanelRefresh(L: PLuaState): Integer; cdecl;
begin
  Result := PushBool(L, Assigned(GApi.PanelRefresh) and (GApi.PanelRefresh() = 0));
end;

function LClipGet(L: PLuaState): Integer; cdecl;
var
  Value: string;
  Ok: Boolean;
begin
  Ok := Assigned(GApi.ClipboardGet) and
    ReadHostText(function(ABuf: PAnsiChar; ASize: Int64): Int64 begin Result := GApi.ClipboardGet(ABuf, ASize); end, Value);
  Result := PushText(L, Ok, Value);
end;

function LClipSet(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 1));
  Result := PushBool(L, Assigned(GApi.ClipboardSet) and (GApi.ClipboardSet(PAnsiChar(Raw)) = 0));
end;

{ ---- dialogs ---- }

function Control(const AType, AId, AText: string; ACol, ARow, AWidth, AHeight: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AType);
  if AId <> '' then
    Result.AddPair('id', AId);
  if AText <> '' then
    Result.AddPair('text', AText);
  Result.AddPair('col', TJSONNumber.Create(ACol));
  Result.AddPair('row', TJSONNumber.Create(ARow));
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(AHeight));
end;

function BuildDialog(const AKind, ATitle, AText, ADefault: string;
  const AItems: TArray<string>): string;
var
  Root, Obj: TJSONObject;
  Kids, Items: TJSONArray;
  Lines: TArray<string>;
  Row, I, ListRows: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('type', 'dialog');
    Root.AddPair('version', '2.0');
    Root.AddPair('title', ATitle);
    Root.AddPair('width', TJSONNumber.Create(cDialogWidth));
    Kids := TJSONArray.Create;
    Root.AddPair('children', Kids);
    Row := 1;
    if AKind = 'choose' then
    begin
      ListRows := Min(Max(Length(AItems), 1), cMaxListRows);
      Obj := Control('list', 'list', '', 2, 1, cDialogWidth - 6, ListRows);
      Items := TJSONArray.Create;
      for I := 0 to High(AItems) do
        Items.Add(AItems[I]);
      Obj.AddPair('items', Items);
      Obj.AddPair('selected', TJSONNumber.Create(0));
      Kids.AddElement(Obj);
      Row := ListRows + 2;
    end
    else
    begin
      Lines := AText.Split([#10]);
      for I := 0 to Min(High(Lines), cMaxTextLines - 1) do
      begin
        Kids.AddElement(Control('label', '', TrimRight(Lines[I]), 2, Row, cDialogWidth - 6, 1));
        Inc(Row);
      end;
      if AKind = 'input' then
      begin
        Obj := Control('input', 'value', '', 2, Row, cDialogWidth - 6, 1);
        Obj.AddPair('value', ADefault);
        Kids.AddElement(Obj);
        Inc(Row);
      end;
    end;
    Inc(Row);
    Obj := Control('button', 'ok', LocalText('dlg.ok', 'OK'), 18, Row, 12, 1);
    Obj.AddPair('default', TJSONBool.Create(True));
    Kids.AddElement(Obj);
    Obj := Control('button', 'cancel', LocalText('dlg.cancel', 'Cancel'), 33, Row, 12, 1);
    Obj.AddPair('cancel', TJSONBool.Create(True));
    Kids.AddElement(Obj);
    Root.AddPair('height', TJSONNumber.Create(Row + 4));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure DialogDone(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
begin
  if NativeInt(AUserData) <> GDlgSerial then
    Exit;
  GDlgId := UTF8ToString(AControlId);
  GDlgValues := UTF8ToString(AValuesJson);
  GDlgPending := False;
end;

// mtn_dialog(kind, title, text, default, items): True when the dialog is shown.
function LDialog(L: PLuaState): Integer; cdecl;
var
  Kind, Title, Body, Def, Json: string;
  Items: TArray<string>;
  I, N: Integer;
  Raw: UTF8String;
  Shown: Boolean;
begin
  Kind := lua_tostr(L, 1);
  Title := lua_tostr(L, 2);
  Body := lua_tostr(L, 3);
  Def := lua_tostr(L, 4);
  Items := nil;
  if lua_type(L, 5) = LUA_TTABLE then
  begin
    N := Integer(lua_rawlen(L, 5));
    SetLength(Items, N);
    for I := 1 to N do
    begin
      lua_geti(L, 5, I);
      Items[I - 1] := lua_tostr(L, -1);
      lua_pop(L, 1);
    end;
  end;
  Shown := False;
  if Assigned(GApi.ShowDialog) and not GDlgPending then
  begin
    Inc(GDlgSerial);
    GDlgKind := Kind;
    GDlgItems := Items;
    GDlgId := '';
    GDlgValues := '';
    Json := BuildDialog(Kind, Title, Body, Def, Items);
    Raw := UTF8String(Json);
    GDlgPending := True;
    Shown := GApi.ShowDialog(PAnsiChar(GPlugin), PAnsiChar(Raw), DialogDone, Pointer(NativeInt(GDlgSerial))) = 0;
    if not Shown then
      GDlgPending := False;
  end;
  Result := PushBool(L, Shown);
end;

function LDialogPending(L: PLuaState): Integer; cdecl;
begin
  Result := PushBool(L, GDlgPending);
end;

// The answer: input -> text or nil, confirm -> boolean, choose -> index or nil.
function LDialogResult(L: PLuaState): Integer; cdecl;
var
  V: TJSONValue;
  Chosen: string;
  I: Integer;
  Ok: Boolean;
begin
  Ok := GDlgId = 'ok';
  Result := 1;
  if GDlgKind = 'confirm' then
  begin
    lua_pushboolean(L, Ord(Ok));
    Exit;
  end;
  if not Ok then
  begin
    lua_pushnil(L);
    Exit;
  end;
  Chosen := '';
  V := TJSONObject.ParseJSONValue(GDlgValues);
  try
    if V is TJSONObject then
      Chosen := TJSONObject(V).GetValue<string>(IfThen(GDlgKind = 'choose', 'list', 'value'), '');
  finally
    V.Free;
  end;
  if GDlgKind = 'input' then
    lua_pushstr(L, Chosen)
  else
  begin
    for I := 0 to High(GDlgItems) do
      if GDlgItems[I] = Chosen then
      begin
        lua_pushinteger(L, I + 1);
        Exit;
      end;
    lua_pushnil(L);
  end;
end;

{ ---- programs ---- }

function TCancelToken.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

procedure TCancelToken.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

constructor TExecJob.Create(const AExe: string; const AArgs: TArray<string>; const AStdIn: string;
  ATimeoutMs: Cardinal);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FExe := AExe;
  FArgs := AArgs;
  FStdIn := AStdIn;
  FTimeoutMs := ATimeoutMs;
  FToken := TCancelToken.Create;
end;

procedure TExecJob.Execute;
begin
  try
    case PlatformRunCaptured(FExe, FArgs, FStdIn, FTimeoutMs, FToken, Output, ExitCode) of
      srOk: ;
      srSpawnFailed: Failure := 'could not start';
      srTimeout: Failure := 'timed out';
      srCancelled: Failure := 'cancelled';
    end;
  except
    on E: Exception do
      Failure := E.Message;
  end;
  TInterlocked.Exchange(FDone, 1);
end;

procedure TExecJob.Abort;
begin
  FToken.Cancel;
end;

function TExecJob.Finished: Boolean;
begin
  Result := TInterlocked.CompareExchange(FDone, 0, 0) <> 0;
end;

function ExecAllowed(const AProgram, AAllowed: string): Boolean;
var
  Name, Item: string;
begin
  Result := False;
  Name := Trim(AProgram);
  if (Name = '') or (Name.IndexOfAny(['/', '\', ':', #0]) >= 0) or (Name[1] = '-') then
    Exit;
  Name := LowerCase(ChangeFileExt(Name, ''));
  for Item in AAllowed.Split([',', ';', ' ']) do
    if (Item <> '') and (LowerCase(ChangeFileExt(Item, '')) = Name) then
      Exit(True);
end;

procedure ReleaseJob;
begin
  if GJob = nil then
    Exit;
  GJob.Abort;
  GJob.WaitFor;
  FreeAndNil(GJob);
end;

// mtn_exec_start(program, args, stdin, seconds): True, or nil and the reason.
function LExecStart(L: PLuaState): Integer; cdecl;
var
  Prog, StdIn, Why: string;
  Args: TArray<string>;
  I, N: Integer;
  Seconds: Int64;
begin
  Prog := lua_tostr(L, 1);
  Why := '';
  Args := nil;
  if not ExecAllowed(Prog, GExecAllowed) then
    Why := 'the program is not listed in the exec field of the macro'
  else if (GJob <> nil) and not GJob.Finished then
    Why := 'a program is already running'
  else
  begin
    if lua_type(L, 2) = LUA_TTABLE then
    begin
      N := Integer(lua_rawlen(L, 2));
      SetLength(Args, N);
      for I := 1 to N do
      begin
        lua_geti(L, 2, I);
        Args[I - 1] := lua_tostr(L, -1);
        lua_pop(L, 1);
      end;
    end;
    StdIn := lua_tostr(L, 3);
    Seconds := Min(Max(lua_tointeger(L, 4), 0), cMaxExecSeconds);
    if Seconds = 0 then
      Seconds := cDefaultExecSeconds;
    ReleaseJob;
    GJob := TExecJob.Create(Prog, Args, StdIn, Cardinal(Seconds) * 1000);
    GJob.Start;
  end;
  if Why = '' then
    lua_pushboolean(L, 1)
  else
  begin
    lua_pushnil(L);
    lua_pushstr(L, Why);
    Exit(2);
  end;
  Result := 1;
end;

function LExecDone(L: PLuaState): Integer; cdecl;
begin
  Result := PushBool(L, (GJob = nil) or GJob.Finished);
end;

// {ok, code, output, error} of the finished program.
function LExecResult(L: PLuaState): Integer; cdecl;
var
  Output: string;
begin
  lua_createtable(L, 0, 4);
  if GJob <> nil then
  begin
    Output := GJob.Output;
    if Length(Output) > cMaxOutputChars then
      SetLength(Output, cMaxOutputChars);
    lua_pushboolean(L, Ord(GJob.Failure = ''));
    lua_setfield(L, -2, 'ok');
    lua_pushinteger(L, GJob.ExitCode);
    lua_setfield(L, -2, 'code');
    lua_pushstr(L, Output);
    lua_setfield(L, -2, 'output');
    lua_pushstr(L, GJob.Failure);
    lua_setfield(L, -2, 'error');
    ReleaseJob;
  end;
  Result := 1;
end;

procedure LuaHostReset;
begin
  ReleaseJob;
  Inc(GDlgSerial);
  GDlgPending := False;
end;

procedure LuaHostRegister(L: PLuaState; AApi: PHostApiTable; const APluginId: string;
  ATr: TLuaText);
begin
  GApi := AApi;
  GPlugin := UTF8String(APluginId);
  GTr := ATr;
  lua_register(L, 'mtn_doc_info', LDocInfo);
  lua_register(L, 'mtn_doc_text', LDocText);
  lua_register(L, 'mtn_doc_line', LDocLine);
  lua_register(L, 'mtn_doc_replace', LDocReplace);
  lua_register(L, 'mtn_doc_cursor', LDocCursor);
  lua_register(L, 'mtn_doc_select', LDocSelect);
  lua_register(L, 'mtn_panel_list', LPanelList);
  lua_register(L, 'mtn_panel_goto', LPanelGoto);
  lua_register(L, 'mtn_panel_cursor', LPanelCursor);
  lua_register(L, 'mtn_panel_select', LPanelSelect);
  lua_register(L, 'mtn_panel_refresh', LPanelRefresh);
  lua_register(L, 'mtn_clip_get', LClipGet);
  lua_register(L, 'mtn_clip_set', LClipSet);
  lua_register(L, 'mtn_dialog', LDialog);
  lua_register(L, 'mtn_dialog_pending', LDialogPending);
  lua_register(L, 'mtn_dialog_result', LDialogResult);
  lua_register(L, 'mtn_exec_start', LExecStart);
  lua_register(L, 'mtn_exec_done', LExecDone);
  lua_register(L, 'mtn_exec_result', LExecResult);
end;

end.
