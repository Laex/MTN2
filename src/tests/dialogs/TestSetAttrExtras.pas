unit TestSetAttrExtras;

{ The attributes dialog beyond Read-only / Hidden / Archive / System: the other
  file flags (Temporary, Not indexed, ...), the volume and device lines of a
  drive root and the System properties button. Works on throw-away files in
  %TEMP%. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSetAttrExtras = class
  public
    [Test] procedure TestFlagsRoundTripThroughAPlan;
    [Test] procedure TestDialogShowsCurrentFlagsAndKeepsUnchangedOnes;
    [Test] procedure TestDriveRootHasVolumeAndDevice;
    [Test] procedure TestOtherPathsHaveNoVolume;
    [Test] procedure TestSystemPropertiesButtonKeepsTheDialogOpen;
    [Test] procedure TestFileDialogHasNoVolumeLines;
    [Test] procedure TestSubfoldersOptionIsOnlyForFolders;
    [Test] procedure TestOwnerIsChosenFromAList;
    [Test] procedure TestFlagListsOfBothColumnsAreEquallyWide;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uFileAttrTypes, uWinFileAttr,
  uPlatformFileAttr, uDualPanelFileDialogs;

var
  GPlan: TFileAttrPlan;
  GPropsPaths: TArray<string>;
  GLastKind: THostDialogKind;

function MakeController(ADialog: TDialogHost): TFileOpDialogController;
begin
  Result := TFileOpDialogController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string) begin end,
    procedure(AKind: THostDialogKind) begin GLastKind := AKind; end,
    procedure begin end,
    nil, nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, nil, nil, nil,
    procedure(const APaths: TArray<string>; const APlan: TFileAttrPlan)
    begin
      GPlan := APlan;
    end);
  Result.OnSystemProperties :=
    procedure(APaths: TArray<string>)
    begin
      GPropsPaths := APaths;
    end;
end;

function FindControl(ADialog: TDialogHost; const AId: string): TDialogControl;
var
  I: Integer;
begin
  for I := 0 to ADialog.ControlCount - 1 do
    if ADialog.GetControl(I).Id = AId then
      Exit(ADialog.GetControl(I));
  Result := Default(TDialogControl);
end;

