unit TestFunctionBarHints;

{ F-bar hints of the output search in the console and the terminal, and of the
  bookmark commands of the viewer and the editor. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFunctionBarHints = class
  public
    [Test] procedure TestConsoleShowsTheSearchKeys;
    [Test] procedure TestTerminalShowsTheSearchKeys;
    [Test] procedure TestEditorAndViewerShowTheBookmarkKeys;
    [Test] procedure TestWidePanelsBarNamesThePaletteKey;
    [Test] procedure TestNarrowPanelsBarKeepsOnlyTheFKeys;
    [Test] procedure TestFindResultsBarOmitsCreateAndRename;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, uFunctionBar;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join('|', AItems);
end;

procedure TTestFunctionBarHints.TestConsoleShowsTheSearchKeys;
var
  Items, Letters: TArray<string>;
begin
  FunctionBarGetItems(fbcConsole, [], Items, Letters);
  Assert.AreEqual('3Next', Items[2], 'F3 is the next match');
  FunctionBarGetItems(fbcConsole, [ssShift], Items, Letters);
  Assert.AreEqual('3Prev', Items[2], 'Shift+F3 is the previous match');
  FunctionBarGetItems(fbcConsole, [ssCtrl, ssShift], Items, Letters);
  Assert.IsTrue(Joined(Letters).Contains('F:Find'), 'Ctrl+Shift+F is Find: ' + Joined(Letters));
end;

procedure TTestFunctionBarHints.TestTerminalShowsTheSearchKeys;
var
  Items, Letters: TArray<string>;
begin
  FunctionBarGetItems(fbcTerminal, [], Items, Letters);
  Assert.AreEqual('3Next', Items[2]);
  FunctionBarGetItems(fbcTerminal, [ssCtrl, ssShift], Items, Letters);
  Assert.IsTrue(Joined(Letters).Contains('F:Find'), Joined(Letters));
end;

procedure TTestFunctionBarHints.TestEditorAndViewerShowTheBookmarkKeys;
var
  Items, Letters: TArray<string>;
begin
  FunctionBarGetItems(fbcEditor, [ssCtrl], Items, Letters);
  Assert.AreEqual('2Mark', Items[1], 'Ctrl+F2 sets a bookmark');
  FunctionBarGetItems(fbcEditor, [ssCtrl, ssShift], Items, Letters);
  Assert.AreEqual('2MarkNx', Items[1], 'Ctrl+Shift+F2 goes to the next one');
  FunctionBarGetItems(fbcViewer, [ssCtrl, ssAlt], Items, Letters);
  Assert.AreEqual('2MarkPv', Items[1], 'Ctrl+Alt+F2 goes to the previous one');
end;

procedure TTestFunctionBarHints.TestWidePanelsBarNamesThePaletteKey;
var
  Items, Letters: TArray<string>;
  Hit: TFunctionBarHit;
  Key: Word;
  KeyChar: Char;
  Shift: TShiftState;
begin
  FunctionBarGetItems(fbcPanels, [], Items, Letters, '', 120);
  Assert.IsTrue(Joined(Letters).Contains('Shift+F9:Palette'), Joined(Letters));
  // A click on the hint presses the key it names.
  Hit := FunctionBarHitTest(2, 120, Items, Letters, [], False);
  Assert.AreEqual(Ord(fbhHint), Ord(Hit.Kind));
  Assert.IsTrue(FunctionBarHitToInput(Hit, [], Key, KeyChar, Shift));
  Assert.AreEqual(Integer(vkF9), Integer(Key));
  Assert.IsTrue(ssShift in Shift, 'the hint carries Shift');
end;

procedure TTestFunctionBarHints.TestNarrowPanelsBarKeepsOnlyTheFKeys;
var
  Items, Letters: TArray<string>;
begin
  FunctionBarGetItems(fbcPanels, [], Items, Letters, '', 80);
  Assert.IsTrue(Length(Letters) = 0, 'no room for a hint at 80 columns');
  FunctionBarGetItems(fbcPanels, [], Items, Letters);
  Assert.IsTrue(Length(Letters) = 0, 'unknown width adds nothing');
end;

procedure TTestFunctionBarHints.TestFindResultsBarOmitsCreateAndRename;
var
  Plain, Found: TArray<string>;
  Letters: TArray<string>;
begin
  FunctionBarGetItems(fbcPanels, [], Plain, Letters, '', 80);
  FunctionBarGetItems(fbcFindResults, [], Found, Letters, '', 80);
  Assert.AreEqual('7MkDir', Plain[6], 'a folder bar offers MkDir on F7');
  Assert.AreEqual('7', Found[6], 'found items cannot get a folder created');
  Assert.AreEqual(Plain[4], Found[4], 'Copy stays');
  Assert.AreEqual(Plain[7], Found[7], 'Delete stays');
  Assert.AreEqual(Plain[2], Found[2], 'View stays');
  FunctionBarGetItems(fbcFindResults, [ssShift], Found, Letters, '', 80);
  Assert.AreEqual('4', Found[3], 'Shift+F4 (new file) is not offered');
  Assert.AreEqual('5', Found[4], 'Shift+F5 (copy in place) is not offered');
  Assert.AreEqual('6', Found[5], 'Shift+F6 (rename) is not offered');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFunctionBarHints);

end.
