program TestWinFileAttr;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  Winapi.Windows,
  uWinFileAttr in '..\Core\uWinFileAttr.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function HasBit(const APath: string; ABit: DWORD): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(APath));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and ((Attr and ABit) <> 0);
end;

procedure TestChoiceIndex;
begin
  Writeln('Choice index');
  Expect(FileAttrChoiceToIndex(facKeep) = 0, 'Keep=0');
  Expect(FileAttrChoiceToIndex(facSet) = 1, 'Set=1');
  Expect(FileAttrChoiceToIndex(facClear) = 2, 'Clear=2');
  Expect(FileAttrIndexToChoice(0) = facKeep, '0=Keep');
  Expect(FileAttrIndexToChoice(1) = facSet, '1=Set');
  Expect(FileAttrIndexToChoice(2) = facClear, '2=Clear');
  Expect(FileAttrIndexToChoice(-1) = facKeep, 'clamp low');
  Expect(FileAttrIndexToChoice(9) = facClear, 'clamp high');
end;

procedure TestNoOp;
var
  Plan: TFileAttrPlan;
begin
  Writeln('No-op plan');
  Plan := Default(TFileAttrPlan);
  Expect(FileAttrPlanIsNoOp(Plan), 'all Keep, no owner');
  Plan.ReadOnly := facSet;
  Expect(not FileAttrPlanIsNoOp(Plan), 'Set is not no-op');
  Plan.ReadOnly := facKeep;
  Plan.ChangeOwner := True;
  Expect(not FileAttrPlanIsNoOp(Plan), 'Change owner is not no-op');
end;

procedure TestSetClearReadOnly;
var
  Dir, Path, Err: string;
  Snap: TFileAttrSnapshot;
  Plan: TFileAttrPlan;
begin
  Writeln('Set/clear read-only');
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-attr-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  Path := TPath.Combine(Dir, 'a.txt');
  try
    TFile.WriteAllText(Path, 'x', TEncoding.UTF8);
    Expect(TryReadFileAttrSnapshot(Path, Snap, Err), 'read snapshot');
    Plan := Default(TFileAttrPlan);
    Plan.ReadOnly := facSet;
    Expect(ApplyFileAttrPlan(Path, Plan, Err), 'set read-only: ' + Err);
    Expect(HasBit(Path, FILE_ATTRIBUTE_READONLY), 'RO bit set');
    Plan.ReadOnly := facClear;
    Expect(ApplyFileAttrPlan(Path, Plan, Err), 'clear read-only: ' + Err);
    Expect(not HasBit(Path, FILE_ATTRIBUTE_READONLY), 'RO bit cleared');
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
  Writeln('Merge mixed selection');
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
    Expect(State.ReadOnly = facKeep, 'mixed RO is Keep');
    Expect(not State.OwnerMixed, 'same owner not mixed');
    Expect(State.Owner <> '', 'owner name present');
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
  Writeln('Recurse + owner');
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-attr-rec-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  Nested := TPath.Combine(Dir, 'sub');
  TDirectory.CreateDirectory(Nested);
  Child := TPath.Combine(Nested, 'c.txt');
  try
    TFile.WriteAllText(Child, 'c', TEncoding.UTF8);
    Expect(TryReadFileAttrSnapshot(Dir, Snap, Err), 'read dir snapshot');
    Expect(Snap.Owner <> '', 'owner is non-empty');
    Expect(Snap.Owner <> '(unknown)', 'owner resolved');

    Plan := Default(TFileAttrPlan);
    Plan.Hidden := facSet;
    Plan.Recurse := True;
    ApplyFileAttrRoots(TArray<string>.Create(Dir), Plan, Ok, Fail, FirstPath, FirstErr);
    Expect(Fail = 0, 'recurse set Hidden: ' + FirstErr);
    Expect(HasBit(Dir, FILE_ATTRIBUTE_HIDDEN), 'dir hidden');
    Expect(HasBit(Nested, FILE_ATTRIBUTE_HIDDEN), 'subdir hidden');
    Expect(HasBit(Child, FILE_ATTRIBUTE_HIDDEN), 'child hidden');

    Plan := Default(TFileAttrPlan);
    Plan.Hidden := facClear;
    Plan.Recurse := True;
    ApplyFileAttrRoots(TArray<string>.Create(Dir), Plan, Ok, Fail, FirstPath, FirstErr);
    Expect(Fail = 0, 'recurse clear Hidden: ' + FirstErr);
    Expect(not HasBit(Child, FILE_ATTRIBUTE_HIDDEN), 'child unhidden');

    Plan := Default(TFileAttrPlan);
    Plan.ChangeOwner := True;
    Plan.Owner := Snap.Owner;
    ApplyFileAttrRoots(TArray<string>.Create(Child), Plan, Ok, Fail, FirstPath, FirstErr);
    Expect(Fail = 0, 'set current owner is no-op: ' + FirstErr);
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
  Expect(FormatFileAttrTime(0) = '', '0 formats as empty');
  Expect(TryParseFileAttrTime(FormatFileAttrTime(T), P) and SameDateTime(P, T),
    'format -> parse round-trip: ' + FormatFileAttrTime(T));
  Expect(TryParseFileAttrTime('  ' + FormatFileAttrTime(T) + ' ', P) and SameDateTime(P, T),
    'surrounding spaces are ignored');
  Expect(TryParseFileAttrTime(DateToStr(T) + ' ' + FormatDateTime('hh:nn', T), P) and
    SameDateTime(P, EncodeDateTime(2021, 3, 4, 5, 6, 0, 0)), 'seconds are optional');
  Expect(TryParseFileAttrTime(DateToStr(T), P) and SameDateTime(P, EncodeDate(2021, 3, 4)),
    'date alone means midnight');
  Expect(not TryParseFileAttrTime('', P), 'empty is not a date');
  Expect(not TryParseFileAttrTime('yesterday', P), 'garbage is not a date');
  Expect(not TryParseFileAttrTime(DateToStr(EncodeDate(1500, 1, 1)), P),
    'before 1601 cannot be a file time');
