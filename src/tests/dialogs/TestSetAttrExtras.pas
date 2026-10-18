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
    [Test] procedure TestDialogOpensOnTheCurrentFlagsAndPutsThemInThePlan;
    [Test] procedure TestDriveRootHasVolumeAndDevice;
    [Test] procedure TestOtherPathsHaveNoVolume;
    [Test] procedure TestSystemPropertiesButtonKeepsTheDialogOpen;
    [Test] procedure TestFileDialogHasNoVolumeLines;
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

procedure TTestSetAttrExtras.TestDialogOpensOnTheCurrentFlagsAndPutsThemInThePlan;
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
    Assert.AreEqual<Integer>(Ord(facSet), Dialog.GetListSelectedIndex('attr_temp'), 'Temporary shows Set');
    Assert.AreEqual<Integer>(Ord(facClear), Dialog.GetListSelectedIndex('attr_noidx'), 'Not indexed shows Clear');

    GPlan := Default(TFileAttrPlan);
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Assert.IsTrue(GPlan.Temporary = facSet, 'Temporary reaches the plan');
    Assert.IsTrue(GPlan.NotIndexed = facClear, 'Not indexed reaches the plan');
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

initialization
  TDUnitX.RegisterTestFixture(TTestSetAttrExtras);

end.