function NewTempFile(out ADir: string): string;
begin
  ADir := TPath.Combine(TPath.GetTempPath, 'mtn2-attr-extras-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(ADir);
  Result := TPath.Combine(ADir, 'a.txt');
  TFile.WriteAllText(Result, 'a', TEncoding.UTF8);
end;

function Snapshot(const APath: string): TFileAttrSnapshot;
var
  Err: string;
begin
  Assert.IsTrue(TryReadFileAttrSnapshot(APath, Result, Err), 'attributes readable: ' + Err);
end;

procedure TTestSetAttrExtras.TestFlagsRoundTripThroughAPlan;
var
  Dir, Path, Err: string;
  Plan: TFileAttrPlan;
begin
  Path := NewTempFile(Dir);
  try
    Plan := Default(TFileAttrPlan);
    Plan.Temporary := facSet;
    Plan.NotIndexed := facSet;
    Assert.IsTrue(ApplyFileAttrPlan(Path, Plan, Err), 'applied: ' + Err);
    Assert.IsTrue(Snapshot(Path).Temporary, 'Temporary set');
    Assert.IsTrue(Snapshot(Path).NotIndexed, 'Not indexed set');
    Assert.IsFalse(Snapshot(Path).Offline, 'untouched flag stays');

    Plan := Default(TFileAttrPlan);
    Plan.Temporary := facClear;
    Assert.IsTrue(ApplyFileAttrPlan(Path, Plan, Err), 'applied: ' + Err);
    Assert.IsFalse(Snapshot(Path).Temporary, 'Temporary cleared');
    Assert.IsTrue(Snapshot(Path).NotIndexed, 'a Keep flag is left alone');
    Assert.IsFalse(FileAttrPlanIsNoOp(Plan), 'a flag change is not a no-op');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetAttrExtras.TestDialogShowsCurrentFlagsAndKeepsUnchangedOnes;
var
  Dir, Path, Err: string;
  Plan: TFileAttrPlan;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
begin
  Path := NewTempFile(Dir);
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    Plan := Default(TFileAttrPlan);
    Plan.Temporary := facSet;
    Assert.IsTrue(ApplyFileAttrPlan(Path, Plan, Err), 'applied: ' + Err);

    C.BeginSetAttributes([Path]);
    Assert.IsTrue(Dialog.Visible, 'dialog opens');
    Assert.AreEqual(2, Dialog.GetCheckboxState('attr_temp'), 'a set flag opens checked');
    Assert.AreEqual(1, Dialog.GetCheckboxState('attr_noidx'), 'a clear flag opens unchecked');

    GPlan := Default(TFileAttrPlan);
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Assert.IsTrue(GPlan.Temporary = facKeep, 'Temporary is left as it is');
    Assert.IsTrue(GPlan.NotIndexed = facKeep, 'Not indexed is left as it is');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetAttrExtras.TestDriveRootHasVolumeAndDevice;
var
  Root: string;
  State: TFileAttrDialogState;
begin
  Root := ExtractFileDrive(TPath.GetTempPath) + '\';
  if not (Length(Root) = 3) then
    Exit;
  State := BuildFileAttrDialogState([Root]);
  Assert.AreEqual(Root, State.Summary, 'a drive root is shown by its path');
  Assert.IsTrue(State.Volume.StartsWith('\\?\Volume{'), 'volume GUID path: ' + State.Volume);
  Assert.IsTrue(State.Device.StartsWith('\Device\'), 'device name: ' + State.Device);
end;

procedure TTestSetAttrExtras.TestOtherPathsHaveNoVolume;
var
  State: TFileAttrDialogState;
begin
  State := BuildFileAttrDialogState([TPath.GetTempPath]);
  Assert.AreEqual('', State.Volume);
  Assert.AreEqual('', State.Device);
end;

procedure TTestSetAttrExtras.TestSystemPropertiesButtonKeepsTheDialogOpen;
var
  Dir, Path: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
begin
  Path := NewTempFile(Dir);
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    C.BeginSetAttributes([Path]);
    SetLength(GPropsPaths, 0);
    GLastKind := hdkNone;
    C.DispatchCommand(hdkSetAttributes, 'sys_props');
    Assert.AreEqual<Integer>(1, Length(GPropsPaths), 'the paths go to the Windows properties');
    Assert.AreEqual(Path, GPropsPaths[0]);
    Assert.IsTrue(Dialog.Visible and (GLastKind = hdkSetAttributes), 'the dialog stays open');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetAttrExtras.TestFileDialogHasNoVolumeLines;
var
  Dir, Path: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
begin
  Path := NewTempFile(Dir);
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    C.BeginSetAttributes([Path]);
    Assert.IsFalse(Dialog.HasControl('volume'), 'no volume field for a file');
    Assert.IsFalse(Dialog.HasControl('device'), 'no device field for a file');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetAttrExtras.TestSubfoldersOptionIsOnlyForFolders;
var
  Dir, Path: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
begin
  Path := NewTempFile(Dir);
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    C.BeginSetAttributes([Path]);
    Assert.IsTrue(FindControl(Dialog, 'recurse').Disabled, 'a file has no subfolders');
    C.BeginSetAttributes([Dir]);
    Assert.IsFalse(FindControl(Dialog, 'recurse').Disabled, 'a folder may be processed with its contents');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetAttrExtras.TestOwnerIsChosenFromAList;
var
  Dir, Path: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
  Own: TDialogControl;
begin
  Path := NewTempFile(Dir);
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    C.BeginSetAttributes([Path]);
    Own := FindControl(Dialog, 'owner');
    Assert.IsTrue(Own.Kind = dckDropDown, 'owner is a drop-down');
    Assert.IsTrue(Length(Own.Items) > 0, 'the list is not empty');
    Assert.IsTrue(Dialog.GetListSelectedText('owner') <> '', 'an owner is selected');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetAttrExtras.TestFlagListsOfBothColumnsAreEquallyWide;
var
  Dir, Path: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;

  function BoxWidth(const AId: string): Integer;
  var
    I: Integer;
  begin
    for I := 0 to Dialog.ControlCount - 1 do
      if Dialog.GetControl(I).Id = AId then
        Exit(Dialog.ControlBoundsAt(I).Width);
    Result := -1;
  end;

begin
  Path := NewTempFile(Dir);
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    C.BeginSetAttributes([Path]);
    Assert.IsTrue(BoxWidth('attr_ro') > 0, 'left list is laid out');
    Assert.AreEqual(BoxWidth('attr_ro'), BoxWidth('attr_enc'), 'right list is as wide as the left one');
    Assert.AreEqual(BoxWidth('attr_ro'), BoxWidth('attr_off'), 'last right list is as wide as the left one');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSetAttrExtras);

end.
