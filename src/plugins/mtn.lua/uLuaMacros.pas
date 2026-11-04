unit uLuaMacros;

(* Macro engine: macros are Lua files in the macros folder of the settings
  directory. A file calls macro { name = ..., area = ..., the fields key and menu,
  requires = ..., run = function() ... end }. A running macro is a coroutine:
  every call that touches the program (mtn.key, mtn.text, mtn.action) yields
  afterwards and is resumed from the main loop, so the program draws and handles
  what the macro started before it goes on. The Lua state is a sandbox (base,
  string, table, math, utf8, coroutine; no io, os, package or debug), and an
  instruction budget and Esc end a macro that does not stop. *)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uPluginHostAbi;

type
  TMacro = class
  public
    Id: string;
    Name: string;
    Areas: string;      // '' = anywhere, else comma-separated panels, editor, viewer, terminal
    Key: string;
    InMenu: Boolean;
    Requires: string;
    RunRef: Integer;
    Path: string;
  end;

  /// <summary>Text for the user; the plugin glue supplies the translation.</summary>
  TMacroText = reference to function(const AKey, ADefault: string): string;

  TMacroEngine = class
  private
    FApi: PHostApiTable;
    FPluginId: UTF8String;
    FMacros: TObjectList<TMacro>;
    FTr: TMacroText;
    FState: Pointer;
    FThread: Pointer;
    FThreadRef: Integer;
    FRunning: TMacro;
    function Tr(const AKey, ADefault: string): string;
    procedure Notify(const AText: string; AKind: Integer = 0);
    procedure Step;
    procedure Finish;
    function Probe(AMacro: TMacro; out AWhy: string): Boolean;
  public
    /// <summary>Loads one macro file; nil (after telling the user) when it declares no macro.</summary>
    function LoadFile(const APath: string): TMacro;

    constructor Create(AApi: PHostApiTable; const APluginId: string; ATr: TMacroText);
    destructor Destroy; override;
    /// <summary>Opens the Lua state; False when the library is missing.</summary>
    function Open(const AFolder: string; out AError: string): Boolean;
    procedure LoadFolder(const AFolder: string);
    function Run(AMacro: TMacro): Boolean;
    /// <summary>Esc while a macro runs.</summary>
    procedure RequestAbort;
    property Macros: TObjectList<TMacro> read FMacros;
    property Running: TMacro read FRunning;
    property Api: PHostApiTable read FApi;
    function CurrentState: string;
    /// <summary>area of the program now: panels, editor, viewer or terminal.</summary>
    function CurrentArea: string;
    function HostText(AFn: THostTextOutFn): string;
  end;

var
  GEngine: TMacroEngine;

/// <summary>The text of AValue as a Lua string literal.</summary>
function LuaQuote(const AValue: string): string;

implementation

uses
  System.JSON, System.IOUtils, System.NetEncoding, uLuaApi;

const
  cHookCount = 10000;
  cMaxSlices = 5000;

  cPrelude =
    'local k, t, a, s, m, sel, reg = mtn_key, mtn_text, mtn_action, mtn_state, mtn_message, mtn_selected, mtn_register' + #10 +
    'local yield = coroutine.yield' + #10 +
    'mtn = {}' + #10 +
    'function mtn.key(c) local ok = k(c); yield(); return ok end' + #10 +
    'function mtn.text(x) local ok = t(x); yield(); return ok end' + #10 +
    'function mtn.action(n) local ok = a(n); yield(); return ok end' + #10 +
    'function mtn.wait_idle() yield() end' + #10 +
    'mtn.state = s' + #10 +
    'mtn.message = m' + #10 +
    'mtn.selected = sel' + #10 +
    'function macro(def) reg(def) end' + #10 +
    'mtn_key, mtn_text, mtn_action, mtn_state, mtn_message, mtn_selected, mtn_register = nil' + #10 +
    'dofile, loadfile, load, print, collectgarbage = nil' + #10;

function LuaQuote(const AValue: string): string;
var
  Raw: UTF8String;
  I: Integer;
  B: Byte;
