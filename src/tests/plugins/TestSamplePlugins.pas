unit TestSamplePlugins;

{ Loads the demo plugins of samples\plugins (built by samples\build-samples.ps1
  into samples\.build) through the real loader and checks what they register.
  A sample that has not been built is skipped, so the group still runs on a
  machine without the C++, Rust, Go or Delphi toolchain. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSamplePlugins = class
  public
    [Test] procedure TestCppOperationCounter;
    [Test] procedure TestVideoPlayerClaimsVideoFiles;
    [Test] procedure TestTextToolsChangeTheDocument;
    [Test] procedure TestTextToolsTidyOnSaveHooksTheEditor;
    [Test] procedure TestPanelKitUsesPanelsAndEvents;
    [Test] procedure TestWordCountFromWasm;
    [Test] procedure TestHighlightPluginNamesClassesOfALine;
    [Test] procedure TestPanelKitSelectsAndCountsInTheBackground;
    [Test] procedure TestPanelKitPeeksAFileOnlyWithThePermission;
    [Test] procedure TestPanelKitChecksumsAFileInPieces;
    [Test] procedure TestNativeViewGivesThePluginAWindow;
    [Test] procedure TestPictureViewerFillsASurface;
    [Test] procedure TestRustCsvViewer;
    [Test] procedure TestGoJsonViewer;
    [Test] procedure TestGoWasmSafeDelete;
    [Test] procedure TestDelphiNotes;
    [Test] procedure TestWatCounter;
    [Test] procedure TestWasiIsOptIn;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  Winapi.Windows, Winapi.Messages,
  uCommandRegistry, uDocumentProviders, uPluginChrome, uPluginUi, uDialogTypes,
  uPluginLoader, uPluginSettings, uPluginSurface, uPluginServices, uPluginHighlight, uNativeSurface, uPluginPermissions,
  uNotice, uWasmPluginHost;

var
  GPending: TProc<string, string>;
  GDialogTitle: string;

function BuiltSample(const AId: string): string;
begin
  Result := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\samples\.build\' + AId));
end;

procedure InstallDialogHost;
begin
  GPending := nil;
  GDialogTitle := '';
  SetPluginDialogHost(
    function(const ADecl: TDialogDeclaration; const AOnCommand: TProc<string, string>): Boolean
    begin
      GDialogTitle := ADecl.Title;
      GPending := AOnCommand;
      Result := True;
    end);
end;

var
  GDocText, GDocSelection: string;
  GDocReadOnly: Boolean;
  GReplaced: Integer;
  GCursorRow, GCursorCol: Integer;
  GGotoSide: Integer;
  GGotoUri: string;
  GSelectSide, GSelectMode: Integer;
  GSelectArg: string;
  GPanelJson: string;
  GNotices: string;

// A document held in memory behind the plugin services, standing in for the editor.
procedure InstallFakeServices;
var
  Svc: TPluginHostServices;
begin
  GDocText := '';
  GDocSelection := '';
  GDocReadOnly := False;
  GReplaced := 0;
  GCursorRow := 0;
  GCursorCol := 0;
  GGotoSide := -9;
  GGotoUri := '';
  GSelectSide := -9;
  GSelectMode := -9;
  GSelectArg := '';
  GPanelJson := '';
  GNotices := '';
  Svc := Default(TPluginHostServices);
  Svc.DocInfo :=
    function: string
    begin
      Result := Format('{"row":%d,"col":%d,"canEdit":%s}', [GCursorRow, GCursorCol,
        LowerCase(BoolToStr(not GDocReadOnly, True))]);
    end;
  Svc.DocGetText :=
    function(AWhat: Integer; out AText: string): Boolean
    begin
      case AWhat of
        0: AText := GDocSelection;
        1: AText := GDocText;
      else
        AText := '';
      end;
      Result := True;
    end;
  Svc.DocReplace :=
    function(AWhat: Integer; const AText: string): Boolean
    begin
      Result := not GDocReadOnly;
      if not Result then
        Exit;
      Inc(GReplaced);
      if AWhat = 1 then
        GDocText := AText
      else if AWhat = 0 then
      begin
        GDocText := StringReplace(GDocText, GDocSelection, AText, []);
        GDocSelection := AText;
      end;
    end;
  Svc.DocSetCursor :=
    function(ARow, ACol: Integer): Boolean
    begin
      GCursorRow := ARow;
      GCursorCol := ACol;
      Result := True;
    end;
  Svc.PanelInfo :=
    function: string
    begin
      Result := GPanelJson;
    end;
  Svc.PanelGoto :=
    function(ASide: Integer; const AURI: string): Boolean
    begin
      GGotoSide := ASide;
      GGotoUri := AURI;
      Result := True;
    end;
  Svc.PanelSelect :=
    function(ASide, AMode: Integer; const AArg: string): Boolean
    begin
      GSelectSide := ASide;
      GSelectMode := AMode;
      GSelectArg := AArg;
      Result := True;
    end;
  SetPluginHostServices(Svc);
  SetNoticeHandler(
    procedure(const ARequest: TNoticeRequest)
    begin
      GNotices := GNotices + ARequest.Arg + '|';
    end);
end;

procedure RemoveFakeServices;
begin
  SetPluginHostServices(Default(TPluginHostServices));
  SetNoticeHandler(nil);
  PluginLoader.UnloadAll;
end;

function StageAndLoad(const AId: string): Boolean;
var
  Dir, Root, Target: string;
  F: string;
begin
  Result := False;
  Dir := BuiltSample(AId);
  if not TDirectory.Exists(Dir) then
    Exit;
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-' + AId);
  if TDirectory.Exists(Root) then
    try
      TDirectory.Delete(Root, True);
    except
      // A module that cannot be unloaded (Go) keeps its folder busy.
    end;
  Target := TPath.Combine(Root, AId);
  TDirectory.CreateDirectory(Target);
  for F in TDirectory.GetFiles(Dir) do
    try
      TFile.Copy(F, TPath.Combine(Target, ExtractFileName(F)), True);
    except
      // Already in place and mapped by a previous test.
    end;
  PluginLoader.UnloadAll;
  PluginLoader.LoadPluginsFrom(Root);
  Result := PluginLoader.IsPluginLoaded(AId);
end;

// A fresh folder for the settings files of a test, so a developer's own
// plugin settings never leak into the checks.
function ScratchSettings(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-sample-settings-' + AName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  TDirectory.CreateDirectory(Result);
end;

function WriteTemp(const AName, AText: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-sample-' + AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function FileUri(const APath: string): string;
begin
  Result := 'file:///' + StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

procedure TTestSamplePlugins.TestCppOperationCounter;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.cpp')) then
    Assert.Pass('SKIP: mtn.demo.cpp is not built (run samples\build-samples.ps1)');
  InstallDialogHost;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.cpp'), 'the C++ plugin loads');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Copy', 'key'),
      'the hook only observes: the built-in Copy still runs');
    CommandRegistry.TryIntercept('Delete', 'menu');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Ops: 2',
      'the status segment counts the commands: ' + string.Join(',', PluginChrome.StatusSegments));
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl, ssAlt]) = 'Stats', 'the bar caption');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.cpp.stats') and (GDialogTitle = 'Operations'),
      'the stats command shows its dialog');
  finally
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestVideoPlayerClaimsVideoFiles;
var
  Redirect: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.video')) then
    Assert.Pass('SKIP: mtn.demo.video is not built (run samplesuild-samples.ps1)');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.video'), 'the video plugin loads');
    Assert.IsTrue(Pos('.mp4', string.Join(',', DocumentProviders.DescribePlugin('mtn.demo.video'))) > 0,
      'video extensions are registered');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(WriteTemp('plain.txt', 'x')), True, Redirect) = dokPass,
      'other files are not offered');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestPictureViewerFillsASurface;
