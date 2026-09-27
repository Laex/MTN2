unit TestShellIcons;

{ Smoke: Windows shell icons by extension / directory. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestShellIcons = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestAsyncEnqueue;
    [Test] procedure TestExeEmbedded;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  FMX.Types,
  FMX.Graphics,
  uVfsTypes,
  uDualPanelTypes,
  uShellAssoc,
  uShellIcons;

procedure CheckRow(const ALabel: string; const ARow: TPanelRow);
var
  Id: Integer;
  Bmp: TBitmap;
begin
  Id := ShellIconIdForRowWait(ARow);
  Bmp := ShellIconBitmap(Id);
  Assert.IsTrue(Id > 0, ALabel + ' id>0');
  Assert.IsTrue((Bmp <> nil) and (Bmp.Width >= 8) and (Bmp.Height >= 8),
    ALabel + ' bitmap');
end;

procedure TestExeEmbedded;
var
  Cmd, Notepad: string;
  RowA, RowB: TPanelRow;
  IdA, IdB, IdGeneric: Integer;
begin
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
  Assert.IsTrue(IdA > 0, 'cmd.exe id');
  Assert.IsTrue(ShellIconBitmap(IdA) <> nil, 'cmd.exe bmp');
  if TFile.Exists(Notepad) then
  begin
    Assert.IsTrue(IdB > 0, 'notepad.exe id');
    // Different binaries should not share the path-cache id.
    Assert.IsTrue(IdA <> IdB, 'cmd vs notepad distinct ids');
  end;
  // Generic *.exe (no path) still resolves via extension.
  IdGeneric := ShellIconIdForRowWait(MakePanelRow('x.exe', False, 1, '1', '', ''));
  Assert.IsTrue(IdGeneric > 0, 'generic exe fallback');
end;

procedure TestAsyncEnqueue;
var
  Row: TPanelRow;
  Id: Integer;
  Deadline: UInt64;
begin
  Row := MakePanelRow('a.zzzasync', False, 1, '1', '', 'file:///a.zzzasync');
  Id := ShellIconIdForRow(Row);
  Assert.IsTrue(Id = 0, 'async miss is 0');
  Deadline := TThread.GetTickCount64 + 3000;
  repeat
    CheckSynchronize(20);
    Id := ShellIconIdForRow(Row);
  until (Id > 0) or (TThread.GetTickCount64 >= Deadline);
  Assert.IsTrue(Id > 0, 'async ext arrives');
  Assert.IsTrue(ShellIconBitmap(Id) <> nil, 'async bmp');
end;

{ TTestShellIcons }

procedure TTestShellIcons.SetupFixture;
begin
  GlobalUseGPUCanvas := False;
  Assert.IsTrue(cShellIconCells = 2, 'cell span 2');
  CheckRow('dir', MakePanelRow('Docs/', True, -1, '<DIR>', '', 'file:///Docs'));
  CheckRow('parent', MakePanelRow('..', True, -1, '<DIR>', '', 'file:///', True));
  CheckRow('txt', MakePanelRow('a.txt', False, 1, '1', '', 'file:///a.txt'));
  CheckRow('exe', MakePanelRow('a.exe', False, 1, '1', '', 'file:///a.exe'));
  CheckRow('png', MakePanelRow('a.png', False, 1, '1', '', 'file:///a.png'));
  Assert.IsTrue(ShellIconIdForRowWait(MakePanelRow('b.txt', False, 1, '1', '', 'file:///b.txt')) =
    ShellIconIdForRowWait(MakePanelRow('c.txt', False, 1, '1', '', 'file:///c.txt')),
    'same ext shares id');
end;

procedure TTestShellIcons.TestAsyncEnqueue;
begin
  TestShellIcons.TestAsyncEnqueue;
end;

procedure TTestShellIcons.TestExeEmbedded;
begin
  TestShellIcons.TestExeEmbedded;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestShellIcons);

end.
