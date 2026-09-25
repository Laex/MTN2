program TestFileCompare;

{$APPTYPE CONSOLE}

{ Stage 34: line-based text diff for Compare Files. }

uses
  System.SysUtils,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uTextEncoding in '..\Core\uTextEncoding.pas',
  uFileCompare in '..\Core\uFileCompare.pas';

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

function HasLine(const ALines: TArray<string>; const ANeedle: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(ALines) do
    if Pos(ANeedle, ALines[I]) > 0 then
      Exit(True);
  Result := False;
end;

procedure TestReplaceLine;
var
  Lines: TArray<string>;
  Changed: Integer;
begin
  Writeln('Replace a middle line');
  Lines := BuildTextDiff(
    'keep' + sLineBreak + 'old' + sLineBreak + 'tail',
    'keep' + sLineBreak + 'new' + sLineBreak + 'tail', Changed);
  Expect(Changed = 2, 'replace counts delete+insert');
  Expect(HasLine(Lines, '- old'), 'diff shows the left line');
  Expect(HasLine(Lines, '+ new'), 'diff shows the right line');
  Expect(HasLine(Lines, '  keep'), 'diff keeps unchanged context');
end;

procedure TestInsertAndDelete;
var
  Lines: TArray<string>;
  Changed: Integer;
begin
  Writeln('Insert and delete');
  Lines := BuildTextDiff(
    'a' + sLineBreak + 'gone' + sLineBreak + 'c',
    'a' + sLineBreak + 'c' + sLineBreak + 'added', Changed);
  Expect(HasLine(Lines, '- gone'), 'deleted line is marked');
  Expect(HasLine(Lines, '+ added'), 'inserted line is marked');
  Expect(Changed >= 2, 'at least two changed lines');
end;

procedure TestIdenticalText;
var
  Lines: TArray<string>;
  Changed: Integer;
begin
  Writeln('Identical text');
  Lines := BuildTextDiff('same' + sLineBreak + 'file', 'same' + sLineBreak + 'file',
    Changed);
  Expect(Changed = 0, 'identical text has 0 changed lines');
end;

procedure TestOffsetHelper;
var
  A, B: TBytes;
begin
  Writeln('Byte offset helper');
  SetLength(A, 3);
  SetLength(B, 3);
  A[0] := 1; A[1] := 2; A[2] := 3;
  B[0] := 1; B[1] := 9; B[2] := 3;
  Expect(FirstByteDiffOffset(A, B) = 1, 'first differing byte is offset 1');
  B[1] := 2;
  Expect(FirstByteDiffOffset(A, B) = -1, 'equal buffers report -1');
end;

begin
  Failed := 0;
  try
    TestReplaceLine;
    TestInsertAndDelete;
    TestIdenticalText;
    TestOffsetHelper;
    if Failed = 0 then
      Writeln('All FileCompare tests PASSED')
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