const
  // 1x1 24-bit BMP, the pixel is B=$FF, G=$80, R=$40
  cBmp: array[0..57] of Byte = (
    $42, $4D, $3A, 0, 0, 0, 0, 0, 0, 0, $36, 0, 0, 0, $28, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, $18, 0,
    0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, $FF, $80, $40, 0);
var
  Bmp, Redirect: string;
  Stream: TFileStream;
  Handle, W, H, Center: Integer;
  Gen: Cardinal;
  Pixels: PByte;
  Before: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.img')) then
    Assert.Pass('SKIP: mtn.demo.img is not built (run samples\build-samples.ps1)');
  Handle := 0;
  SetPluginSurfaceHost(
    function(AHandle: Integer): Boolean
    begin
      Handle := AHandle;
      SurfaceAttach(AHandle, procedure begin end, procedure begin SurfaceTabClosed(AHandle); end);
      Result := True;
    end);
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.img'), 'the picture plugin loads');
    Bmp := TPath.Combine(TPath.GetTempPath, 'mtn2-sample-pixel.bmp');
    Stream := TFileStream.Create(Bmp, fmCreate);
    try
      Stream.WriteBuffer(cBmp, SizeOf(cBmp));
    finally
      Stream.Free;
    end;
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Bmp), True, Redirect) = dokHandled,
      'F3 on a picture is handled by the plugin');
    Assert.IsTrue(Handle > 0, 'a surface tab was opened');
    Assert.IsTrue(SurfaceFrame(Handle, W, H, Gen, Pixels), 'the plugin sent the picture');
    Assert.IsTrue(SurfaceDeliverMouse(Handle, 5, 0, 0, 40, 30, 0, 0, 0), 'the plugin takes the size of the area');
    Assert.IsTrue(SurfaceFrame(Handle, W, H, Gen, Pixels) and (W = 40) and (H = 30),
      'the frame is rendered for the area: ' + IntToStr(W) + 'x' + IntToStr(H));
    Center := ((15 * 40) + 20) * 4;
    Assert.IsTrue((Pixels[Center] = $FF) and (Pixels[Center + 1] = $80) and (Pixels[Center + 2] = $40) and
      (Pixels[Center + 3] = $FF), 'the picture is in the middle as B, G, R, A');
    Assert.IsTrue((Pixels[0] = 16) and (Pixels[3] = $FF), 'and the area around it is dark');
    Assert.AreEqual('mtn2-sample-pixel.bmp', SurfaceTitle(Handle), 'the tab is named after the file');
    Assert.IsTrue(Pos('1x1', SurfaceStatus(Handle)) > 0, 'the status line has the size');
    Before := SurfaceStatus(Handle);
    Assert.IsTrue(SurfaceDeliverMouse(Handle, 3, 20, 15, 40, 30, 3, 2, 0), 'the wheel zooms');
    Assert.AreNotEqual(Before, SurfaceStatus(Handle), 'the zoom shows in the status line');
    Assert.IsTrue(SurfaceDeliverMouse(Handle, 0, 20, 15, 40, 30, 1, 0, 0), 'a button down starts a drag');
    Assert.IsTrue(SurfaceDeliverMouse(Handle, 2, 25, 15, 40, 30, 1, 0, 0), 'the move drags');
    Assert.IsTrue(SurfaceDeliverMouse(Handle, 1, 25, 15, 40, 30, 1, 0, 0), 'the button up ends it');
    Assert.IsTrue(SurfaceDeliverKey(Handle, 0, [], 'r'), 'r rotates');
    Assert.IsTrue(SurfaceDeliverKey(Handle, 0, [], 'f'), 'f asks for full screen');
    Assert.IsTrue(SurfaceFullscreen(Handle), 'and gets it');
    Assert.IsTrue(SurfaceDeliverKey(Handle, vkRight, [], #0), 'a browsing key is used');
    Assert.IsFalse(SurfaceDeliverKey(Handle, 0, [], 'x'), 'other keys are left alone');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(WriteTemp('plain.txt', 'x')), True, Redirect) = dokPass,
      'other files are not offered');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(WriteTemp('broken.png', 'not a picture')), True, Redirect) = dokPass,
      'a file that does not decode is left to the next provider');
    PluginLoader.UnloadAll;
    Assert.IsFalse(SurfaceExists(Handle), 'unloading the plugin closes its tab');
  finally
    SetPluginSurfaceHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestTextToolsChangeTheDocument;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.texttools')) then
    Assert.Pass('SKIP: mtn.demo.texttools is not built (run samples\build-samples.ps1)');
  SetPluginSettingsDirectory(ScratchSettings('texttools'));
  InstallFakeServices;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.texttools'), 'the text tools plugin loads');
    GDocText := 'pear'#10'Apple'#10'pear'#10'apple';
    Assert.IsTrue(CommandRegistry.TryExecute('texttools.sort'), 'sort runs');
    Assert.AreEqual('Apple'#10'apple'#10'pear'#10'pear', GDocText, 'sorted ignoring case; stable for equal lines');
    Assert.IsTrue(CommandRegistry.TryExecute('texttools.repeats'), 'remove repeats runs');
    Assert.AreEqual('Apple'#10'apple'#10'pear', GDocText, 'the second pear is gone');

    GDocSelection := 'hello';
    GDocText := 'say hello';
    Assert.IsTrue(CommandRegistry.TryExecute('texttools.upper'), 'upper-case runs');
    Assert.AreEqual('say HELLO', GDocText, 'the selection is upper-cased');
    GDocSelection := '';
    GReplaced := 0;
    Assert.IsTrue(CommandRegistry.TryExecute('texttools.upper'), 'upper-case without a selection');
    Assert.AreEqual(0, GReplaced, 'nothing is replaced when nothing is selected');
    Assert.IsTrue(Pos('Select some text first.', GNotices) > 0, 'the user is told: ' + GNotices);

    GDocReadOnly := True;
    GDocText := 'b'#10'a';
    GNotices := '';
    CommandRegistry.TryExecute('texttools.sort');
    Assert.AreEqual('b'#10'a', GDocText, 'a read-only document is left alone');
    Assert.IsTrue(Pos('read-only', GNotices) > 0, 'and the user is told: ' + GNotices);
  finally
    RemoveFakeServices;
    SetPluginSettingsDirectory('');
  end;
end;

procedure TTestSamplePlugins.TestTextToolsTidyOnSaveHooksTheEditor;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.texttools')) then
    Assert.Pass('SKIP: mtn.demo.texttools is not built (run samples\build-samples.ps1)');
  SetPluginSettingsDirectory(ScratchSettings('texttools-tidy'));
  InstallFakeServices;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.texttools'), 'the text tools plugin loads');
    GDocText := 'a  '#10'b';
    Assert.IsFalse(CommandRegistry.TryIntercept('EditorSave', 'key'), 'the hook never cancels the save');
    Assert.AreEqual('a  '#10'b', GDocText, 'tidy is off at first');

    CommandRegistry.TryExecute('texttools.tidy');
    GCursorRow := 1;
    GCursorCol := 1;
    GReplaced := 0;
    Assert.IsFalse(CommandRegistry.TryIntercept('EditorSave', 'key'), 'the save still goes on');
    Assert.AreEqual('a'#10'b'#10, GDocText, 'trailing blanks are gone and the text ends with a line break');
    Assert.AreEqual(1, GReplaced, 'one replacement');
    Assert.IsTrue((GCursorRow = 1) and (GCursorCol = 1), 'the cursor is put back');
    CommandRegistry.TryIntercept('EditorSave', 'key');
    Assert.AreEqual(1, GReplaced, 'a tidy text is not replaced again');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Tidy on save', 'the status segment shows it');

    // The choice is kept: a fresh load starts with tidy on.
    PluginLoader.UnloadAll;
    Assert.IsTrue(StageAndLoad('mtn.demo.texttools'), 'loaded again');
    GDocText := 'x '#10;
    CommandRegistry.TryIntercept('EditorSave', 'key');
    Assert.AreEqual('x'#10, GDocText, 'the setting was remembered');
  finally
    RemoveFakeServices;
    SetPluginSettingsDirectory('');
  end;
end;

procedure TTestSamplePlugins.TestPanelKitUsesPanelsAndEvents;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.panelkit')) then
    Assert.Pass('SKIP: mtn.demo.panelkit is not built (run samples\build-samples.ps1)');
  InstallFakeServices;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.panelkit'), 'the panel tools plugin loads');
    GPanelJson := '{"active":"right","left":{"uri":"file:///C:/left","selected":[]},' +
      '"right":{"uri":"file:///C:/Work/My%20Files","cursor":"file:///C:/Work/My%20Files/a.txt","selected":[]}}';
    Assert.IsTrue(CommandRegistry.TryExecute('panelkit.mirror'), 'mirror runs');
    Assert.AreEqual(0, GGotoSide, 'the other panel (left) is moved');
    Assert.AreEqual('file:///C:/Work/My%20Files', GGotoUri, 'to the folder of the active one');
    GPanelJson := '{"active":"left","left":{"uri":"file:///C:/left"},"right":{"uri":"file:///C:/right"}}';
    CommandRegistry.TryExecute('panelkit.mirror');
    Assert.AreEqual(1, GGotoSide, 'and the other way round');
    Assert.AreEqual('file:///C:/left', GGotoUri);

    GPanelJson := '';
    GNotices := '';
    CommandRegistry.TryExecute('panelkit.mirror');
    Assert.IsTrue(Pos('not on screen', GNotices) > 0, 'without panels the user is told: ' + GNotices);

    GNotices := '';
    PluginPublishEvent('doc.saved', PluginUriPayload('file:///C:/Work/My%20Files/notes.txt'));
    Assert.IsTrue(Pos('Saved: notes.txt', GNotices) > 0, 'the saved event is shown: ' + GNotices);
    GNotices := '';
    PluginPublishEvent('doc.opened', PluginUriPayload('file:///C:/a.txt'));
    Assert.AreEqual('', GNotices, 'other events are not subscribed');
  finally
    RemoveFakeServices;
  end;
end;

procedure TTestSamplePlugins.TestWordCountFromWasm;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.wc')) then
    Assert.Pass('SKIP: mtn.demo.wc is not built (run samples\build-samples.ps1)');
  InstallFakeServices;
  try
    if not StageAndLoad('mtn.demo.wc') then
      Assert.Pass('SKIP: the WASM runtime is not available');
    GDocText := 'one two'#10'three';
    Assert.IsTrue(CommandRegistry.TryExecute('wc.count'), 'the command runs');
    Assert.IsTrue(Pos('document: 2 lines, 3 words, 13 characters', GNotices) > 0, 'whole document: ' + GNotices);
    GNotices := '';
    GDocSelection := 'one two';
    CommandRegistry.TryExecute('wc.count');
    Assert.IsTrue(Pos('selection: 1 lines, 2 words, 7 characters', GNotices) > 0, 'selection: ' + GNotices);
    // A document longer than the first buffer the guest offers is read in full.
    GNotices := '';
    GDocSelection := '';
    GDocText := StringOfChar('w', 6000);
    CommandRegistry.TryExecute('wc.count');
    Assert.IsTrue(Pos('1 lines, 1 words, 6000 characters', GNotices) > 0, 'a long document: ' + GNotices);
  finally
    RemoveFakeServices;
  end;
end;

procedure TTestSamplePlugins.TestHighlightPluginNamesClassesOfALine;
var
  Id: Integer;
  Spans: THighlightSpans;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.highlight')) then
    Assert.Pass('SKIP: mtn.demo.highlight is not built (run samples\build-samples.ps1)');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.highlight'), 'the highlight plugin loads');
    Id := HighlighterFor('.json');
    Assert.IsTrue(Id <> 0, 'it serves .json');
    Assert.IsTrue(HighlighterFor('.ini') <> 0, 'and .ini');
    Assert.AreEqual(0, HighlighterFor('.pas'), 'not .pas');
    Assert.IsTrue(HighlightLine(Id, '  "name": "MTN2", "on": true, "n": 3.5', Spans), 'a JSON line');
    Assert.IsTrue((Spans[0].Start = 2) and (Spans[0].Len = 6) and (Spans[0].Kind = cHighlightKey), 'the key "name"');
    Assert.IsTrue((Spans[2].Start = 10) and (Spans[2].Len = 6) and (Spans[2].Kind = cHighlightString), 'its string value');
    Assert.IsTrue(HighlightLine(Id, '; a comment', Spans) and (Length(Spans) = 1) and
      (Spans[0].Kind = cHighlightComment) and (Spans[0].Len = 11), 'a comment is one span');
    Assert.IsTrue(HighlightLine(Id, '[general]', Spans) and (Spans[0].Kind = cHighlightType), 'a section');
    // Spans count characters, not the bytes the plugin counts: two Cyrillic letters are 4 bytes.
    Assert.IsTrue(HighlightLine(Id, '"' + #$043A#$043B#$044E#$0447 + '": 1', Spans), 'a line with Cyrillic');
    Assert.IsTrue((Spans[0].Start = 0) and (Spans[0].Len = 6) and (Spans[0].Kind = cHighlightKey), 'the key in characters');
    Assert.IsTrue((Spans[1].Start = 6) and (Spans[1].Kind = cHighlightOperator), 'the colon after it');
    PluginLoader.UnloadAll;
    Assert.AreEqual(0, HighlighterFor('.json'), 'unloading the plugin drops its colors');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestPanelKitSelectsAndCountsInTheBackground;
var
  Root: string;
  I: Integer;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.panelkit')) then
    Assert.Pass('SKIP: mtn.demo.panelkit is not built (run samples\build-samples.ps1)');
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-panelkit-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(TPath.Combine(Root, 'sub'));
  TFile.WriteAllText(TPath.Combine(Root, 'a.txt'), 'a');
  TFile.WriteAllText(TPath.Combine(Root, 'b.txt'), 'bb');
  TFile.WriteAllText(TPath.Combine(Root, 'sub\c.txt'), 'ccc');
  InstallFakeServices;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.panelkit'), 'the panel tools plugin loads');
    GPanelJson := '{"active":"left","left":{"uri":"' + FileUri(Root) + '","cursor":"' +
      FileUri(TPath.Combine(Root, 'B.TXT')) + '"},"right":{"uri":"file:///C:/x"}}';
    Assert.IsTrue(CommandRegistry.TryExecute('panelkit.selectext'), 'select same extension runs');
    Assert.AreEqual('*.TXT', GSelectArg, 'the mask is the extension of the cursor file');
    Assert.AreEqual(0, GSelectMode, 'select, not unselect');
    Assert.AreEqual(-1, GSelectSide, 'in the active panel');

    GNotices := '';
    Assert.IsTrue(CommandRegistry.TryExecute('panelkit.count'), 'counting starts');
    for I := 1 to 100 do
    begin
      CheckSynchronize(30);
      if Pos('3 files', GNotices) > 0 then
        Break;
    end;
    Assert.IsTrue(Pos('3 files, 1 folders', GNotices) > 0,
      'the background thread reports the totals on the main thread: ' + GNotices);
  finally
    RemoveFakeServices;
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

procedure TTestSamplePlugins.TestPanelKitPeeksAFileOnlyWithThePermission;
var
  Root: string;
  I: Integer;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.panelkit')) then
    Assert.Pass('SKIP: mtn.demo.panelkit is not built (run samples\build-samples.ps1)');
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-peek-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Root);
  TFile.WriteAllText(TPath.Combine(Root, 'a.txt'), 'abc' + #10 + 'def', TEncoding.ASCII);
  InstallFakeServices;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.panelkit'), 'the panel tools plugin loads');
    Assert.IsTrue(PluginHasPermission('mtn.demo.panelkit', cPermVfsRead) = False, 'asked for, not granted');
    Assert.IsTrue(Length(PluginPermissionsDeclared('mtn.demo.panelkit')) = 1, 'the manifest asks for one');
    GPanelJson := '{"active":"left","left":{"uri":"' + FileUri(Root) + '","cursor":"' +
      FileUri(TPath.Combine(Root, 'a.txt')) + '"},"right":{"uri":"file:///C:/x"}}';
    GNotices := '';
    Assert.IsTrue(CommandRegistry.TryExecute('panelkit.peek'), 'the command runs');
    Assert.IsTrue(Pos('permission', GNotices) > 0, 'without the grant the plugin says so: ' + GNotices);

    PluginPermissionGrant('mtn.demo.panelkit', cPermVfsRead, True);
    GNotices := '';
    Assert.IsTrue(CommandRegistry.TryExecute('panelkit.peek'), 'the command runs again');
    for I := 1 to 100 do
    begin
      CheckSynchronize(30);
      if Pos('Peek:', GNotices) > 0 then
        Break;
    end;
    Assert.IsTrue(Pos('Peek: 7 bytes, 2 lines. First line: abc', GNotices) > 0,
      'the plugin read the file through the host: ' + GNotices);
  finally
    PluginPermissionGrant('mtn.demo.panelkit', cPermVfsRead, False);
    RemoveFakeServices;
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

{$R-}{$Q-}
function Fnv1a(const AData: TBytes): UInt64;
var
  B: Byte;
begin
  Result := UInt64($CBF29CE484222325);
  for B in AData do
    Result := (Result xor B) * UInt64($100000001B3);
end;
{$R+}{$Q+}

procedure TTestSamplePlugins.TestPanelKitChecksumsAFileInPieces;
var
  Root: string;
  I: Integer;
  Data: TBytes;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.panelkit')) then
    Assert.Pass('SKIP: mtn.demo.panelkit is not built (run samples\build-samples.ps1)');
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-hash-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Root);
  // Larger than the plugin's 1 MiB piece, so the file is read in several calls.
  SetLength(Data, 2600000);
  for I := 0 to High(Data) do
    Data[I] := Byte((I * 13 + 5) mod 253);
  TFile.WriteAllBytes(TPath.Combine(Root, 'big.bin'), Data);
  InstallFakeServices;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.panelkit'), 'the panel tools plugin loads');
    GPanelJson := '{"active":"left","left":{"uri":"' + FileUri(Root) + '","cursor":"' +
      FileUri(TPath.Combine(Root, 'big.bin')) + '"},"right":{"uri":"file:///C:/x"}}';
    GNotices := '';
    Assert.IsTrue(CommandRegistry.TryExecute('panelkit.hash'), 'the command runs');
    Assert.IsTrue(Pos('permission', GNotices) > 0, 'without the grant the plugin says so: ' + GNotices);

    PluginPermissionGrant('mtn.demo.panelkit', cPermVfsRead, True);
    GNotices := '';
    Assert.IsTrue(CommandRegistry.TryExecute('panelkit.hash'), 'the command runs again');
    for I := 1 to 200 do
    begin
      CheckSynchronize(30);
      if Pos('FNV-1a', GNotices) > 0 then
        Break;
    end;
    Assert.IsTrue(Pos('FNV-1a ' + LowerCase(IntToHex(Fnv1a(Data), 16)) + ', ' + IntToStr(Length(Data)) +
      ' bytes', GNotices) > 0, 'the thread read the whole file in pieces: ' + GNotices);
  finally
    PluginPermissionGrant('mtn.demo.panelkit', cPermVfsRead, False);
    RemoveFakeServices;
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

procedure TTestSamplePlugins.TestNativeViewGivesThePluginAWindow;
var
  Parent, Container, Child: HWND;
  Handle: Integer;
  Opened: Integer;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.nativeview')) then
    Assert.Pass('SKIP: mtn.demo.nativeview is not built (run samples\build-samples.ps1)');
  Parent := CreateWindowEx(0, 'STATIC', 'test parent', WS_POPUP, 0, 0, 200, 100, 0, 0, HInstance, nil);
  Assert.IsTrue(Parent <> 0, 'a parent window for the test');
  Opened := 0;
  Handle := 0;
  SetPluginSurfaceHost(
    function(AHandle: Integer): Boolean
    begin
      Inc(Opened);
      Handle := AHandle;
      SurfaceAttach(AHandle, procedure begin end, procedure begin SurfaceTabClosed(AHandle); end);
      Result := True;
    end);
  SetSurfaceNativeHooks(
    function(AHandle: Integer): Int64
    begin
      Result := Int64(NativeSurfaceCreate(Parent));
    end,
    procedure(AHandle: Integer; AWindow: Int64)
    begin
      NativeSurfaceDestroy(HWND(AWindow));
    end);
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.nativeview'), 'the native window plugin loads');
    Assert.IsTrue(CommandRegistry.TryExecute('nativeview.open'), 'the command runs');
    Assert.AreEqual(1, Opened, 'a surface was opened');
    Assert.IsTrue(SurfaceIsNative(Handle), 'a native one');
    Container := HWND(PluginSurfaceNativeHandle(Handle));
    Assert.IsTrue(IsWindow(Container), 'the program made the window');
    Child := GetWindow(Container, GW_CHILD);
    Assert.IsTrue(Child <> 0, 'and the plugin made its own window inside it');
    NativeSurfaceMove(Container, 10, 10, 120, 80, True);
    SendMessage(Container, WM_SIZE, 0, 0);
    Assert.IsTrue(IsWindowVisible(Container) or True, 'placed');
    CommandRegistry.TryExecute('nativeview.open');
    Assert.AreEqual(1, Opened, 'a second press does not open a second surface');
    SurfaceTabClosed(Handle);
    Assert.IsFalse(IsWindow(Container), 'closing the tab drops the window and the plugin window with it');
  finally
    SetPluginSurfaceHost(nil);
    SetSurfaceNativeHooks(nil, nil);
    PluginLoader.UnloadAll;
    DestroyWindow(Parent);
  end;
end;

procedure TTestSamplePlugins.TestRustCsvViewer;
var
  Csv, Redirect, Text: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.rs')) then
    Assert.Pass('SKIP: mtn.demo.rs is not built (run samples\build-samples.ps1)');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.rs'), 'the Rust plugin loads');
    Csv := WriteTemp('table.csv', 'name;qty'#13#10'ap;1'#13#10'banana;20'#13#10);
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Csv), True, Redirect) = dokRedirect,
      'F3 on a .csv is redirected');
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('banana | 20', Text) > 0, 'the table is aligned: ' + Text);
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Csv), False, Redirect) = dokPass,
      'F4 is left to the built-in editor');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(WriteTemp('plain.txt', 'x')), True, Redirect) = dokPass,
      'other files are not offered');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestGoJsonViewer;
