unit uLuaMacros;

(* Macro engine: macros are Lua files in the macros folder of the settings
  directory. A file calls macro { name = ..., area = ..., the fields key and menu,
  requires = ..., exec = ..., run = function() ... end }. A running macro is a
  coroutine: every call that touches the program (mtn.key, mtn.text,
  mtn.action, mtn.editor.replace, ...) yields afterwards and is resumed from
  the main loop, so the program draws and handles what the macro started before
  it goes on. A file may also call mtn.on(topic, fn) while it loads: fn then
  runs as a macro when the host publishes that event. mtn.column{...} declares
  a file panel column whose cells a Lua function computes for every file. The Lua state is a
  sandbox (base, string, table, math, utf8, coroutine; no io, os, package or
  debug), and an instruction budget and Esc end a macro that does not stop. *)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  uPluginHostAbi, uLuaHostFns;

type
  TMacro = class
  public
    Id: string;
    Name: string;
    Areas: string;      // '' = anywhere, else comma-separated panels, editor, viewer, terminal
    Key: string;
    InMenu: Boolean;
    Requires: string;
    /// <summary>Program names mtn.exec may start for this macro, comma separated.</summary>
    Exec: string;
    RunRef: Integer;
    Path: string;
  end;

  /// <summary>A function registered with mtn.on.</summary>
  THandler = class
  public
    Topic: string;
    Exec: string;
    Path: string;
    Ref: Integer;
  end;

  /// <summary>A panel column declared with mtn.column.</summary>
  TColumn = class
  public
    Id: string;
    Title: string;
    Width: Integer;
    Right: Boolean;
    IsDefault: Boolean;
    Ref: Integer;
    /// <summary>Set after the value function failed; the column is then left empty.</summary>
    Broken: Boolean;
  end;

  TPendingEvent = record
    Handler: THandler;
    Payload: string;
  end;

  /// <summary>Text for the user; the plugin glue supplies the translation.</summary>
  TMacroText = TLuaText;

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
    FHandlers: TObjectList<THandler>;
    FQueue: TList<TPendingEvent>;
    FSubscribed: TStringList;
    FEventMacro: TMacro;
    FStartArgs: Integer;
    FColumns: TObjectList<TColumn>;
    FColumnsDirty: Boolean;
    function Tr(const AKey, ADefault: string): string;
    procedure Notify(const AText: string; AKind: Integer = 0);
    procedure Step;
    procedure Finish;
    function Probe(AMacro: TMacro; out AWhy: string): Boolean;
    procedure Launch(AMacro: TMacro; const APayload: string; AIsEvent: Boolean);
    procedure NextEvent;
    procedure ClearHandlers;
    procedure Subscribe(const ATopic: string);
    procedure ClearColumns;
    procedure PublishColumns;
    function EvalColumn(AColumn: TColumn; ARow: TJSONObject): string;
  public
    /// <summary>Computes the cells of the declared columns for the folders of both
    /// panels and hands them to the host. Postponed while a macro runs.</summary>
    procedure RefreshColumns;
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
    /// <summary>Runs the handlers registered for ATopic with the payload as a
    /// table. Dropped while a macro or handler runs, so a handler's own edits
    /// cannot start it again.</summary>
    procedure DispatchEvent(const ATopic, APayload: string);
    property Macros: TObjectList<TMacro> read FMacros;
    property Handlers: TObjectList<THandler> read FHandlers;
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
  System.IOUtils, System.NetEncoding, System.Math, uLuaApi;

