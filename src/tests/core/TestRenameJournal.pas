unit TestRenameJournal;

{ uRenameJournal: the journal survives a reload, and the undo plan only
  reverses pairs whose new name exists and whose original name is free. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRenameJournal = class
  public
    [Test] procedure JournalRoundTripsPairs;
    [Test] procedure MissingJournalLoadsNothing;
    [Test] procedure ClearRemovesJournal;
    [Test] procedure UndoReversesPlainRename;
    [Test] procedure UndoSkipsPairWhoseNewNameIsGone;
    [Test] procedure UndoSkipsPairWhoseOldNameIsTaken;
    [Test] procedure UndoOrdersChainSoNoNameIsTaken;
    [Test] procedure UndoLeavesSwapAlone;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, uRenameJournal;

function ExistsIn(const ANames: array of string): TFunc<string, Boolean>;
var
  Set_: TArray<string>;
  I: Integer;
begin
  SetLength(Set_, Length(ANames));
  for I := 0 to High(ANames) do
    Set_[I] := ANames[I];
  Result :=
    function(APath: string): Boolean
    var
      S: string;
    begin
      for S in Set_ do
        if SameText(S, APath) then
          Exit(True);
      Result := False;
    end;
end;

function TempJournal: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-renamelog-test.json');
end;

procedure TTestRenameJournal.JournalRoundTripsPairs;
var
  S, D: TArray<string>;
begin
  SaveRenameJournal(TempJournal, ['C:\x\a.txt', 'C:\x\caf' + #$E9 + '.txt'], ['C:\x\b.txt', 'C:\x\c d.txt']);
  try
    Assert.IsTrue(LoadRenameJournal(TempJournal, S, D));
    Assert.AreEqual(2, Integer(Length(S)));
    Assert.AreEqual('C:\x\a.txt', S[0]);
    Assert.AreEqual('C:\x\c d.txt', D[1]);
  finally
    ClearRenameJournal(TempJournal);
  end;
end;

procedure TTestRenameJournal.MissingJournalLoadsNothing;
var
  S, D: TArray<string>;
begin
  ClearRenameJournal(TempJournal);
  Assert.IsFalse(LoadRenameJournal(TempJournal, S, D));
  Assert.AreEqual(0, Integer(Length(S)));
end;

procedure TTestRenameJournal.ClearRemovesJournal;
var
  S, D: TArray<string>;
begin
  SaveRenameJournal(TempJournal, ['a'], ['b']);
  ClearRenameJournal(TempJournal);
  Assert.IsFalse(LoadRenameJournal(TempJournal, S, D));
end;

procedure TTestRenameJournal.UndoReversesPlainRename;
var
  F, T: TArray<string>;
  Skipped: Integer;
begin
  Skipped := PlanRenameUndo(['a', 'b'], ['a2', 'b2'], ExistsIn(['a2', 'b2']), F, T);
  Assert.AreEqual(0, Skipped);
  Assert.AreEqual(2, Integer(Length(F)));
  Assert.AreEqual('a2', F[0]);
  Assert.AreEqual('a', T[0]);
  Assert.AreEqual('b2', F[1]);
  Assert.AreEqual('b', T[1]);
end;

procedure TTestRenameJournal.UndoSkipsPairWhoseNewNameIsGone;
var
  F, T: TArray<string>;
  Skipped: Integer;
begin
  Skipped := PlanRenameUndo(['a', 'b'], ['a2', 'b2'], ExistsIn(['b2']), F, T);
  Assert.AreEqual(1, Skipped);
  Assert.AreEqual(1, Integer(Length(F)));
  Assert.AreEqual('b2', F[0]);
end;

procedure TTestRenameJournal.UndoSkipsPairWhoseOldNameIsTaken;
var
  F, T: TArray<string>;
  Skipped: Integer;
begin
  Skipped := PlanRenameUndo(['a', 'b'], ['a2', 'b2'], ExistsIn(['a', 'a2', 'b2']), F, T);
  Assert.AreEqual(1, Skipped);
  Assert.AreEqual(1, Integer(Length(F)));
  Assert.AreEqual('b2', F[0]);
end;

procedure TTestRenameJournal.UndoOrdersChainSoNoNameIsTaken;
var
  F, T: TArray<string>;
  Skipped: Integer;
begin
  // a -> b and b -> c: afterwards b (formerly a) and c (formerly b) exist.
  Skipped := PlanRenameUndo(['a', 'b'], ['b', 'c'], ExistsIn(['b', 'c']), F, T);
  Assert.AreEqual(0, Skipped);
  Assert.AreEqual(2, Integer(Length(F)));
  Assert.AreEqual('b', F[0], 'the older name goes back first');
  Assert.AreEqual('a', T[0]);
  Assert.AreEqual('c', F[1]);
  Assert.AreEqual('b', T[1]);
end;

procedure TTestRenameJournal.UndoLeavesSwapAlone;
var
  F, T: TArray<string>;
  Skipped: Integer;
begin
  // a <-> b: every original name is taken, so nothing can move without a temp name.
  Skipped := PlanRenameUndo(['a', 'b'], ['b', 'a'], ExistsIn(['a', 'b']), F, T);
  Assert.AreEqual(2, Skipped);
  Assert.AreEqual(0, Integer(Length(F)));
end;

end.
