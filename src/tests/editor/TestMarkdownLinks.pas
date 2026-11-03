unit TestMarkdownLinks;

{ Markdown Viewer links (F3 on .md): which targets count as external,
  Tab / Shift+Tab walk the links, Enter / click on a local link opens that
  file in the window (Backspace / Alt+Left return), on an external one asks
  before opening it and Esc leaves it unopened (the test never answers OK --
  that would start the browser); the image Overlay steps aside while the
  question is up. Temp files only.
  Build with -U"..\..\Core;..\..\Themes". }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMarkdownLinks = class
  public
    [Test] procedure TestIsExternalLink;
    [Test] procedure TestViewerLinks;
    [Test] procedure TestViewerLinkClicks;
    [Test] procedure TestHelpFollowsLinks;
    [Test] procedure TestViewerFollowsLocalLinks;
    [Test] procedure TestLinksClickableInAnyLayout;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uThemeRegistry, uEditorWindow, uStrings,
  uHelpViewer;

procedure Pump(AMs: Integer = 600);
var
  T: UInt64;
begin
  T := TThread.GetTickCount64 + UInt64(AMs);
  while TThread.GetTickCount64 < T do
  begin
    CheckSynchronize(10);
    Sleep(5);
  end;
end;

procedure Key(AView: TEditorWindow; AKey: Word; AShift: TShiftState = []);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := #0;
  AView.HandleInput(K, AShift, Ch);
end;

{ TTestMarkdownLinks }

procedure TTestMarkdownLinks.TestIsExternalLink;
begin
  Assert.IsTrue(TEditorWindow.IsExternalLink('https://example.com/a?b=1#c'), 'https');
  Assert.IsTrue(TEditorWindow.IsExternalLink('http://example.com'), 'http');
  Assert.IsTrue(TEditorWindow.IsExternalLink('mailto:someone@example.com'), 'mailto');
  Assert.IsTrue(TEditorWindow.IsExternalLink('ftp://host/file'), 'ftp');
  Assert.IsTrue(TEditorWindow.IsExternalLink('git+ssh://host/repo'), 'scheme with "+"');
  Assert.IsFalse(TEditorWindow.IsExternalLink(''), 'empty');
  Assert.IsFalse(TEditorWindow.IsExternalLink('keys.md'), 'topic');
  Assert.IsFalse(TEditorWindow.IsExternalLink('keys.md#top'), 'topic with anchor');
  Assert.IsFalse(TEditorWindow.IsExternalLink('#top'), 'anchor');
  Assert.IsFalse(TEditorWindow.IsExternalLink('C:\docs\a.md'), 'drive path');
  Assert.IsFalse(TEditorWindow.IsExternalLink('docs/a:b.md'), 'colon after a slash');
  Assert.IsFalse(TEditorWindow.IsExternalLink('1http://x'), 'scheme must start with a letter');
end;

