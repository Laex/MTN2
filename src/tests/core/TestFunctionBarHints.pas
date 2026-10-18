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
  end;

implementation

uses
  System.SysUtils, System.Classes, uFunctionBar;

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

initialization
  TDUnitX.RegisterTestFixture(TTestFunctionBarHints);

end.
