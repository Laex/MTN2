unit TestWinFileAttr;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWinFileAttr = class
  public
    [Test] procedure TestTimeText;
    [Test] procedure TestNoOpTimes;
    [Test] procedure TestApplyTimes;
    [Test] procedure TestChoiceIndex;
    [Test] procedure TestNoOp;
    [Test] procedure TestSetClearReadOnly;
    [Test] procedure TestMergeMixed;
    [Test] procedure TestRecurseAndOwner;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  Winapi.Windows,
  uWinFileAttr;

function HasBit(const APath: string; ABit: DWORD): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(APath));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and ((Attr and ABit) <> 0);
end;

procedure TestChoiceIndex;
begin
  Assert.IsTrue(FileAttrChoiceToIndex(facKeep) = 0, 'Keep=0');
  Assert.IsTrue(FileAttrChoiceToIndex(facSet) = 1, 'Set=1');
  Assert.IsTrue(FileAttrChoiceToIndex(facClear) = 2, 'Clear=2');
  Assert.IsTrue(FileAttrIndexToChoice(0) = facKeep, '0=Keep');
  Assert.IsTrue(FileAttrIndexToChoice(1) = facSet, '1=Set');
  Assert.IsTrue(FileAttrIndexToChoice(2) = facClear, '2=Clear');
  Assert.IsTrue(FileAttrIndexToChoice(-1) = facKeep, 'clamp low');
  Assert.IsTrue(FileAttrIndexToChoice(9) = facClear, 'clamp high');
end;

procedure TestNoOp;
var
  Plan: TFileAttrPlan;
begin
  Plan := Default(TFileAttrPlan);
  Assert.IsTrue(FileAttrPlanIsNoOp(Plan), 'all Keep, no owner');
  Plan.ReadOnly := facSet;
  Assert.IsTrue(not FileAttrPlanIsNoOp(Plan), 'Set is not no-op');
  Plan.ReadOnly := facKeep;
  Plan.ChangeOwner := True;
  Assert.IsTrue(not FileAttrPlanIsNoOp(Plan), 'Change owner is not no-op');
end;

procedure TestSetClearReadOnly;
var
  Dir, Path, Err: string;
  Snap: TFileAttrSnapshot;
  Plan: TFileAttrPlan;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-attr-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  Path := TPath.Combine(Dir, 'a.txt');
  try
    TFile.WriteAllText(Path, 'x', TEncoding.UTF8);
    Assert.IsTrue(TryReadFileAttrSnapshot(Path, Snap, Err), 'read snapshot');
    Plan := Default(TFileAttrPlan);
    Plan.ReadOnly := facSet;
    Assert.IsTrue(ApplyFileAttrPlan(Path, Plan, Err), 'set read-only: ' + Err);
    Assert.IsTrue(HasBit(Path, FILE_ATTRIBUTE_READONLY), 'RO bit set');
    Plan.ReadOnly := facClear;
    Assert.IsTrue(ApplyFileAttrPlan(Path, Plan, Err), 'clear read-only: ' + Err);
    Assert.IsTrue(not HasBit(Path, FILE_ATTRIBUTE_READONLY), 'RO bit cleared');
  finally
    SetFileAttributes(PChar(Path), FILE_ATTRIBUTE_NORMAL);
    if TFile.Exists(Path) then
      TFile.Delete(Path);
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TestMergeMixed;
var
  Dir, A, B: string;
  State: TFileAttrDialogState;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-attr-mix-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  A := TPath.Combine(Dir, 'ro.txt');
  B := TPath.Combine(Dir, 'rw.txt');
  try
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    TFile.WriteAllText(B, 'b', TEncoding.UTF8);
    SetFileAttributes(PChar(A), FILE_ATTRIBUTE_ARCHIVE or FILE_ATTRIBUTE_READONLY);
    SetFileAttributes(PChar(B), FILE_ATTRIBUTE_ARCHIVE);
    State := BuildFileAttrDialogState(TArray<string>.Create(A, B));
    Assert.IsTrue(State.ReadOnly = facKeep, 'mixed RO is Keep');
    Assert.IsTrue(not State.OwnerMixed, 'same owner not mixed');
    Assert.IsTrue(State.Owner <> '', 'owner name present');
  finally
    SetFileAttributes(PChar(A), FILE_ATTRIBUTE_NORMAL);
    SetFileAttributes(PChar(B), FILE_ATTRIBUTE_NORMAL);
    if TFile.Exists(A) then
      TFile.Delete(A);
    if TFile.Exists(B) then
      TFile.Delete(B);
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TestRecurseAndOwner;
var
  Dir, Nested, Child, Err: string;
  Snap: TFileAttrSnapshot;
  Plan: TFileAttrPlan;
  Ok, Fail: Integer;
  FirstPath, FirstErr: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-attr-rec-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  Nested := TPath.Combine(Dir, 'sub');
  TDirectory.CreateDirectory(Nested);
  Child := TPath.Combine(Nested, 'c.txt');
  try
    TFile.WriteAllText(Child, 'c', TEncoding.UTF8);
    Assert.IsTrue(TryReadFileAttrSnapshot(Dir, Snap, Err), 'read dir snapshot');
    Assert.IsTrue(Snap.Owner <> '', 'owner is non-empty');
    Assert.IsTrue(Snap.Owner <> '(unknown)', 'owner resolved');

    Plan := Default(TFileAttrPlan);
    Plan.Hidden := facSet;
    Plan.Recurse := True;
    ApplyFileAttrRoots(TArray<string>.Create(Dir), Plan, Ok, Fail, FirstPath, FirstErr);
    Assert.IsTrue(Fail = 0, 'recurse set Hidden: ' + FirstErr);
    Assert.IsTrue(HasBit(Dir, FILE_ATTRIBUTE_HIDDEN), 'dir hidden');
    Assert.IsTrue(HasBit(Nested, FILE_ATTRIBUTE_HIDDEN), 'subdir hidden');
    Assert.IsTrue(HasBit(Child, FILE_ATTRIBUTE_HIDDEN), 'child hidden');

    Plan := Default(TFileAttrPlan);
    Plan.Hidden := facClear;
    Plan.Recurse := True;
    ApplyFileAttrRoots(TArray<string>.Create(Dir), Plan, Ok, Fail, FirstPath, FirstErr);
    Assert.IsTrue(Fail = 0, 'recurse clear Hidden: ' + FirstErr);
    Assert.IsTrue(not HasBit(Child, FILE_ATTRIBUTE_HIDDEN), 'child unhidden');

    Plan := Default(TFileAttrPlan);
    Plan.ChangeOwner := True;
    Plan.Owner := Snap.Owner;
    ApplyFileAttrRoots(TArray<string>.Create(Child), Plan, Ok, Fail, FirstPath, FirstErr);
    Assert.IsTrue(Fail = 0, 'set current owner is no-op: ' + FirstErr);
  finally
    SetFileAttributes(PChar(Child), FILE_ATTRIBUTE_NORMAL);
    SetFileAttributes(PChar(Nested), FILE_ATTRIBUTE_NORMAL);
    SetFileAttributes(PChar(Dir), FILE_ATTRIBUTE_NORMAL);
    if TFile.Exists(Child) then
      TFile.Delete(Child);
    if TDirectory.Exists(Nested) then
      TDirectory.Delete(Nested, True);
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

