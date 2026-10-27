unit uDatePickerControl;

{ State, drawing and input of the date picker dialog control (dckDatePicker,
  TDialogHost): a month calendar.

    line 0       "<<  <  October 2026  >  >>": year and month steps
    line 1       the weekday names, the week starts on Monday
    lines 2..7   the days of the month, six weeks

  Left / Right move the day by one, Up / Down by a week, PgUp / PgDn by a
  month, Ctrl+PgUp / Ctrl+PgDn by a year, Home / End to the first / last day
  of the month. A mouse click on a day selects it, on the header steps the
  month or the year. The time of day is not part of the control. }

interface

uses
  System.Classes, System.UITypes,
  uTerminalTypes;

const
  cCalendarWidth = 22;
  cCalendarHeight = 8;

type
  TDatePickerState = record
    Year, Month, Day: Integer;
  end;

function DatePickerEmpty: TDatePickerState;
/// <summary>Starts on the date part of ADate; 0 means today.</summary>
procedure DatePickerInit(var S: TDatePickerState; ADate: TDateTime);
function DatePickerDate(const S: TDatePickerState): TDateTime;
/// <summary>Moves to ADate, kept inside the range a file time can hold.</summary>
procedure DatePickerSetDate(var S: TDatePickerState; ADate: TDateTime);

/// <summary>Draws the control into the cCalendarWidth x cCalendarHeight cells at (ALeft, ATop).</summary>
procedure DatePickerDraw(const AGrid: TTerminalGrid; ALeft, ATop: Integer;
  const S: TDatePickerState; ALabelFg, ALabelBg: TAlphaColor);
