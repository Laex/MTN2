unit TestInputLineControlChars;

{ A control character in an input field is drawn as a dot in the middle of its
  cell, so that a tab or a line break in a path or a name can be seen. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInputLineControlChars = class
  public
    [Test] procedure TestControlCharactersAreDots;
    [Test] procedure TestOrdinaryTextIsUntouched;
    [Test] procedure TestOuterSpacesAreDots;
    [Test] procedure TestNonLatinTextIsUntouched;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.UITypes, uTerminalTypes, uInputLine;

function DrawRow(const AText: string; AWidth: Integer): string;
var
  Grid: TTerminalGrid;
  Line: TInputLine;
  X: Integer;
begin
  SetLength(Grid, 1);
  SetLength(Grid[0], AWidth);
  for X := 0 to AWidth - 1 do
    Grid[0][X] := TCharCell.Make(' ', TAlphaColor($FF000000), TAlphaColor($FF00AAAA));
  Line := InputLineEmpty;
  InputLineSetText(Line, AText);
  InputLineDraw(Grid, 0, 0, AWidth, Line, False,
    InputLineDialogColors(False), False, False);
  Result := '';
  for X := 0 to AWidth - 1 do
    Result := Result + Grid[0][X].CharValue;
end;

function CodesOf(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    Result := Result + IfThen(I > 1, ' ', '') + IntToHex(Ord(S[I]), 4);
end;

procedure TTestInputLineControlChars.TestControlCharactersAreDots;
begin
  Assert.AreEqual('a' + #$00B7 + 'b' + #$00B7 + 'c ', DrawRow('a'#9'b'#10'c', 6));
  Assert.AreEqual(#$00B7 + #$00B7 + '  ', DrawRow(#0#$7F, 4));
end;

procedure TTestInputLineControlChars.TestOrdinaryTextIsUntouched;
begin
  Assert.AreEqual('C:\My dir\a.txt ', DrawRow('C:\My dir\a.txt', 15 + 1));
end;

procedure TTestInputLineControlChars.TestOuterSpacesAreDots;
begin
  Assert.AreEqual(#$00B7 + #$00B7 + 'a b' + #$00B7 + '  ', DrawRow('  a b ', 8));
  Assert.AreEqual(#$00B7 + #$00B7 + #$00B7 + ' ', DrawRow('   ', 4));
end;

procedure TTestInputLineControlChars.TestNonLatinTextIsUntouched;
begin
  Assert.AreEqual('041F 0435 0440 0020 0412 0020', CodesOf(DrawRow(#$041F#$0435#$0440 + ' ' + #$0412, 6)));
end;

end.