{ ---- Created / Modified / Accessed ------------------------------------ }

// What the panel shows: uFileVfs reads FindData and converts it with
// FileTimeToLocalFileTime -- the dialog must round-trip to the same value.
function PanelModified(const APath: string): TDateTime;
var
  SR: TSearchRec;
  LFT: TFileTime;
  ST: TSystemTime;
begin
  Result := 0;
  if FindFirst(ExcludeTrailingPathDelimiter(APath), faAnyFile, SR) <> 0 then
    Exit;
  try
    if FileTimeToLocalFileTime(SR.FindData.ftLastWriteTime, LFT) and
       FileTimeToSystemTime(LFT, ST) then
      Result := SystemTimeToDateTime(ST);
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

function SameSecond(A, B: TDateTime): Boolean;
begin
  Result := FormatFileAttrTime(A) = FormatFileAttrTime(B);
end;

procedure TestTimeText;
var
  T, P: TDateTime;
begin
  Writeln('Time text (locale ', FormatSettings.ShortDateFormat, ')');
  T := EncodeDateTime(2021, 3, 4, 5, 6, 7, 0);
  Assert.IsTrue(FormatFileAttrTime(0) = '', '0 formats as empty');
  Assert.IsTrue(TryParseFileAttrTime(FormatFileAttrTime(T), P) and SameDateTime(P, T),
    'format -> parse round-trip: ' + FormatFileAttrTime(T));
  Assert.IsTrue(TryParseFileAttrTime('  ' + FormatFileAttrTime(T) + ' ', P) and SameDateTime(P, T),
    'surrounding spaces are ignored');
  Assert.IsTrue(TryParseFileAttrTime(DateToStr(T) + ' ' + FormatDateTime('hh:nn', T), P) and
    SameDateTime(P, EncodeDateTime(2021, 3, 4, 5, 6, 0, 0)), 'seconds are optional');
  Assert.IsTrue(TryParseFileAttrTime(DateToStr(T), P) and SameDateTime(P, EncodeDate(2021, 3, 4)),
    'date alone means midnight');
  Assert.IsTrue(not TryParseFileAttrTime('', P), 'empty is not a date');
  Assert.IsTrue(not TryParseFileAttrTime('yesterday', P), 'garbage is not a date');
  Assert.IsTrue(not TryParseFileAttrTime(DateToStr(EncodeDate(1500, 1, 1)), P),
    'before 1601 cannot be a file time');
end;

procedure TestNoOpTimes;
var
  Plan: TFileAttrPlan;
begin
  Plan := Default(TFileAttrPlan);
  Plan.Times.Modified := Now; // a value without its flag changes nothing
  Assert.IsTrue(FileAttrPlanIsNoOp(Plan), 'unflagged time is no-op');
  Plan.SetModified := True;
  Assert.IsTrue(not FileAttrPlanIsNoOp(Plan), 'SetModified is not no-op');
