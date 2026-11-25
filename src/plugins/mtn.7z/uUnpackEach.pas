unit uUnpackEach;

{***************************************************************************}
{ Unpacks every archive of a list into its own folder next to the others in }
{ one destination (name.zip -> name\). An existing folder is never reused:  }
{ the new one gets a free name (name (2)). A folder of an archive that      }
{ failed or was cancelled is removed, so no half-unpacked tree is left.     }
{***************************************************************************}

interface

uses
  System.SysUtils;

type
  TUnpackEachCancelled = reference to function: Boolean;

/// <summary>Folder name for an archive file name: the name without its
/// extension, and without ".tar" when the extension is ".tar.gz" and the like.</summary>
function UnpackEachFolderName(const AArchiveName: string): string;

/// <summary>Free folder path for AArchiveName in ADestDir.</summary>
function UnpackEachTargetDir(const ADestDir, AArchiveName: string): string;

/// <summary>Unpacks each archive of AArchives into its own folder in ADestDir.
/// AUnpacked receives the number of finished archives, AFailed the names of
/// the archives that could not be unpacked. Returns False when cancelled.
/// The 7-Zip engine must be loaded.</summary>
function UnpackEachArchive(const AArchives: TArray<string>; const ADestDir: string;
  const ACancelled: TUnpackEachCancelled; out AUnpacked: Integer;
  out AFailed: TArray<string>): Boolean;

implementation

uses
  System.IOUtils, uSevenZipApi;

function UnpackEachFolderName(const AArchiveName: string): string;
begin
  Result := ChangeFileExt(AArchiveName, '');
  if SameText(ExtractFileExt(Result), '.tar') then
    Result := ChangeFileExt(Result, '');
  if Result = '' then
    Result := AArchiveName;
end;

function UnpackEachTargetDir(const ADestDir, AArchiveName: string): string;
var
  Base: string;
  N: Integer;
begin
  Base := TPath.Combine(ADestDir, UnpackEachFolderName(AArchiveName));
  Result := Base;
  N := 2;
  while TFile.Exists(Result) or TDirectory.Exists(Result) do
  begin
    Result := Format('%s (%d)', [Base, N]);
    Inc(N);
  end;
end;

function UnpackEachArchive(const AArchives: TArray<string>; const ADestDir: string;
  const ACancelled: TUnpackEachCancelled; out AUnpacked: Integer;
  out AFailed: TArray<string>): Boolean;
var
  Arc, Target, Err: string;
begin
  AUnpacked := 0;
  AFailed := nil;
  for Arc in AArchives do
  begin
    if Assigned(ACancelled) and ACancelled() then
      Exit(False);
    Target := UnpackEachTargetDir(ADestDir, ExtractFileName(Arc));
    if SevenZipExtractTree(Arc, '', Target, False, Err) and
       not (Assigned(ACancelled) and ACancelled()) then
      Inc(AUnpacked)
    else
    begin
      if TDirectory.Exists(Target) then
        TDirectory.Delete(Target, True);
      if Assigned(ACancelled) and ACancelled() then
        Exit(False);
      AFailed := AFailed + [ExtractFileName(Arc)];
    end;
  end;
  Result := True;
end;

end.
