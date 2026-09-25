program TestFileVfsScanner;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uVfsTypes,
  uFileVfsScanner in '..\Core\uFileVfsScanner.pas';

procedure TestScanner;
var
  LEntries: TArray<TVfsEntry>;
  LSuccess: Boolean;
begin
  LSuccess := TFileVfsScanner.ScanDirectory('.', LEntries);
  Assert(LSuccess, 'Should scan current directory successfully');
  Assert(Length(LEntries) > 0, 'Current directory should contain entries');

  Writeln('OK: TestScanner passed');
end;

begin
  try
    TestScanner;
    Writeln('All FileVfsScanner tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
