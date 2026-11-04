unit TestLuaMacros;

{ The macro engine against a stub host: macro files are Lua, the host records the
  keys, text and actions a macro sends and hands out a fixed program state.
  Skipped (passes with a note) when no Lua library is next to the plugin sources. }

interface

uses
  DUnitX.TestFramework, System.Classes, uPluginHostAbi, uLuaMacros;

type
  [TestFixture]
  TTestLuaMacros = class
  private
    FEngine: TMacroEngine;
    FApi: THostApiTable;
    FDir: string;
    function Load(const ASource: string): TMacro;
    procedure Pump;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestMacroSendsKeysTextAndActionsInOrder;
    [Test] procedure TestMacroReadsTheProgramState;
    [Test] procedure TestAreaMismatchStopsTheRun;
    [Test] procedure TestRequiresSelectionStopsTheRun;
    [Test] procedure TestRunawayLoopIsStopped;
    [Test] procedure TestSandboxHasNoFileAccess;
    [Test] procedure TestQuotedTextRoundTripsThroughAMacroFile;
    [Test] procedure TestEscapeStopsARunningMacro;
    [Test] procedure TestSampleMacrosRun;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, uLuaApi;

var
  GKeys, GTexts, GActions, GMessages: TStringList;
  GState: string;
  GQueue: TList<THostMainCallback>;

function StubSendKey(AChord: PAnsiChar): Int64; cdecl;
begin
  GKeys.Add(UTF8ToString(AChord));
  Result := 0;
end;

function StubSendText(AText: PAnsiChar): Int64; cdecl;
begin
  GTexts.Add(UTF8ToString(AText));
  Result := 0;
end;

function StubRunAction(AAction: PAnsiChar): Int64; cdecl;
begin
  GActions.Add(UTF8ToString(AAction));
  Result := 0;
end;

function StubShowMessage(AText: PAnsiChar; AKind: Int64): Int64; cdecl;
begin
  GMessages.Add(UTF8ToString(AText));
  Result := 0;
end;

function StubAppState(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(GState);
  Result := Length(Raw);
  if (ABuf <> nil) and (Result < ABufSize) then
    Move(PAnsiChar(Raw)^, ABuf^, Length(Raw) + 1);
end;

function StubPostToMain(APluginId: PAnsiChar; ACallback: THostMainCallback;
  AUserData: Pointer): Int64; cdecl;
begin
  GQueue.Add(ACallback);
  Result := 0;
end;

function FindLuaFolder: string;
var
  Dir: string;
  I: Integer;
begin
  Dir := ExtractFilePath(ParamStr(0));
  for I := 1 to 6 do
  begin
    if TFile.Exists(TPath.Combine(TPath.Combine(Dir, 'tools'), 'lua' + PathDelim + 'lua55.dll')) then
      Exit(TPath.Combine(TPath.Combine(Dir, 'tools'), 'lua'));
    if TFile.Exists(TPath.Combine(TPath.Combine(TPath.Combine(Dir, 'src'), 'tools'), 'lua' + PathDelim + 'lua55.dll')) then
      Exit(TPath.Combine(TPath.Combine(TPath.Combine(Dir, 'src'), 'tools'), 'lua'));
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
  end;
  Result := GetEnvironmentVariable('MTN2_LUA_DIR');
end;

function FindSamples: string;
var
  Dir: string;
  I: Integer;
begin
  Dir := ExtractFilePath(ParamStr(0));
  for I := 1 to 6 do
  begin
    if TDirectory.Exists(TPath.Combine(TPath.Combine(Dir, 'samples'), 'macros')) then
      Exit(TPath.Combine(TPath.Combine(Dir, 'samples'), 'macros'));
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
  end;
  Result := '';
end;

const
  cPanelsState =
    '{"area":"panels","panels":{"active":"left","left":{"uri":"file:///C:/Work",' +
    '"cursor":"file:///C:/Work/a%20b.txt","cursorIsDirectory":false,' +
    '"selected":["file:///C:/Work/one","file:///C:/Work/two"]}}}';

procedure TTestLuaMacros.Setup;
var
  Err, Folder: string;
begin
  GKeys := TStringList.Create;
  GTexts := TStringList.Create;
  GActions := TStringList.Create;
  GMessages := TStringList.Create;
  GQueue := TList<THostMainCallback>.Create;
  GState := cPanelsState;
  FApi := Default(THostApiTable);
  FApi.AbiVersion := cPluginAbiVersion;
  FApi.SendKey := @StubSendKey;
  FApi.SendText := @StubSendText;
  FApi.RunAction := @StubRunAction;
  FApi.AppState := @StubAppState;
  FApi.ShowMessage := @StubShowMessage;
  FApi.PostToMain := @StubPostToMain;
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-lua-test-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FEngine := TMacroEngine.Create(@FApi, 'mtn.lua', nil);
  GEngine := FEngine;
  // Windows tests use the library fetched into tools\lua and are skipped
  // without it. Elsewhere the system library is used when it is installed.
  Folder := FindLuaFolder;
  {$IFDEF MSWINDOWS}
  if Folder = '' then
    Exit;
  {$ENDIF}
  if not FEngine.Open(Folder, Err) then
  begin
    {$IFDEF MSWINDOWS}
    Assert.Fail('Lua did not open: ' + Err);
    {$ENDIF}
  end;
end;

procedure TTestLuaMacros.TearDown;
begin
  GEngine := nil;
  FEngine.Free;
  LuaUnload;
  TDirectory.Delete(FDir, True);
  GKeys.Free;
  GTexts.Free;
  GActions.Free;
  GMessages.Free;
  GQueue.Free;
end;

function TTestLuaMacros.Load(const ASource: string): TMacro;
var
  Path: string;
begin
  Path := TPath.Combine(FDir, 'm' + IntToStr(FEngine.Macros.Count) + '.lua');
  TFile.WriteAllText(Path, ASource, TUTF8Encoding.Create(False));
  Result := FEngine.LoadFile(Path);
end;

procedure TTestLuaMacros.Pump;
var
  Guard: Integer;
  Cb: THostMainCallback;
begin
  Guard := 0;
  while (GQueue.Count > 0) and (Guard < 10000) do
  begin
    Cb := GQueue[0];
    GQueue.Delete(0);
    Cb(nil);
    Inc(Guard);
  end;
end;

procedure TTestLuaMacros.TestMacroSendsKeysTextAndActionsInOrder;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "t", run = function() mtn.key("F5"); mtn.text("ab"); mtn.action("Copy") end }');
  Assert.IsNotNull(M);
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('F5', GKeys[0]);
  Assert.AreEqual('ab', GTexts[0]);
  Assert.AreEqual('Copy', GActions[0]);
  Assert.IsNull(FEngine.Running);
