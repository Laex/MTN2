unit TestDualPanelPluginJson;

{ Panel JSON the plugin host reads. The checks call the builder the window uses. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelPluginJson = class
  public
    [Test] procedure SideNumberZeroIsLeft;
    [Test] procedure ParentCursorIsOmittedAndSelectionIsKept;
    [Test] procedure ListSkipsTheParentAndCountsTheCursorAfterIt;
    [Test] procedure ListStopsAfterTheRowCap;
    [Test] procedure ListAddsCellsForTheRowName;
  end;

implementation

uses
  System.SysUtils, System.JSON,
  uDualPanelTypes, uDualPanelPluginJson, uPluginColumns;

function Row(const AName, AUri: string; ADir, AParent: Boolean): TPanelRow;
begin
  Result := MakePanelRow(AName, ADir, 12, '', '', AUri, AParent);
end;

procedure TTestDualPanelPluginJson.SideNumberZeroIsLeft;
begin
  Assert.AreEqual(psLeft, PluginPanelSide(0, psRight));
  Assert.AreEqual(psRight, PluginPanelSide(1, psLeft));
  Assert.AreEqual(psRight, PluginPanelSide(2, psRight));
  Assert.AreEqual(psLeft, PluginPanelSide(-1, psLeft));
end;

procedure TTestDualPanelPluginJson.ParentCursorIsOmittedAndSelectionIsKept;
var
  Left, Right: TPluginPanelSideInfo;
  Json: string;
begin
  Left.Uri := 'file:///C:/a';
  SetLength(Left.Rows, 1);
  Left.Rows[0] := Row('..', 'file:///C:/', True, True);
  Left.CursorIndex := 0;
  SetLength(Left.Selected, 1);
  Left.Selected[0] := 'file:///C:/a/b';
  Right.Uri := 'file:///C:/b';
  SetLength(Right.Rows, 1);
  Right.Rows[0] := Row('d/', 'file:///C:/b/d', True, False);
  Right.CursorIndex := 0;
  Json := BuildPluginPanelInfoJson(True, Left, Right);
  Assert.AreEqual(
    '{"active":"left","left":{"uri":"file:///C:/a","selected":["file:///C:/a/b"]},' +
    '"right":{"uri":"file:///C:/b","cursor":"file:///C:/b/d","cursorIsDirectory":true,"selected":[]}}',
    Json);
end;

procedure TTestDualPanelPluginJson.ListSkipsTheParentAndCountsTheCursorAfterIt;
var
  Rows: TPanelRows;
  Root: TJSONObject;
  Json: string;
begin
  SetLength(Rows, 2);
  Rows[0] := Row('..', 'file:///C:/', True, True);
  Rows[1] := Row('a.txt', 'file:///C:/a.txt', False, False);
  Rows[1].Size := 4;
  Rows[1].Extension := '.txt';
  Json := BuildPluginPanelListJson('file:///C:/work', Rows, 1);
  Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
  try
    Assert.AreEqual('file:///C:/work', Root.GetValue('uri').Value);
    Assert.AreEqual('0', Root.GetValue('cursor').Value);
    Assert.AreEqual<Integer>(1, TJSONArray(Root.GetValue('rows')).Count);
    Assert.AreEqual('a.txt', TJSONObject(TJSONArray(Root.GetValue('rows')).Items[0]).GetValue('name').Value);
    Assert.AreEqual('.txt', TJSONObject(TJSONArray(Root.GetValue('rows')).Items[0]).GetValue('ext').Value);
    Assert.IsNull(TJSONObject(TJSONArray(Root.GetValue('rows')).Items[0]).GetValue('mtime'));
  finally
    Root.Free;
  end;
end;

procedure TTestDualPanelPluginJson.ListStopsAfterTheRowCap;
var
  Rows: TPanelRows;
  I: Integer;
  Root: TJSONObject;
begin
  SetLength(Rows, cPluginPanelListMaxRows + 2);
  Rows[0] := Row('..', 'file:///C:/', True, True);
  for I := 1 to cPluginPanelListMaxRows + 1 do
    Rows[I] := Row('f', 'file:///C:/f', False, False);
  Root := TJSONObject.ParseJSONValue(
    BuildPluginPanelListJson('file:///C:/work', Rows, cPluginPanelListMaxRows + 1)) as TJSONObject;
  try
    Assert.AreEqual('true', Root.GetValue('truncated').Value);
    Assert.AreEqual<Integer>(cPluginPanelListMaxRows, TJSONArray(Root.GetValue('rows')).Count);
    Assert.IsNull(Root.GetValue('cursor'));
  finally
    Root.Free;
  end;
end;

procedure TTestDualPanelPluginJson.ListAddsCellsForTheRowName;
var
  Rows: TPanelRows;
  Root, Cols: TJSONObject;
begin
  SetFolderCells('mtn.test', 'file:///C:/Pics', '{"photo.jpg":{"dim":"1x2","camera":""}}');
  try
    SetLength(Rows, 1);
    Rows[0] := Row('photo.jpg/', 'file:///C:/Pics/photo.jpg', False, False);
    Root := TJSONObject.ParseJSONValue(
      BuildPluginPanelListJson('file:///C:/Pics/', Rows, 0)) as TJSONObject;
    try
      Cols := TJSONObject(TJSONObject(TJSONArray(Root.GetValue('rows')).Items[0]).GetValue('cols'));
      Assert.AreEqual('1x2', Cols.GetValue('dim').Value);
      Assert.IsNull(Cols.GetValue('camera'));
      Assert.AreEqual('0', Root.GetValue('cursor').Value);
    finally
      Root.Free;
    end;
  finally
    SetFolderCells('mtn.test', 'file:///C:/Pics', '');
  end;
end;

end.
