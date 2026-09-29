unit TestFolderTree;

{ Folder tree (Alt+F10) on an in-memory folder layout:
  - the tree opens at the drive root with the path to the panel's folder
    open and the cursor on it, drawn with box-drawing lines ("[+]" /
    "[-]" mark a closed / open branch);
  - Right / Left open, enter, close and leave branches; the cursor keeps
    its folder when rows appear or go above it; a letter jumps;
  - the controller lists in the background: the tree shows once built, a
    branch opens when its listing lands, and a listing that lands after
    the tree closed is dropped;
  - one tree per window, closed when the panel under it goes elsewhere; a
    click outside it is not the tree's; a click on a folder shows it in the
    other panel at once and gives that panel the focus, a click on "[+]" /
    "[-]" opens / closes the branch and keeps the focus;
  - the tree follows the other panel: a folder there on the same drive
    opens its path and gets the cursor, keeping open branches; another
    drive rebuilds the tree; an unchanged other panel is not followed
    again. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFolderTree = class
  public
    [Test] procedure TestOpenAt;
    [Test] procedure TestLines;
    [Test] procedure TestStepInOut;
    [Test] procedure TestJumpToLetter;
    [Test] procedure TestControllerBackground;
    [Test] procedure TestControllerOwner;
    [Test] procedure TestSyncWithOtherPanel;
    [Test] procedure TestMouse;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections,
  uThemeTypes, uDualPanelTypes, uVfsTypes, uDualPanelFolderTree;

//   C:\
//   +- Apps        (Tools, Games)
//   |    Tools     (Bin)
//   +- Users       (me)
//   Windows        (no subfolders)
function FakeList(const APath: string): TArray<TFolderEntry>;

  function E(const AName: string; ASub: Boolean): TFolderEntry;
  begin
    Result.Name := AName;
    Result.HasSubfolders := ASub;
  end;

var
  P: string;
begin
  P := ExcludeTrailingPathDelimiter(APath);
  if SameText(P, 'C:') then
    Result := [E('Apps', True), E('Users', True), E('Windows', False)]
  else if SameText(P, 'C:\Apps') then
    Result := [E('Games', False), E('Tools', True)]
  else if SameText(P, 'C:\Apps\Tools') then
    Result := [E('Bin', False)]
  else if SameText(P, 'C:\Users') then
    Result := [E('me', False)]
  else
    Result := nil;
end;

function Names(ATree: TFolderTree): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to ATree.Count - 1 do
    Result := Result + ATree.Node(I).Name + ';';
end;

procedure TTestFolderTree.TestOpenAt;
var
  Tree: TFolderTree;
begin
  Tree := TFolderTree.Create(FakeList);
  try
    Tree.OpenAt('C:\Apps\Tools');
    Assert.AreEqual('C:\;Apps;Games;Tools;Bin;Users;Windows;', Names(Tree),
      'root, the path open, siblings closed');
    Assert.AreEqual('C:\Apps\Tools', Tree.CursorPath, 'cursor on the panel folder');
    Tree.OpenAt('C:\Apps\Missing\Deep');
    Assert.AreEqual('C:\Apps', Tree.CursorPath, 'cursor on the deepest folder that exists');
    Tree.OpenAt('C:\');
    Assert.AreEqual('C:\;Apps;Users;Windows;', Names(Tree), 'root only open');
    Assert.AreEqual(0, Tree.Cursor, 'cursor on the root');
  finally
    Tree.Free;
  end;
end;

procedure TTestFolderTree.TestLines;
var
  Tree: TFolderTree;
begin
  Tree := TFolderTree.Create(FakeList);
  try
    Tree.OpenAt('C:\Apps\Tools');
    Assert.AreEqual('', Tree.LinePrefix(0), 'root');
    Assert.AreEqual(#$251C'[-]'#$2500' ', Tree.LinePrefix(1), 'Apps: open, siblings below');
    Assert.AreEqual(#$2502'   '#$251C#$2500#$2500' ', Tree.LinePrefix(2), 'Games: no subfolders');
    Assert.AreEqual(#$2502'   '#$2514'[-]'#$2500' ', Tree.LinePrefix(3), 'Tools: open, last in Apps');
    Assert.AreEqual(#$2502'       '#$2514#$2500#$2500' ', Tree.LinePrefix(4), 'Bin: under a last sibling');
    Assert.AreEqual(#$251C'[+]'#$2500' ', Tree.LinePrefix(5), 'Users: closed, has subfolders');
    Assert.AreEqual(#$2514#$2500#$2500' ', Tree.LinePrefix(6), 'Windows: last, no subfolders');
  finally
    Tree.Free;
  end;
end;

procedure TTestFolderTree.TestStepInOut;
var
  Tree: TFolderTree;
begin
  Tree := TFolderTree.Create(FakeList);
  try
    Tree.OpenAt('C:\Apps\Tools\Bin');
    Assert.AreEqual('C:\Apps\Tools\Bin', Tree.CursorPath);
    Tree.StepOut;
    Assert.AreEqual('C:\Apps\Tools', Tree.CursorPath, 'Left on a leaf: to the parent');
    Tree.StepOut;
    Assert.AreEqual('C:\;Apps;Games;Tools;Users;Windows;', Names(Tree), 'Left closes an open branch');
    Assert.AreEqual('C:\Apps\Tools', Tree.CursorPath, 'cursor stays on it');

    Tree.Cursor := Tree.IndexOfPath('C:\Users');
    Tree.Collapse(Tree.IndexOfPath('C:\Apps'));
    Assert.AreEqual('C:\Users', Tree.CursorPath, 'rows gone above: the cursor keeps its folder');
    Assert.IsTrue(Tree.ExpandWith(Tree.IndexOfPath('C:\Apps'), FakeList('C:\Apps')),
      'opened with a listing');
    Assert.AreEqual('C:\Users', Tree.CursorPath, 'rows added above: the cursor keeps its folder');

    Tree.Cursor := Tree.IndexOfPath('C:\Apps\Tools');
    Tree.Collapse(Tree.IndexOfPath('C:\Apps'));
    Assert.AreEqual('C:\Apps', Tree.CursorPath, 'closing the branch it was in: cursor on the branch');
    Assert.IsFalse(Tree.Expand(Tree.IndexOfPath('C:\Windows')), 'nothing to open');
  finally
    Tree.Free;
  end;
end;

procedure TTestFolderTree.TestJumpToLetter;
var
  Tree: TFolderTree;
begin
  Tree := TFolderTree.Create(FakeList);
  try
    Tree.OpenAt('C:\');
    Assert.IsTrue(Tree.JumpToLetter('w'), 'w');
    Assert.AreEqual('C:\Windows', Tree.CursorPath);
    Assert.IsTrue(Tree.JumpToLetter('A'), 'wraps');
    Assert.AreEqual('C:\Apps', Tree.CursorPath);
    Assert.IsFalse(Tree.JumpToLetter('z'), 'no such folder');
    Assert.AreEqual('C:\Apps', Tree.CursorPath, 'cursor stays');
  finally
    Tree.Free;
  end;
end;

procedure WaitIdle(ACtl: TFolderTreeController);
var
  I: Integer;
begin
  for I := 1 to 200 do
  begin
    CheckSynchronize(10);
    if not ACtl.Loading then
      Break;
  end;
  // A branch listing lands through the same queue.
  for I := 1 to 20 do
    CheckSynchronize(10);
end;

procedure TTestFolderTree.TestControllerBackground;
var
  Ctl: TFolderTreeController;
  PanelUri: string;
  Navigated: string;
  Key: Word;
  Ch: Char;
begin
  PanelUri := PathToFileUri('C:\Apps');
  Navigated := '';
  Ctl := TFolderTreeController.Create(nil, nil,
    function(ASide: TPanelSide): TRectI
    begin
      Result := TRectI.Make(0, 2, 39, 25);
    end,
    function(ASide: TPanelSide): string
    begin
      Result := PanelUri;
    end,
    procedure(ASide: TPanelSide; const AURI: string)
    begin
      Navigated := AURI;
    end,
    FakeList);
  try
    Ctl.Open(psLeft);
    Assert.IsTrue(Ctl.Visible and Ctl.Loading, 'shows at once, builds in the background');
    WaitIdle(Ctl);
    Assert.IsFalse(Ctl.Loading, 'built');
    Assert.AreEqual('C:\Apps', Ctl.Tree.CursorPath, 'on the panel folder');

    Key := vkDown;
    Ch := #0;
    Ctl.HandleInput(Key, [], Ch);
    Key := vkDown;
    Ctl.HandleInput(Key, [], Ch);
    Assert.AreEqual('C:\Apps\Tools', Ctl.Tree.CursorPath);
    Key := vkRight;
    Ctl.HandleInput(Key, [], Ch);
    WaitIdle(Ctl);
    Assert.AreEqual('C:\;Apps;Games;Tools;Bin;Users;Windows;', Names(Ctl.Tree),
      'Right opens the branch when its listing lands');

    Key := vkDown;
    Ctl.HandleInput(Key, [], Ch);
    Key := vkDown;
    Ctl.HandleInput(Key, [], Ch);
    Assert.AreEqual('C:\Users', Ctl.Tree.CursorPath);
    Key := vkRight;
    Ctl.HandleInput(Key, [], Ch);
    Key := vkEscape;
    Ctl.HandleInput(Key, [], Ch);
    Assert.IsFalse(Ctl.Visible, 'Esc closes');
    WaitIdle(Ctl);
    Assert.IsTrue(Ctl.Tree.IndexOfPath('C:\Users\me') < 0,
      'a listing that lands after the tree closed is dropped');

    Ctl.Open(psLeft);
    WaitIdle(Ctl);
    Key := vkReturn;
    Ctl.HandleInput(Key, [], Ch);
    Assert.IsFalse(Ctl.Visible, 'Enter closes');
    Assert.AreEqual(PathToFileUri('C:\Apps'), Navigated, 'and opens the folder');
  finally
    Ctl.Free;
  end;
end;

procedure TTestFolderTree.TestControllerOwner;
var
  Ctl: TFolderTreeController;
  PanelUri: string;
begin
  PanelUri := PathToFileUri('C:\Users');
  Ctl := TFolderTreeController.Create(nil, nil,
    function(ASide: TPanelSide): TRectI
    begin
      Result := TRectI.Make(0, 2, 39, 25);
    end,
    function(ASide: TPanelSide): string
    begin
      Result := PanelUri;
    end,
    nil, FakeList);
  try
    Ctl.Open(psRight);
    Assert.IsTrue(Ctl.Visible and (Ctl.Side = psRight), 'open over the right panel');
    WaitIdle(Ctl);
    Assert.IsTrue(Ctl.HandleClick(60, 10) = ftcOutside, 'a click outside goes to the panels');
    Assert.IsTrue(Ctl.Visible, 'and leaves the tree open');
    Assert.IsTrue(Ctl.HandleClick(0, 5) = ftcFocusTree, 'the frame: focus to the tree');
    Ctl.Toggle(psLeft);
    Assert.IsFalse(Ctl.Visible, 'the other panel''s Alt+F10 closes it, never a second tree');
    Ctl.Open(psRight);
    WaitIdle(Ctl);
    PanelUri := PathToFileUri('D:\Work');
    Ctl.CheckOwner;
    Assert.IsFalse(Ctl.Visible, 'the panel under it went elsewhere: closed');
    Ctl.Open(psRight);
    WaitIdle(Ctl);
    Ctl.SwapSide;
    Assert.IsTrue(Ctl.Visible and (Ctl.Side = psLeft), 'Ctrl+U: the tree moves with its panel');
    Ctl.CheckOwner;
    Assert.IsTrue(Ctl.Visible, 'the panel under it still shows the same folder');
    Ctl.Close;
    PanelUri := 'sftp://host/home';
    Ctl.Open(psRight);
    Assert.IsFalse(Ctl.Visible, 'no tree for a folder that is not on a local disk');
  finally
    Ctl.Free;
  end;
end;

procedure TTestFolderTree.TestSyncWithOtherPanel;
var
  Ctl: TFolderTreeController;
  Uris: array[TPanelSide] of string;
  Key: Word;
  Ch: Char;
begin
  Uris[psLeft] := PathToFileUri('C:\Apps');
  Uris[psRight] := PathToFileUri('C:\');
  Ctl := TFolderTreeController.Create(nil, nil,
    function(ASide: TPanelSide): TRectI
    begin
      Result := TRectI.Make(0, 2, 39, 25);
    end,
    function(ASide: TPanelSide): string
    begin
      Result := Uris[ASide];
    end,
    procedure(ASide: TPanelSide; const AURI: string)
    begin
      Uris[ASide] := AURI;
    end,
    FakeList);
  try
    Ctl.Open(psLeft);
    WaitIdle(Ctl);
    Ctl.SyncWithOther;
    Assert.AreEqual('C:\Apps', Ctl.Tree.CursorPath, 'the other panel as it was at opening: no move');

    Uris[psRight] := PathToFileUri('C:\Users\me');
    Ctl.SyncWithOther;
    WaitIdle(Ctl);
    Assert.AreEqual('C:\Users\me', Ctl.Tree.CursorPath, 'follows the other panel');
    Assert.IsTrue(Ctl.Tree.IndexOfPath('C:\Apps\Tools') >= 0, 'open branches stay open');

    // The cursor moved in the tree while the other panel stays: no pull back.
    Key := vkUp;
    Ch := #0;
    Ctl.HandleInput(Key, [], Ch);
    Ctl.SyncWithOther;
    WaitIdle(Ctl);
    Assert.AreEqual('C:\Users', Ctl.Tree.CursorPath, 'an unchanged other panel is not followed again');

    Uris[psRight] := PathToFileUri('D:\Work');
    Ctl.SyncWithOther;
    WaitIdle(Ctl);
    Assert.AreEqual('D:\', Ctl.Tree.Node(0).Path, 'another drive: its tree');
  finally
    Ctl.Free;
  end;
end;

procedure TTestFolderTree.TestMouse;
var
  Ctl: TFolderTreeController;
  Uris: array[TPanelSide] of string;
  Row, Idx: Integer;
begin
  Uris[psLeft] := PathToFileUri('C:\');
  Uris[psRight] := PathToFileUri('D:\Other');
  Ctl := TFolderTreeController.Create(nil, nil,
    function(ASide: TPanelSide): TRectI
    begin
      Result := TRectI.Make(0, 2, 39, 7);
    end,
    function(ASide: TPanelSide): string
    begin
      Result := Uris[ASide];
    end,
    procedure(ASide: TPanelSide; const AURI: string)
    begin
      Uris[ASide] := AURI;
    end,
    FakeList);
  try
    Ctl.Open(psLeft);
    WaitIdle(Ctl);
    // Three list rows (3..5) under the frame top: C:\, Apps, Users.
    Idx := Ctl.Tree.IndexOfPath('C:\Users');
    Row := 3 + Idx;
    Assert.IsTrue(Ctl.HandleClick(10, Row) = ftcFocusFiles, 'a folder name: focus to the files');
    Assert.AreEqual(PathToFileUri('C:\Users'), Uris[psRight], 'shown in the other panel at once');
    Assert.AreEqual('C:\Users', Ctl.Tree.CursorPath, 'cursor on it');

    // "[+]" of Apps takes columns 2..4 (text starts at column 1 after "├").
    Idx := Ctl.Tree.IndexOfPath('C:\Apps');
    Assert.IsTrue(Ctl.HandleClick(3, 3 + Idx) = ftcKeep, '"[+]": the focus stays');
    WaitIdle(Ctl);
    Assert.IsTrue(Ctl.Tree.Node(Idx).Expanded, 'the branch opens');
    Assert.AreEqual('C:\Users', Ctl.Tree.CursorPath, 'the cursor does not move');
    Assert.AreEqual(PathToFileUri('C:\Users'), Uris[psRight], 'the other panel stays');
    Assert.IsTrue(Ctl.HandleClick(4, 3 + Idx) = ftcKeep, '"[-]": the focus stays');
    Assert.IsFalse(Ctl.Tree.Node(Idx).Expanded, 'the branch closes');

    // The wheel scrolls the rows: the first row moves, the cursor does not.
    Ctl.HandleClick(3, 3 + Idx);
    WaitIdle(Ctl);
    Assert.IsTrue(Ctl.HandleClick(10, 3) = ftcFocusFiles, 'cursor on the root');
    Ctl.ScrollBy(3);
    Assert.IsTrue(Ctl.HandleClick(10, 3) = ftcFocusFiles, 'the top row after the wheel');
    Assert.AreEqual(Ctl.Tree.Node(3).Path, Ctl.Tree.CursorPath,
      'the top row is the fourth one: the rows moved by three');
    Ctl.ScrollBy(-3);
    Ctl.Tree.Cursor := 0;
    Ctl.ScrollBy(2);
    Assert.AreEqual(0, Ctl.Tree.Cursor, 'the wheel leaves the cursor where it is');
  finally
    Ctl.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFolderTree);

end.