const
  cHookCount = 10000;
  cMaxSlices = 5000;

  cPrelude =
    'local k, t, a, s, m, sel, reg = mtn_key, mtn_text, mtn_action, mtn_state, mtn_message, mtn_selected, mtn_register' + #10 +
    'local di, dt, dl, dr, dc, ds = mtn_doc_info, mtn_doc_text, mtn_doc_line, mtn_doc_replace, mtn_doc_cursor, mtn_doc_select' + #10 +
    'local pl, pg, pc, ps, pr = mtn_panel_list, mtn_panel_goto, mtn_panel_cursor, mtn_panel_select, mtn_panel_refresh' + #10 +
    'local cg, cs, on, col = mtn_clip_get, mtn_clip_set, mtn_on, mtn_column' + #10 +
    'local dlg, dpend, dres = mtn_dialog, mtn_dialog_pending, mtn_dialog_result' + #10 +
    'local xs, xd, xr = mtn_exec_start, mtn_exec_done, mtn_exec_result' + #10 +
    'local yield = coroutine.yield' + #10 +
    'mtn = {}' + #10 +
    // Documents and folder listings are read in the background and take no input
    // until they are ready; every call that can start one waits for it.
    'local function settle() while s().busy do yield() end end' + #10 +
    'function mtn.key(c) local ok = k(c); yield(); settle(); return ok end' + #10 +
    'function mtn.text(x) local ok = t(x); yield(); settle(); return ok end' + #10 +
    'function mtn.action(n) local ok = a(n); yield(); settle(); return ok end' + #10 +
    'function mtn.wait_idle() yield() end' + #10 +
    // copy, move, delete and other jobs that go on in the background
    'function mtn.wait_jobs() yield() while s().jobs > 0 do yield() end end' + #10 +
    'mtn.state = s' + #10 +
    'mtn.message = m' + #10 +
    'mtn.selected = sel' + #10 +
    'function macro(def) reg(def) end' + #10 +
    'mtn.on = on' + #10 +
    // a number a column function returns is shown as text
    'function mtn.column(def) if type(def) ~= "table" or type(def.value) ~= "function" then return end' +
    ' local fn = def.value def.value = function(f) local v = fn(f)' +
    ' if type(v) == "number" then return tostring(v) end return v end col(def) end' + #10 +
    'local function after(ok) yield() settle() return ok end' + #10 +
    'local function str(x) if type(x) ~= "string" then error("text expected", 3) end return x end' + #10 +
    'local function side(x) if x == nil or x == "left" or x == "right" then return x end error("side is left or right", 3) end' + #10 +
    // editor and viewer document; lines and columns count from 1
    'mtn.editor = {}' + #10 +
    'function mtn.editor.info() local i = di() if not i then return nil end' +
    ' return {uri = i.uri, lines = i.lines, row = (i.row or 0) + 1, col = (i.col or 0) + 1,' +
    ' dirty = i.dirty, can_edit = i.canEdit, has_selection = i.hasSelection} end' + #10 +
    'function mtn.editor.text() return dt(1) end' + #10 +
    'function mtn.editor.selection() return dt(0) end' + #10 +
    'function mtn.editor.current_line() return dt(2) end' + #10 +
    'function mtn.editor.line(n) return dl(n) end' + #10 +
    'function mtn.editor.replace(x) return after(dr(0, str(x))) end' + #10 +
    'function mtn.editor.replace_all(x) return after(dr(1, str(x))) end' + #10 +
    'function mtn.editor.replace_line(x) return after(dr(2, str(x))) end' + #10 +
    'function mtn.editor.set_cursor(r, c) return after(dc(r, c)) end' + #10 +
    'function mtn.editor.set_selection(r1, c1, r2, c2) return after(ds(r1, c1, r2, c2)) end' + #10 +
    // panels; a side is "left", "right" or nil for the active one
    'local function plist(s) local t = pl(side(s)) if not t then return nil end' +
    ' local r = {path = t.uri, files = t.rows or {}, truncated = t.truncated or false}' +
    ' if t.cursor then r.cursor = t.cursor + 1 end return r end' + #10 +
    'mtn.panel = {list = plist}' + #10 +
    'function mtn.panel.path(s) local t = pl(side(s)) return t and t.uri end' + #10 +
    'function mtn.panel.cursor(s) local t = plist(s) return t and t.cursor and t.files[t.cursor] end' + #10 +
    'function mtn.panel.open(uri, s) return after(pg(side(s), str(uri))) end' + #10 +
    'function mtn.panel.set_cursor(uri, s) return after(pc(side(s), str(uri))) end' + #10 +
    'function mtn.panel.select(mask, s) return after(ps(side(s), 0, str(mask))) end' + #10 +
    'function mtn.panel.unselect(mask, s) return after(ps(side(s), 1, str(mask))) end' + #10 +
    'function mtn.panel.clear_selection(s) return after(ps(side(s), 2, "")) end' + #10 +
    'function mtn.panel.select_item(uri, s) return after(ps(side(s), 3, str(uri))) end' + #10 +
    'function mtn.panel.unselect_item(uri, s) return after(ps(side(s), 4, str(uri))) end' + #10 +
    'function mtn.panel.refresh() return after(pr()) end' + #10 +
    'mtn.clipboard = {get = cg}' + #10 +
    'function mtn.clipboard.set(x) return after(cs(str(x))) end' + #10 +
    // dialogs wait for the answer
    'local function ask(kind, title, text, def, items)' +
    ' if not dlg(kind, title or "Macro", text or "", def or "", items) then return nil end' +
    ' while dpend() do yield() end return dres() end' + #10 +
    'function mtn.input(prompt, default, title) return ask("input", title, prompt, default) end' + #10 +
    'function mtn.confirm(text, title) return ask("confirm", title, text) or false end' + #10 +
    'function mtn.choose(title, items) return ask("choose", title, "", "", items) end' + #10 +
    // a program of the exec field: returns its output and exit code, or nil and the reason
    'function mtn.exec(program, args, opts) opts = opts or {}' +
    ' local ok, why = xs(program, args or {}, opts.stdin or "", opts.timeout or 0)' +
    ' if not ok then return nil, why end' +
    ' while not xd() do yield() end' +
    ' local r = xr() if not r.ok then return nil, r.error end return r.output, r.code end' + #10 +
    'mtn_key, mtn_text, mtn_action, mtn_state, mtn_message, mtn_selected, mtn_register = nil' + #10 +
    'mtn_doc_info, mtn_doc_text, mtn_doc_line, mtn_doc_replace, mtn_doc_cursor, mtn_doc_select = nil' + #10 +
    'mtn_panel_list, mtn_panel_goto, mtn_panel_cursor, mtn_panel_select, mtn_panel_refresh = nil' + #10 +
    'mtn_clip_get, mtn_clip_set, mtn_on, mtn_column, mtn_dialog, mtn_dialog_pending, mtn_dialog_result = nil' + #10 +
    'mtn_exec_start, mtn_exec_done, mtn_exec_result = nil' + #10 +
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
  /// <summary>Handlers registered by the file being loaded.</summary>
  GNewHandlers: TList<THandler>;
  GNewColumns: TList<TColumn>;
  GLoading: Boolean;
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
    Jobs: Integer;        // background jobs that have not finished
    Busy: Boolean;        // a document is being read or saved, or a folder listed
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
    Result.Busy := JsonBool(Root, 'busy');
    if Root.GetValue('jobs') is TJSONNumber then
      Result.Jobs := TJSONNumber(Root.GetValue('jobs')).AsInt;
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
  SetBool(L, 'busy', F.Busy);
  SetInt(L, 'jobs', F.Jobs);
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
  M.Exec := FieldStr(L, 'exec');
  lua_getfield(L, 1, 'menu');
  M.InMenu := lua_toboolean(L, -1) <> 0;
  lua_pop(L, 1);
  lua_getfield(L, 1, 'run');
  if lua_type(L, -1) = LUA_TFUNCTION then
    M.RunRef := luaL_ref(L, LUA_REGISTRYINDEX)
  else
    lua_pop(L, 1);
