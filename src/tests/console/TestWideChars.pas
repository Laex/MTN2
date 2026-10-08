unit TestWideChars;

{ Wide (two-cell) characters in the terminal grids and the console buffer:
  a wide character takes a head cell and a filler cell, wraps as a unit and
  never leaves an orphaned half behind. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWideChars = class
  public
    [Test] procedure TestDrawGridCharFillsTwoCells;
    [Test] procedure TestDrawGridCharInLastColumnBlanks;
    [Test] procedure TestOverwriteHeadBlanksFiller;
    [Test] procedure TestOverwriteFillerBlanksHead;
    [Test] procedure TestWideOverWideLeavesNoOrphan;
    [Test] procedure TestPutGridTextAdvancesByWidth;
    [Test] procedure TestPutGridTextClippedKeepsWideCharacterWhole;
    [Test] procedure TestPrimaryGridAdvancesTwoColumns;
    [Test] procedure TestPrimaryGridWrapsWideCharacter;
    [Test] procedure TestPrimaryGridDeleteBeforeCursorRemovesBothHalves;
    [Test] procedure TestAltGridAdvancesAndWraps;
    [Test] procedure TestConsoleBufferKeepsColumnsAligned;
    [Test] procedure TestConsoleBufferLegacyLineKeepsColumnsAligned;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uPrimaryScreenGrid, uAltScreenGrid, uConsoleBuffer, uCharWidth;

const
  Fg: TAlphaColor = $FFE0E0E0;
  Bg: TAlphaColor = $FF000000;
  cHan = #$6F22;
  cHira = #$3072;

function MakeGrid(ACols: Integer): TTerminalGrid;
begin
  AllocTerminalGrid(Result, ACols, 1);
  ClearTerminalGrid(Result, Fg, Bg);
end;

procedure TTestWideChars.TestDrawGridCharFillsTwoCells;
var
  G: TTerminalGrid;
begin
  G := MakeGrid(6);
  DrawGridChar(G, 1, 0, cHan, Fg, Bg);
  Assert.IsTrue(ccaWide in G[0][1].Attributes, 'head flag');
  Assert.AreEqual(cHan, G[0][1].CharValue);
  Assert.IsTrue(ccaWideTail in G[0][2].Attributes, 'filler flag');
  Assert.AreEqual(' ', G[0][2].CharValue);
  Assert.IsFalse(ccaWide in G[0][2].Attributes);
  Assert.IsFalse(ccaWideTail in G[0][1].Attributes);
  Assert.IsTrue(G[0][2].FgColor = Fg, 'filler keeps the colours');
  Assert.IsTrue(G[0][0].Attributes = [], 'left neighbour untouched');
  Assert.IsTrue(G[0][3].Attributes = [], 'right neighbour untouched');
end;

procedure TTestWideChars.TestDrawGridCharInLastColumnBlanks;
var
  G: TTerminalGrid;
begin
  G := MakeGrid(4);
  DrawGridChar(G, 3, 0, cHan, Fg, Bg);
  Assert.AreEqual(' ', G[0][3].CharValue, 'half a character is never drawn');
  Assert.IsTrue(G[0][3].Attributes = []);
end;

procedure TTestWideChars.TestOverwriteHeadBlanksFiller;
var
  G: TTerminalGrid;
begin
  G := MakeGrid(6);
  DrawGridChar(G, 1, 0, cHan, Fg, Bg);
  DrawGridChar(G, 1, 0, 'x', Fg, Bg);
  Assert.AreEqual('x', G[0][1].CharValue);
  Assert.IsTrue(G[0][2].Attributes = [], 'filler cleared');
  Assert.AreEqual(' ', G[0][2].CharValue);
end;

procedure TTestWideChars.TestOverwriteFillerBlanksHead;
var
  G: TTerminalGrid;
begin
  G := MakeGrid(6);
  DrawGridChar(G, 1, 0, cHan, Fg, Bg);
  DrawGridChar(G, 2, 0, 'x', Fg, Bg);
  Assert.AreEqual(' ', G[0][1].CharValue, 'head blanked');
  Assert.IsTrue(G[0][1].Attributes = []);
  Assert.AreEqual('x', G[0][2].CharValue);
end;

procedure TTestWideChars.TestWideOverWideLeavesNoOrphan;
var
  G: TTerminalGrid;
begin
  G := MakeGrid(6);
  DrawGridChar(G, 0, 0, cHan, Fg, Bg);
  DrawGridChar(G, 2, 0, cHan, Fg, Bg);
  // Shifted by one column: covers the filler of the first and the head of the second.
  DrawGridChar(G, 1, 0, cHira, Fg, Bg);
  Assert.AreEqual(' ', G[0][0].CharValue, 'first character lost its filler');
  Assert.IsTrue(G[0][0].Attributes = []);
  Assert.IsTrue(ccaWide in G[0][1].Attributes);
  Assert.IsTrue(ccaWideTail in G[0][2].Attributes);
  Assert.IsFalse(ccaWideTail in G[0][3].Attributes, 'no orphaned filler');
  Assert.AreEqual(' ', G[0][3].CharValue);
end;

procedure TTestWideChars.TestPutGridTextAdvancesByWidth;
var
  G: TTerminalGrid;
begin
  G := MakeGrid(8);
  PutGridText(G, 1, 0, 'a' + cHan + cHira + 'b', Fg, Bg);
  Assert.AreEqual('a', G[0][1].CharValue);
  Assert.AreEqual(cHan, G[0][2].CharValue);
  Assert.IsTrue(ccaWideTail in G[0][3].Attributes);
  Assert.AreEqual(cHira, G[0][4].CharValue);
  Assert.IsTrue(ccaWideTail in G[0][5].Attributes);
  Assert.AreEqual('b', G[0][6].CharValue);
end;

procedure TTestWideChars.TestPutGridTextClippedKeepsWideCharacterWhole;
var
  G: TTerminalGrid;
begin
  G := MakeGrid(8);
  PutGridTextClipped(G, 0, 0, 2, 'a' + cHan + cHira, Fg, Bg);
  Assert.AreEqual('a', G[0][0].CharValue);
  Assert.AreEqual(cHan, G[0][1].CharValue, 'fits columns 1-2');
  Assert.AreEqual(' ', G[0][3].CharValue, 'next wide character would cross the limit');
  Assert.IsTrue(G[0][3].Attributes = []);
end;

procedure TTestWideChars.TestPrimaryGridAdvancesTwoColumns;
var
  Grid: TPrimaryScreenGrid;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(8, 2, Fg, Bg);
    Grid.PutCell('a', Fg, Bg, []);
    Grid.PutCell(cHan, Fg, Bg, []);
    Grid.PutCell('b', Fg, Bg, []);
    Assert.AreEqual(4, Grid.CursorCol);
    Assert.IsTrue(ccaWide in Grid.Grid[0][1].Attributes);
    Assert.IsTrue(ccaWideTail in Grid.Grid[0][2].Attributes);
    Assert.AreEqual('b', Grid.Grid[0][3].CharValue);
  finally
    Grid.Free;
  end;
end;

procedure TTestWideChars.TestPrimaryGridWrapsWideCharacter;
var
  Grid: TPrimaryScreenGrid;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(5, 3, Fg, Bg);
    Grid.PutCell('a', Fg, Bg, []);
    Grid.PutCell('b', Fg, Bg, []);
    Grid.PutCell('c', Fg, Bg, []);
    Grid.PutCell('d', Fg, Bg, []);
    // One column left, the wide character needs two.
    Grid.PutCell(cHan, Fg, Bg, []);
    Assert.AreEqual(1, Grid.CursorRow);
    Assert.AreEqual(2, Grid.CursorCol);
    Assert.AreEqual(' ', Grid.Grid[0][4].CharValue, 'last column left blank');
    Assert.AreEqual(cHan, Grid.Grid[1][0].CharValue);
    Assert.IsTrue(ccaWideTail in Grid.Grid[1][1].Attributes);
    // Two more wide characters: the second ends at the edge only after a
    // blank is left, so the cursor ends up on the following row.
    Grid.PutCell(cHira, Fg, Bg, []);
    Assert.AreEqual(4, Grid.CursorCol);
    Grid.PutCell(cHira, Fg, Bg, []);
    Assert.AreEqual(2, Grid.CursorRow, 'wrapped to the next row');
    Assert.AreEqual(2, Grid.CursorCol);
  finally
    Grid.Free;
  end;
end;

procedure TTestWideChars.TestPrimaryGridDeleteBeforeCursorRemovesBothHalves;
var
  Grid: TPrimaryScreenGrid;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(8, 1, Fg, Bg);
    Grid.PutCell('a', Fg, Bg, []);
    Grid.PutCell(cHan, Fg, Bg, []);
    Assert.IsTrue(Grid.DeleteCharBeforeCursor(0, Fg, Bg));
    Assert.AreEqual(1, Grid.CursorCol);
    Assert.AreEqual('a', Grid.Grid[0][0].CharValue);
    Assert.AreEqual(' ', Grid.Grid[0][1].CharValue);
    Assert.IsTrue(Grid.Grid[0][1].Attributes = []);
    Assert.IsTrue(Grid.Grid[0][2].Attributes = []);
  finally
    Grid.Free;
  end;
end;

procedure TTestWideChars.TestAltGridAdvancesAndWraps;
var
  Grid: TAltScreenGrid;
begin
  Grid := TAltScreenGrid.Create;
  try
    Grid.Alloc(4, 3);
    Grid.ClearAll(Fg, Bg);
    Grid.PutCell('a', Fg, Bg, []);
    Grid.PutCell(cHan, Fg, Bg, []);
    Assert.AreEqual(3, Grid.CursorCol);
    Assert.IsTrue(ccaWideTail in Grid.Grid[0][2].Attributes);
    // Column 3 is the last one: the next wide character moves to the next row.
    Grid.PutCell(cHira, Fg, Bg, []);
    Assert.AreEqual(1, Grid.CursorRow);
    Assert.AreEqual(2, Grid.CursorCol);
    Assert.AreEqual(cHira, Grid.Grid[1][0].CharValue);
    Assert.AreEqual(' ', Grid.Grid[0][3].CharValue);
  finally
    Grid.Free;
  end;
end;

procedure TTestWideChars.TestConsoleBufferKeepsColumnsAligned;
var
  Buf: TConsoleBuffer;
  Line: string;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('A' + cHan + cHira + 'B', 80, 1);
    Line := Buf.GetLine(Buf.LineCount - 1);
    // One character per cell: each wide character is followed by its filler.
    Assert.AreEqual(6, Length(Line));
    Assert.AreEqual('B', string(Line[6]));
    Assert.AreEqual('A' + cHan + cHira + 'B', StripWideFillers(Line));
  finally
    Buf.Free;
  end;
end;

procedure TTestWideChars.TestConsoleBufferLegacyLineKeepsColumnsAligned;
var
  Buf: TConsoleBuffer;
  Line: string;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('A' + cHan + 'B');
    Line := Buf.GetLine(Buf.LineCount - 1);
    Assert.AreEqual(4, Length(Line));
    Assert.AreEqual('A' + cHan + 'B', StripWideFillers(Line));
  finally
    Buf.Free;
  end;
end;

end.
