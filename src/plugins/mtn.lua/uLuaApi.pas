unit uLuaApi;

{ Dynamic binding to the Lua 5.4 or 5.5 C library (lua55.dll or lua54.dll next to
  the plugin on Windows, liblua5.5.so or liblua5.4.so on Linux). Nothing is linked statically, so the plugin
  loads and reports a clear error when the library is missing. Only what the
  macro engine needs is bound; the macros of lua.h (lua_pop, lua_pcall, ...) are
  small functions here. }

interface

type
  PLuaState = Pointer;
  TLuaCFunction = function(L: PLuaState): Integer; cdecl;
  TLuaHook = procedure(L: PLuaState; ADebug: Pointer); cdecl;

const
  LUA_OK = 0;
  LUA_YIELD = 1;
  LUA_MULTRET = -1;
  LUA_TNIL = 0;
  LUA_TBOOLEAN = 1;
  LUA_TNUMBER = 3;
  LUA_TSTRING = 4;
  LUA_TTABLE = 5;
  LUA_TFUNCTION = 6;
  LUA_MASKCOUNT = 8;

/// <summary>Loads the Lua library; False (with the reason in ALastError) when it is missing.</summary>
function LuaLoad(const AFolder: string): Boolean;
function LuaLoaded: Boolean;
function LuaLastError: string;
procedure LuaUnload;

var
  /// <summary>Lua 5.4 puts the registry at -1001000, 5.5 at -(INT_MAX div 2 + 1000); set by LuaLoad.</summary>
  LUA_REGISTRYINDEX: Integer = -1001000;
  luaL_newstate: function: PLuaState; cdecl;
  lua_close: procedure(L: PLuaState); cdecl;
  luaL_requiref: procedure(L: PLuaState; AName: PAnsiChar; AOpen: TLuaCFunction; AGlobal: Integer); cdecl;
  luaopen_base: function(L: PLuaState): Integer; cdecl;
  luaopen_string: function(L: PLuaState): Integer; cdecl;
  luaopen_table: function(L: PLuaState): Integer; cdecl;
  luaopen_math: function(L: PLuaState): Integer; cdecl;
  luaopen_utf8: function(L: PLuaState): Integer; cdecl;
  luaopen_coroutine: function(L: PLuaState): Integer; cdecl;
  lua_gettop: function(L: PLuaState): Integer; cdecl;
  lua_settop: procedure(L: PLuaState; AIndex: Integer); cdecl;
  lua_type: function(L: PLuaState; AIndex: Integer): Integer; cdecl;
  lua_tolstring: function(L: PLuaState; AIndex: Integer; ALen: PNativeUInt): PAnsiChar; cdecl;
  lua_tointegerx: function(L: PLuaState; AIndex: Integer; AIsNum: PInteger): Int64; cdecl;
  lua_toboolean: function(L: PLuaState; AIndex: Integer): Integer; cdecl;
  lua_pushnil: procedure(L: PLuaState); cdecl;
  lua_pushinteger: procedure(L: PLuaState; N: Int64); cdecl;
  lua_pushboolean: procedure(L: PLuaState; B: Integer); cdecl;
  lua_pushlstring: function(L: PLuaState; S: PAnsiChar; ALen: NativeUInt): PAnsiChar; cdecl;
  lua_pushcclosure: procedure(L: PLuaState; F: TLuaCFunction; N: Integer); cdecl;
  lua_pushvalue: procedure(L: PLuaState; AIndex: Integer); cdecl;
  lua_createtable: procedure(L: PLuaState; AArr, ARec: Integer); cdecl;
  lua_setfield: procedure(L: PLuaState; AIndex: Integer; AKey: PAnsiChar); cdecl;
  lua_getfield: function(L: PLuaState; AIndex: Integer; AKey: PAnsiChar): Integer; cdecl;
  lua_seti: procedure(L: PLuaState; AIndex: Integer; N: Int64); cdecl;
  lua_geti: function(L: PLuaState; AIndex: Integer; N: Int64): Integer; cdecl;
  lua_rawlen: function(L: PLuaState; AIndex: Integer): UInt64; cdecl;
  lua_setglobal: procedure(L: PLuaState; AName: PAnsiChar); cdecl;
  lua_getglobal: function(L: PLuaState; AName: PAnsiChar): Integer; cdecl;
  lua_next: function(L: PLuaState; AIndex: Integer): Integer; cdecl;
  lua_newthread: function(L: PLuaState): PLuaState; cdecl;
  lua_xmove: procedure(AFrom, ATo: PLuaState; N: Integer); cdecl;
  lua_resume: function(L, AFrom: PLuaState; AArgs: Integer; AResults: PInteger): Integer; cdecl;
  lua_yieldk: function(L: PLuaState; AResults: Integer; ACtx: NativeInt; AK: Pointer): Integer; cdecl;
  lua_status: function(L: PLuaState): Integer; cdecl;
  lua_sethook: procedure(L: PLuaState; AHook: TLuaHook; AMask, ACount: Integer); cdecl;
  lua_rawgeti: function(L: PLuaState; AIndex: Integer; N: Int64): Integer; cdecl;
  luaL_ref: function(L: PLuaState; ATable: Integer): Integer; cdecl;
  luaL_unref: procedure(L: PLuaState; ATable, ARef: Integer); cdecl;
  luaL_loadbufferx: function(L: PLuaState; ABuf: PAnsiChar; ASize: NativeUInt;
    AName, AMode: PAnsiChar): Integer; cdecl;
  lua_pcallk: function(L: PLuaState; AArgs, AResults, AErrFunc: Integer; ACtx: NativeInt;
    AK: Pointer): Integer; cdecl;
  luaL_error: function(L: PLuaState; AFmt, AArg: PAnsiChar): Integer; cdecl;