procedure TTestMarkdownLinks.TestViewerLinks;
var
  Dir, Md, Target: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Y: Integer;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-mdlinks-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  Md := TPath.Combine(Dir, 'readme.md');
  TFile.WriteAllText(Md, '# Title' + sLineBreak + sLineBreak +
    'See [local](other.md) and [site](https://example.com/page).' + sLineBreak +
    sLineBreak + '![pic](pic.png)' + sLineBreak, TEncoding.UTF8);
  // 1x1 PNG: the image line gets an Overlay block.
  TFile.WriteAllBytes(TPath.Combine(Dir, 'pic.png'), TBytes.Create(
    $89, $50, $4E, $47, $0D, $0A, $1A, $0A, $00, $00, $00, $0D, $49, $48, $44, $52,
    $00, $00, $00, $01, $00, $00, $00, $01, $08, $06, $00, $00, $00, $1F, $15, $C4,
    $89, $00, $00, $00, $0D, $49, $44, $41, $54, $78, $9C, $63, $00, $01, $00, $00,
    $05, $00, $01, $0D, $0A, $2D, $B4, $00, $00, $00, $00, $49, $45, $4E, $44, $AE,
    $42, $60, $82));
  SetLength(Grid, 24);
  for Y := 0 to High(Grid) do
    SetLength(Grid[Y], 80);
  View := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  try
    View.Open(PathToFileUri(Md), True);
    Pump;
    Assert.IsTrue(View.DocReady, 'document loaded');
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(View.MarkdownImageOverlayVisible, 'image Overlay shown');

    Key(View, vkTab);
    Assert.IsTrue(View.LinkAtCursor(Target) and (Target = 'other.md'), 'Tab: first link');
    Key(View, vkReturn);
    Assert.IsFalse(View.DialogOpen, 'Enter on a local link: no question');

    Key(View, vkTab);
    Assert.IsTrue(View.LinkAtCursor(Target) and (Target = 'https://example.com/page'),
      'Tab: second link');
    Key(View, vkTab, [ssShift]);
    Assert.IsTrue(View.LinkAtCursor(Target) and (Target = 'other.md'), 'Shift+Tab: back');
    Key(View, vkTab);

    Key(View, vkReturn);
    Assert.IsTrue(View.DialogOpen, 'Enter on an external link asks first');
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsFalse(View.MarkdownImageOverlayVisible,
      'no image Overlay over the question');
    Key(View, vkTab);
    Assert.IsTrue(View.DialogOpen, 'the question owns the keys');
    Key(View, vkEscape);
    Assert.IsFalse(View.DialogOpen, 'Esc closes the question');
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(View.MarkdownImageOverlayVisible, 'image back after the question');
    Assert.IsTrue(View.LinkAtCursor(Target) and (Target = 'https://example.com/page'),
      'cursor stays on the link');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestMarkdownLinks.TestViewerLinkClicks;

  function FindWord(const AGrid: TTerminalGrid; const AWord: string;
    out AX, AY: Integer): Boolean;
  var
    X, Y, I: Integer;
  begin
    for Y := 0 to High(AGrid) do
      for X := 0 to High(AGrid[Y]) - Length(AWord) do
      begin
        I := 1;
        while (I <= Length(AWord)) and (AGrid[Y][X + I - 1].CharValue = AWord[I]) do
          Inc(I);
        if I > Length(AWord) then
        begin
          AX := X;
          AY := Y;
          Exit(True);
        end;
      end;
    Result := False;
  end;

var
  Dir, Md: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  X, Y: Integer;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-mdclick-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  Md := TPath.Combine(Dir, 'readme.md');
  TFile.WriteAllText(Md, '# Title' + sLineBreak + sLineBreak +
    'See [local](other.md) and [site](https://example.com/page) now.' + sLineBreak,
    TEncoding.UTF8);
  SetLength(Grid, 24);
  for Y := 0 to High(Grid) do
    SetLength(Grid[Y], 80);
  View := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  try
    View.Open(PathToFileUri(Md), True);
    Pump;
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(FindWord(Grid, 'site', X, Y), 'link text is drawn without its brackets');

    // A click on a local link does nothing.
    Assert.IsTrue(FindWord(Grid, 'local', X, Y), 'local link text is drawn');
    View.HandleMouseDown(X + 1, Y, []);
    View.HandleMouseUp;
    Assert.IsFalse(View.DialogOpen, 'click on a local link: no question');

    // A click on an external link asks before opening it.
    FindWord(Grid, 'site', X, Y);
    View.HandleMouseDown(X + 1, Y, []);
    View.HandleMouseUp;
    Assert.IsTrue(View.DialogOpen, 'click on an external link asks first');
    Key(View, vkEscape);
    Assert.IsFalse(View.DialogOpen, 'Esc closes the question');

    // A second quick click on the same cell is not a word selection.
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    View.HandleMouseDown(X + 1, Y, []);
    View.HandleMouseUp;
    Assert.IsTrue(View.DialogOpen, 'first quick click asks');
    Key(View, vkEscape);
    View.HandleMouseDown(X + 1, Y, []);
    View.HandleMouseUp;
    Assert.IsTrue(View.DialogOpen, 'second quick click on the link asks again');
    Key(View, vkEscape);

    // A one-cell jitter between press and release is still a click.
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    View.HandleMouseDown(X + 1, Y, []);
    View.HandleMouseMove(X + 2, Y);
    View.HandleMouseUp;
    Assert.IsTrue(View.DialogOpen, 'press and release one cell apart still asks');
    Key(View, vkEscape);

    // A drag across the link selects text and does not ask.
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    View.HandleMouseDown(X, Y, []);
    View.HandleMouseMove(X + 3, Y);
    View.HandleMouseUp;
    Assert.IsFalse(View.DialogOpen, 'drag selection on a link: no question');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestMarkdownLinks.TestHelpFollowsLinks;

  function GridHas(const AGrid: TTerminalGrid; const AWord: string;
    out AX, AY: Integer): Boolean;
  var
    X, Y, I: Integer;
  begin
    for Y := 0 to High(AGrid) do
      for X := 0 to High(AGrid[Y]) - Length(AWord) do
      begin
        I := 1;
        while (I <= Length(AWord)) and (AGrid[Y][X + I - 1].CharValue = AWord[I]) do
          Inc(I);
        if I > Length(AWord) then
        begin
          AX := X;
          AY := Y;
          Exit(True);
        end;
      end;
    Result := False;
  end;