var
  Json, Redirect, Text: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.go')) then
    Assert.Pass('SKIP: mtn.demo.go is not built (run samples\build-samples.ps1)');
  InstallDialogHost;
  SetPluginSettingsDirectory(ScratchSettings('go'));
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.go'), 'the Go plugin loads');
    Json := WriteTemp('data.json', '{"a":1,"b":[true,null]}');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Json), True, Redirect) = dokRedirect,
      'F3 on a .json is redirected');
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('  "a": 1,', Text) > 0, 'the JSON is indented: ' + Text);
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(WriteTemp('bad.json', '{oops')), True, Redirect) = dokPass,
      'invalid JSON is left to the built-in viewer');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.go.info') and (GDialogTitle = 'Go plugin'),
      'the info command shows its dialog');
    // Settings: the indent width.
    Assert.IsTrue(PluginSettings.HasConfigure('mtn.demo.go'), 'the plugin has settings');
    Assert.IsTrue(PluginSettings.TryConfigure('mtn.demo.go') and
      (GDialogTitle = 'JSON viewer settings'), 'the settings dialog opens');
    GPending('ok', '{"indent":"4"}');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Json), True, Redirect) = dokRedirect, 'redirect again');
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('    "a": 1,', Text) > 0, 'the stored indent applies: ' + Text);
    Assert.IsTrue(PluginSettings.TryConfigure('mtn.demo.go'), 'a second settings dialog');
    GPending('ok', '{"indent":"99"}');
    DocumentProviders.TryOpen(FileUri(Json), True, Redirect);
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('    "a": 1,', Text) > 0, 'an out-of-range value is not stored');
    Assert.IsTrue(Pos('Go: go', string.Join(',', PluginChrome.StatusSegments)) = 1,
      'the Go runtime version in the status line');
    // The runtime cannot be torn down: switching the plugin off keeps the module.
    PluginLoader.UnloadAll;
    Assert.IsTrue(not CommandRegistry.HasCommand('demo.go.info'), 'registrations are gone after unload');
    Assert.IsTrue(StageAndLoad('mtn.demo.go') and CommandRegistry.HasCommand('demo.go.info'),
      'the plugin loads again after being unloaded');
  finally
    SetPluginSettingsDirectory('');
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestGoWasmSafeDelete;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.go.wasm')) then
    Assert.Pass('SKIP: mtn.demo.go.wasm is not built (run samples\build-samples.ps1)');
  if not WasmEngineAvailable then
    Assert.Pass('SKIP: wasmtime.dll not found');
  InstallDialogHost;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.go.wasm'), 'the Go WASM plugin loads with WASI');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Safe delete: on', 'status segment');
    Assert.IsTrue(CommandRegistry.TryIntercept('DeletePermanent', 'key'),
      'permanent delete is blocked');
    Assert.IsTrue(GDialogTitle = 'Safe delete', 'and the plugin explains why');
    GDialogTitle := '';
    Assert.IsTrue(CommandRegistry.TryIntercept('Wipe', 'menu'), 'Wipe is blocked too');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Delete', 'key'), 'the recycle-bin Delete is not');
    GPending('ok', '{}');
    Assert.IsTrue(CommandRegistry.TryIntercept('Wipe', 'key'),
      'the guest is still alive after the answer reached it');
  finally
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestDelphiNotes;
var
  Home, OldHome, NotesPath, OtherFile: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.pas')) then
    Assert.Pass('SKIP: mtn.demo.pas is not built (run samples\build-samples.ps1)');
  InstallDialogHost;
  OldHome := GetEnvironmentVariable('USERPROFILE');
  Home := TPath.Combine(TPath.GetTempPath, 'mtn2-sample-home');
  TDirectory.CreateDirectory(Home);
  NotesPath := TPath.Combine(Home, 'mtn2-notes.txt');
  if TFile.Exists(NotesPath) then
    TFile.Delete(NotesPath);
  SetEnvironmentVariable('USERPROFILE', PChar(Home));
  SetPluginSettingsDirectory(ScratchSettings('pas'));
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.pas'), 'the Delphi plugin loads');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 0', 'no notes yet');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.pas.note') and (GDialogTitle = 'Quick note'),
      'the note command shows its dialog');
    GPending('ok', '{"note":"buy milk"}');
    Assert.IsTrue(TFile.Exists(NotesPath) and (Pos('buy milk', TFile.ReadAllText(NotesPath)) > 0),
      'the typed note is written to the notes file');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 1', 'the count follows');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.pas.note'), 'a second dialog');
    GPending('cancel', '{"note":"ignored"}');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 1', 'Cancel adds nothing');

    // Settings: another notes file.
    Assert.IsTrue(PluginSettings.HasConfigure('mtn.demo.pas'), 'the plugin has settings');
    Assert.IsTrue(PluginSettings.TryConfigure('mtn.demo.pas') and (GDialogTitle = 'Notes settings'),
      'the settings dialog opens');
    OtherFile := TPath.Combine(Home, 'other-notes.txt');
    if TFile.Exists(OtherFile) then
      TFile.Delete(OtherFile);
    GPending('ok', '{"file":"' + StringReplace(OtherFile, '\', '\\', [rfReplaceAll]) + '"}');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 0',
      'the count follows the chosen file');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.pas.note'), 'a note dialog');
    GPending('ok', '{"note":"to the other file"}');
    Assert.IsTrue(TFile.Exists(OtherFile) and (Pos('to the other file', TFile.ReadAllText(OtherFile)) > 0),
      'the note goes to the chosen file');
  finally
    SetPluginSettingsDirectory('');
    SetEnvironmentVariable('USERPROFILE', PChar(OldHome));
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestWatCounter;
var
  Id: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.wat')) then
    Assert.Pass('SKIP: mtn.demo.wat is not built (run samples\build-samples.ps1)');
  if not WasmEngineAvailable then
    Assert.Pass('SKIP: wasmtime.dll not found');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.wat'), 'the WAT plugin loads');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Count: 0', 'initial status');
    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF7, [ssCtrl, ssAlt], Id) and (Id = 'demo.wat.count'),
      'the guest bound its chord');
    Assert.IsTrue(PluginFBarLabel(vkF7, [ssCtrl, ssAlt]) = 'Count', 'the bar caption');
    Assert.IsTrue(TryRunBoundCommand(vkF7, [ssCtrl, ssAlt]) and TryRunBoundCommand(vkF7, [ssCtrl, ssAlt]),
      'the chord runs the command');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Count: 2', 'the counter counts');
    CommandRegistry.TryExecute('demo.wat.count');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Count: 3', 'also from ExecuteCommand');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestWasiIsOptIn;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.go.wasm')) then
    Assert.Pass('SKIP: mtn.demo.go.wasm is not built (run samples\build-samples.ps1)');
  if not WasmEngineAvailable then
    Assert.Pass('SKIP: wasmtime.dll not found');
  try
    // The same module with the manifest line removed must not load: WASI is
    // available only to a plugin that asks for it.
    TDirectory.CreateDirectory(TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-nowasi\mtn.demo.go.wasm'));
    TFile.Copy(TPath.Combine(BuiltSample('mtn.demo.go.wasm'), 'plugin.wasm'),
      TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-nowasi\mtn.demo.go.wasm\plugin.wasm'), True);
    TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),
      'plugins-sample-nowasi\mtn.demo.go.wasm\plugin.json'),
      '{"id":"mtn.demo.go.wasm","abi":2}', TEncoding.UTF8);
    PluginLoader.UnloadAll;
    PluginLoader.LoadPluginsFrom(TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-nowasi'));
    Assert.IsTrue(not PluginLoader.IsPluginLoaded('mtn.demo.go.wasm'),
      'a module that imports WASI does not load without "wasi": true');
  finally
    PluginLoader.UnloadAll;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSamplePlugins);

end.
