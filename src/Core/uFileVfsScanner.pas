unit uFileVfsScanner;

{ File VFS Directory Scanner: Isolates directory listing, wildcard filtering,
  and VFS entry assembly from uFileVfs.pas. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes, uVfsUtils;

type
  /// <summary>Scanner for local disk filesystem directory structures.</summary>
  TFileVfsScanner = class
  public
    class function ScanDirectory(const APath: string; out AEntries: TArray<TVfsEntry>): Boolean;
  end;

implementation

class function TFileVfsScanner.ScanDirectory(const APath: string; out AEntries: TArray<TVfsEntry>): Boolean;
var
  LFiles, LDirs: TArray<string>;
  LItem: string;
  LCount: Integer;
begin
  SetLength(AEntries, 0);
  if not TDirectory.Exists(APath) then
    Exit(False);

  try
    LDirs := TDirectory.GetDirectories(APath);
    LFiles := TDirectory.GetFiles(APath);

    SetLength(AEntries, Length(LDirs) + Length(LFiles));
    LCount := 0;

    for LItem in LDirs do
    begin
      AEntries[LCount].Name := ExtractFileName(LItem);
      AEntries[LCount].TargetURI := PathToFileUri(LItem);
      AEntries[LCount].IsDirectory := True;
      AEntries[LCount].Size := 0;
      Inc(LCount);
    end;

    for LItem in LFiles do
    begin
      AEntries[LCount].Name := ExtractFileName(LItem);
      AEntries[LCount].TargetURI := PathToFileUri(LItem);
      AEntries[LCount].IsDirectory := False;
      AEntries[LCount].Size := TFile.GetSize(LItem);
      Inc(LCount);
    end;

    Result := True;
  except
    Result := False;
  end;
end;

end.
