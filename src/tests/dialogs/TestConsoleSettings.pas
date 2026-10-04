unit TestConsoleSettings;

{ Console options: scrollback choices, multi-line detection, trimming of
  trailing spaces, and the Options > Console dialog. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleSettings = class
  public
    [Test] procedure TestScrollbackChoices;
    [Test] procedure TestLineCounting;
    [Test] procedure TestTrimTrailingSpaces;
    [Test] procedure TestLineBreaksToEnter;
    [Test] procedure TestBackgroundShowChoices;
    [Test] procedure TestConsoleOptionsDialog;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uStrings,
  uConsoleSettings, uDialogTypes, uDialogHost, uThemeRegistry;

procedure TTestConsoleSettings.TestScrollbackChoices;
begin
  Assert.AreEqual(cDefaultScrollbackLines, DefaultConsoleSettings.ScrollbackLines, 'default size');
  Assert.IsFalse(DefaultConsoleSettings.ConfirmMultiLinePaste, 'no paste prompt by default');
  Assert.IsFalse(DefaultConsoleSettings.TrimCopiedSpaces, 'no trimming on copy by default');
  Assert.IsFalse(DefaultConsoleSettings.TrimPastedSpaces, 'no trimming on paste by default');
  Assert.IsFalse(DefaultConsoleSettings.ReturnToPanels, 'the console stays in front by default');
  Assert.AreEqual(1000, ClampScrollbackLines(1), 'below the list goes to the first size');
  Assert.AreEqual(5000, ClampScrollbackLines(7000), 'the nearest size');
  Assert.AreEqual(10000, ClampScrollbackLines(10000), 'a listed size stays');
  Assert.AreEqual(50000, ClampScrollbackLines(1000000), 'above the list goes to the last size');
  Assert.AreEqual(2, ScrollbackIndexOf(10000), 'index of the default');
  Assert.AreEqual(25000, ScrollbackAt(3), 'size at an index');
  Assert.AreEqual(1000, ScrollbackAt(-5), 'index below the list');
  Assert.AreEqual(50000, ScrollbackAt(99), 'index above the list');
  Assert.AreEqual(Integer(Length(cScrollbackChoices)), Integer(Length(ScrollbackItems)), 'one item per size');
end;

procedure TTestConsoleSettings.TestLineCounting;
begin
  Assert.AreEqual(0, CountTextLines(''), 'empty text');
  Assert.AreEqual(0, CountTextLines(#10#13#10), 'only line breaks');
  Assert.AreEqual(1, CountTextLines('ls'), 'one line');
  Assert.AreEqual(1, CountTextLines('ls'#10), 'a trailing line break is not a line');
  Assert.AreEqual(2, CountTextLines('a'#10'b'), 'two lines');
  Assert.AreEqual(2, CountTextLines('a'#13#10'b'#13#10), 'CRLF lines');
  Assert.AreEqual(3, CountTextLines('a'#13'b'#13'c'), 'CR-only lines');
  Assert.IsFalse(IsMultiLineText('dir'#13#10), 'one command with Enter is not multi-line');
  Assert.IsTrue(IsMultiLineText('cd /'#10'ls'), 'two commands are multi-line');
end;

procedure TTestConsoleSettings.TestTrimTrailingSpaces;
begin
  Assert.AreEqual('', TrimTrailingSpaces(''), 'empty');
  Assert.AreEqual('a', TrimTrailingSpaces('a   '), 'spaces at the end');
  Assert.AreEqual('a'#10'b', TrimTrailingSpaces('a  '#10'b '), 'every line');
  Assert.AreEqual('a'#13#10'b', TrimTrailingSpaces('a '#13#10'b'), 'CRLF kept');
  Assert.AreEqual('  lead', TrimTrailingSpaces('  lead'), 'leading spaces stay');
  Assert.AreEqual('x'#10, TrimTrailingSpaces('x'#9' '#10), 'tabs go too, the break stays');
  Assert.AreEqual('a b', TrimTrailingSpaces('a b'), 'inner spaces stay');
  Assert.AreEqual(#10#10, TrimTrailingSpaces('  '#10' '#10), 'blank lines stay blank');
end;

procedure TTestConsoleSettings.TestBackgroundShowChoices;
var
  Items: TArray<string>;
begin
  SetLocale('');
  Assert.AreEqual(cDefaultBackgroundShowMs, DefaultConsoleSettings.BackgroundShowMs, 'default time');
  Assert.AreEqual(500, ClampBackgroundShowMs(1), 'below the list goes to the first time');
  Assert.AreEqual(2000, ClampBackgroundShowMs(2200), 'the nearest time');
  Assert.AreEqual(10000, ClampBackgroundShowMs(99999), 'above the list goes to the last time');
  Assert.AreEqual(2, BackgroundShowIndexOf(2000), 'index of a listed time');
  Assert.AreEqual(3000, BackgroundShowAt(3), 'time at an index');
  Assert.AreEqual(10000, BackgroundShowAt(99), 'index above the list');
  Items := BackgroundShowItems;
  Assert.AreEqual(Integer(Length(cBackgroundShowChoices)), Integer(Length(Items)), 'one item per time');
  Assert.AreEqual('0.5 s', Items[0], 'half a second');
  Assert.AreEqual('2 s', Items[2], 'whole seconds without a fraction');
end;

procedure TTestConsoleSettings.TestLineBreaksToEnter;
begin
  Assert.AreEqual('', LineBreaksToEnter(''), 'empty');
  Assert.AreEqual('ls', LineBreaksToEnter('ls'), 'no break');
  Assert.AreEqual('a'#13'b'#13, LineBreaksToEnter('a'#10'b'#10), 'LF becomes Enter');
  Assert.AreEqual('a'#13'b'#13, LineBreaksToEnter('a'#13#10'b'#13#10), 'CRLF is one Enter');
  Assert.AreEqual('a'#13'b', LineBreaksToEnter('a'#13'b'), 'CR stays');
  Assert.AreEqual(#13#13, LineBreaksToEnter(#10#10), 'blank lines stay');
end;

procedure TTestConsoleSettings.TestConsoleOptionsDialog;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  Text: string;
  X, Y: Integer;
begin
  SetLocale('');
  Host := TDialogHost.Create(CreateThemeByName('NDN'));
  try
    Host.Open(BuildConsoleOptionsDialog(3, True, False, True, True, 4), nil);
    AllocTerminalGrid(Grid, 100, 30);
    ClearTerminalGrid(Grid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
    Host.Draw(Grid, 100, 30);
    Text := '';
    for Y := 0 to High(Grid) do
    begin
      for X := 0 to High(Grid[Y]) do
        Text := Text + Grid[Y][X].CharValue;
      Text := Text + #10;
    end;
    Assert.IsTrue(Pos('Scrollback', Text) > 0, 'scrollback label drawn');
    Assert.IsTrue(Pos('25000 lines', Text) > 0, 'saved size shown');
    Assert.IsTrue(Pos('Confirm multi-line paste', Text) > 0, 'paste confirmation drawn');
    Assert.IsTrue(Pos('on copy', Text) > 0, 'copy trimming drawn');
    Assert.IsTrue(Pos('on paste', Text) > 0, 'paste trimming drawn');
    Assert.IsTrue(Pos('return to the panels', Text) > 0, 'return to the panels drawn');
    Assert.IsTrue(Pos('Background run:', Text) > 0, 'background time label drawn');
    Assert.IsTrue(Pos('5 s', Text) > 0, 'saved time shown');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleSettings);

end.
