unit TestSevenZipDllWarning;

{ The startup warning about a missing 7z.dll: HostSevenZipDllMissing is True
  only when the mtn.7z plugin folder exists without a 7z.dll. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSevenZipDllWarning = class
  public
    [Test] procedure MissingOnlyWhenPluginFolderLacksDll;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uPluginHost;

procedure TTestSevenZipDllWarning.MissingOnlyWhenPluginFolderLacksDll;
var
  Root: string;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-warning-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Root);
  try
    StartPluginHost(Root);
    Assert.IsFalse(HostSevenZipDllMissing, 'no mtn.7z folder: the plugin is not installed');
    TDirectory.CreateDirectory(TPath.Combine(Root, 'mtn.7z'));
    Assert.IsTrue(HostSevenZipDllMissing, 'plugin folder without 7z.dll');
    TFile.WriteAllText(TPath.Combine(Root, 'mtn.7z' + PathDelim + '7z.dll'), 'x');
    Assert.IsFalse(HostSevenZipDllMissing, '7z.dll present');
  finally
    StopPluginHost;
    TDirectory.Delete(Root, True);
  end;
end;

end.
