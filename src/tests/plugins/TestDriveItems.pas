unit TestDriveItems;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDriveItems = class
  public
    [Test] procedure TestItemsKeepPriorityOrderThenRegistrationOrder;
    [Test] procedure TestRepeatedRegistrationReplacesTheItem;
    [Test] procedure TestInvalidItemsAreRefused;
    [Test] procedure TestAtMostFiveItemsAreAccepted;
    [Test] procedure TestUnregisterDropsThePluginItems;
    [Test] procedure TestItemsFollowTheBuiltInNumberedEntries;
    [Test] procedure TestPanelOnItemSchemeIsMarkedAsThatItem;
    [Test] procedure TestChangeNotificationOnRegisterAndUnregister;
  end;

implementation

uses
  System.SysUtils,
  uDriveItems, uDriveInfo, uPluginChrome;

procedure Clean;
begin
  DriveItems.UnregisterPlugin('t.a');
  DriveItems.UnregisterPlugin('t.b');
  SetPluginChromeChanged(nil);
end;

procedure TTestDriveItems.TestItemsKeepPriorityOrderThenRegistrationOrder;
var
  Items: TArray<TDriveItem>;
begin
  try
    Assert.IsTrue(DriveItems.RegisterItem('t.a', 'x', 'X', 'xa://', 50));
    Assert.IsTrue(DriveItems.RegisterItem('t.b', 'y', 'Y', 'yb://', 10));
    Assert.IsTrue(DriveItems.RegisterItem('t.a', 'z', 'Z', 'za://', 50));
    Items := DriveItems.Items;
    Assert.IsTrue(Length(Items) = 3);
    Assert.AreEqual('Y', Items[0].Caption);
    Assert.AreEqual('X', Items[1].Caption);
    Assert.AreEqual('Z', Items[2].Caption);
  finally
    Clean;
  end;
end;

procedure TTestDriveItems.TestRepeatedRegistrationReplacesTheItem;
var
  Items: TArray<TDriveItem>;
begin
  try
    Assert.IsTrue(DriveItems.RegisterItem('t.a', 'x', 'First', 'xa:///', 50));
    Assert.IsTrue(DriveItems.RegisterItem('T.A', 'X', 'Second', 'xa:///root', 50));
    Items := DriveItems.Items;
    Assert.IsTrue(Length(Items) = 1);
    Assert.AreEqual('Second', Items[0].Caption);
    Assert.AreEqual('xa:///root', Items[0].Uri);
  finally
    Clean;
  end;
end;

procedure TTestDriveItems.TestInvalidItemsAreRefused;
begin
  try
    Assert.IsFalse(DriveItems.RegisterItem('', 'x', 'X', 'xa://', 0), 'no plugin id');
    Assert.IsFalse(DriveItems.RegisterItem('t.a', '', 'X', 'xa://', 0), 'no item id');
    Assert.IsFalse(DriveItems.RegisterItem('t.a', 'x', '  ', 'xa://', 0), 'no caption');
    Assert.IsFalse(DriveItems.RegisterItem('t.a', 'x', 'X', 'no-scheme', 0), 'no scheme');
    Assert.IsFalse(DriveItems.RegisterItem('t.a', 'x', 'X', 'file:///C:/', 0),
      'file scheme would shadow the drives');
    Assert.IsTrue(Length(DriveItems.Items) = 0);
  finally
    Clean;
  end;
end;

procedure TTestDriveItems.TestAtMostFiveItemsAreAccepted;
var
  I: Integer;
begin
  try
    for I := 1 to cMaxDriveItems do
      Assert.IsTrue(DriveItems.RegisterItem('t.a', 'i' + IntToStr(I), 'I' + IntToStr(I),
        'xa://' + IntToStr(I), I));
    Assert.IsFalse(DriveItems.RegisterItem('t.b', 'extra', 'Extra', 'yb://', 0),
      'a sixth item has no digit left');
    Assert.IsTrue(DriveItems.RegisterItem('t.a', 'i1', 'Renamed', 'xa://1', 1),
      'replacing an existing item still works when full');
    Assert.IsTrue(Length(DriveItems.Items) = cMaxDriveItems);
  finally
    Clean;
  end;
