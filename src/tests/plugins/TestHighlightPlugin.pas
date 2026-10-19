unit TestHighlightPlugin;

{ The syntax highlighting plugin (syntect in WASM) through the real host: languages by file
  name, colors, and the state that carries a block comment over the lines. Passes as skipped
  when wasmtime.dll or plugin.wasm is missing. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHighlightPlugin = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestLanguagesAreFoundByFileName;
    [Test] procedure TestBlockCommentCarriesOverTheLines;
    [Test] procedure TestEditedLineRecolorsTheLinesBelow;
    [Test] procedure TestWholeFileIsColoredQuickly;
    [Test] procedure TestUnloadedPluginColorsNothing;
  end;

implementation

uses
  uTestPaths,
  System.SysUtils, System.IOUtils, System.Diagnostics,
  uWasmtimeApi, uPluginManifest, uPluginLoader, uPluginHighlight;

var
  GLoaded: Boolean;
  GSkipReason: string;

procedure LoadPlugin;
var
  Src, Wasm, Dest, Root: string;
  Loaded, Failed: Integer;
begin
  GLoaded := False;
  Src := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    NativePath('../../plugins/mtn.highlight')));
  Wasm := TPath.Combine(Src, 'plugin.wasm');
  if FindWasmtimeDll = '' then
  begin
    GSkipReason := 'wasmtime.dll not found';
    Exit;
  end;
  if not TFile.Exists(Wasm) then
  begin
    GSkipReason := 'plugin.wasm missing (cargo build --target wasm32-unknown-unknown --release)';
    Exit;
  end;
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-hl-test');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Dest := TPath.Combine(Root, 'mtn.highlight');
  TDirectory.CreateDirectory(Dest);
  TFile.Copy(Wasm, TPath.Combine(Dest, 'plugin.wasm'), True);
  TFile.Copy(TPath.Combine(Src, 'plugin.json'), TPath.Combine(Dest, 'plugin.json'), True);
  Loaded := 0;
  Failed := 0;
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      if AResult = plrLoaded then
        Inc(Loaded)
      else if AResult <> plrSkippedHelperDll then
        Inc(Failed);
    end;
  PluginLoader.LoadPluginsFrom(Root);
  GLoaded := (Loaded >= 1) and (Failed = 0);
  if not GLoaded then
    GSkipReason := '';
end;

{ TTestHighlightPlugin }

procedure TTestHighlightPlugin.Setup;
begin
  if not GLoaded then
    LoadPlugin;
  if GSkipReason <> '' then
    Assert.Pass('SKIP: ' + GSkipReason);
  Assert.IsTrue(GLoaded, 'the highlighting plugin loads');
end;

procedure TTestHighlightPlugin.TearDown;
begin
end;

procedure TTestHighlightPlugin.TestLanguagesAreFoundByFileName;
begin
  Assert.IsTrue(HighlighterForFile('D:\src\main.rs') <> 0, 'Rust');
  Assert.IsTrue(HighlighterForFile('unit1.pas') <> 0, 'Pascal');
  Assert.IsTrue(HighlighterForFile('C:\w\Makefile') <> 0, 'a whole file name');
  Assert.IsTrue(HighlighterIsStateful(HighlighterForFile('a.py')), 'a language keeps its state');
  Assert.AreEqual<Integer>(0, HighlighterForFile('notes.txt'), 'plain text stays plain');
  Assert.AreEqual<Integer>(0, HighlighterForFile('archive.zip'), 'an unknown extension');
end;

procedure TTestHighlightPlugin.TestBlockCommentCarriesOverTheLines;
var
  Id, State1, State2, State3, PlainState: Integer;
  Spans: THighlightSpans;
  Span: THighlightSpan;
  HasCode: Boolean;
  PlainSpans: THighlightSpans;
