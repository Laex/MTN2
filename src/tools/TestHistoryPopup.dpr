program TestHistoryPopup;

{$APPTYPE CONSOLE}

{ THistoryPopup (command line / live filter / F7 history drop-down): where it
  opens, keys, Del, clicks, drawing; plus command-line Tab completion of
  disk paths (CmdLinePathCompletions). }

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils,
  uTerminalTypes, uThemeTypes, uHistoryPopup, uDualPanelCmd;

var
  Failed: Integer;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

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
  Writeln('Popup');
  P := THistoryPopup.Create;
  try
    Removed := '';
    P.OnRemove := procedure(S: string) begin Removed := S; end;

    P.Open([], '', 20, 10, 50, 80, 25);
    Expect(not P.Visible, 'no items: stays closed');

    P.Open(['dir', 'git status', 'make'], 'git status', 20, 10, 50, 80, 25);
    Expect(P.Visible and (P.Hover = 1), 'opens on the current entry');
    Expect((P.Bounds.Bottom = 19) and (P.Bounds.Height = 5), 'above the field, 3 rows + frame');
    Expect((P.Bounds.Left = 10) and (P.Bounds.Right = 50), 'as wide as the field');

    Expect(Key(P, vkDown, [], Picked) = hpkHandled, 'Down moves');
    Expect(Key(P, vkReturn, [], Picked) = hpkPicked, 'Enter picks');
    Expect((Picked = 'make') and not P.Visible, 'picked entry, list closed');

    P.Open(['a', 'b', 'c'], '', 20, 10, 50, 80, 25);
    Key(P, vkDelete, [], Picked);
    Expect((Removed = 'a') and (Length(P.Items) = 2) and P.Visible, 'Del removes and reports');
    Expect(Key(P, Ord('x'), [], Picked, 'x') = hpkPassOn, 'other key: pass on');
    Expect(not P.Visible, 'and closes the list');
    Expect(Key(P, vkDown, [], Picked) = hpkNotOpen, 'closed list ignores keys');

    P.Open(['a', 'b'], '', 20, 10, 50, 80, 25);
    Expect(Key(P, vkDown, [ssCtrl], Picked) = hpkHandled, 'Ctrl+Down again');
    Expect(not P.Visible, 'closes (toggle)');

    P.Open(['a', 'b'], '', 20, 10, 50, 80, 25);
    Expect(Key(P, vkEscape, [], Picked) = hpkHandled, 'Esc handled');
    Expect(not P.Visible, 'Esc closes');

    // No room above: opens below.
    P.Open(['a', 'b'], '', 1, 0, 20, 80, 25);
    Expect(P.Bounds.Top = 2, 'no room above -> below the field');

    // Long lists scroll; click picks the row under the mouse.
    SetLength(Items, 30);
    for I := 0 to High(Items) do
      Items[I] := 'cmd' + IntToStr(I);
    P.Open(Items, '', 20, 0, 40, 80, 25);
    Expect(P.Bounds.Height = cHistoryPopupMaxRows + 2, 'at most 12 rows');
    Key(P, vkEnd, [], Picked);
    Expect(P.Hover = 29, 'End');
    Expect(P.HandleClick(5, P.Bounds.Top + 1, Picked, Valid) and Valid and (Picked = 'cmd18'),
      'click on the first visible row after scrolling: ' + Picked);
    P.Open(Items, '', 20, 0, 40, 80, 25);
    Expect(not P.HandleClick(70, 2, Picked, Valid) and not Valid and not P.Visible,
      'click outside closes and is not consumed');

    SetLength(Grid, 25);
    for I := 0 to 24 do
      SetLength(Grid[I], 80);
    P.Open(['alpha', 'beta'], 'beta', 20, 10, 50, 80, 25);
    P.Draw(Grid, nil);
    Expect((Grid[P.Bounds.Top + 1][11].CharValue = 'a') and
      (Grid[P.Bounds.Top + 2][11].CharValue = 'b'), 'rows drawn inside the frame');
    Expect(Grid[P.Bounds.Top + 2][11].BgColor <> Grid[P.Bounds.Top + 1][11].BgColor,
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
  Writeln('Tab completion of disk paths');
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-cmdpath-test');
  if TDirectory.Exists(Dir) then
    TDirectory.Delete(Dir, True);
  ForceDirectories(TPath.Combine(Dir, 'src\Core'));
  ForceDirectories(TPath.Combine(Dir, 'Scripts'));
  TFile.WriteAllText(TPath.Combine(Dir, 'src\sample.txt'), '');
  TFile.WriteAllText(TPath.Combine(Dir, 'setup.exe'), '');
  try
    Expect(not CmdLineTokenIsPath('src'), 'bare name is not a path (panel names)');
    Expect(CmdLineTokenIsPath('src\') and CmdLineTokenIsPath('a/b') and CmdLineTokenIsPath('C:'),
      'separators and drive make a path');
    M := CmdLinePathCompletions('src\', Dir);
    Expect((Length(M) = 2) and (M[0] = 'src\Core') and (M[1] = 'src\sample.txt'),
      'relative folder, folders first: ' + string.Join(',', M));
    M := CmdLinePathCompletions('src\s', Dir);
    Expect((Length(M) = 1) and (M[0] = 'src\sample.txt'), 'prefix, case-insensitive');
    M := CmdLinePathCompletions('src/C', Dir);
    Expect((Length(M) = 1) and (M[0] = 'src/Core'), 'forward slash kept as typed');
    M := CmdLinePathCompletions(IncludeTrailingPathDelimiter(Dir) + 's', '');
    Expect((Length(M) = 3) and (M[0] = IncludeTrailingPathDelimiter(Dir) + 'Scripts'),
      'absolute path: ' + string.Join(',', M));
    M := CmdLinePathCompletions('nosuch\x', Dir);
    Expect(Length(M) = 0, 'missing folder -> nothing');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

begin
  Failed := 0;
  try
    TestPopup;
    TestPathCompletion;
    if Failed = 0 then
      Writeln('All HistoryPopup tests PASSED')
    else
    begin
      Writeln('FAILED: ', Failed, ' check(s)');
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
