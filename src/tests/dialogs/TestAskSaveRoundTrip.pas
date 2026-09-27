unit TestAskSaveRoundTrip;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAskSaveRoundTrip = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils,
  uDialogTypes,
  uDialogJson,
  uDialogResources,
  uInputLine,
  uTerminalTypes,
  uTextEncoding;
var
  D1, D2: TDialogDeclaration;
  J: string;
  I: Integer;

{ TTestAskSaveRoundTrip }

procedure TTestAskSaveRoundTrip.Run;
begin
  D1 := BuildAskSaveDialog('test.txt');
  System.Writeln('v1 name=', D1.Title, ' ver=', D1.Version, ' n=', Length(D1.Controls));
  for I := 0 to High(D1.Controls) do
    System.Writeln(Format('  %d kind=%d id=%s def=%s can=%s col=%d row=%d w=%d',
      [I, Ord(D1.Controls[I].Kind), D1.Controls[I].Id,
       BoolToStr(D1.Controls[I].IsDefault, True),
       BoolToStr(D1.Controls[I].IsCancel, True),
       D1.Controls[I].Col, D1.Controls[I].Row, D1.Controls[I].BoxW]));
  J := DeclarationToJson(D1);
  System.Writeln('JSON=', Copy(J, 1, 400));
  Assert.IsTrue(TryParseDialogJson(J, D2), 'serialized dialog parses back');
  System.Writeln('v2 n=', Length(D2.Controls), ' ver=', D2.Version);
  for I := 0 to High(D2.Controls) do
    System.Writeln(Format('  %d kind=%d id=%s def=%s can=%s col=%d row=%d w=%d',
      [I, Ord(D2.Controls[I].Kind), D2.Controls[I].Id,
       BoolToStr(D2.Controls[I].IsDefault, True),
       BoolToStr(D2.Controls[I].IsCancel, True),
       D2.Controls[I].Col, D2.Controls[I].Row, D2.Controls[I].BoxW]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAskSaveRoundTrip);

end.