end;

procedure TTestLuaMacros.TestMacroReadsTheProgramState;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "s", run = function()' +
    ' local s = mtn.state(); mtn.text(s.area .. "|" .. s.cursor_name .. "|" .. s.selected_count .. "|" .. #mtn.selected()) end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('panels|a b.txt|2|2', GTexts[0]);
end;

procedure TTestLuaMacros.TestAreaMismatchStopsTheRun;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "e", area = "editor", run = function() mtn.text("x") end }');
  Assert.IsFalse(FEngine.Run(M));
  Pump;
  Assert.AreEqual(0, GTexts.Count);
  Assert.AreEqual(1, GMessages.Count);
end;

procedure TTestLuaMacros.TestRequiresSelectionStopsTheRun;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  GState := '{"area":"panels","panels":{"active":"left","left":{"uri":"file:///C:/Work","selected":[]}}}';
  M := Load('macro { name = "r", requires = "has_selection", run = function() mtn.text("x") end }');
  Assert.IsFalse(FEngine.Run(M));
  Assert.AreEqual(0, GTexts.Count);
end;

procedure TTestLuaMacros.TestRunawayLoopIsStopped;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "w", run = function() while true do end end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.IsNull(FEngine.Running);
  Assert.AreEqual(1, GMessages.Count);
  Assert.IsTrue(GMessages[0].Contains('too many steps'), GMessages[0]);
end;

procedure TTestLuaMacros.TestSandboxHasNoFileAccess;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "x", run = function() mtn.text(tostring(io) .. tostring(os) .. tostring(require)) end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('nilnilnil', GTexts[0]);
end;

procedure TTestLuaMacros.TestQuotedTextRoundTripsThroughAMacroFile;
const
  cText = 'say "hi"' + #9 + 'C:\dir' + #10 + 'ünï';
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "q", run = function() mtn.text(' + LuaQuote(cText) + ') end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual(1, GTexts.Count);
  Assert.AreEqual(cText, GTexts[0]);
end;

procedure TTestLuaMacros.TestEscapeStopsARunningMacro;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "l", run = function() for i = 1, 100 do mtn.key("Down") end end }');
  Assert.IsTrue(FEngine.Run(M));
  Assert.IsNotNull(FEngine.Running);
  FEngine.RequestAbort;
  Pump;
  Assert.IsNull(FEngine.Running);
  Assert.IsTrue(GKeys.Count < 100);
end;

procedure TTestLuaMacros.TestSampleMacrosRun;
var
  Samples: string;
  M: TMacro;
begin
  Samples := FindSamples;
  if not LuaLoaded or (Samples = '') then
    Exit;
  M := FEngine.LoadFile(TPath.Combine(Samples, 'selection-report.lua'));
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('2 marked: one (+1)', GMessages[0]);

  M := FEngine.LoadFile(TPath.Combine(Samples, 'new-folder.lua'));
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('F7,Enter', GKeys.CommaText);
  Assert.AreEqual('New folder', GTexts[0]);

  GState := '{"area":"editor","doc":{"canEdit":true,"hasSelection":false}}';
  GKeys.Clear;
  M := FEngine.LoadFile(TPath.Combine(Samples, 'sort-unique-lines.lua'));
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('Ctrl+A', GKeys[0]);
  Assert.AreEqual('EditorSortLines,EditorUniqueLines', GActions.CommaText);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLuaMacros);

end.
