unit uCloudFiles;

{***************************************************************************}
{ Counts the cloud-only files (placeholders whose content is fetched from a  }
{ cloud service when read) among the items of a copy, so the user can be    }
{ warned before the transfer starts a download of each of them. The walk is }
{ bounded by a number of visited entries and by time, so a huge tree or a   }
{ slow share cannot hold up the confirmation dialog.                        }
{***************************************************************************}

interface

uses
  System.SysUtils;

type
  TIsCloudOnly = reference to function(const APath: string): Boolean;

const
  cCloudScanMaxEntries = 3000;
  cCloudScanMaxMs = 300;

/// <summary>Number of cloud-only files in APaths (files, and folders walked
/// recursively). AIsCloudOnly decides per file; nil uses the platform check.
/// AMaxEntries / AMaxMs bound the walk.</summary>
function CountCloudOnlyFiles(const APaths: TArray<string>;
  const AIsCloudOnly: TIsCloudOnly = nil;
  AMaxEntries: Integer = cCloudScanMaxEntries;
  AMaxMs: Integer = cCloudScanMaxMs): Integer;

implementation

uses
  System.IOUtils, System.Diagnostics, uPlatformFileOps;

function CountCloudOnlyFiles(const APaths: TArray<string>;
  const AIsCloudOnly: TIsCloudOnly; AMaxEntries, AMaxMs: Integer): Integer;
var
  Visited: Integer;
  Watch: TStopwatch;
  Check: TIsCloudOnly;
  Total: Integer;

  function OutOfBudget: Boolean;
  begin
    Result := (Visited >= AMaxEntries) or (Watch.ElapsedMilliseconds >= AMaxMs);
  end;

  procedure Walk(const APath: string);
  var
    SR: TSearchRec;
  begin
    if OutOfBudget then
      Exit;
    Inc(Visited);
    if not TDirectory.Exists(APath) then
    begin
      if Check(APath) then
        Inc(Total);
      Exit;
    end;
    if PlatformIsLinkNode(APath) then
      Exit; // a link to a folder could lead back up
    if FindFirst(TPath.Combine(APath, '*'), faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
          Walk(TPath.Combine(APath, SR.Name));
      until OutOfBudget or (FindNext(SR) <> 0);
    finally
      FindClose(SR);
    end;
  end;

var
  P: string;
begin
  Total := 0;
  Visited := 0;
  Watch := TStopwatch.StartNew;
  if Assigned(AIsCloudOnly) then
    Check := AIsCloudOnly
  else
    Check := function(const APath: string): Boolean
      begin
        Result := PlatformIsCloudOnlyFile(APath);
      end;
  for P in APaths do
    Walk(P);
  Result := Total;
end;

end.
