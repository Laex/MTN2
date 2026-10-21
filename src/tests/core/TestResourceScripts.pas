unit TestResourceScripts;

{ The resource scripts: MTN2Resource.rc is the one list of embedded assets
  (the Windows, test and Linux builds all compile it), MTN2.rc holds only the
  program icon, and every file a script names exists. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestResourceScripts = class
  public
    [Test] procedure TestIconScriptHoldsNoEmbeddedAssets;
    [Test] procedure TestEveryNamedFileExists;
    [Test] procedure TestResourceNamesAreUnique;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.Generics.Collections;

const
  cSrcRoot = '../../';
  cEntry = '^\s*([A-Za-z0-9_]+)\s+(RCDATA|ICON|BITMAP|CURSOR)\s+"([^"]+)"';

function ScriptLines(const AName: string): TArray<string>;
begin
  Result := TFile.ReadAllLines(TPath.Combine(
    ExtractFilePath(ParamStr(0)), cSrcRoot + AName), TEncoding.UTF8);
end;

procedure TTestResourceScripts.TestIconScriptHoldsNoEmbeddedAssets;
var
  Line: string;
  M: TMatch;
begin
  for Line in ScriptLines('MTN2.rc') do
  begin
    M := TRegEx.Match(Line, cEntry);
    if M.Success then
      Assert.AreEqual('ICON', M.Groups[2].Value,
        M.Groups[1].Value + ' belongs in MTN2Resource.rc, not MTN2.rc');
  end;
end;

procedure TTestResourceScripts.TestEveryNamedFileExists;
var
  Script, Line, Path: string;
  M: TMatch;
begin
  for Script in ['MTN2.rc', 'MTN2Resource.rc'] do
    for Line in ScriptLines(Script) do
    begin
      M := TRegEx.Match(Line, cEntry);
      if not M.Success then
        Continue;
      Path := StringReplace(M.Groups[3].Value, '\', PathDelim, [rfReplaceAll]);
      Assert.IsTrue(TFile.Exists(TPath.Combine(ExtractFilePath(ParamStr(0)),
        cSrcRoot + Path)), Script + ' names a missing file: ' + Path);
    end;
end;

procedure TTestResourceScripts.TestResourceNamesAreUnique;
var
  Seen: TDictionary<string, Boolean>;
  Line, Name: string;
  M: TMatch;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Line in ScriptLines('MTN2Resource.rc') do
    begin
      M := TRegEx.Match(Line, cEntry);
      if not M.Success then
        Continue;
      Name := UpperCase(M.Groups[1].Value);
      Assert.IsFalse(Seen.ContainsKey(Name), Name + ' is embedded twice');
      Seen.Add(Name, True);
    end;
  finally
    Seen.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestResourceScripts);

end.