begin
  Raw := UTF8String(AValue);
  Result := '"';
  for I := 1 to Length(Raw) do
  begin
    B := Byte(Raw[I]);
    case B of
      Ord('\'): Result := Result + '\\';
      Ord('"'): Result := Result + '\"';
      10: Result := Result + '\n';
      13: Result := Result + '\r';
      9: Result := Result + '\t';
    else
      if (B < 32) or (B > 126) then
        Result := Result + '\' + Format('%.3d', [B])
      else
        Result := Result + Char(B);
    end;
  end;
  Result := Result + '"';
end;

var
  GDeclared: TMacro;
  GAbort: Boolean;
  GSlices: Integer;

{ ---- state of the program, as the macro sees it ---- }

function JsonStr(AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  if AObj = nil then
    Exit;
  V := AObj.GetValue(AName);
  if V <> nil then
    Result := V.Value;
end;

function JsonBool(AObj: TJSONObject; const AName: string): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  if AObj = nil then
    Exit;
  V := AObj.GetValue(AName);
  Result := (V is TJSONBool) and TJSONBool(V).AsBoolean;
end;

function UriName(const AUri: string): string;
var
  S: string;
begin
  S := AUri;
  while (S <> '') and (S[Length(S)] = '/') do
    Delete(S, Length(S), 1);
  Result := TNetEncoding.URL.Decode(Copy(S, LastDelimiter('/', S) + 1, MaxInt));
end;

function UriScheme(const AUri: string): string;
var
  P: Integer;
begin
  P := Pos(':', AUri);
  if P > 1 then
    Result := LowerCase(Copy(AUri, 1, P - 1))
  else
    Result := '';
end;

type
  TAppFacts = record
    Area: string;
    HasSelection: Boolean;
    SelectedCount: Integer;
    CursorKind: string;   // file, dir or ''
    CursorName: string;
    PanelKind: string;    // URI scheme of the active panel
    ActiveSide: string;
    EditorModified: Boolean;
    EditorHasSelection: Boolean;
    CanEdit: Boolean;
    Selected: TArray<string>;
  end;

function ReadFacts(const AJson: string): TAppFacts;
var
  Root, Doc, Panels, Side: TJSONObject;
  V: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Cursor: string;
begin
  Result := Default(TAppFacts);
  if AJson = '' then
    Exit;
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if not (V is TJSONObject) then
      Exit;
    Root := TJSONObject(V);
    Result.Area := JsonStr(Root, 'area');
    if Root.GetValue('doc') is TJSONObject then
    begin
      Doc := TJSONObject(Root.GetValue('doc'));
      Result.EditorModified := JsonBool(Doc, 'dirty');
      Result.EditorHasSelection := JsonBool(Doc, 'hasSelection');
      Result.CanEdit := JsonBool(Doc, 'canEdit');
    end;
    if Root.GetValue('panels') is TJSONObject then
    begin
      Panels := TJSONObject(Root.GetValue('panels'));
      Result.ActiveSide := JsonStr(Panels, 'active');
      if Panels.GetValue(Result.ActiveSide) is TJSONObject then
      begin
        Side := TJSONObject(Panels.GetValue(Result.ActiveSide));
        Result.PanelKind := UriScheme(JsonStr(Side, 'uri'));
        Cursor := JsonStr(Side, 'cursor');
        if Cursor <> '' then
        begin
          Result.CursorName := UriName(Cursor);
          if JsonBool(Side, 'cursorIsDirectory') then
            Result.CursorKind := 'dir'
          else
            Result.CursorKind := 'file';
        end;
        if Side.GetValue('selected') is TJSONArray then
        begin
          Arr := TJSONArray(Side.GetValue('selected'));
          SetLength(Result.Selected, Arr.Count);
          for I := 0 to Arr.Count - 1 do
            Result.Selected[I] := Arr.Items[I].Value;
          Result.SelectedCount := Arr.Count;
        end;
      end;
    end;
    Result.HasSelection := (Result.SelectedCount > 0) or Result.EditorHasSelection;
  finally
    V.Free;
  end;
end;

{ ---- Lua functions the macros reach through the mtn table ---- }

function LKey(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 1));
  lua_pushboolean(L, Ord((Raw <> '') and Assigned(GEngine.Api.SendKey) and
    (GEngine.Api.SendKey(PAnsiChar(Raw)) = 0)));
  Result := 1;
end;

function LText(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 1));
  lua_pushboolean(L, Ord(Assigned(GEngine.Api.SendText) and (GEngine.Api.SendText(PAnsiChar(Raw)) = 0)));
  Result := 1;
end;

function LAction(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 1));
  lua_pushboolean(L, Ord(Assigned(GEngine.Api.RunAction) and (GEngine.Api.RunAction(PAnsiChar(Raw)) = 0)));
  Result := 1;
end;