procedure lua_pop(L: PLuaState; N: Integer);
procedure lua_pushcfunction(L: PLuaState; F: TLuaCFunction);
procedure lua_register(L: PLuaState; AName: PAnsiChar; F: TLuaCFunction);
procedure lua_newtable(L: PLuaState);
function lua_pcall(L: PLuaState; AArgs, AResults: Integer): Integer;
function lua_isnil(L: PLuaState; AIndex: Integer): Boolean;
/// <summary>The Lua string (UTF-8) at AIndex as a Delphi string; '' for a non-string.</summary>
function lua_tostr(L: PLuaState; AIndex: Integer): string;
procedure lua_pushstr(L: PLuaState; const S: string);
function lua_tointeger(L: PLuaState; AIndex: Integer): Int64;
/// <summary>Raises a Lua error with AMsg. Lua unwinds with a long jump, so the caller
/// must hold no managed locals (strings, interfaces) at that point.</summary>
function lua_fail(L: PLuaState; AMsg: PAnsiChar): Integer;

implementation

uses
  System.SysUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ELSE}, Posix.Dlfcn{$ENDIF};

var
  GLib: NativeUInt;
  GError: string;

function Sym(const AName: AnsiString): Pointer;
begin
  {$IFDEF MSWINDOWS}
  Result := GetProcAddress(HMODULE(GLib), PAnsiChar(AName));
  {$ELSE}
  Result := dlsym(GLib, PAnsiChar(AName));
  {$ENDIF}
  if Result = nil then
    GError := 'missing function ' + string(AName);
end;

function LuaLoad(const AFolder: string): Boolean;
var
  Candidates: TArray<string>;
  Name: string;
