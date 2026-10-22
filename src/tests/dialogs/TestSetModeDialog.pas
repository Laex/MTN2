unit TestSetModeDialog;

{ The Set attributes command on a platform with permission bits: the
  permissions dialog (octal mode, owner and group) opens on the values of the
  item, only a field that was edited goes into the plan, and the plan reaches chmod. Platforms without permission bits keep the
  attribute dialog. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSetModeDialog = class
  public
    [Test] procedure PermissionsDialogBuildsModePlan;
    [Test] procedure ModeTextRoundTrips;
    [Test] procedure ModeIsAppliedToTheFile;
    [Test] procedure CreationTimeOfNewFileIsRecent;
    [Test] procedure FileSystemFlagsAreAppliedAndRead;
    [Test] procedure FlagBoxesGoIntoThePlanOnlyWhenChanged;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uFileAttrTypes, uWinFileAttr,
  uPlatformFileAttr, uDualPanelFileDialogs;

var
  GApplyCount: Integer;
  GPlan: TFileAttrPlan;

function MakeController(ADialog: TDialogHost): TFileOpDialogController;
begin
  Result := TFileOpDialogController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string) begin end,
    procedure(AKind: THostDialogKind) begin end,
    procedure begin end,
    nil, nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, nil, nil, nil,
    procedure(const APaths: TArray<string>; const APlan: TFileAttrPlan)
    begin
      Inc(GApplyCount);
      GPlan := APlan;
    end);
end;

procedure TTestSetModeDialog.PermissionsDialogBuildsModePlan;
var
  Dir, A: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
  Snap: TFileAttrSnapshot;
  Err: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-setmode-dlg-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  A := TPath.Combine(Dir, 'a.txt');
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    C.BeginSetAttributes([A]);
    Assert.IsTrue(Dialog.Visible, 'dialog opens');
    if not PlatformFileModeSupported then
    begin
      Assert.AreEqual('', Dialog.GetInputValue('group'), 'attribute dialog has no group field');
      Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
      Assert.AreEqual(-1, Snap.Mode, 'no permission bits on this platform');
      Exit;
    end;
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
    Assert.IsTrue(Snap.Mode >= 0, 'mode is read');
    Assert.AreEqual(FileModeToOctal(Snap.Mode), Dialog.GetInputValue('mode'), 'mode shown in octal');
    Assert.AreEqual(Snap.Group, Dialog.GetInputValue('group'), 'group shown');

    GApplyCount := 0;
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Assert.AreEqual(0, GApplyCount, 'untouched fields apply nothing');

    C.BeginSetAttributes([A]);
    Dialog.SetInputValue('mode', '9x');
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Assert.IsTrue(Dialog.Visible and (GApplyCount = 0), 'invalid mode keeps the dialog open');

    Dialog.SetInputValue('mode', '0700');
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Assert.AreEqual(1, GApplyCount, 'OK applies');
    Assert.IsTrue(GPlan.ChangeMode, 'mode change requested');
    Assert.AreEqual($1C0, GPlan.Mode, 'octal 0700');
    Assert.IsFalse(GPlan.ChangeOwner or GPlan.ChangeGroup, 'owner and group untouched');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetModeDialog.ModeTextRoundTrips;
var
  Mode: Integer;
begin
  Assert.AreEqual('0644', FileModeToOctal($1A4), 'octal text');
  Assert.AreEqual('rw-r--r--', FileModeToSymbolic($1A4), 'symbolic text');
  Assert.IsTrue(TryParseFileMode('755', Mode) and (Mode = $1ED), '755 parses');
  Assert.IsTrue(TryParseFileMode('4755', Mode) and (Mode = $9ED), 'setuid bit parses');
  Assert.IsFalse(TryParseFileMode('', Mode), 'empty');
  Assert.IsFalse(TryParseFileMode('800', Mode), 'digit 8');
  Assert.IsFalse(TryParseFileMode('77777', Mode), 'too long');
end;

