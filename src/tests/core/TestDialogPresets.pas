unit TestDialogPresets;

{ uDialogPresets: presets survive a reload, a name is unique ignoring case,
  and a damaged file loads as empty. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogPresets = class
  public
    [Test] procedure PresetsRoundTripThroughFile;
    [Test] procedure SameNameReplacesIgnoringCase;
    [Test] procedure BlankNameIsRejected;
    [Test] procedure DeleteRemovesPreset;
    [Test] procedure DamagedFileLoadsEmpty;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uDialogPresets;

function TempPresets: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-presets-test.json');
  if TFile.Exists(Result) then
    TFile.Delete(Result);
end;

function Sample(const AMode: string): TPresetValues;
begin
  SetLength(Result, 0);
  PresetAdd(Result, 'mode', AMode);
  PresetAdd(Result, 'text', 'caf' + #$E9 + ' "q"');
end;

procedure TTestDialogPresets.PresetsRoundTripThroughFile;
var
  Path: string;
  P: TDialogPresets;
  V: TPresetValues;
begin
  Path := TempPresets;
  P := TDialogPresets.Create(Path);
  try
    Assert.IsTrue(P.Put('first', Sample('a')));
    Assert.IsTrue(P.Put('second', Sample('b')));
  finally
    P.Free;
  end;
  P := TDialogPresets.Create(Path);
  try
    Assert.AreEqual(2, Integer(Length(P.Names)));
    Assert.AreEqual('first', P.Names[0]);
    Assert.IsTrue(P.Find('second', V));
    Assert.AreEqual('b', PresetGet(V, 'mode', ''));
    Assert.AreEqual('caf' + #$E9 + ' "q"', PresetGet(V, 'text', ''));
    Assert.AreEqual('x', PresetGet(V, 'missing', 'x'));
  finally
    P.Free;
    TFile.Delete(Path);
  end;
end;

procedure TTestDialogPresets.SameNameReplacesIgnoringCase;
var
  Path: string;
  P: TDialogPresets;
  V: TPresetValues;
begin
  Path := TempPresets;
  P := TDialogPresets.Create(Path);
  try
    P.Put('Work', Sample('a'));
    P.Put('work', Sample('b'));
    Assert.AreEqual(1, Integer(Length(P.Names)));
    Assert.IsTrue(P.Find('WORK', V));
    Assert.AreEqual('b', PresetGet(V, 'mode', ''));
  finally
    P.Free;
    TFile.Delete(Path);
  end;
end;

procedure TTestDialogPresets.BlankNameIsRejected;
var
  Path: string;
  P: TDialogPresets;
begin
  Path := TempPresets;
  P := TDialogPresets.Create(Path);
  try
    Assert.IsFalse(P.Put('   ', Sample('a')));
    Assert.AreEqual(0, Integer(Length(P.Names)));
    Assert.IsFalse(TFile.Exists(Path), 'nothing is written for a rejected name');
  finally
    P.Free;
  end;
end;

procedure TTestDialogPresets.DeleteRemovesPreset;
var
  Path: string;
  P: TDialogPresets;
  V: TPresetValues;
begin
  Path := TempPresets;
  P := TDialogPresets.Create(Path);
  try
    P.Put('a', Sample('1'));
    P.Put('b', Sample('2'));
    Assert.IsTrue(P.Delete('A'));
    Assert.IsFalse(P.Delete('a'), 'a second delete finds nothing');
  finally
    P.Free;
  end;
  P := TDialogPresets.Create(Path);
  try
    Assert.AreEqual(1, Integer(Length(P.Names)));
    Assert.IsFalse(P.Find('a', V));
    Assert.IsTrue(P.Find('b', V));
  finally
    P.Free;
    TFile.Delete(Path);
  end;
end;

procedure TTestDialogPresets.DamagedFileLoadsEmpty;
var
  Path: string;
  P: TDialogPresets;
begin
  Path := TempPresets;
  TFile.WriteAllText(Path, '{ not json', TEncoding.UTF8);
  P := TDialogPresets.Create(Path);
  try
    Assert.AreEqual(0, Integer(Length(P.Names)));
    Assert.IsTrue(P.Put('ok', Sample('a')), 'a damaged file is overwritten on save');
  finally
    P.Free;
    TFile.Delete(Path);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogPresets);

end.
