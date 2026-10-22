unit TestLinuxSamplePlugins;

{ The demo plugins of samples/plugins built for Linux (samples/build-samples.sh
  into samples/.build-linux) loaded through the real loader: what they register
  and what they do with a file. A sample that is not built is skipped. The
  Windows counterpart is TestSamplePlugins. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLinuxSamplePlugins = class
  public
    [Test] procedure CppPluginRegistersItsCommand;
    [Test] procedure TextToolsRegisterTheirCommands;
    [Test] procedure RustCsvViewerAlignsTheTable;
    [Test] procedure GoJsonViewerIndentsTheText;
    [Test] procedure PictureViewerFillsASurface;
    [Test] procedure RustPluginsLoad;
    [Test] procedure WasmPluginsRun;
  end;

implementation

uses
  uTestPaths,
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uCommandRegistry, uDocumentProviders, uPluginChrome, uDialogTypes, uPluginLoader,
  uPluginSurface, uWasmPluginHost, uVfsTypes, uPlatformPaths;

function BuiltSample(const AId: string): string;
begin
  Result := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    NativePath('../../../samples/.build-linux/') + AId));
end;

procedure RequireBuilt(const AId: string);
begin
  if not PlatformPosixPaths then
    Assert.Pass('SKIP: the samples of this fixture are Linux libraries');
  if not TDirectory.Exists(BuiltSample(AId)) then
    Assert.Pass('SKIP: ' + AId + ' is not built (run samples/build-samples.sh)');
end;

// The plugin folder is copied beside the test program, as the program's own plugins folder holds it.
function StageAndLoad(const AId: string): Boolean;
var
  Root, Target, F: string;
begin
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-' + AId);
  if TDirectory.Exists(Root) then
    try
      TDirectory.Delete(Root, True);
    except
      // A module that cannot be unloaded (Go) keeps its folder busy.
    end;
  Target := TPath.Combine(Root, AId);
  TDirectory.CreateDirectory(Target);
  for F in TDirectory.GetFiles(BuiltSample(AId)) do
    try
      TFile.Copy(F, TPath.Combine(Target, ExtractFileName(F)), True);
    except
      // Already in place and mapped by a previous test.
    end;
  PluginLoader.UnloadAll;
  PluginLoader.LoadPluginsFrom(Root);
  Result := PluginLoader.IsPluginLoaded(AId);
end;