var
  Root, OldRoot, HelpDir: string;
  Help: THelpViewer;
  Grid: TTerminalGrid;
  X, Y: Integer;
  K: Word;
  Ch: Char;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-helplinks-' + TPath.GetGUIDFileName(False));
  HelpDir := TPath.Combine(TPath.Combine(Root, 'en'), 'help');
  ForceDirectories(HelpDir);
  TFile.WriteAllText(TPath.Combine(HelpDir, 'index.md'),
    '## Start' + sLineBreak + sLineBreak +
    'Go to [second page](second.md) or [third page](third.md#deep).' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(HelpDir, 'second.md'),
    '## Second heading' + sLineBreak + sLineBreak + 'Body.' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(HelpDir, 'third.md'),
    '## Third heading' + sLineBreak + sLineBreak + 'Body.' + sLineBreak,
    TEncoding.UTF8);
  OldRoot := ResourceRoot;
  SetResourceRoot(Root);
  SetLength(Grid, 40);
  for Y := 0 to High(Grid) do
    SetLength(Grid[Y], 100);
  Help := THelpViewer.Create(CreateThemeByName('NDN'));
  try
    Assert.IsTrue(Help.Open('index.md'), 'index opens');
    Pump;
    Help.Paint(Grid, 100, 40, 0, 0);
    Assert.IsTrue(GridHas(Grid, 'second page', X, Y), 'link text is drawn');

    // Mouse: a plain click on the link opens its topic.
    Help.HandleMouseDown(X + 1, Y, []);
    Help.HandleMouseUp;
    Pump;
    Help.Paint(Grid, 100, 40, 0, 0);
    Assert.IsTrue(GridHas(Grid, 'Second heading', X, Y), 'click follows the link');

    // Backspace returns to the previous topic.
    K := vkBack;
    Ch := #0;
    Help.HandleInput(K, [], Ch);
    Pump;
    Help.Paint(Grid, 100, 40, 0, 0);
    Assert.IsTrue(GridHas(Grid, 'second page', X, Y), 'Backspace goes back');

    // Keyboard: the cursor is back on the first link, Tab moves to the second,
    // Enter follows it (the anchor part of the target is accepted).
    K := vkTab;
    Ch := #0;
    Help.HandleInput(K, [], Ch);
    K := vkReturn;
    Ch := #0;
    Help.HandleInput(K, [], Ch);
    Pump;
    Help.Paint(Grid, 100, 40, 0, 0);
    Assert.IsTrue(GridHas(Grid, 'Third heading', X, Y), 'Tab + Enter follows the link');
  finally
    Help.Free;
    SetResourceRoot(OldRoot);
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestMarkdownLinks.TestViewerFollowsLocalLinks;

  function Find(const AGrid: TTerminalGrid; const AWord: string;
    out AX, AY: Integer): Boolean;
  var
    X, Y, I: Integer;
  begin
    for Y := 0 to High(AGrid) do
      for X := 0 to High(AGrid[Y]) - Length(AWord) do
      begin
        I := 1;
        while (I <= Length(AWord)) and (AGrid[Y][X + I - 1].CharValue = AWord[I]) do
          Inc(I);
        if I > Length(AWord) then
        begin
          AX := X;
          AY := Y;
          Exit(True);
        end;
      end;
    Result := False;
  end;

