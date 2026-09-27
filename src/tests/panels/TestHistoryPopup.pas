unit TestHistoryPopup;

{ THistoryPopup (command line / live filter / F7 history drop-down): where it
  opens, keys, Del, clicks, drawing; plus command-line Tab completion of
  disk paths (CmdLinePathCompletions). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHistoryPopup = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestPopup;
    [Test] procedure TestPathCompletion;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils,
  uTerminalTypes, uThemeTypes, uHistoryPopup, uDualPanelCmd;

function Key(P: THistoryPopup; AKey: Word; AShift: TShiftState; out APicked: string;
  AChar: Char = #0): THistoryPopupKeyResult;
begin
  Result := P.HandleKey(AKey, AShift, AChar, APicked);
end;

procedure TestPopup;
var
  P: THistoryPopup;
  Picked, Removed: string;
  Valid: Boolean;
  Items: TArray<string>;
  I: Integer;
  Grid: TTerminalGrid;
begin
  P := THistoryPopup.Create;
  try
    Removed := '';
    P.OnRemove := procedure(S: string) begin Removed := S; end;

    P.Open([], '', 20, 10, 50, 80, 25);
    Assert.IsTrue(not P.Visible, 'no items: stays closed');

    P.Open(['dir', 'git status', 'make'], 'git status', 20, 10, 50, 80, 25);
    Assert.IsTrue(P.Visible and (P.Hover = 1), 'opens on the current entry');
    Assert.IsTrue((P.Bounds.Bottom = 19) and (P.Bounds.Height = 5), 'above the field, 3 rows + frame');
    Assert.IsTrue((P.Bounds.Left = 10) and (P.Bounds.Right = 50), 'as wide as the field');

    Assert.IsTrue(Key(P, vkDown, [], Picked) = hpkHandled, 'Down moves');
    Assert.IsTrue(Key(P, vkReturn, [], Picked) = hpkPicked, 'Enter picks');
    Assert.IsTrue((Picked = 'make') and not P.Visible, 'picked entry, list closed');

    P.Open(['a', 'b', 'c'], '', 20, 10, 50, 80, 25);
    Key(P, vkDelete, [], Picked);
    Assert.IsTrue((Removed = 'a') and (Length(P.Items) = 2) and P.Visible, 'Del removes and reports');
    Assert.IsTrue(Key(P, Ord('x'), [], Picked, 'x') = hpkPassOn, 'other key: pass on');
    Assert.IsTrue(not P.Visible, 'and closes the list');
    Assert.IsTrue(Key(P, vkDown, [], Picked) = hpkNotOpen, 'closed list ignores keys');

    P.Open(['a', 'b'], '', 20, 10, 50, 80, 25);
    Assert.IsTrue(Key(P, vkDown, [ssCtrl], Picked) = hpkHandled, 'Ctrl+Down again');
    Assert.IsTrue(not P.Visible, 'closes (toggle)');

    P.Open(['a', 'b'], '', 20, 10, 50, 80, 25);
    Assert.IsTrue(Key(P, vkEscape, [], Picked) = hpkHandled, 'Esc handled');
    Assert.IsTrue(not P.Visible, 'Esc closes');

    // No room above: opens below.
    P.Open(['a', 'b'], '', 1, 0, 20, 80, 25);
    Assert.IsTrue(P.Bounds.Top = 2, 'no room above -> below the field');

    // Long lists scroll; click picks the row under the mouse.
    SetLength(Items, 30);
    for I := 0 to High(Items) do
      Items[I] := 'cmd' + IntToStr(I);
    P.Open(Items, '', 20, 0, 40, 80, 25);
    Assert.IsTrue(P.Bounds.Height = cHistoryPopupMaxRows + 2, 'at most 12 rows');
    Key(P, vkEnd, [], Picked);
    Assert.IsTrue(P.Hover = 29, 'End');
    Assert.IsTrue(P.HandleClick(5, P.Bounds.Top + 1, Picked, Valid) and Valid and (Picked = 'cmd18'),
      'click on the first visible row after scrolling: ' + Picked);
    P.Open(Items, '', 20, 0, 40, 80, 25);
    Assert.IsTrue(not P.HandleClick(70, 2, Picked, Valid) and not Valid and not P.Visible,
      'click outside closes and is not consumed');

    SetLength(Grid, 25);
    for I := 0 to 24 do
      SetLength(Grid[I], 80);
    P.Open(['alpha', 'beta'], 'beta', 20, 10, 50, 80, 25);
    P.Draw(Grid, nil);
    Assert.IsTrue((Grid[P.Bounds.Top + 1][11].CharValue = 'a') and
      (Grid[P.Bounds.Top + 2][11].CharValue = 'b'), 'rows drawn inside the frame');
    Assert.IsTrue(Grid[P.Bounds.Top + 2][11].BgColor <> Grid[P.Bounds.Top + 1][11].BgColor,
      'hovered row highlighted');
  finally
    P.Free;
  end;
end;

procedure TestPathCompletion;
var
  Dir: string;
  M: TArray<string>;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-cmdpath-test');
  if TDirectory.Exists(Dir) then
    TDirectory.Delete(Dir, True);
  ForceDirectories(TPath.Combine(Dir, 'src\Core'));
  ForceDirectories(TPath.Combine(Dir, 'Scripts'));
  TFile.WriteAllText(TPath.Combine(Dir, 'src\sample.txt'), '');
  TFile.WriteAllText(TPath.Combine(Dir, 'setup.exe'), '');
  try
    Assert.IsTrue(not CmdLineTokenIsPath('src'), 'bare name is not a path (panel names)');
    Assert.IsTrue(CmdLineTokenIsPath('src\') and CmdLineTokenIsPath('a/b') and CmdLineTokenIsPath('C:'),
      'separators and drive make a path');
    M := CmdLinePathCompletions('src\', Dir);
    Assert.IsTrue((Length(M) = 2) and (M[0] = 'src\Core') and (M[1] = 'src\sample.txt'),
      'relative folder, folders first: ' + string.Join(',', M));
    M := CmdLinePathCompletions('src\s', Dir);
    Assert.IsTrue((Length(M) = 1) and (M[0] = 'src\sample.txt'), 'prefix, case-insensitive');
    M := CmdLinePathCompletions('src/C', Dir);
    Assert.IsTrue((Length(M) = 1) and (M[0] = 'src/Core'), 'forward slash kept as typed');
    M := CmdLinePathCompletions(IncludeTrailingPathDelimiter(Dir) + 's', '');
    Assert.IsTrue((Length(M) = 3) and (M[0] = IncludeTrailingPathDelimiter(Dir) + 'Scripts'),
      'absolute path: ' + string.Join(',', M));
    M := CmdLinePathCompletions('nosuch\x', Dir);
    Assert.IsTrue(Length(M) = 0, 'missing folder -> nothing');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ TTestHistoryPopup }

procedure TTestHistoryPopup.SetupFixture;
begin
end;

procedure TTestHistoryPopup.TestPopup;
begin
  TestHistoryPopup.TestPopup;
end;

procedure TTestHistoryPopup.TestPathCompletion;
begin
  TestHistoryPopup.TestPathCompletion;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHistoryPopup);

end.