begin
  if GLib <> 0 then
    Exit(True);
  GError := '';
  {$IFDEF MSWINDOWS}
  Candidates := ['lua55.dll', 'lua54.dll', 'lua5.4.dll'];
  for Name in Candidates do
  begin
    GLib := LoadLibrary(PChar(IncludeTrailingPathDelimiter(AFolder) + Name));
    if GLib <> 0 then
    begin
      if SameText(Name, 'lua55.dll') then
        LUA_REGISTRYINDEX := -(MaxInt div 2 + 1000);
      Break;
    end;
  end;
  {$ELSE}
  Candidates := ['liblua5.5.so', 'liblua5.5.so.0', 'liblua-5.5.so', 'liblua5.4.so', 'liblua5.4.so.0', 'liblua-5.4.so'];
  for Name in Candidates do
  begin
    GLib := NativeUInt(dlopen(PAnsiChar(AnsiString(IncludeTrailingPathDelimiter(AFolder) + Name)), RTLD_NOW));
    if GLib = 0 then
      GLib := NativeUInt(dlopen(PAnsiChar(AnsiString(Name)), RTLD_NOW));
    if GLib <> 0 then
    begin
      if Pos('5.5', Name) > 0 then
        LUA_REGISTRYINDEX := -(MaxInt div 2 + 1000);
      Break;
    end;
  end;
  {$ENDIF}
  if GLib = 0 then
  begin
    GError := '(Lua 5.4/5.5 not found)';
    Exit(False);
  end;
  @luaL_newstate := Sym('luaL_newstate');
  @lua_close := Sym('lua_close');
  @luaL_requiref := Sym('luaL_requiref');
  @luaopen_base := Sym('luaopen_base');
  @luaopen_string := Sym('luaopen_string');
  @luaopen_table := Sym('luaopen_table');
  @luaopen_math := Sym('luaopen_math');
  @luaopen_utf8 := Sym('luaopen_utf8');
  @luaopen_coroutine := Sym('luaopen_coroutine');
  @lua_gettop := Sym('lua_gettop');
  @lua_settop := Sym('lua_settop');
  @lua_type := Sym('lua_type');
  @lua_tolstring := Sym('lua_tolstring');
  @lua_tointegerx := Sym('lua_tointegerx');
  @lua_toboolean := Sym('lua_toboolean');
  @lua_pushnil := Sym('lua_pushnil');
  @lua_pushinteger := Sym('lua_pushinteger');
  @lua_pushboolean := Sym('lua_pushboolean');
  @lua_pushlstring := Sym('lua_pushlstring');
  @lua_pushcclosure := Sym('lua_pushcclosure');
  @lua_pushvalue := Sym('lua_pushvalue');
  @lua_createtable := Sym('lua_createtable');
  @lua_setfield := Sym('lua_setfield');
  @lua_getfield := Sym('lua_getfield');
  @lua_seti := Sym('lua_seti');
  @lua_geti := Sym('lua_geti');
  @lua_rawlen := Sym('lua_rawlen');
  @lua_setglobal := Sym('lua_setglobal');
  @lua_getglobal := Sym('lua_getglobal');
  @lua_next := Sym('lua_next');
  @lua_newthread := Sym('lua_newthread');
  @lua_xmove := Sym('lua_xmove');
  @lua_resume := Sym('lua_resume');
  @lua_yieldk := Sym('lua_yieldk');
  @lua_status := Sym('lua_status');
  @lua_sethook := Sym('lua_sethook');
  @lua_rawgeti := Sym('lua_rawgeti');
  @luaL_ref := Sym('luaL_ref');
  @luaL_unref := Sym('luaL_unref');
  @luaL_loadbufferx := Sym('luaL_loadbufferx');
  @lua_pcallk := Sym('lua_pcallk');
  @luaL_error := Sym('luaL_error');
  Result := GError = '';
  if not Result then
    LuaUnload;
end;

function LuaLoaded: Boolean;
begin
  Result := GLib <> 0;
end;

function LuaLastError: string;
begin
  Result := GError;
end;

procedure LuaUnload;
begin
  if GLib = 0 then
    Exit;
  {$IFDEF MSWINDOWS}
  FreeLibrary(HMODULE(GLib));
  {$ELSE}
  dlclose(GLib);
  {$ENDIF}
  GLib := 0;
end;

procedure lua_pop(L: PLuaState; N: Integer);
begin
  lua_settop(L, -N - 1);
end;

procedure lua_pushcfunction(L: PLuaState; F: TLuaCFunction);
begin
  lua_pushcclosure(L, F, 0);
end;

procedure lua_register(L: PLuaState; AName: PAnsiChar; F: TLuaCFunction);
begin
  lua_pushcclosure(L, F, 0);
  lua_setglobal(L, AName);
end;

procedure lua_newtable(L: PLuaState);
begin
  lua_createtable(L, 0, 0);
end;

function lua_pcall(L: PLuaState; AArgs, AResults: Integer): Integer;
begin
  Result := lua_pcallk(L, AArgs, AResults, 0, 0, nil);
end;

function lua_isnil(L: PLuaState; AIndex: Integer): Boolean;
begin
  Result := lua_type(L, AIndex) = LUA_TNIL;
end;

function lua_tostr(L: PLuaState; AIndex: Integer): string;
var
  P: PAnsiChar;
  Len: NativeUInt;
  Raw: UTF8String;
begin
  Result := '';
  if lua_type(L, AIndex) <> LUA_TSTRING then
    Exit;
  P := lua_tolstring(L, AIndex, @Len);
  if (P = nil) or (Len = 0) then
    Exit;
  SetString(Raw, P, Len);
  Result := UTF8ToString(Raw);
end;

procedure lua_pushstr(L: PLuaState; const S: string);
var
  Raw: UTF8String;
begin
  Raw := UTF8String(S);
  lua_pushlstring(L, PAnsiChar(Raw), Length(Raw));
end;

function lua_tointeger(L: PLuaState; AIndex: Integer): Int64;
begin
  Result := lua_tointegerx(L, AIndex, nil);
end;

function lua_fail(L: PLuaState; AMsg: PAnsiChar): Integer;
begin
  Result := luaL_error(L, '%s', AMsg);
end;

end.
