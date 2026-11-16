unit TestDialogCommandFields;

{ Characterization of ReadDialogCommandFields: the snapshot DialogCommand takes
  of dual-panel dialog controls before dispatch. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogCommandFields = class
  public
    [Test] procedure NilDialogYieldsDefaults;
    [Test] procedure SearchDialogFields;
    [Test] procedure CopyMoveDialogFields;
    [Test] procedure PackDialogFields;
  end;

implementation

uses
  System.SysUtils,
  uDialogHost, uDialogBuilders, uDualPanelUiTypes, uFileFind;

procedure TTestDialogCommandFields.NilDialogYieldsDefaults;
var
  Fields: TDialogCommandFields;
begin
  Fields := ReadDialogCommandFields(nil);
  Assert.AreEqual('', Fields.Name, 'name');
  Assert.AreEqual('', Fields.DestPath, 'dest');
  Assert.AreEqual(0, Fields.ExistingIdx, 'existing default is 0 from Default record');
  Assert.IsFalse(Fields.PreserveTs, 'timestamps');
  Assert.IsFalse(Fields.SyncTwoWay, 'sync');
end;

procedure TTestDialogCommandFields.SearchDialogFields;
var
  Host: TDialogHost;
  Filters: TFindFilterText;
  Fields: TDialogCommandFields;
begin
  Host := TDialogHost.Create(nil);
  try
    Filters := Default(TFindFilterText);
    Filters.SizeMin := '10K';
    Filters.SizeMax := '1M';
    Filters.DateFrom := '2024-01-01';
    Filters.DateTo := '2024-12-31';
    Filters.AttrReadOnly := fasSet;
    Filters.AttrHidden := fasClear;
    Filters.AttrSystem := fasAny;
    Filters.AttrArchive := fasSet;
    Host.Open(BuildSearchDialog('*.pas', 'todo', True, False, True, False,
      '74 6F 64 6F', True, False, 1, 2, Filters), nil);
    Fields := ReadDialogCommandFields(Host);
    Assert.AreEqual('*.pas', Fields.Mask, 'mask');
    Assert.AreEqual('todo', Fields.Containing, 'text');
    Assert.IsTrue(Fields.CaseSens, 'case');
    Assert.IsFalse(Fields.WholeWords, 'words');
    Assert.IsTrue(Fields.SearchFolders, 'folders');
    Assert.IsFalse(Fields.UseRegex, 'regex');
    Assert.AreEqual('74 6F 64 6F', Fields.HexText, 'hex');
    Assert.IsTrue(Fields.Subdirs, 'subdirs');
    Assert.IsFalse(Fields.SearchArchives, 'archives');
    Assert.AreEqual(1, Fields.SearchEngineIdx, 'engine');
    Assert.AreEqual(2, Fields.SearchEncodingIdx, 'encoding');
    Assert.AreEqual('10K', Fields.Filters.SizeMin, 'size min');
    Assert.AreEqual('1M', Fields.Filters.SizeMax, 'size max');
    Assert.AreEqual('2024-01-01', Fields.Filters.DateFrom, 'date from');
    Assert.AreEqual('2024-12-31', Fields.Filters.DateTo, 'date to');
    Assert.AreEqual(fasSet, Fields.Filters.AttrReadOnly, 'attr ro');
    Assert.AreEqual(fasClear, Fields.Filters.AttrHidden, 'attr hidden');
    Assert.AreEqual(fasAny, Fields.Filters.AttrSystem, 'attr system');
    Assert.AreEqual(fasSet, Fields.Filters.AttrArchive, 'attr archive');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogCommandFields.CopyMoveDialogFields;
var
  Host: TDialogHost;
  Fields: TDialogCommandFields;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildCopyMoveDialog('Copy', 'prompt', 'D:\out', 1, True, True,
      False, 2, True, '*.bak'), nil);
    Fields := ReadDialogCommandFields(Host);
    Assert.AreEqual('D:\out', Fields.DestPath, 'dest');
    Assert.AreEqual(1, Fields.ExistingIdx, 'existing');
    Assert.AreEqual(2, Fields.RetryIdx, 'retry');
    Assert.IsTrue(Fields.PreserveTs, 'timestamps');
    Assert.IsTrue(Fields.OnlyNewer, 'only newer');
    Assert.IsFalse(Fields.FollowSymlinks, 'symlinks');
    Assert.IsTrue(Fields.UseExclude, 'filter');
    Assert.AreEqual('*.bak', Fields.ExcludeMask, 'exclude');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogCommandFields.PackDialogFields;
var
  Host: TDialogHost;
  Fields: TDialogCommandFields;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPackDialog('Pack', 'prompt', 'D:\a.7z', 1), nil);
    Fields := ReadDialogCommandFields(Host);
    Assert.AreEqual('D:\a.7z', Fields.DestPath, 'dest');
    Assert.AreEqual(1, Fields.PackTypeIdx, 'pack type');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogCommandFields);

end.
