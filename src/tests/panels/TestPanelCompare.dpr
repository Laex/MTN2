program TestPanelCompare;

{$APPTYPE CONSOLE}

{ Compare folders (Ctrl+Shift+C): which rows of the two panels get
  selected. Pure row logic -- no files are touched. }

uses
  System.SysUtils,
  System.DateUtils,
  uDualPanelTypes,
  uPanelCompare;

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

function Row(const AName: string; ASize: Int64; const ATime: TDateTime;
  AIsDir: Boolean = False; const ASideTag: string = 'L'): TPanelRow;
begin
  Result := MakePanelRow(AName, AIsDir, ASize);
  Result.URI := 'file:///' + ASideTag + '/' + AName;
  Result.ModificationTime := ATime;
end;

function Parent: TPanelRow;
begin
  Result := MakePanelRow('..', True, -1, '', '', 'file:///', True);
end;

function Has(const AList: TArray<string>; const AURI: string): Boolean;
var
  S: string;
begin
  for S in AList do
    if S = AURI then
      Exit(True);
  Result := False;
end;

var
  T0, T1: TDateTime;
  Left, Right: TPanelRows;
  Res: TPanelCompareResult;
begin
  Failed := 0;
  try
    T0 := EncodeDateTime(2025, 1, 1, 12, 0, 0, 0);
    T1 := IncHour(T0, 1);

    Left := [Parent,
      Row('only-left.txt', 10, T0),
      Row('newer-left.txt', 10, T1),
      Row('older-left.txt', 10, T0),
      Row('same.txt', 10, T0),
      Row('size-differs.txt', 10, T0),
      Row('fat-time.txt', 10, T0),
      Row('Case.TXT', 10, T0),
      Row('dir-left', -1, T0, True),
      Row('dir-both', -1, T0, True),
      Row('file-vs-dir', 10, T1)];
    Right := [Parent,
      Row('only-right.txt', 10, T0, False, 'R'),
      Row('newer-left.txt', 10, T0, False, 'R'),
      Row('older-left.txt', 10, T1, False, 'R'),
      Row('same.txt', 10, T0, False, 'R'),
      Row('size-differs.txt', 20, T0, False, 'R'),
      Row('fat-time.txt', 10, IncSecond(T0, 2), False, 'R'),
      Row('case.txt', 10, T0, False, 'R'),
      Row('dir-right/', -1, T0, True, 'R'),
      Row('dir-both/', -1, T1, True, 'R'),
      Row('file-vs-dir', -1, T0, True, 'R')];
    Res := ComparePanelRows(Left, Right);

    Expect(Has(Res.LeftUris, 'file:///L/only-left.txt'), 'file only on the left is selected');
    Expect(Has(Res.RightUris, 'file:///R/only-right.txt'), 'file only on the right is selected');
    Expect(Has(Res.LeftUris, 'file:///L/newer-left.txt') and
      not Has(Res.RightUris, 'file:///R/newer-left.txt'), 'newer side only');
    Expect(Has(Res.RightUris, 'file:///R/older-left.txt') and
      not Has(Res.LeftUris, 'file:///L/older-left.txt'), 'newer right side only');
    Expect(not Has(Res.LeftUris, 'file:///L/same.txt') and
      not Has(Res.RightUris, 'file:///R/same.txt'), 'equal files are not selected');
    Expect(Has(Res.LeftUris, 'file:///L/size-differs.txt') and
      Has(Res.RightUris, 'file:///R/size-differs.txt'), 'same time, other size: both');
    Expect(not Has(Res.LeftUris, 'file:///L/fat-time.txt') and
      not Has(Res.RightUris, 'file:///R/fat-time.txt'), '2 s apart counts as the same time (FAT)');
    Expect(not Has(Res.LeftUris, 'file:///L/Case.TXT') and
      not Has(Res.RightUris, 'file:///R/case.txt'), 'names compare case-insensitively');
    Expect(Has(Res.LeftUris, 'file:///L/dir-left'), 'folder only on the left is selected');
    Expect(Has(Res.RightUris, 'file:///R/dir-right/'), 'folder only on the right (trailing /) is selected');
    Expect(not Has(Res.LeftUris, 'file:///L/dir-both') and
      not Has(Res.RightUris, 'file:///R/dir-both/'), 'folders on both sides: never by time');
    Expect(not Has(Res.LeftUris, 'file:///L/file-vs-dir') and
      not Has(Res.RightUris, 'file:///R/file-vs-dir'), 'file against folder of the same name: left alone');
    Expect(Length(Res.LeftUris) = 4, Format('left count = 4 (%d)', [Length(Res.LeftUris)]));
    Expect(Length(Res.RightUris) = 4, Format('right count = 4 (%d)', [Length(Res.RightUris)]));

    Res := ComparePanelRows([Parent, Row('a.txt', 1, T0)],
      [Parent, Row('a.txt', 1, T0, False, 'R')]);
    Expect((Length(Res.LeftUris) = 0) and (Length(Res.RightUris) = 0),
      'identical folders: nothing selected, ".." never');

    // VFS without times (0): only presence and size count.
    Res := ComparePanelRows([Row('a', 5, 0), Row('b', 5, 0)],
      [Row('a', 5, T1, False, 'R'), Row('b', 6, 0, False, 'R')]);
    Expect((Length(Res.LeftUris) = 1) and Has(Res.LeftUris, 'file:///L/b') and
      Has(Res.RightUris, 'file:///R/b'), 'no time: size decides');

    Res := ComparePanelRows([Row('x', 1, T0), Row('X', 1, T1)], []);
    Expect(Length(Res.LeftUris) = 2, 'same-name duplicates (flat view) are both unique');

    if Failed = 0 then
      Writeln('All PanelCompare tests PASSED')
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