function LMessage(L: PLuaState): Integer; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(lua_tostr(L, 1));
  if Assigned(GEngine.Api.ShowMessage) then
    GEngine.Api.ShowMessage(PAnsiChar(Raw), 0);
  Result := 0;
end;

procedure SetStr(L: PLuaState; const AName, AValue: string);
var
  Name: AnsiString;
begin
  Name := AnsiString(AName);
  lua_pushstr(L, AValue);
  lua_setfield(L, -2, PAnsiChar(Name));
end;

procedure SetBool(L: PLuaState; const AName: string; AValue: Boolean);
var
  Name: AnsiString;
begin
  Name := AnsiString(AName);
  lua_pushboolean(L, Ord(AValue));
  lua_setfield(L, -2, PAnsiChar(Name));
end;

procedure SetInt(L: PLuaState; const AName: string; AValue: Int64);
var
  Name: AnsiString;
begin
  Name := AnsiString(AName);
  lua_pushinteger(L, AValue);
  lua_setfield(L, -2, PAnsiChar(Name));
end;

function LState(L: PLuaState): Integer; cdecl;
var
  F: TAppFacts;
begin
  F := ReadFacts(GEngine.CurrentState);
  lua_newtable(L);
  SetStr(L, 'area', F.Area);
  SetBool(L, 'has_selection', F.HasSelection);
  SetInt(L, 'selected_count', F.SelectedCount);
  SetStr(L, 'cursor_kind', F.CursorKind);
  SetStr(L, 'cursor_name', F.CursorName);
  SetStr(L, 'panel_kind', F.PanelKind);
  SetStr(L, 'active_side', F.ActiveSide);
  SetBool(L, 'editor_modified', F.EditorModified);
  SetBool(L, 'editor_has_selection', F.EditorHasSelection);
  SetBool(L, 'viewer_mode', F.Area = 'viewer');
  Result := 1;
end;

function LSelected(L: PLuaState): Integer; cdecl;
var
  F: TAppFacts;
  I: Integer;
begin
  F := ReadFacts(GEngine.CurrentState);
  lua_createtable(L, Length(F.Selected), 0);
  for I := 0 to High(F.Selected) do
  begin
    lua_pushstr(L, F.Selected[I]);
    lua_seti(L, -2, I + 1);
  end;
  Result := 1;
end;

function FieldStr(L: PLuaState; const AName: AnsiString): string;
begin
  lua_getfield(L, -1, PAnsiChar(AName));
  Result := lua_tostr(L, -1);
  lua_pop(L, 1);
end;

function LRegister(L: PLuaState): Integer; cdecl;
var
  M: TMacro;
begin
  Result := 0;
  if lua_type(L, 1) <> LUA_TTABLE then
    Exit;
  lua_settop(L, 1);
  GDeclared.Free;
  M := TMacro.Create;
  GDeclared := M;
  M.RunRef := -1;
  M.Name := FieldStr(L, 'name');
  M.Areas := LowerCase(StringReplace(FieldStr(L, 'area'), ' ', '', [rfReplaceAll]));
  if M.Areas = 'any' then
    M.Areas := '';
  M.Key := FieldStr(L, 'key');
  M.Requires := LowerCase(StringReplace(FieldStr(L, 'requires'), ' ', '', [rfReplaceAll]));
  lua_getfield(L, 1, 'menu');
  M.InMenu := lua_toboolean(L, -1) <> 0;
  lua_pop(L, 1);
  lua_getfield(L, 1, 'run');
  if lua_type(L, -1) = LUA_TFUNCTION then
    M.RunRef := luaL_ref(L, LUA_REGISTRYINDEX)
  else
    lua_pop(L, 1);
end;

{ Raised in the count hook: a stop asked for (Esc) or an instruction budget spent
  without the macro yielding. No managed locals: Lua leaves by a long jump. }
procedure CountHook(L: PLuaState; ADebug: Pointer); cdecl;
begin
  Inc(GSlices);
  if GAbort then
    lua_fail(L, 'macro stopped')
  else if GSlices > cMaxSlices then
    lua_fail(L, 'macro used too many steps without waiting');
end;

procedure OnStepCallback(AUserData: Pointer); cdecl;
begin
  try
    if GEngine <> nil then
      GEngine.Step;
  except
    // Never let an exception cross into the host.
  end;
end;

{ ---- TMacroEngine ---- }