var
  Dir: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  X, Y, Top, Row, Col: Integer;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-mdlocal-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  TFile.WriteAllText(TPath.Combine(Dir, 'readme.md'),
    '# Readme heading' + sLineBreak + sLineBreak +
    'Go to [other page](other.md#deep) or [jump](#tail).' + sLineBreak +
    sLineBreak + '## Tail' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(Dir, 'other.md'),
    '# Other heading' + sLineBreak + sLineBreak + 'Body.' + sLineBreak,
    TEncoding.UTF8);
  SetLength(Grid, 24);
  for Y := 0 to High(Grid) do
    SetLength(Grid[Y], 80);
  View := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  try
    View.Open(PathToFileUri(TPath.Combine(Dir, 'readme.md')), True);
    Pump;
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(Find(Grid, 'other page', X, Y), 'link text is drawn');

    // Mouse: a click on a local link opens that file in the same window.
    View.HandleMouseDown(X + 1, Y, []);
    View.HandleMouseUp;
    Pump;
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(Find(Grid, 'Other heading', X, Y), 'click opens the linked file');

    // Backspace returns to the first document.
    Key(View, vkBack);
    Pump;
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(Find(Grid, 'Readme heading', X, Y), 'Backspace goes back');

    // Keyboard: the cursor is on the first link after Back, so Tab twice
    // wraps around to it again; Enter opens it, Alt+Left returns.
    Key(View, vkTab);
    Key(View, vkTab);
    Key(View, vkReturn);
    Pump;
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(Find(Grid, 'Other heading', X, Y), 'Tab + Enter opens the linked file');
    Key(View, vkLeft, [ssAlt]);
    Pump;
    View.PaintEmbedded(Grid, 0, 0, 80, 24, 0, 0);
    Assert.IsTrue(Find(Grid, 'Readme heading', X, Y), 'Alt+Left goes back');

    // "#anchor" link scrolls inside the same document and Back undoes it.
    Assert.IsTrue(Find(Grid, 'jump', X, Y), 'anchor link text is drawn');
    View.HandleMouseDown(X + 1, Y, []);
    View.HandleMouseUp;
    View.GetViewPos(Top, Row, Col);
    Assert.AreEqual(4, Row, 'the anchor link moves the cursor to its heading');
    Key(View, vkBack);
    View.GetViewPos(Top, Row, Col);
    Assert.AreEqual(2, Row, 'Back returns to the line of the link');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestMarkdownLinks.TestLinksClickableInAnyLayout;
var
  Dir, Md, Src: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  X, Y, I, J: Integer;
  Words: TArray<string>;
  Fails: string;

  function Find(const AWord: string): Boolean;
  var
    XX, YY, K: Integer;
  begin
    for YY := 0 to High(Grid) do
      for XX := 0 to High(Grid[YY]) - Length(AWord) do
      begin
        K := 1;
        while (K <= Length(AWord)) and (Grid[YY][XX + K - 1].CharValue = AWord[K]) do
          Inc(K);
        if K > Length(AWord) then
        begin
          X := XX;
          Y := YY;
          Exit(True);
        end;
      end;
    Result := False;
  end;

begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-mdprobe-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  Md := TPath.Combine(Dir, 'readme.md');
  Src := '# Title' + sLineBreak + sLineBreak +
    'Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua [wrapped](https://a.example/1) tail.' + sLineBreak + sLineBreak +
    '- **Bold** item with [inlist](https://a.example/2) and `code` then [aftercode](https://a.example/3)' + sLineBreak + sLineBreak +
    'Text [one](https://a.example/4)[two](https://a.example/5) end [firstpart secondpart](https://a.example/6) end.' + sLineBreak + sLineBreak +
    '| a | b |' + sLineBreak + '|---|---|' + sLineBreak + '| [intable](https://a.example/7) | x |' + sLineBreak + sLineBreak +
    '## Head [inhead](https://a.example/8)' + sLineBreak;
  TFile.WriteAllText(Md, Src, TEncoding.UTF8);
  SetLength(Grid, 30);
  for Y := 0 to High(Grid) do
    SetLength(Grid[Y], 60);
  Words := TArray<string>.Create('wrapped', 'inlist', 'aftercode', 'one', 'two',
    'firstpart', 'secondpart', 'intable', 'inhead');
  Fails := '';
  View := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  try
    View.Open(PathToFileUri(Md), True);
    Pump;
    View.PaintEmbedded(Grid, 0, 0, 60, 30, 0, 0);
    for I := 0 to High(Words) do
    begin
      View.PaintEmbedded(Grid, 0, 0, 60, 30, 0, 0);
      if not Find(Words[I]) then
      begin
        Fails := Fails + Words[I] + ': not drawn; ';
        Continue;
      end;
      for J := 0 to Length(Words[I]) - 1 do
      begin
        View.HandleMouseDown(X + J, Y, []);
        View.HandleMouseUp;
        if not View.DialogOpen then
          Fails := Fails + Words[I] + '+' + IntToStr(J) + ': no dialog; '
        else
          Key(View, vkEscape);
        Pump(300);
      end;
    end;
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
  Assert.AreEqual('', Fails, 'link clicks');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMarkdownLinks);

end.