begin
  Id := HighlighterForFile('x.rs');
  Assert.IsTrue(HighlightLineState(Id, 'let a = 1; /* start', 0, Spans, State1), 'first line');
  Assert.IsTrue(State1 > 0, 'the open comment is a state of its own');
  Assert.IsTrue(HighlightLineState(Id, 'still comment', State1, Spans, State2), 'inside the comment');
  Assert.AreEqual<Integer>(1, Length(Spans), 'one span');
  Assert.AreEqual<Integer>(cHighlightComment, Spans[0].Kind, 'the whole line is a comment');
  Assert.AreEqual<Integer>(0, Spans[0].Start);
  Assert.AreEqual<Integer>(Length('still comment'), Spans[0].Len);
  Assert.AreEqual<Integer>(State1, State2, 'the same state while the comment goes on');
  Assert.IsTrue(HighlightLineState(Id, 'end */ let b = 2;', State2, Spans, State3), 'comment ends');
  HighlightLineState(Id, 'let q = 1;', 0, PlainSpans, PlainState);
  Assert.AreEqual<Integer>(PlainState, State3, 'back at the state of plain code');
  Assert.AreEqual<Integer>(cHighlightComment, Spans[0].Kind, 'the end of the comment');
  Assert.AreEqual<Integer>(0, Spans[0].Start);
  HasCode := False;
  for Span in Spans do
    if (Span.Kind <> cHighlightComment) and (Span.Start >= 6) then
      HasCode := True;
  Assert.IsTrue(HasCode, 'code after the comment is colored again');
end;

procedure TTestHighlightPlugin.TestEditedLineRecolorsTheLinesBelow;
var
  Lines: TArray<string>;
  Tracker: THighlightTracker;
  Spans: THighlightSpans;
  Id, StateOut, PlainState: Integer;
  Get: TFunc<Integer, string>;
begin
  Id := HighlighterForFile('x.rs');
  Lines := ['/* open', 'inside', 'let x = 1;'];
  Get := function(AIndex: Integer): string
    begin
      Result := Lines[AIndex];
    end;
  Tracker := THighlightTracker.Create(Id);
  try
    Assert.IsTrue(Tracker.Reach(2, Get, 1000), 'states known');
    Assert.IsTrue(Tracker.StateAt(2) > 0, 'the third line is inside the comment');
    HighlightLineState(Id, Lines[2], Tracker.StateAt(2), Spans, StateOut);
    Assert.AreEqual<Integer>(cHighlightComment, Spans[0].Kind, 'colored as comment');

    Lines[0] := 'let y = 0;';
    Lines[1] := 'let z = 1;';
    Tracker.InvalidateFrom(0);
    Assert.IsTrue(Tracker.Reach(2, Get, 1000), 'states known again');
    HighlightLineState(Id, 'let y = 0;', 0, Spans, PlainState);
    Assert.AreEqual<Integer>(PlainState, Tracker.StateAt(2), 'no comment is open any more');
    HighlightLineState(Id, Lines[2], Tracker.StateAt(2), Spans, StateOut);
    Assert.IsTrue((Length(Spans) > 0) and (Spans[0].Kind <> cHighlightComment), 'colored as code');
  finally
    Tracker.Free;
  end;
end;

procedure TTestHighlightPlugin.TestWholeFileIsColoredQuickly;
var
  Lines: TArray<string>;
  Tracker: THighlightTracker;
  Get: TFunc<Integer, string>;
  Watch: TStopwatch;
begin
  // A real source file of the project: Pascal, several thousand lines.
  Lines := TFile.ReadAllLines(ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    NativePath('../../Core/uDialogHost.pas'))));
  Assert.IsTrue(Length(Lines) > 3000, 'the sample is long enough');
  Get := function(AIndex: Integer): string
    begin
      Result := Lines[AIndex];
    end;
  Tracker := THighlightTracker.Create(HighlighterForFile('uDialogHost.pas'));
  try
    Watch := TStopwatch.StartNew;
    Assert.IsTrue(Tracker.Reach(High(Lines), Get, 60000), 'every line has its state');
    Assert.IsTrue(Watch.ElapsedMilliseconds < 20000,
      Format('%d lines in %d ms', [Length(Lines), Watch.ElapsedMilliseconds]));
  finally
    Tracker.Free;
  end;
end;

procedure TTestHighlightPlugin.TestUnloadedPluginColorsNothing;
begin
  PluginLoader.UnloadAll;
  Assert.AreEqual<Integer>(0, HighlighterForFile('x.rs'), 'unloading drops the languages');
  GLoaded := False;
  GSkipReason := '';
end;

end.
