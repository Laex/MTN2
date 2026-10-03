unit TestSettingsTransfer;

{ Export and import of the settings zip (uSettingsTransfer): only settings
  files travel, histories stay, an import takes known names only. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsTransfer = class
  public
    [Test] procedure TestImportableEntries;
    [Test] procedure TestRoundTrip;
    [Test] procedure TestRejectsForeignZip;
    [Test] procedure TestIgnoresUnknownEntries;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, uSettingsTransfer;

function MakeDir(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-settings-test-' + AName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  TDirectory.CreateDirectory(Result);
end;

procedure PutFile(const ADir, ARelPath, AText: string);
var
  Path: string;
begin
  Path := TPath.Combine(ADir, StringReplace(ARelPath, '/', PathDelim, [rfReplaceAll]));
  ForceDirectories(ExtractFilePath(Path));
  TFile.WriteAllText(Path, AText, TEncoding.UTF8);
end;

procedure TTestSettingsTransfer.TestImportableEntries;
begin
  Assert.IsTrue(IsImportableEntry('session.json'), 'a settings file');
  Assert.IsTrue(IsImportableEntry('KeyMap.JSON'), 'case does not matter');
  Assert.IsTrue(IsImportableEntry('themes/My.theme.json'), 'a user theme');
  Assert.IsTrue(IsImportableEntry('themes\My.theme.json'), 'a user theme, backslash');
  Assert.IsFalse(IsImportableEntry('history.json'), 'histories do not travel');
  Assert.IsFalse(IsImportableEntry('MTN2.exe'), 'nothing executable');
  Assert.IsFalse(IsImportableEntry('themes/sub/x.json'), 'no deeper folders');
  Assert.IsFalse(IsImportableEntry('themes/..\\x.json'), 'no way out of the themes folder');
  Assert.IsFalse(IsImportableEntry('../session.json'), 'no way out of the folder');
  Assert.IsFalse(IsImportableEntry('themes/x.exe'), 'themes are .json only');
  Assert.IsFalse(IsImportableEntry(''), 'empty name');
end;

procedure TTestSettingsTransfer.TestRoundTrip;
var
  Src, Dst, ZipPath, Err: string;
  Count: Integer;
begin
  Src := MakeDir('src');
  Dst := MakeDir('dst');
  ZipPath := TPath.Combine(TPath.GetTempPath, 'mtn2-settings-test.zip');
  try
    PutFile(Src, 'session.json', '{"a":1}');
    PutFile(Src, 'keymap.json', '{"b":2}');
    PutFile(Src, 'history.json', '["secret command"]');
    PutFile(Src, 'themes/Mine.theme.json', '{"c":3}');
    Assert.IsTrue(ExportSettingsFrom(Src, ZipPath, Count, Err), 'export ' + Err);
    Assert.AreEqual(3, Count, 'three settings files exported, no history');

    PutFile(Dst, 'session.json', '{"old":true}');
    Assert.IsTrue(ImportSettingsInto(ZipPath, Dst, Count, Err), 'import ' + Err);
    Assert.AreEqual(3, Count, 'three files imported');
    Assert.AreEqual('{"a":1}', TFile.ReadAllText(TPath.Combine(Dst, 'session.json')),
      'the session was replaced');
    Assert.AreEqual('{"b":2}', TFile.ReadAllText(TPath.Combine(Dst, 'keymap.json')),
      'a missing file was added');
    Assert.AreEqual('{"c":3}', TFile.ReadAllText(TPath.Combine(Dst, 'themes' + PathDelim +
      'Mine.theme.json')), 'a theme was added');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Dst, 'history.json')), 'no history came along');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'settings-backup.zip')),
      'the replaced settings were backed up');
  finally
    if TFile.Exists(ZipPath) then
      TFile.Delete(ZipPath);
    TDirectory.Delete(Src, True);
    TDirectory.Delete(Dst, True);
  end;
end;

procedure TTestSettingsTransfer.TestRejectsForeignZip;
var
  Dst, ZipPath, Err: string;
  Zip: TZipFile;
  Data: TBytesStream;
  Count: Integer;
begin
  Dst := MakeDir('foreign');
  ZipPath := TPath.Combine(TPath.GetTempPath, 'mtn2-foreign.zip');
  try
    Zip := TZipFile.Create;
    try
      Zip.Open(ZipPath, zmWrite);
      Data := TBytesStream.Create(TEncoding.UTF8.GetBytes('{}'));
      try
        Zip.Add(Data, 'session.json');
      finally
        Data.Free;
      end;
    finally
      Zip.Free;
    end;
    Assert.IsFalse(ImportSettingsInto(ZipPath, Dst, Count, Err), 'a zip without the marker');
    Assert.IsTrue(Err <> '', 'the reason is given');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Dst, 'session.json')), 'nothing was written');
    Assert.IsFalse(ImportSettingsInto(TPath.Combine(Dst, 'nope.zip'), Dst, Count, Err),
      'a missing file');
  finally
    if TFile.Exists(ZipPath) then
      TFile.Delete(ZipPath);
    TDirectory.Delete(Dst, True);
  end;
end;

procedure TTestSettingsTransfer.TestIgnoresUnknownEntries;
var
  Root, Dst, ZipPath, Err: string;
  Zip: TZipFile;
  Data: TBytesStream;
  Count: Integer;

  procedure AddEntry(const AName: string);
  begin
    Data := TBytesStream.Create(TEncoding.UTF8.GetBytes('x'));
    try
      Zip.Add(Data, AName);
    finally
      Data.Free;
    end;
  end;

begin
  Root := MakeDir('root');
  Dst := TPath.Combine(Root, 'config');
  TDirectory.CreateDirectory(Dst);
  ZipPath := TPath.Combine(TPath.GetTempPath, 'mtn2-unknown.zip');
  try
    Zip := TZipFile.Create;
    try
      Zip.Open(ZipPath, zmWrite);
      AddEntry(cSettingsMarker);
      AddEntry('session.json');
      AddEntry('sub/evil.json');
      AddEntry('MTN2.exe');
      AddEntry('themes/ok.json');
    finally
      Zip.Free;
    end;
    Assert.IsTrue(ImportSettingsInto(ZipPath, Dst, Count, Err), 'import ' + Err);
    Assert.AreEqual(2, Count, 'only the known entries were taken');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'session.json')), 'known file written');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Dst, 'sub' + PathDelim + 'evil.json')), 'unknown folders are not created');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Root, 'evil.json')), 'nothing outside the folder');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Dst, 'MTN2.exe')), 'no executable');
  finally
    if TFile.Exists(ZipPath) then
      TFile.Delete(ZipPath);
    TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsTransfer);

end.
