unit TestPanelUriLabels;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelUriLabels = class
  public
    [Test] procedure TestCollectDescribeItemNames;
    [Test] procedure TestCollectClipboardItemTexts;
    [Test] procedure TestDriveCaption;
  end;

implementation

uses
  System.SysUtils,
  uDualPanelTypes, uPanelUriLabels, uDriveInfo, uDriveTypes;

procedure TTestPanelUriLabels.TestCollectDescribeItemNames;
var
  Tab: TTab;
  Rows: TPanelRows;
  Names: TArray<string>;
begin
  Tab := MakeTab(1, 't', 'file:///C:/Work');
  SetLength(Rows, 3);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///C:/', True);
  Rows[1] := MakePanelRow('a.txt', False, 1, '1', '', 'file:///C:/Work/a.txt');
  Rows[2] := MakePanelRow('b.txt', False, 1, '1', '', 'file:///C:/Work/b.txt');

  Tab.CursorIndex := 0;
  Names := CollectDescribeItemNames(Tab, Rows);
  Assert.IsTrue(Length(Names) = 0, 'parent cursor yields nothing');

  Tab.CursorIndex := 1;
  Names := CollectDescribeItemNames(Tab, Rows);
  Assert.IsTrue(Length(Names) = 1, 'cursor file');
  Assert.AreEqual('a.txt', Names[0], 'cursor name');

  TabSetSelected(Tab, Rows[1].URI, True);
  TabSetSelected(Tab, Rows[2].URI, True);
  Names := CollectDescribeItemNames(Tab, Rows);
  Assert.IsTrue(Length(Names) = 2, 'selection collects both');
  Assert.AreEqual('a.txt', Names[0], 'selection order follows rows');
  Assert.AreEqual('b.txt', Names[1], 'second selected');
end;

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

initialization
  TDUnitX.RegisterTestFixture(TTestPanelUriLabels);

end.