constructor TMacroEngine.Create(AApi: PHostApiTable; const APluginId: string; ATr: TMacroText);
begin
  inherited Create;
  FApi := AApi;
  FPluginId := UTF8String(APluginId);
  FTr := ATr;
  FMacros := TObjectList<TMacro>.Create(True);
end;

destructor TMacroEngine.Destroy;
begin
  if FState <> nil then
    lua_close(FState);
  FMacros.Free;
  GDeclared.Free;
  GDeclared := nil;
  inherited;
end;

function TMacroEngine.Tr(const AKey, ADefault: string): string;
begin
  if Assigned(FTr) then
    Result := FTr(AKey, ADefault)
  else
    Result := ADefault;
end;

procedure TMacroEngine.Notify(const AText: string; AKind: Integer);
var
  Raw: UTF8String;
begin
  Raw := UTF8String(AText);
  if Assigned(FApi.ShowMessage) then
    FApi.ShowMessage(PAnsiChar(Raw), AKind);
end;

function TMacroEngine.HostText(AFn: THostTextOutFn): string;
var
  Len: Int64;
  Raw: UTF8String;
begin
  Result := '';
  if not Assigned(AFn) then
    Exit;
  Len := AFn(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Raw, Len + 1);
  if AFn(PAnsiChar(Raw), Len + 1) = Len then
    Result := UTF8ToString(Copy(Raw, 1, Len));
end;

function TMacroEngine.CurrentState: string;
begin
  Result := HostText(FApi.AppState);
end;

function TMacroEngine.CurrentArea: string;
begin
  Result := ReadFacts(CurrentState).Area;
end;

function TMacroEngine.Open(const AFolder: string; out AError: string): Boolean;
var
  L: PLuaState;
  Prelude: UTF8String;
begin
  Result := False;
  AError := '';
  if not LuaLoad(AFolder) then
  begin
    AError := LuaLastError;
    Exit;
  end;
  L := luaL_newstate();
  if L = nil then
  begin
    AError := 'cannot create a Lua state';
    Exit;
  end;
  FState := L;
  luaL_requiref(L, '_G', luaopen_base, 1);
  luaL_requiref(L, 'string', luaopen_string, 1);
  luaL_requiref(L, 'table', luaopen_table, 1);
  luaL_requiref(L, 'math', luaopen_math, 1);
  luaL_requiref(L, 'utf8', luaopen_utf8, 1);
  luaL_requiref(L, 'coroutine', luaopen_coroutine, 1);
  lua_settop(L, 0);
  lua_register(L, 'mtn_key', LKey);
  lua_register(L, 'mtn_text', LText);
  lua_register(L, 'mtn_action', LAction);
  lua_register(L, 'mtn_state', LState);
  lua_register(L, 'mtn_message', LMessage);
  lua_register(L, 'mtn_selected', LSelected);
  lua_register(L, 'mtn_register', LRegister);
  Prelude := UTF8String(cPrelude);
  if (luaL_loadbufferx(L, PAnsiChar(Prelude), Length(Prelude), '=prelude', nil) <> LUA_OK) or
     (lua_pcall(L, 0, 0) <> LUA_OK) then
  begin
    AError := lua_tostr(L, -1);
    Exit;
  end;
  Result := True;
end;

function TMacroEngine.LoadFile(const APath: string): TMacro;
var
  Bytes: TBytes;
  Chunk: UTF8String;
  M: TMacro;
  ChunkName: AnsiString;
begin
  Result := nil;
  Bytes := TFile.ReadAllBytes(APath);
  // A UTF-8 byte order mark is not Lua.
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Bytes := Copy(Bytes, 3, MaxInt);
  if Length(Bytes) = 0 then
    Exit;
  SetString(Chunk, PAnsiChar(@Bytes[0]), Length(Bytes));
  ChunkName := AnsiString('=' + TPath.GetFileName(APath));
  GDeclared.Free;
  GDeclared := nil;
  if (luaL_loadbufferx(FState, PAnsiChar(Chunk), Length(Chunk), PAnsiChar(ChunkName), nil) <> LUA_OK) or
     (lua_pcall(FState, 0, 0) <> LUA_OK) then
  begin
    Notify(Format(Tr('err.load', 'Macro file %s: %s'),
      [TPath.GetFileName(APath), lua_tostr(FState, -1)]), 1);
    lua_settop(FState, 0);
    Exit;
  end;
  if (GDeclared = nil) or (GDeclared.RunRef < 0) then
  begin
    Notify(Format(Tr('err.nomacro', 'Macro file %s declares no macro with a run function'),
      [TPath.GetFileName(APath)]), 1);
    Exit;
  end;
  M := GDeclared;
  GDeclared := nil;
  M.Path := APath;
  M.Id := TPath.GetFileNameWithoutExtension(APath);
  if M.Name = '' then
    M.Name := M.Id;
  FMacros.Add(M);
  Result := M;
