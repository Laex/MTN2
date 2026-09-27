unit TestMarkdownLinks;

{ Markdown Viewer links (F3 on .md): which targets count as external,
  Tab / Shift+Tab walk the links, Enter on a local link does nothing, Enter
  on an external one asks before opening it and Esc leaves it unopened (the
  test never answers OK -- that would start the browser); the image Overlay
  steps aside while the question is up. Temp files only.
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
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uNDNTheme, uEditorWindow;

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
  View := TEditorWindow.Create(TNDNTheme.Create, 1);
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

initialization
  TDUnitX.RegisterTestFixture(TTestMarkdownLinks);

end.