end;

// mtn.on(topic, fn, opts): only while a macro file loads. opts.exec lists the
// programs the handler may start.
function LOn(L: PLuaState): Integer; cdecl;
var
  H: THandler;
  Topic: string;
begin
  Result := 0;
  Topic := LowerCase(Trim(lua_tostr(L, 1)));
  if not GLoading or (lua_type(L, 2) <> LUA_TFUNCTION) or (Topic = '') or
     (Topic = '*') or (Topic = 'input.key') then
    Exit;
  H := THandler.Create;
  H.Topic := Topic;
  if lua_type(L, 3) = LUA_TTABLE then
  begin
    lua_settop(L, 3);
    H.Exec := FieldStr(L, 'exec');
  end;
  lua_pushvalue(L, 2);
  H.Ref := luaL_ref(L, LUA_REGISTRYINDEX);
  GNewHandlers.Add(H);
end;

// mtn.column{id, title, width, align, default, value}: only while a macro file loads.
function LColumn(L: PLuaState): Integer; cdecl;
var
  C: TColumn;
begin
  Result := 0;
  if not GLoading or (lua_type(L, 1) <> LUA_TTABLE) then
    Exit;
  lua_settop(L, 1);
  lua_getfield(L, 1, 'value');
  if lua_type(L, -1) <> LUA_TFUNCTION then
  begin
    lua_pop(L, 1);
    Exit;
  end;
  C := TColumn.Create;
  C.Ref := luaL_ref(L, LUA_REGISTRYINDEX);
  C.Id := Trim(FieldStr(L, 'id'));
  C.Title := FieldStr(L, 'title');
  if C.Title = '' then
    C.Title := C.Id;
  lua_getfield(L, 1, 'width');
  C.Width := EnsureRange(lua_tointeger(L, -1), 0, 80);
  lua_pop(L, 1);
  if C.Width = 0 then
    C.Width := 10;
  C.Right := LowerCase(FieldStr(L, 'align')) = 'right';
  lua_getfield(L, 1, 'default');
  C.IsDefault := lua_toboolean(L, -1) <> 0;
  lua_pop(L, 1);
  if C.Id = '' then
  begin
    luaL_unref(L, LUA_REGISTRYINDEX, C.Ref);
    C.Free;
    Exit;
  end;
  GNewColumns.Add(C);