end;

procedure TTestDriveItems.TestUnregisterDropsThePluginItems;
begin
  try
    DriveItems.RegisterItem('t.a', 'x', 'X', 'xa://', 0);
    DriveItems.RegisterItem('t.b', 'y', 'Y', 'yb://', 0);
    DriveItems.UnregisterPlugin('T.A');
    Assert.IsTrue(Length(DriveItems.Items) = 1);
    Assert.AreEqual('Y', DriveItems.Items[0].Caption);
  finally
    Clean;
  end;
end;

procedure TTestDriveItems.TestItemsFollowTheBuiltInNumberedEntries;
var
  Uri: string;
  Glyphs: TArray<Char>;
begin
  try
    Assert.AreEqual(ChangeDriveSpecialCount, ChangeDriveItemCount);
    DriveItems.RegisterItem('t.a', 'x', 'Net', 'xa:///', 0);
    Assert.AreEqual(ChangeDriveSpecialCount + 1, ChangeDriveItemCount);
    Assert.AreEqual('Net', ChangeDriveSpecialTitle(ChangeDriveSpecialCount));
    Assert.AreEqual('xa:///', ChangeDriveItemUri(ChangeDriveSpecialCount));
    Assert.AreEqual(Char(Ord('1') + ChangeDriveSpecialCount),
      ChangeDriveSpecialGlyph(ChangeDriveSpecialCount));
    Assert.IsTrue(IsChangeDriveSpecialGlyph(Char(Ord('1') + ChangeDriveSpecialCount)));
    Assert.IsTrue(TryChangeDriveSpecialUri(Char(Ord('1') + ChangeDriveSpecialCount), Uri));
    Assert.AreEqual('xa:///', Uri);
    Glyphs := EnumDriveBarGlyphs;
    Assert.AreEqual(Char(Ord('1') + ChangeDriveSpecialCount), Glyphs[High(Glyphs)],
      'the drive bar ends with the plugin item');
    DriveItems.UnregisterPlugin('t.a');
    Assert.IsFalse(IsChangeDriveSpecialGlyph(Char(Ord('1') + ChangeDriveSpecialCount)));
    Assert.AreEqual(ChangeDriveSpecialCount, ChangeDriveItemCount);
  finally
    Clean;
  end;
end;

procedure TTestDriveItems.TestPanelOnItemSchemeIsMarkedAsThatItem;
var
  Glyph: Char;
begin
  try
    DriveItems.RegisterItem('t.a', 'x', 'Net', 'xa:///', 0);
    Glyph := Char(Ord('1') + ChangeDriveSpecialCount);
    Assert.AreEqual(Glyph, DriveBarGlyphFromUri('xa:///'));
    Assert.AreEqual(Glyph, DriveBarGlyphFromUri('XA://session/dir/file'));
    Assert.AreNotEqual(Glyph, DriveBarGlyphFromUri('other://host/'));
    Assert.AreEqual(ChangeDriveSpecialGlyph(3), DriveBarGlyphFromUri('ws:///'),
      'built-in items keep their glyphs');
  finally
    Clean;
  end;
end;

procedure TTestDriveItems.TestChangeNotificationOnRegisterAndUnregister;
var
  Calls: Integer;
begin
  Calls := 0;
  try
    SetPluginChromeChanged(procedure begin Inc(Calls); end);
    DriveItems.RegisterItem('t.a', 'x', 'X', 'xa://', 0);
    Assert.AreEqual(1, Calls, 'new item');
    DriveItems.RegisterItem('', 'x', 'X', 'xa://', 0);
    Assert.AreEqual(1, Calls, 'a refused item changes nothing');
    DriveItems.UnregisterPlugin('t.b');
    Assert.AreEqual(1, Calls, 'a plugin without items changes nothing');
    DriveItems.UnregisterPlugin('t.a');
    Assert.AreEqual(2, Calls, 'removed item');
  finally
    Clean;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDriveItems);

end.
