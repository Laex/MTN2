program TestShellIcons;

{$APPTYPE CONSOLE}

{ Smoke: Windows shell icons by extension / directory. }

uses
  System.SysUtils, System.Classes, System.IOUtils,
  FMX.Types,
  FMX.Graphics,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uShellAssoc in '..\Core\uShellAssoc.pas',
  uShellIcons in '..\Core\uShellIcons.pas';

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

procedure CheckRow(const ALabel: string; const ARow: TPanelRow);
var
  Id: Integer;
  Bmp: TBitmap;
begin
  Id := ShellIconIdForRowWait(ARow);
  Bmp := ShellIconBitmap(Id);
  Expect(Id > 0, ALabel + ' id>0');
  Expect((Bmp <> nil) and (Bmp.Width >= 8) and (Bmp.Height >= 8),
    ALabel + ' bitmap');
end;

procedure TestExeEmbedded;
var
  Cmd, Notepad: string;
  RowA, RowB: TPanelRow;
  IdA, IdB, IdGeneric: Integer;
begin
  Writeln('Embedded exe icons');
  Cmd := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\cmd.exe');
  Notepad := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\notepad.exe');
  if not TFile.Exists(Cmd) then
  begin
    Writeln('  SKIP cmd.exe missing');
    Exit;
  end;
  RowA := MakePanelRow('cmd.exe', False, 1, '1', '', PathToFileUri(Cmd));
  RowB := MakePanelRow('notepad.exe', False, 1, '1', '', PathToFileUri(Notepad));
  IdA := ShellIconIdForRowWait(RowA);
  IdB := ShellIconIdForRowWait(RowB);
  Expect(IdA > 0, 'cmd.exe id');
  Expect(ShellIconBitmap(IdA) <> nil, 'cmd.exe bmp');
  if TFile.Exists(Notepad) then
  begin
    Expect(IdB > 0, 'notepad.exe id');
    // Different binaries should not share the path-cache id.
    Expect(IdA <> IdB, 'cmd vs notepad distinct ids');
  end;
  // Generic *.exe (no path) still resolves via extension.
  IdGeneric := ShellIconIdForRowWait(MakePanelRow('x.exe', False, 1, '1', '', ''));
  Expect(IdGeneric > 0, 'generic exe fallback');
end;

procedure TestAsyncEnqueue;
var
  Row: TPanelRow;
  Id: Integer;
  Deadline: UInt64;
begin
  Writeln('Async enqueue');
  Row := MakePanelRow('a.zzzasync', False, 1, '1', '', 'file:///a.zzzasync');
  Id := ShellIconIdForRow(Row);
  Expect(Id = 0, 'async miss is 0');
  Deadline := TThread.GetTickCount64 + 3000;
  repeat
    CheckSynchronize(20);
    Id := ShellIconIdForRow(Row);
  until (Id > 0) or (TThread.GetTickCount64 >= Deadline);
  Expect(Id > 0, 'async ext arrives');
  Expect(ShellIconBitmap(Id) <> nil, 'async bmp');
end;

begin
  Failed := 0;
  try
    GlobalUseGPUCanvas := False;
    Writeln('Shell icons');
    Expect(cShellIconCells = 2, 'cell span 2');
    CheckRow('dir', MakePanelRow('Docs/', True, -1, '<DIR>', '', 'file:///Docs'));
    CheckRow('parent', MakePanelRow('..', True, -1, '<DIR>', '', 'file:///', True));
    CheckRow('txt', MakePanelRow('a.txt', False, 1, '1', '', 'file:///a.txt'));
    CheckRow('exe', MakePanelRow('a.exe', False, 1, '1', '', 'file:///a.exe'));
    CheckRow('png', MakePanelRow('a.png', False, 1, '1', '', 'file:///a.png'));
    // Cache hit returns same id.
    Expect(ShellIconIdForRowWait(MakePanelRow('b.txt', False, 1, '1', '', 'file:///b.txt')) =
      ShellIconIdForRowWait(MakePanelRow('c.txt', False, 1, '1', '', 'file:///c.txt')),
      'same ext shares id');
    TestAsyncEnqueue;
    TestExeEmbedded;
  except
    on E: Exception do
    begin
      Inc(Failed);
      Writeln('  FAIL exception: ', E.Message);
    end;
  end;
  if Failed = 0 then
  begin
    Writeln;
    Writeln('All checks passed.');
    Halt(0);
  end;
  Writeln;
  Writeln('FAILED: ', Failed);
  Halt(1);
end.