end;

procedure OnHostEvent(AUserData: Pointer; ATopic, APayloadJson: PAnsiChar); cdecl;
begin
  try
    if GEngine <> nil then
      GEngine.DispatchEvent(UTF8ToString(ATopic), UTF8ToString(APayloadJson));
  except
    // Never let an exception cross into the host.
  end;
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
  FHandlers := TObjectList<THandler>.Create(True);
  FQueue := TList<TPendingEvent>.Create;
  FSubscribed := TStringList.Create;
  GNewHandlers := TList<THandler>.Create;
  GNewColumns := TList<TColumn>.Create;
  FColumns := TObjectList<TColumn>.Create(True);
end;

destructor TMacroEngine.Destroy;
begin
  if FState <> nil then
    lua_close(FState);
  FMacros.Free;
  FHandlers.Free;
  FQueue.Free;
  FSubscribed.Free;
  FreeAndNil(GNewHandlers);
  FreeAndNil(GNewColumns);
  if FApi <> nil then
    PublishColumns;
  FColumns.Free;
  FEventMacro.Free;
  LuaHostReset;
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
  lua_register(L, 'mtn_on', LOn);
  lua_register(L, 'mtn_column', LColumn);
  LuaHostRegister(L, FApi, string(FPluginId), FTr);
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
  H: THandler;
  C: TColumn;
  Failed, HasHandlers: Boolean;

  procedure AddColumns;
  var
    Known, New: TColumn;
    Dup: Boolean;
  begin
    for New in GNewColumns do
    begin
      Dup := False;
      for Known in FColumns do
        if SameText(Known.Id, New.Id) then
          Dup := True;
      if Dup then
      begin
        luaL_unref(FState, LUA_REGISTRYINDEX, New.Ref);
        New.Free;
      end
      else
        FColumns.Add(New);
    end;
    HasHandlers := GNewColumns.Count > 0;
    GNewColumns.Clear;
    if HasHandlers then
    begin
      Subscribe('panel.dir');
      PublishColumns;
      RefreshColumns;
    end;
  end;

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
  GNewHandlers.Clear;
  GNewColumns.Clear;
  GLoading := True;
  try
    Failed := (luaL_loadbufferx(FState, PAnsiChar(Chunk), Length(Chunk), PAnsiChar(ChunkName), nil) <> LUA_OK) or
      (lua_pcall(FState, 0, 0) <> LUA_OK);
  finally
    GLoading := False;
  end;
  if Failed then
  begin
    Notify(Format(Tr('err.load', 'Macro file %s: %s'),
      [TPath.GetFileName(APath), lua_tostr(FState, -1)]), 1);
    lua_settop(FState, 0);
    for H in GNewHandlers do
    begin
      luaL_unref(FState, LUA_REGISTRYINDEX, H.Ref);
      H.Free;
    end;
    GNewHandlers.Clear;
    for C in GNewColumns do
    begin
      luaL_unref(FState, LUA_REGISTRYINDEX, C.Ref);
      C.Free;
    end;
    GNewColumns.Clear;
    Exit;
  end;
  AddColumns;
  // Handlers stay registered even when the file declares no macro.
  for H in GNewHandlers do
  begin
    H.Path := APath;
    FHandlers.Add(H);
    Subscribe(H.Topic);
  end;
  HasHandlers := HasHandlers or (GNewHandlers.Count > 0);
  GNewHandlers.Clear;
  if (GDeclared = nil) or (GDeclared.RunRef < 0) then
  begin
    if not HasHandlers then
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
  ClearHandlers;
  ClearColumns;
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
  Launch(AMacro, '', False);
  Result := True;
end;