end;

procedure TestNoOpTimes;
var
  Plan: TFileAttrPlan;
begin
  Writeln('No-op plan with times');
  Plan := Default(TFileAttrPlan);
  Plan.Times.Modified := Now; // a value without its flag changes nothing
  Expect(FileAttrPlanIsNoOp(Plan), 'unflagged time is no-op');
  Plan.SetModified := True;
  Expect(not FileAttrPlanIsNoOp(Plan), 'SetModified is not no-op');
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
  Writeln('Apply times');
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

    Expect(TryReadFileAttrSnapshot(A, Before, Err), 'read times');
    Expect(Before.Times.Modified > 0, 'modified time is read');

    Plan := Default(TFileAttrPlan);
    Plan.SetCreated := True;
    Plan.Times.Created := Created;
    Plan.SetModified := True;
    Plan.Times.Modified := Modified;
    Expect(ApplyFileAttrPlan(A, Plan, Err), 'set created + modified: ' + Err);
    Expect(TryReadFileAttrSnapshot(A, Snap, Err), 're-read');
    Expect(SameSecond(Snap.Times.Created, Created), 'created written: ' +
      FormatFileAttrTime(Snap.Times.Created));
    Expect(SameSecond(Snap.Times.Modified, Modified), 'modified written: ' +
      FormatFileAttrTime(Snap.Times.Modified));
    Expect(SameSecond(PanelModified(A), Modified), 'the panel shows the same modified time');

    // Unflagged times are left alone.
    Plan := Default(TFileAttrPlan);
    Plan.SetAccessed := True;
    Plan.Times.Accessed := Created;
    Expect(ApplyFileAttrPlan(A, Plan, Err), 'set accessed only: ' + Err);
    Expect(TryReadFileAttrSnapshot(A, Snap, Err) and SameSecond(Snap.Times.Modified, Modified),
      'modified untouched when only accessed is set');

    // Read-only file: FILE_WRITE_ATTRIBUTES still allowed.
    SetFileAttributes(PChar(B), FILE_ATTRIBUTE_READONLY);
    Plan := Default(TFileAttrPlan);
    Plan.SetModified := True;
    Plan.Times.Modified := Modified;
    Expect(ApplyFileAttrPlan(B, Plan, Err), 'read-only file takes a new time: ' + Err);
    Expect(SameSecond(PanelModified(B), Modified), 'read-only file time written');

    // Same modified time on both -> shown; different -> empty (keep).
    State := BuildFileAttrDialogState(TArray<string>.Create(A, B));
    Expect(SameSecond(State.Times.Modified, Modified), 'equal times across items are shown');
    Expect(State.Times.Created = 0, 'different created times -> empty field');

    // Directory, recursively.
    Plan := Default(TFileAttrPlan);
    Plan.SetModified := True;
    Plan.Times.Modified := Created;
    Plan.Recurse := True;
    ApplyFileAttrRoots(TArray<string>.Create(Sub), Plan, Ok, Fail, FirstPath, FirstErr);
    Expect(Fail = 0, 'recurse set modified: ' + FirstErr);
    Expect(SameSecond(PanelModified(Sub), Created), 'folder time written');
    Expect(SameSecond(PanelModified(Child), Created), 'child time written');
  finally
    SetFileAttributes(PChar(B), FILE_ATTRIBUTE_NORMAL);
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

begin
  try
    TestTimeText;
    TestNoOpTimes;
    TestApplyTimes;
    TestChoiceIndex;
    TestNoOp;
    TestSetClearReadOnly;
    TestMergeMixed;
    TestRecurseAndOwner;
    Writeln('All WinFileAttr tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
