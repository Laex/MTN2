unit TestDatePickerControl;

{ uDatePickerControl: the month calendar's keys, clicks and date range. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDatePickerControl = class
  public
    [Test] procedure TestInit;
    [Test] procedure TestKeys;
    [Test] procedure TestClicks;
    [Test] procedure TestRange;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDatePickerControl;

procedure PressKey(var S: TDatePickerState; AKey: Word; AShift: TShiftState = []);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := #0;
  DatePickerHandleKey(S, K, AShift, Ch);
end;

procedure TTestDatePickerControl.TestInit;
var
  S: TDatePickerState;
begin
  DatePickerInit(S, EncodeDate(2026, 10, 27) + 0.5);
  Assert.AreEqual(EncodeDate(2026, 10, 27), DatePickerDate(S), 'the time of day is dropped');
  DatePickerInit(S, 0);
  Assert.AreEqual(Trunc(Date), Trunc(DatePickerDate(S)), '0 means today');
end;

procedure TTestDatePickerControl.TestKeys;
var
  S: TDatePickerState;
begin
  DatePickerInit(S, EncodeDate(2026, 1, 31));
  PressKey(S, vkRight);
  Assert.AreEqual(EncodeDate(2026, 2, 1), DatePickerDate(S), 'Right crosses a month');
  PressKey(S, vkDown);
  Assert.AreEqual(EncodeDate(2026, 2, 8), DatePickerDate(S), 'Down is a week');
  PressKey(S, vkUp);
  PressKey(S, vkLeft);
  Assert.AreEqual(EncodeDate(2026, 1, 31), DatePickerDate(S), 'Up and Left step back');
  PressKey(S, vkNext);
  Assert.AreEqual(EncodeDate(2026, 2, 28), DatePickerDate(S), 'PgDn keeps the day inside a shorter month');
  PressKey(S, vkPrior, [ssCtrl]);
  Assert.AreEqual(EncodeDate(2025, 2, 28), DatePickerDate(S), 'Ctrl+PgUp is a year');
  PressKey(S, vkHome);
  Assert.AreEqual(EncodeDate(2025, 2, 1), DatePickerDate(S), 'Home is the first day');
  PressKey(S, vkEnd);
  Assert.AreEqual(EncodeDate(2025, 2, 28), DatePickerDate(S), 'End is the last day');
end;

procedure TTestDatePickerControl.TestClicks;
var
  S: TDatePickerState;
begin
  // October 2026 starts on a Thursday: the first week row has 3 blank cells.
  DatePickerInit(S, EncodeDate(2026, 10, 27));
  Assert.IsTrue(DatePickerClick(S, 3 * 3 + 1, 2), 'a click inside the grid is used');
  Assert.AreEqual(EncodeDate(2026, 10, 1), DatePickerDate(S), 'Thursday of the first week is the 1st');
  DatePickerClick(S, 0, 3);
  Assert.AreEqual(EncodeDate(2026, 10, 5), DatePickerDate(S), 'Monday of the second week is the 5th');
  DatePickerClick(S, 0, 2);
  Assert.AreEqual(EncodeDate(2026, 10, 5), DatePickerDate(S), 'a blank cell keeps the date');
  DatePickerClick(S, 18, 0);
  Assert.AreEqual(EncodeDate(2026, 11, 5), DatePickerDate(S), '> is the next month');
  DatePickerClick(S, 3, 0);
  Assert.AreEqual(EncodeDate(2026, 10, 5), DatePickerDate(S), '< is the previous month');
  DatePickerClick(S, 21, 0);
  Assert.AreEqual(EncodeDate(2027, 10, 5), DatePickerDate(S), '>> is the next year');
  DatePickerClick(S, 0, 0);
  Assert.AreEqual(EncodeDate(2026, 10, 5), DatePickerDate(S), '<< is the previous year');
  Assert.IsFalse(DatePickerClick(S, 30, 3), 'outside the control');
end;

procedure TTestDatePickerControl.TestRange;
var
  S: TDatePickerState;
begin
  DatePickerSetDate(S, EncodeDate(1500, 1, 1));
  Assert.IsTrue(DatePickerDate(S) >= EncodeDate(1601, 1, 1), 'before the file time epoch is clamped');
  DatePickerSetDate(S, EncodeDate(9999, 12, 31));
  Assert.IsTrue(DatePickerDate(S) <= EncodeDate(9999, 12, 31), 'the last year is clamped');
  PressKey(S, vkNext, [ssCtrl]);
  Assert.IsTrue(DatePickerDate(S) <= EncodeDate(9999, 12, 31), 'stepping past the end stays in range');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDatePickerControl);

end.