procedure TMacroEngine.Launch(AMacro: TMacro; const APayload: string; AIsEvent: Boolean);
begin
  FThread := lua_newthread(FState);
  FThreadRef := luaL_ref(FState, LUA_REGISTRYINDEX);
  lua_rawgeti(FState, LUA_REGISTRYINDEX, AMacro.RunRef);
  lua_xmove(FState, FThread, 1);
  FStartArgs := 0;
  if AIsEvent then
  begin
    // The handler gets the payload as a table with the topic added.
    LuaPushJson(FThread, APayload);
    if lua_type(FThread, -1) <> LUA_TTABLE then
    begin
      lua_pop(FThread, 1);
      lua_newtable(FThread);
    end;
    lua_pushstr(FThread, AMacro.Name);
    lua_setfield(FThread, -2, 'topic');
    FStartArgs := 1;
  end;
  lua_sethook(FThread, CountHook, LUA_MASKCOUNT, cHookCount);
  GAbort := False;
  GExecAllowed := AMacro.Exec;
  FRunning := AMacro;
  Step;
end;

procedure TMacroEngine.ClearHandlers;
var
  H: THandler;
begin
  FQueue.Clear;
  if FState <> nil then
    for H in FHandlers do
      luaL_unref(FState, LUA_REGISTRYINDEX, H.Ref);
  FHandlers.Clear;
end;

procedure TMacroEngine.Subscribe(const ATopic: string);
var
  Plugin, Topic: UTF8String;
begin
  // doc.saved reaches the engine through the plugin's own subscription.
  if (ATopic = 'doc.saved') or (FSubscribed.IndexOf(ATopic) >= 0) or
     not Assigned(FApi.Subscribe) then
    Exit;
  Plugin := FPluginId;
  Topic := UTF8String(ATopic);
  FApi.Subscribe(PAnsiChar(Plugin), PAnsiChar(Topic), OnHostEvent, nil);
  FSubscribed.Add(ATopic);
end;

procedure TMacroEngine.DispatchEvent(const ATopic, APayload: string);
var
  H: THandler;
  Ev: TPendingEvent;
  Topic: string;
begin
  Topic := LowerCase(ATopic);
  if (Topic = 'panel.dir') and (FColumns.Count > 0) then
    RefreshColumns;
  if (FState = nil) or (FRunning <> nil) then
    Exit;
  for H in FHandlers do
    if H.Topic = Topic then
    begin
      Ev.Handler := H;
      Ev.Payload := APayload;
      FQueue.Add(Ev);
    end;
  NextEvent;
end;

procedure TMacroEngine.NextEvent;
var
  Ev: TPendingEvent;
begin
  if (FRunning <> nil) or (FQueue.Count = 0) then
    Exit;
  Ev := FQueue[0];
  FQueue.Delete(0);
  FEventMacro.Free;
  FEventMacro := TMacro.Create;
  FEventMacro.Name := Ev.Handler.Topic;
  FEventMacro.Exec := Ev.Handler.Exec;
  FEventMacro.RunRef := Ev.Handler.Ref;
  Launch(FEventMacro, Ev.Payload, True);
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
  Status := lua_resume(FThread, FState, FStartArgs, @NRes);
  FStartArgs := 0;
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
  GExecAllowed := '';
  LuaHostReset;
  if FColumnsDirty then
    RefreshColumns;
  NextEvent;
end;

function PanelListText(AApi: PHostApiTable; ASide: Int64): string;
var
  Len: Int64;
  Buf: UTF8String;