end;

procedure TMacroEngine.LoadFolder(const AFolder: string);
var
  F: string;
begin
  FMacros.Clear;
  if (FState = nil) or not TDirectory.Exists(AFolder) then
    Exit;
  for F in TDirectory.GetFiles(AFolder, '*.lua') do
    try
      LoadFile(F);
    except
      on E: Exception do
        Notify(Format(Tr('err.load', 'Macro file %s: %s'), [TPath.GetFileName(F), E.Message]), 1);
    end;
end;

function TMacroEngine.Probe(AMacro: TMacro; out AWhy: string): Boolean;
var
  F: TAppFacts;
  Req, Area: string;
  Fits: Boolean;
begin
  AWhy := '';
  F := ReadFacts(CurrentState);
  if AMacro.Areas <> '' then
  begin
    Fits := False;
    for Area in AMacro.Areas.Split([',']) do
      if Area = F.Area then
        Fits := True;
    if not Fits then
    begin
      AWhy := Format(Tr('err.area', 'The macro "%s" runs in: %s'), [AMacro.Name, AMacro.Areas]);
      Exit(False);
    end;
  end;
  for Req in AMacro.Requires.Split([',']) do
  begin
    if Req = '' then
      Continue;
    if ((Req = 'has_selection') and not F.HasSelection) or
       ((Req = 'no_selection') and F.HasSelection) or
       ((Req = 'cursor_file') and (F.CursorKind <> 'file')) or
       ((Req = 'cursor_dir') and (F.CursorKind <> 'dir')) or
       ((Req = 'editable') and not F.CanEdit) or
       ((Req = 'modified') and not F.EditorModified) then
    begin
      AWhy := Format(Tr('err.requires', 'The macro "%s" needs: %s'), [AMacro.Name, Req]);
      Exit(False);
    end;
  end;
  Result := True;
end;

function TMacroEngine.Run(AMacro: TMacro): Boolean;
var
  Why: string;
begin
  Result := False;
  if (FState = nil) or (AMacro = nil) or (AMacro.RunRef < 0) then
    Exit;
  if FRunning <> nil then
  begin
    Notify(Tr('err.busy', 'A macro is already running (Esc stops it)'), 1);
    Exit;
  end;
  if not Probe(AMacro, Why) then
  begin
    Notify(Why, 1);
    Exit;
  end;
  FThread := lua_newthread(FState);
  FThreadRef := luaL_ref(FState, LUA_REGISTRYINDEX);
  lua_rawgeti(FState, LUA_REGISTRYINDEX, AMacro.RunRef);
  lua_xmove(FState, FThread, 1);
  lua_sethook(FThread, CountHook, LUA_MASKCOUNT, cHookCount);
  GAbort := False;
  FRunning := AMacro;
  Step;
  Result := True;
end;

procedure TMacroEngine.Step;
var
  Status, NRes: Integer;
  Msg, Name: string;
begin
  if FRunning = nil then
    Exit;
  if GAbort then
  begin
    Notify(Format(Tr('msg.stopped', 'Macro "%s" stopped'), [FRunning.Name]));
    Finish;
    Exit;
  end;
  GSlices := 0;
  NRes := 0;
  Status := lua_resume(FThread, FState, 0, @NRes);
  if Status = LUA_YIELD then
  begin
    lua_settop(FThread, 0);
    if Assigned(FApi.PostToMain) then
      FApi.PostToMain(PAnsiChar(FPluginId), OnStepCallback, nil);
    Exit;
  end;
  if Status <> LUA_OK then
  begin
    Msg := lua_tostr(FThread, -1);
    Name := FRunning.Name;
    Notify(Format(Tr('err.run', 'Macro "%s" failed: %s'), [Name, Msg]), 1);
  end;
  Finish;
end;

procedure TMacroEngine.Finish;
begin
  if FThreadRef <> 0 then
    luaL_unref(FState, LUA_REGISTRYINDEX, FThreadRef);
  FThread := nil;
  FThreadRef := 0;
  FRunning := nil;
  GAbort := False;
end;

procedure TMacroEngine.RequestAbort;
begin
  if FRunning <> nil then
    GAbort := True;
end;

end.
