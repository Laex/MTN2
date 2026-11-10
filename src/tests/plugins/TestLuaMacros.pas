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
    [Test] procedure TestHostCallsWaitWhileTheProgramIsBusy;
    [Test] procedure TestWaitJobsReturnsWhenTheJobsAreDone;
    [Test] procedure TestKeysWaitWhileTheProgramIsBusy;
    [Test] procedure TestMacroSendsKeysTextAndActionsInOrder;
    [Test] procedure TestMacroReadsTheProgramState;
    [Test] procedure TestAreaMismatchStopsTheRun;
    [Test] procedure TestRequiresSelectionStopsTheRun;
    [Test] procedure TestRunawayLoopIsStopped;
    [Test] procedure TestSandboxHasNoFileAccess;
    [Test] procedure TestQuotedTextRoundTripsThroughAMacroFile;
    [Test] procedure TestEscapeStopsARunningMacro;
    [Test] procedure TestSampleMacrosRun;
    [Test] procedure TestEditorFunctionsReadAndReplace;
    [Test] procedure TestEditorLinesCountFromOne;
    [Test] procedure TestPanelFunctionsListAndSelect;
    [Test] procedure TestClipboardRoundTrip;
    [Test] procedure TestHandlerRunsOnEventWithPayload;
    [Test] procedure TestHandlerIsDroppedWhileAMacroRuns;
    [Test] procedure TestExecRefusesProgramOutsideTheList;
    [Test] procedure TestExecAllowListMatchesNamesOnly;
    [Test] procedure TestInputWithoutDialogSupportGivesNil;
    [Test] procedure TestColumnIsDeclaredAndFilledForTheFolder;
    [Test] procedure TestFailingColumnIsReportedOnceAndLeftEmpty;
    [Test] procedure TestColumnsAreWithdrawnWhenTheFolderIsReloaded;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, uLuaApi, uLuaHostFns;

var
  GKeys, GTexts, GActions, GMessages: TStringList;
  GState: string;
  GQueue: TList<THostMainCallback>;
  GDocText, GDocSelection, GClipboard: string;
  GReplaced: TStringList;
  GPanelSelects: TStringList;
  GEventCb: THostEventCallback;
  GColumnDecl, GColumnCells: string;
  GColumnCalls: Integer;

function StubRegisterColumns(APluginId, AScheme, AJson: PAnsiChar): Int64; cdecl;
begin
  if AJson = nil then
    GColumnDecl := ''
  else
    GColumnDecl := AScheme + ':' + UTF8ToString(AJson);
  Result := 0;
end;

function StubSetColumnValues(APluginId, AFolderUri, AJson: PAnsiChar): Int64; cdecl;
begin
  Inc(GColumnCalls);
  GColumnCells := UTF8ToString(AFolderUri) + '|' + UTF8ToString(AJson);
  Result := 0;
end;

function ReplyText(const AValue: string; ABuf: PAnsiChar; ABufSize: Int64): Int64;
var
  Raw: UTF8String;
begin
  Raw := UTF8String(AValue);
  Result := Length(Raw);
  if (ABuf <> nil) and (Result < ABufSize) then
    Move(PAnsiChar(Raw)^, ABuf^, Length(Raw) + 1);
end;