begin
  Result := '';
  Len := AApi.PanelList(ASide, nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := AApi.PanelList(ASide, PAnsiChar(Buf), Len + 1);
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

procedure TMacroEngine.ClearColumns;
var
  C: TColumn;
begin
  if FState <> nil then
    for C in FColumns do
      luaL_unref(FState, LUA_REGISTRYINDEX, C.Ref);
  FColumns.Clear;
  PublishColumns;
end;

procedure TMacroEngine.PublishColumns;
var
  Arr: TJSONArray;
  O: TJSONObject;
  C: TColumn;
  Json, Plugin: UTF8String;
begin
  if not Assigned(FApi.RegisterPanelColumns) or (FApi.AbiVersion < 9) then
    Exit;
  Plugin := FPluginId;
  if FColumns.Count = 0 then
  begin
    FApi.RegisterPanelColumns(PAnsiChar(Plugin), 'file', nil);
    Exit;
  end;
  Arr := TJSONArray.Create;
  try
    for C in FColumns do
    begin
      O := TJSONObject.Create;
      O.AddPair('id', C.Id);
      O.AddPair('title', C.Title);
      O.AddPair('width', TJSONNumber.Create(C.Width));
      if C.Right then
        O.AddPair('align', 'right')
      else
        O.AddPair('align', 'left');
      O.AddPair('sortable', TJSONBool.Create(False));
      O.AddPair('default', TJSONBool.Create(C.IsDefault));
      Arr.Add(O);
    end;
    Json := UTF8String(Arr.ToJSON);
  finally
    Arr.Free;
  end;
  FApi.RegisterPanelColumns(PAnsiChar(Plugin), 'file', PAnsiChar(Json));
end;

{ Runs the value function of AColumn for one row in a thread of its own, with
  the instruction budget of a macro. A column that fails is switched off and the
  user is told once. }
function TMacroEngine.EvalColumn(AColumn: TColumn; ARow: TJSONObject): string;
var
  T: PLuaState;
  Name: string;
  Size: Int64;
  IsDir: Boolean;
begin
  Result := '';
  if (FState = nil) or AColumn.Broken then
    Exit;
  T := lua_newthread(FState);
  try
    lua_sethook(T, CountHook, LUA_MASKCOUNT, cHookCount);
    GSlices := 0;
    GAbort := False;
    lua_rawgeti(T, LUA_REGISTRYINDEX, AColumn.Ref);
    lua_newtable(T);
    Name := JsonStr(ARow, 'name');
    SetStr(T, 'name', Name);
    SetStr(T, 'uri', JsonStr(ARow, 'uri'));
    IsDir := JsonBool(ARow, 'dir');
    SetBool(T, 'dir', IsDir);
    Size := 0;
    ARow.TryGetValue<Int64>('size', Size);
    SetInt(T, 'size', Size);
    if lua_pcall(T, 1, 1) = LUA_OK then
      Result := lua_tostr(T, -1)
    else
    begin
      AColumn.Broken := True;
      Notify(Format(Tr('err.column', 'Column "%s" failed: %s'),
        [AColumn.Id, lua_tostr(T, -1)]), 1);
    end;
  finally
    lua_pop(FState, 1);
  end;
end;

procedure TMacroEngine.RefreshColumns;
const
  cMaxRows = 3000;
var
  Side, I, N: Integer;
  Json: string;
  Root, Rows, Row, Cells, RowCells: TJSONValue;
  Folder, Text: string;
  Plugin, FolderU, CellsU: UTF8String;
  C: TColumn;
begin
  if (FColumns.Count = 0) or (FState = nil) or not Assigned(FApi.PanelList) or
     not Assigned(FApi.SetPanelColumnValues) or (FApi.AbiVersion < 9) then
    Exit;
  if FRunning <> nil then
  begin
    FColumnsDirty := True;
    Exit;
  end;
  FColumnsDirty := False;
  Plugin := FPluginId;
  for Side := 0 to 1 do
  begin
    Json := PanelListText(FApi, Side);
    Root := TJSONObject.ParseJSONValue(Json);
    try
      if not (Root is TJSONObject) then
        Continue;
      Folder := JsonStr(TJSONObject(Root), 'uri');
      Rows := TJSONObject(Root).GetValue('rows');
      if (Folder = '') or not (Rows is TJSONArray) then
        Continue;
      Cells := TJSONObject.Create;
      try
        N := 0;
        for I := 0 to TJSONArray(Rows).Count - 1 do
        begin
          Row := TJSONArray(Rows).Items[I];
          if not (Row is TJSONObject) or (N >= cMaxRows) then
            Continue;
          Inc(N);
          RowCells := TJSONObject.Create;
          for C in FColumns do
          begin
            Text := EvalColumn(C, TJSONObject(Row));
            if Text <> '' then
              TJSONObject(RowCells).AddPair(C.Id, Text);
          end;
          if TJSONObject(RowCells).Count > 0 then
            TJSONObject(Cells).AddPair(JsonStr(TJSONObject(Row), 'name'), RowCells)
          else
            RowCells.Free;
        end;
        CellsU := UTF8String(Cells.ToJSON);
      finally
        Cells.Free;
      end;
      FolderU := UTF8String(Folder);
      FApi.SetPanelColumnValues(PAnsiChar(Plugin), PAnsiChar(FolderU), PAnsiChar(CellsU));
    finally
      Root.Free;
    end;
  end;
end;

procedure TMacroEngine.RequestAbort;
begin
  if FRunning <> nil then
    GAbort := True;
end;

end.