procedure TTestSetModeDialog.CreationTimeOfNewFileIsRecent;
var
  Dir, A, Err: string;
  Snap: TFileAttrSnapshot;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-created-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  try
    A := TPath.Combine(Dir, 'a.txt');
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
    Assert.IsTrue(Abs(Now - Snap.Times.Created) < 1, 'creation time of a new file is within a day of now');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetModeDialog.FileSystemFlagsAreAppliedAndRead;
var
  Dir, A, Err: string;
  Plan: TFileAttrPlan;
  Snap: TFileAttrSnapshot;
begin
  if not PlatformFileModeSupported then
    Exit;
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-fsflags-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  try
    A := TPath.Combine(Dir, 'a.txt');
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
    Assert.IsFalse(Snap.NoDump or Snap.Immutable or Snap.AppendOnly, 'a new file has no flags');
    Plan := Default(TFileAttrPlan);
    Plan.NoDump := facSet;
    // A file system without flags (tmpfs) refuses; there is nothing to check there.
    if not ApplyFileAttrOne(A, Plan, Err) then
    begin
      Assert.IsTrue(Pos('not supported', Err) > 0, Err);
      Exit;
    end;
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
    Assert.IsTrue(Snap.NoDump, 'no dump is set');
    Assert.IsFalse(Snap.Immutable, 'the other flags stay');
    Plan.NoDump := facClear;
    Assert.IsTrue(ApplyFileAttrOne(A, Plan, Err), Err);
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
    Assert.IsFalse(Snap.NoDump, 'no dump is cleared');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetModeDialog.FlagBoxesGoIntoThePlanOnlyWhenChanged;
var
  Dir, A, Err: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
  Plan: TFileAttrPlan;
begin
  if not PlatformFileModeSupported then
    Exit;
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-flagbox-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  A := TPath.Combine(Dir, 'a.txt');
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    Plan := Default(TFileAttrPlan);
    Plan.NoDump := facSet;
    if not ApplyFileAttrOne(A, Plan, Err) then
      Exit;
    C.BeginSetAttributes([A]);
    Assert.IsTrue(Dialog.GetCheckbox('flag_nodump'), 'the flag the file has is checked');
    Assert.IsFalse(Dialog.GetCheckbox('flag_immutable'), 'the others are not');
    GApplyCount := 0;
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Assert.AreEqual(0, GApplyCount, 'untouched boxes apply nothing');
    C.BeginSetAttributes([A]);
    Dialog.SetCheckbox('flag_nodump', False);
    Dialog.SetCheckbox('flag_append', True);
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Assert.AreEqual(1, GApplyCount);
    Assert.IsTrue(GPlan.NoDump = facClear, 'a cleared box clears the flag');
    Assert.IsTrue(GPlan.AppendOnly = facSet, 'a checked box sets the flag');
    Assert.IsTrue(GPlan.Immutable = facKeep, 'an untouched box keeps it');
  finally
    C.Free;
    Dialog.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSetModeDialog.ModeIsAppliedToTheFile;
var
  Dir, A, Err: string;
  Plan: TFileAttrPlan;
  Snap: TFileAttrSnapshot;
begin
  if not PlatformFileModeSupported then
    Exit;
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-setmode-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  try
    A := TPath.Combine(Dir, 'a.txt');
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    Plan := Default(TFileAttrPlan);
    Plan.ChangeMode := True;
    Plan.Mode := $1A4;
    Assert.IsTrue(ApplyFileAttrPlan(A, Plan, Err), Err);
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
    Assert.AreEqual($1A4, Snap.Mode, 'chmod 0644');
    Plan.Mode := $180;
    Assert.IsTrue(ApplyFileAttrPlan(A, Plan, Err), Err);
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), Err);
    Assert.AreEqual($180, Snap.Mode, 'chmod 0600');
    Plan := Default(TFileAttrPlan);
    Plan.ChangeGroup := True;
    Plan.Group := Snap.Group;
    Assert.IsTrue(ApplyFileAttrPlan(A, Plan, Err), Err);
    Plan.Group := 'no-such-group-mtn2';
    Assert.IsFalse(ApplyFileAttrPlan(A, Plan, Err), 'unknown group fails');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSetModeDialog);

end.