function StubDocInfo(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  Result := ReplyText('{"uri":"file:///C:/Work/a.txt","lines":2,"row":0,"col":1,' +
    '"dirty":false,"canEdit":true,"hasSelection":true}', ABuf, ABufSize);
end;

function StubDocGetText(AWhat: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  if AWhat = 0 then
    Result := ReplyText(GDocSelection, ABuf, ABufSize)
  else
    Result := ReplyText(GDocText, ABuf, ABufSize);
end;

function StubDocLine(AIndex: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
var
  Lines: TArray<string>;
begin
  Lines := GDocText.Split([#10]);
  if (AIndex < 0) or (AIndex >= Length(Lines)) then
    Exit(-1);
  Result := ReplyText(Lines[AIndex], ABuf, ABufSize);
end;

function StubDocReplace(AWhat: Int64; AText: PAnsiChar): Int64; cdecl;
begin
  GReplaced.Add(IntToStr(AWhat) + ':' + UTF8ToString(AText));
  Result := 0;
end;

function StubPanelList(ASide: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  Result := ReplyText('{"uri":"file:///C:/Work","cursor":0,"truncated":false,' +
    '"rows":[{"name":"a.txt","uri":"file:///C:/Work/a.txt"},' +
    '{"name":"b.txt","uri":"file:///C:/Work/b.txt"}]}', ABuf, ABufSize);
end;

function StubPanelSelect(ASide, AMode: Int64; AArg: PAnsiChar): Int64; cdecl;
begin
  GPanelSelects.Add(IntToStr(AMode) + ':' + UTF8ToString(AArg));
  Result := 0;
end;

function StubClipboardGet(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
begin
  Result := ReplyText(GClipboard, ABuf, ABufSize);
end;

function StubClipboardSet(AText: PAnsiChar): Int64; cdecl;
begin
  GClipboard := UTF8ToString(AText);
  Result := 0;
end;

function StubSubscribe(APluginId, ATopic: PAnsiChar; AOnEvent: THostEventCallback;
  AUserData: Pointer): Int64; cdecl;
begin
  GEventCb := AOnEvent;
  Result := 0;
end;

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
  GReplaced := TStringList.Create;
  GPanelSelects := TStringList.Create;
  GDocText := '';
  GDocSelection := '';
  GClipboard := '';
  GEventCb := nil;
  GColumnDecl := '';
  GColumnCells := '';
  GColumnCalls := 0;
  GState := cPanelsState;
  FApi := Default(THostApiTable);
  FApi.AbiVersion := cPluginAbiVersion;
  FApi.SendKey := @StubSendKey;
  FApi.SendText := @StubSendText;
  FApi.RunAction := @StubRunAction;
  FApi.AppState := @StubAppState;
  FApi.ShowMessage := @StubShowMessage;
  FApi.PostToMain := @StubPostToMain;
  FApi.DocInfo := @StubDocInfo;
  FApi.DocGetText := @StubDocGetText;
  FApi.DocLine := @StubDocLine;
  FApi.DocReplace := @StubDocReplace;
  FApi.PanelList := @StubPanelList;
  FApi.PanelSelect := @StubPanelSelect;
  FApi.ClipboardGet := @StubClipboardGet;
  FApi.ClipboardSet := @StubClipboardSet;
  FApi.Subscribe := @StubSubscribe;
  FApi.RegisterPanelColumns := @StubRegisterColumns;
  FApi.SetPanelColumnValues := @StubSetColumnValues;
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
  GReplaced.Free;
  GPanelSelects.Free;
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

procedure TTestLuaMacros.TestHostCallsWaitWhileTheProgramIsBusy;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "c", run = function() mtn.clipboard.set("a"); mtn.text("next") end }');
  GState := '{"area":"panels","busy":true}';
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('a', GClipboard);
  Assert.AreEqual(0, GTexts.Count, 'the next call waits for a folder listing');
  GState := cPanelsState;
  Pump;
  Assert.AreEqual('next', GTexts[0]);
  Assert.IsNull(FEngine.Running);
end;

procedure TTestLuaMacros.TestWaitJobsReturnsWhenTheJobsAreDone;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "j", run = function() mtn.key("F5"); mtn.wait_jobs(); mtn.text("done") end }');
  GState := '{"area":"panels","jobs":1}';
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual(0, GTexts.Count, 'the macro waits while a job runs');
  GState := cPanelsState;
  Pump;
  Assert.AreEqual('done', GTexts[0]);
  Assert.IsNull(FEngine.Running);
end;

procedure TTestLuaMacros.TestKeysWaitWhileTheProgramIsBusy;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "w", run = function() mtn.key("F4"); mtn.key("Ctrl+Home"); mtn.text("1") end }');
  GState := '{"area":"editor","busy":true}';
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual(1, GKeys.Count, 'the next key is held back while the document loads');
  Assert.AreEqual('F4', GKeys[0]);
  Assert.IsNotNull(FEngine.Running);
  GState := '{"area":"editor","doc":{"canEdit":true,"hasSelection":false}}';
  Pump;
  Assert.AreEqual(2, GKeys.Count);
  Assert.AreEqual('Ctrl+Home', GKeys[1]);
  Assert.AreEqual('1', GTexts[0]);
  Assert.IsNull(FEngine.Running);
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

procedure TTestLuaMacros.TestEditorFunctionsReadAndReplace;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  GDocText := 'one' + #10 + 'two';
  GDocSelection := 'ne';
  M := Load('macro { name = "e", run = function()' +
    ' local i = mtn.editor.info()' +
    ' mtn.text(i.uri .. "|" .. i.lines .. "|" .. i.row .. "|" .. tostring(i.can_edit))' +
    ' mtn.text(mtn.editor.selection() .. "|" .. mtn.editor.text())' +
    ' mtn.editor.replace("X")' +
    ' mtn.editor.replace_all("Y") end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('file:///C:/Work/a.txt|2|1|true', GTexts[0]);
  Assert.AreEqual('ne|one' + #10 + 'two', GTexts[1]);
  Assert.AreEqual('0:X', GReplaced[0]);
  Assert.AreEqual('1:Y', GReplaced[1]);
end;

procedure TTestLuaMacros.TestEditorLinesCountFromOne;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  GDocText := 'one' + #10 + 'two';
  M := Load('macro { name = "l", run = function()' +
    ' mtn.text(mtn.editor.line(1) .. "," .. mtn.editor.line(2) .. "," .. tostring(mtn.editor.line(3))) end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('one,two,nil', GTexts[0]);
end;

procedure TTestLuaMacros.TestPanelFunctionsListAndSelect;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "p", run = function()' +
    ' local l = mtn.panel.list("left")' +
    ' mtn.text(l.path .. "|" .. #l.files .. "|" .. l.files[l.cursor].name)' +
    ' mtn.panel.select("*.txt")' +
    ' mtn.panel.unselect("b*") end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('file:///C:/Work|2|a.txt', GTexts[0]);
  Assert.AreEqual('0:*.txt', GPanelSelects[0]);
  Assert.AreEqual('1:b*', GPanelSelects[1]);
end;

procedure TTestLuaMacros.TestClipboardRoundTrip;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  GClipboard := 'before';
  M := Load('macro { name = "c", run = function()' +
    ' local old = mtn.clipboard.get() mtn.clipboard.set(old .. "+after") end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('before+after', GClipboard);
end;

procedure TTestLuaMacros.TestHandlerRunsOnEventWithPayload;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('mtn.on("panel.dir", function(e) mtn.text(e.topic .. "|" .. e.uri) end)');
  Assert.IsNull(M);
  Assert.IsTrue(FEngine.Handlers.Count = 1);
  Assert.IsTrue(Assigned(GEventCb), 'the handler subscribes to its topic');
  GEventCb(nil, 'panel.dir', '{"uri":"file:///C:/Work"}');
  Pump;
  Assert.AreEqual('panel.dir|file:///C:/Work', GTexts[0]);
  Assert.IsNull(FEngine.Running);
end;

procedure TTestLuaMacros.TestHandlerIsDroppedWhileAMacroRuns;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  Load('mtn.on("panel.dir", function(e) mtn.text("handler") end)');
  M := Load('macro { name = "r", run = function() mtn.text("macro") end }');
  Assert.IsTrue(FEngine.Run(M));
  GEventCb(nil, 'panel.dir', '{}');
  Pump;
  Assert.AreEqual(1, GTexts.Count);
  Assert.AreEqual('macro', GTexts[0]);
end;

procedure TTestLuaMacros.TestExecRefusesProgramOutsideTheList;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "x", exec = "git", run = function()' +
    ' local out, why = mtn.exec("cmd", {"/c", "echo", "hi"})' +
    ' mtn.text(tostring(out) .. "|" .. tostring(why ~= nil)) end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('nil|true', GTexts[0]);
end;

procedure TTestLuaMacros.TestExecAllowListMatchesNamesOnly;
begin
  Assert.IsTrue(ExecAllowed('git', 'git, hg'));
  Assert.IsTrue(ExecAllowed('GIT.exe', 'git'));
  Assert.IsFalse(ExecAllowed('git', ''));
  Assert.IsFalse(ExecAllowed('', 'git'));
  Assert.IsFalse(ExecAllowed('C:\Tools\git', 'git'));
  Assert.IsFalse(ExecAllowed('../git', 'git'));
  Assert.IsFalse(ExecAllowed('-git', 'git'));
  Assert.IsFalse(ExecAllowed('gitk', 'git'));
end;

procedure TTestLuaMacros.TestInputWithoutDialogSupportGivesNil;
var
  M: TMacro;
begin
  if not LuaLoaded then
    Exit;
  M := Load('macro { name = "i", run = function()' +
    ' mtn.text(tostring(mtn.input("Name?", "x"))) end }');
  Assert.IsTrue(FEngine.Run(M));
  Pump;
  Assert.AreEqual('nil', GTexts[0]);
end;

procedure TTestLuaMacros.TestColumnIsDeclaredAndFilledForTheFolder;
begin
  if not LuaLoaded then
    Exit;
  Load('mtn.column { id = "len", title = "Len", width = 6, align = "right", default = true,' +
    ' value = function(f) if f.dir then return nil end return #f.name end }');
  Assert.IsTrue(GColumnDecl.StartsWith('file:'), 'columns are declared for the file scheme');
  Assert.IsTrue(GColumnDecl.Contains('"id":"len"'));
  Assert.IsTrue(GColumnDecl.Contains('"align":"right"'));
  Assert.IsTrue(GColumnDecl.Contains('"default":true'));
  Assert.IsTrue(GColumnCalls > 0, 'cells are computed when the column is loaded');
  Assert.IsTrue(GColumnCells.StartsWith('file:///C:/Work|'));
  Assert.IsTrue(GColumnCells.Contains('"a.txt":{"len":"5"}'));
end;

procedure TTestLuaMacros.TestFailingColumnIsReportedOnceAndLeftEmpty;
begin
  if not LuaLoaded then
    Exit;
  Load('mtn.column { id = "bad", value = function(f) error("boom") end }');
  Assert.AreEqual(1, GMessages.Count);
  Assert.IsTrue(GMessages[0].Contains('boom'));
  GEventCb(nil, 'panel.dir', '{}');
  Assert.AreEqual(1, GMessages.Count);
  Assert.IsTrue(GColumnCells.EndsWith('|{}'));
end;

procedure TTestLuaMacros.TestColumnsAreWithdrawnWhenTheFolderIsReloaded;
begin
  if not LuaLoaded then
    Exit;
  Load('mtn.column { id = "len", value = function(f) return #f.name end }');
  Assert.IsTrue(GColumnDecl <> '');
  TDirectory.CreateDirectory(TPath.Combine(FDir, 'empty'));
  FEngine.LoadFolder(TPath.Combine(FDir, 'empty'));
  Assert.AreEqual('', GColumnDecl);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLuaMacros);

end.