function WriteTemp(const AName, AText: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-linux-sample-' + AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

procedure TTestLinuxSamplePlugins.CppPluginRegistersItsCommand;
begin
  RequireBuilt('mtn.demo.cpp');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.cpp'), 'the C++ plugin loads');
    Assert.IsTrue(CommandRegistry.HasCommand('demo.cpp.stats'), 'the stats command is registered');
    Assert.IsFalse(CommandRegistry.TryIntercept('Copy', 'key'),
      'the hook only observes: the built-in Copy still runs');
    Assert.AreEqual('Ops: 1', string.Join(',', PluginChrome.StatusSegments), 'the status segment counts');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestLinuxSamplePlugins.TextToolsRegisterTheirCommands;
var
  Id: string;
begin
  RequireBuilt('mtn.demo.texttools');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.texttools'), 'the text tools load');
    for Id in ['texttools.upper', 'texttools.lower', 'texttools.sort', 'texttools.repeats',
               'texttools.tidy'] do
      Assert.IsTrue(CommandRegistry.HasCommand(Id), Id);
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestLinuxSamplePlugins.RustCsvViewerAlignsTheTable;
var
  Csv, Redirect, Text: string;
begin
  RequireBuilt('mtn.demo.rs');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.rs'), 'the Rust plugin loads');
    Csv := WriteTemp('table.csv', 'name;qty'#10'ap;1'#10'banana;20'#10);
    Assert.IsTrue(DocumentProviders.TryOpen(PathToFileUri(Csv), True, Redirect) = dokRedirect,
      'F3 on a .csv is redirected');
    Text := TFile.ReadAllText(FileUriToPath(Redirect), TEncoding.UTF8);
    Assert.IsTrue(Pos('banana | 20', Text) > 0, 'the table is aligned: ' + Text);
    Assert.IsTrue(DocumentProviders.TryOpen(PathToFileUri(Csv), False, Redirect) = dokPass,
      'F4 is left to the built-in editor');
    Assert.IsTrue(DocumentProviders.TryOpen(PathToFileUri(WriteTemp('plain.txt', 'x')), True,
      Redirect) = dokPass, 'other files are not offered');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestLinuxSamplePlugins.GoJsonViewerIndentsTheText;
var
  Json, Redirect, Text: string;
begin
  RequireBuilt('mtn.demo.go');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.go'), 'the Go plugin loads');
    Json := WriteTemp('data.json', '{"a":1,"b":[true,null]}');
    Assert.IsTrue(DocumentProviders.TryOpen(PathToFileUri(Json), True, Redirect) = dokRedirect,
      'F3 on a .json is redirected');
    Text := TFile.ReadAllText(FileUriToPath(Redirect), TEncoding.UTF8);
    Assert.IsTrue(Pos('  "a": 1,', Text) > 0, 'the JSON is indented: ' + Text);
    Assert.IsTrue(DocumentProviders.TryOpen(PathToFileUri(WriteTemp('bad.json', '{oops')), True,
      Redirect) = dokPass, 'invalid JSON is left to the built-in viewer');
    // The Go runtime cannot be torn down: the module stays until the process ends.
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestLinuxSamplePlugins.PictureViewerFillsASurface;
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
begin
  RequireBuilt('mtn.demo.img');
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
    Bmp := TPath.Combine(TPath.GetTempPath, 'mtn2-linux-sample-pixel.bmp');
    Stream := TFileStream.Create(Bmp, fmCreate);
    try
      Stream.WriteBuffer(cBmp, SizeOf(cBmp));
    finally
      Stream.Free;
    end;
    Assert.IsTrue(DocumentProviders.TryOpen(PathToFileUri(Bmp), True, Redirect) = dokHandled,
      'F3 on a picture is handled by the plugin');
    Assert.IsTrue(Handle > 0, 'a surface tab was opened');
    Assert.IsTrue(SurfaceFrame(Handle, W, H, Gen, Pixels), 'the plugin sent the picture');
    Assert.IsTrue(SurfaceDeliverMouse(Handle, 5, 0, 0, 40, 30, 0, 0, 0), 'the plugin takes the size of the area');
    Assert.IsTrue(SurfaceFrame(Handle, W, H, Gen, Pixels) and (W = 40) and (H = 30),
      'the frame is rendered for the area: ' + IntToStr(W) + 'x' + IntToStr(H));
    Center := ((15 * 40) + 20) * 4;
    Assert.IsTrue((Pixels[Center] = $FF) and (Pixels[Center + 1] = $80) and (Pixels[Center + 2] = $40) and
      (Pixels[Center + 3] = $FF), 'the picture is in the middle as B, G, R, A');
    Assert.AreEqual('mtn2-linux-sample-pixel.bmp', SurfaceTitle(Handle), 'the tab is named after the file');
    Assert.IsTrue(DocumentProviders.TryOpen(PathToFileUri(WriteTemp('broken.png', 'not a picture')), True,
      Redirect) = dokPass, 'a file that does not decode is left to the next provider');
    PluginLoader.UnloadAll;
    Assert.IsFalse(SurfaceExists(Handle), 'unloading the plugin closes its tab');
  finally
    SetPluginSurfaceHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestLinuxSamplePlugins.RustPluginsLoad;
var
  Id: string;
begin
  RequireBuilt('mtn.demo.highlight');
  for Id in ['mtn.demo.panelkit', 'mtn.demo.highlight'] do
    if TDirectory.Exists(BuiltSample(Id)) then
      try
        Assert.IsTrue(StageAndLoad(Id), Id + ' loads');
      finally
        PluginLoader.UnloadAll;
      end;
end;

procedure TTestLinuxSamplePlugins.WasmPluginsRun;
var
  Id: string;
begin
  RequireBuilt('mtn.demo.wat');
  if not WasmEngineAvailable then
    Assert.Pass('SKIP: libwasmtime.so not found');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.wat'), 'the WAT plugin loads');
    Assert.AreEqual('Count: 0', string.Join(',', PluginChrome.StatusSegments), 'initial status');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.wat.count'), 'the command runs');
    Assert.AreEqual('Count: 1', string.Join(',', PluginChrome.StatusSegments), 'the counter counts');
    PluginLoader.UnloadAll;
    for Id in ['mtn.demo.wc', 'mtn.demo.go.wasm'] do
      if TDirectory.Exists(BuiltSample(Id)) then
      begin
        Assert.IsTrue(StageAndLoad(Id), Id + ' loads');
        PluginLoader.UnloadAll;
      end;
  finally
    PluginLoader.UnloadAll;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLinuxSamplePlugins);

end.