/// <summary>True when the key was used (Tab and the dialog keys are not).</summary>
function DatePickerHandleKey(var S: TDatePickerState; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
/// <summary>ARelCol / ARelRow are relative to the control's top-left cell.</summary>
function DatePickerClick(var S: TDatePickerState; ARelCol, ARelRow: Integer): Boolean;

implementation

uses
  System.SysUtils, System.DateUtils, System.Math;

const
  cDayCellW = 3;
  cFirstDayRow = 2;

function MinDate: TDateTime;
begin
  Result := EncodeDate(1601, 1, 2);
end;

function MaxDate: TDateTime;
begin
  Result := EncodeDate(9999, 12, 30);
end;

// IncYear / IncMonth raise past the last representable year.
function StepYears(ADate: TDateTime; AYears: Integer): TDateTime;
begin
  try
    Result := IncYear(ADate, AYears);
  except
    on EConvertError do
      Result := ADate;
  end;
end;

function StepMonths(ADate: TDateTime; AMonths: Integer): TDateTime;
begin
  try
    Result := IncMonth(ADate, AMonths);
  except
    on EConvertError do
      Result := ADate;
  end;
end;

function DatePickerEmpty: TDatePickerState;
begin
  Result := Default(TDatePickerState);
  DatePickerInit(Result, 0);
end;

procedure DatePickerSetDate(var S: TDatePickerState; ADate: TDateTime);
var
  D: TDateTime;
begin
  D := EnsureRange(Trunc(ADate), Trunc(MinDate), Trunc(MaxDate));
  S.Year := YearOf(D);
  S.Month := MonthOf(D);
  S.Day := DayOf(D);
end;

procedure DatePickerInit(var S: TDatePickerState; ADate: TDateTime);
begin
  if ADate = 0 then
    ADate := Date;
  DatePickerSetDate(S, ADate);
end;

function DatePickerDate(const S: TDatePickerState): TDateTime;
begin
  Result := EncodeDate(S.Year, S.Month, S.Day);
end;

// Monday-based column (0..6) of the first day of the month.
function FirstColumn(const S: TDatePickerState): Integer;
begin
  Result := (DayOfWeek(EncodeDate(S.Year, S.Month, 1)) + 5) mod 7;
end;

function WeekdayName(ACol: Integer): string;
begin
  Result := Copy(FormatSettings.ShortDayNames[(ACol + 1) mod 7 + 1], 1, 2);
end;

procedure DatePickerDraw(const AGrid: TTerminalGrid; ALeft, ATop: Integer;
  const S: TDatePickerState; ALabelFg, ALabelBg: TAlphaColor);
var
  I, Pos, Row, Col, DaysIn: Integer;
  Title, Text: string;
  Today: TDateTime;
  Attrs: TCharCellAttributes;
begin
  FillGridRect(AGrid, ALeft, ATop, ALeft + cCalendarWidth - 1,
    ATop + cCalendarHeight - 1, ' ', ALabelFg, ALabelBg);
  PutGridText(AGrid, ALeft, ATop, '<<', ALabelFg, ALabelBg);
  PutGridText(AGrid, ALeft + 3, ATop, '<', ALabelFg, ALabelBg);
  PutGridText(AGrid, ALeft + 18, ATop, '>', ALabelFg, ALabelBg);
  PutGridText(AGrid, ALeft + 20, ATop, '>>', ALabelFg, ALabelBg);
  Title := Format('%s %d', [FormatSettings.LongMonthNames[S.Month], S.Year]);
  if Length(Title) > 12 then
    Title := Copy(Title, 1, 12);
  PutGridText(AGrid, ALeft + 5 + (12 - Length(Title)) div 2, ATop, Title,
    ALabelFg, ALabelBg, [ccaBold]);
  for I := 0 to 6 do
    PutGridText(AGrid, ALeft + I * cDayCellW + 1, ATop + 1, WeekdayName(I),
      ALabelFg, ALabelBg, [ccaBold]);

  DaysIn := DaysInAMonth(S.Year, S.Month);
  Today := Date;
  for I := 1 to DaysIn do
  begin
    Pos := FirstColumn(S) + I - 1;
    Row := ATop + cFirstDayRow + Pos div 7;
    Col := ALeft + (Pos mod 7) * cDayCellW + 1;
    Text := Format('%2d', [I]);
    Attrs := [];
    if (S.Year = YearOf(Today)) and (S.Month = MonthOf(Today)) and (I = DayOf(Today)) then
      Attrs := [ccaBold];
    if I = S.Day then
      PutGridText(AGrid, Col, Row, Text, ALabelBg, ALabelFg, Attrs)
    else
      PutGridText(AGrid, Col, Row, Text, ALabelFg, ALabelBg, Attrs);
  end;
end;

function DatePickerHandleKey(var S: TDatePickerState; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  D: TDateTime;
begin
  Result := False;
  if AKey = vkTab then
    Exit;
  D := DatePickerDate(S);
  case AKey of
    vkLeft: D := D - 1;
    vkRight: D := D + 1;
    vkUp: D := D - 7;
    vkDown: D := D + 7;
    vkPrior:
      if ssCtrl in AShift then
        D := StepYears(D, -1)
      else
        D := StepMonths(D, -1);
    vkNext:
      if ssCtrl in AShift then
        D := StepYears(D, 1)
      else
        D := StepMonths(D, 1);
    vkHome: D := EncodeDate(S.Year, S.Month, 1);
    vkEnd: D := EncodeDate(S.Year, S.Month, DaysInAMonth(S.Year, S.Month));
  else
    Exit;
  end;
  DatePickerSetDate(S, D);
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

function DatePickerClick(var S: TDatePickerState; ARelCol, ARelRow: Integer): Boolean;
var
  D: TDateTime;
  Pos, Day: Integer;
begin
  Result := False;
  if (ARelCol < 0) or (ARelCol >= cCalendarWidth) or (ARelRow < 0) or
     (ARelRow >= cCalendarHeight) then
    Exit;
  D := DatePickerDate(S);
  if ARelRow = 0 then
  begin
    if ARelCol < 2 then
      D := StepYears(D, -1)
    else if ARelCol < 5 then
      D := StepMonths(D, -1)
    else if ARelCol >= 20 then
      D := StepYears(D, 1)
    else if ARelCol >= 17 then
      D := StepMonths(D, 1)
    else
      Exit(True);
    DatePickerSetDate(S, D);
    Exit(True);
  end;
  if ARelRow >= cFirstDayRow then
  begin
    Pos := (ARelRow - cFirstDayRow) * 7 + ARelCol div cDayCellW;
    Day := Pos - FirstColumn(S) + 1;
    if (Day >= 1) and (Day <= DaysInAMonth(S.Year, S.Month)) then
      S.Day := Day;
  end;
  Result := True;
end;

end.