end;

procedure TestApplyTimes;
var
  Dir, A, B, Sub, Child, Err: string;
  Snap, Before: TFileAttrSnapshot;
  Plan: TFileAttrPlan;
  State: TFileAttrDialogState;
  Created, Modified: TDateTime;
  Ok, Fail: Integer;
  FirstPath, FirstErr: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-attr-time-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  A := TPath.Combine(Dir, 'a.txt');
  B := TPath.Combine(Dir, 'b.txt');
  Sub := TPath.Combine(Dir, 'sub');
  Child := TPath.Combine(Sub, 'c.txt');
  Created := EncodeDateTime(2020, 1, 2, 3, 4, 5, 0);
  Modified := EncodeDateTime(2021, 6, 7, 8, 9, 10, 0); // summer: DST path
  try
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    TFile.WriteAllText(B, 'b', TEncoding.UTF8);
    TDirectory.CreateDirectory(Sub);
    TFile.WriteAllText(Child, 'c', TEncoding.UTF8);

    Assert.IsTrue(TryReadFileAttrSnapshot(A, Before, Err), 'read times');
    Assert.IsTrue(Before.Times.Modified > 0, 'modified time is read');

    Plan := Default(TFileAttrPlan);
    Plan.SetCreated := True;
    Plan.Times.Created := Created;
    Plan.SetModified := True;
    Plan.Times.Modified := Modified;
    Assert.IsTrue(ApplyFileAttrPlan(A, Plan, Err), 'set created + modified: ' + Err);
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err), 're-read');
    Assert.IsTrue(SameSecond(Snap.Times.Created, Created), 'created written: ' +
      FormatFileAttrTime(Snap.Times.Created));
    Assert.IsTrue(SameSecond(Snap.Times.Modified, Modified), 'modified written: ' +
      FormatFileAttrTime(Snap.Times.Modified));
    Assert.IsTrue(SameSecond(PanelModified(A), Modified), 'the panel shows the same modified time');

    // Unflagged times are left alone.
    Plan := Default(TFileAttrPlan);
    Plan.SetAccessed := True;
    Plan.Times.Accessed := Created;
    Assert.IsTrue(ApplyFileAttrPlan(A, Plan, Err), 'set accessed only: ' + Err);
    Assert.IsTrue(TryReadFileAttrSnapshot(A, Snap, Err) and SameSecond(Snap.Times.Modified, Modified),
      'modified untouched when only accessed is set');

    // Read-only file: FILE_WRITE_ATTRIBUTES still allowed.
    SetFileAttributes(PChar(B), FILE_ATTRIBUTE_READONLY);
    Plan := Default(TFileAttrPlan);
    Plan.SetModified := True;
    Plan.Times.Modified := Modified;
    Assert.IsTrue(ApplyFileAttrPlan(B, Plan, Err), 'read-only file takes a new time: ' + Err);
    Assert.IsTrue(SameSecond(PanelModified(B), Modified), 'read-only file time written');

    // Same modified time on both -> shown; different -> empty (keep).
    State := BuildFileAttrDialogState(TArray<string>.Create(A, B));
    Assert.IsTrue(SameSecond(State.Times.Modified, Modified), 'equal times across items are shown');
    Assert.IsTrue(State.Times.Created = 0, 'different created times -> empty field');

    // Directory, recursively.
    Plan := Default(TFileAttrPlan);
    Plan.SetModified := True;
    Plan.Times.Modified := Created;
    Plan.Recurse := True;
    ApplyFileAttrRoots(TArray<string>.Create(Sub), Plan, Ok, Fail, FirstPath, FirstErr);
    Assert.IsTrue(Fail = 0, 'recurse set modified: ' + FirstErr);
    Assert.IsTrue(SameSecond(PanelModified(Sub), Created), 'folder time written');
    Assert.IsTrue(SameSecond(PanelModified(Child), Created), 'child time written');
  finally
    SetFileAttributes(PChar(B), FILE_ATTRIBUTE_NORMAL);
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

{ TTestWinFileAttr }

procedure TTestWinFileAttr.TestTimeText;
begin
  TestWinFileAttr.TestTimeText;
end;

procedure TTestWinFileAttr.TestNoOpTimes;
begin
  TestWinFileAttr.TestNoOpTimes;
end;

procedure TTestWinFileAttr.TestApplyTimes;
begin
  TestWinFileAttr.TestApplyTimes;
end;

procedure TTestWinFileAttr.TestChoiceIndex;
begin
  TestWinFileAttr.TestChoiceIndex;
end;

procedure TTestWinFileAttr.TestNoOp;
begin
  TestWinFileAttr.TestNoOp;
end;

procedure TTestWinFileAttr.TestSetClearReadOnly;
begin
  TestWinFileAttr.TestSetClearReadOnly;
end;

procedure TTestWinFileAttr.TestMergeMixed;
begin
  TestWinFileAttr.TestMergeMixed;
end;

procedure TTestWinFileAttr.TestRecurseAndOwner;
begin
  TestWinFileAttr.TestRecurseAndOwner;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWinFileAttr);

end.
