unit TestPanelUriLabels;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelUriLabels = class
  public
    [Test] procedure TestCollectClipboardItemTexts;
    [Test] procedure TestDriveCaption;
    [Test] procedure TestQuickDirectoryTarget;
  end;

implementation

uses
  System.SysUtils,
  uDualPanelTypes, uPanelUriLabels, uDriveInfo, uDriveTypes;

procedure TTestPanelUriLabels.TestCollectClipboardItemTexts;
var
  Tab: TTab;
  Rows: TPanelRows;
  Texts: TArray<string>;
begin
  Tab := MakeTab(1, 't', 'file:///C:/Work');
  SetLength(Rows, 3);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///C:/', True);
  Rows[1] := MakePanelRow('a.txt', False, 1, '1', '', 'file:///C:/Work/a.txt');
  Rows[2] := MakePanelRow('b.txt', False, 1, '1', '', 'file:///C:/Work/b.txt');

  Tab.CursorIndex := 1;
  Texts := CollectClipboardItemTexts(Tab, Rows, False);
  Assert.IsTrue(Length(Texts) = 1, 'cursor path');
  Assert.IsTrue(Pos('a.txt', Texts[0]) > 0, 'full path keeps the name');

  Texts := CollectClipboardItemTexts(Tab, Rows, True);
  Assert.IsTrue(Length(Texts) = 1, 'cursor name');
  Assert.AreEqual('a.txt', Texts[0], 'name only');

  TabSetSelected(Tab, Rows[1].URI, True);
  TabSetSelected(Tab, Rows[2].URI, True);
  Texts := CollectClipboardItemTexts(Tab, Rows, True);
  Assert.IsTrue(Length(Texts) = 2, 'selection names');
  Assert.AreEqual('a.txt', Texts[0], 'first selected');
  Assert.AreEqual('b.txt', Texts[1], 'second selected');
end;

procedure TTestPanelUriLabels.TestDriveCaption;
var
  Info: TDriveInfo;
begin
  Info := Default(TDriveInfo);
  Info.RootPath := 'D:\';
  Info.LabelOrPath := 'D:\';
  Assert.AreEqual('D:\', DriveCaption(Info), 'same label keeps root only');
  Info.LabelOrPath := 'Data';
  Assert.AreEqual('D:\ (Data)', DriveCaption(Info), 'label is appended');
end;

procedure TTestPanelUriLabels.TestQuickDirectoryTarget;
var
  Parent, Folder, FileRow: TPanelRow;
begin
  Parent := MakePanelRow('..', True, -1, '', '', 'file:///C:/', True);
  Folder := MakePanelRow('Sub', True, -1, '', '', 'file:///C:/Work/Sub');
  FileRow := MakePanelRow('a.txt', False, 1, '1', '', 'file:///C:/Work/a.txt');
  Assert.AreEqual('file:///C:/Work/Sub',
    QuickDirectoryTarget(True, Folder, 'file:///C:/Work'), 'a folder row shows itself');
  Assert.AreEqual('file:///C:/Work',
    QuickDirectoryTarget(True, Parent, 'file:///C:/Work'), '".." shows the panel folder');
  Assert.AreEqual('', QuickDirectoryTarget(True, FileRow, 'file:///C:/Work'), 'a file has no map');
  Assert.AreEqual('', QuickDirectoryTarget(False, Parent, 'file:///C:/Work'), 'no row, no map');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelUriLabels);

end.
