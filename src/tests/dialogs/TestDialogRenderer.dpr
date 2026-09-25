program TestDialogRenderer;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.UITypes,
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uDialogRenderer in '..\..\Core\uDialogRenderer.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function Joined(const ALines: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ALines) do
  begin
    if I > 0 then
      Result := Result + '|';
    Result := Result + ALines[I];
  end;
end;

procedure TestWrapLabelLines;
var
  Lines: TArray<string>;
  Msg: string;
  I: Integer;
begin
  Writeln('WrapLabelLines');
  Lines := TDialogRenderer.WrapLabelLines('', 78);
  Expect((Length(Lines) = 1) and (Lines[0] = ''), 'empty text is one blank line');

  Lines := TDialogRenderer.WrapLabelLines('hello', 78);
  Expect((Length(Lines) = 1) and (Lines[0] = 'hello'), 'short text stays one line');

  Lines := TDialogRenderer.WrapLabelLines('hello world', 5);
  Expect(Joined(Lines) = 'hello|world', 'wraps on space before width');

  Lines := TDialogRenderer.WrapLabelLines('abcdefghij', 4);
  Expect(Joined(Lines) = 'abcd|efgh|ij', 'hard-wraps a token longer than width');

  Lines := TDialogRenderer.WrapLabelLines('one' + #13#10 + 'two', 78);
  Expect(Joined(Lines) = 'one|two', 'CRLF is a hard break');

  Msg := 'The process cannot access the file because it is being used by another process.';
  Lines := TDialogRenderer.WrapLabelLines(Msg, 78);
  Expect(Length(Lines) >= 1, 'English sharing-violation message wraps to at least one line');
  for I := 0 to High(Lines) do
    Expect(Length(Lines[I]) <= 78, 'English wrap line fits in 78: "' + Lines[I] + '"');

  Msg := 'Процесс не может получить доступ к файлу, так как этот файл занят другим процессом.';
  Lines := TDialogRenderer.WrapLabelLines(Msg, 78);
  Expect(Length(Lines) >= 2, 'Russian sharing-violation message needs more than one 78-col line');
  for I := 0 to High(Lines) do
    Expect(Length(Lines[I]) <= 78, 'Russian wrap line fits in 78: "' + Lines[I] + '"');
  Expect(Pos('процессом', Lines[High(Lines)]) > 0,
    'last wrap line keeps the truncated tail of the OS message');
end;

procedure TestDrawLabelWraps;
var
  Grid: TTerminalGrid;
  Line0, Line1: string;
  X: Integer;
begin
  Writeln('DrawLabel');
  AllocTerminalGrid(Grid, 20, 3);
  ClearTerminalGrid(Grid, TAlphaColor($FFFFFFFF), TAlphaColor($FFAA0000), ' ');
  TDialogRenderer.DrawLabel(Grid, TRectI.Make(0, 0, 19, 1),
    'hello world from wrap', TAlphaColor($FFFFFFFF), TAlphaColor($FFAA0000));
  Line0 := '';
  Line1 := '';
  for X := 0 to 19 do
  begin
    Line0 := Line0 + Grid[0][X].CharValue;
    Line1 := Line1 + Grid[1][X].CharValue;
  end;
  Expect(Trim(Line0) <> '', 'first row has wrapped text');
  Expect(Trim(Line1) <> '', 'second row has the overflow, not a clipped tail');
  Expect(Pos('hello', Line0) > 0, 'first row starts with hello');
end;

begin
  try
    TestWrapLabelLines;
    TestDrawLabelWraps;
    Writeln('All DialogRenderer tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
