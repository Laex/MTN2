unit uPackEach;

{***************************************************************************}
{ Packs every source item into its own ZIP archive (name.zip next to the    }
{ other results in one folder). An existing archive is never replaced: the  }
{ new one gets a free name (name (2).zip). Each archive is written under a  }
{ temporary name and renamed when complete, so a cancelled run leaves no    }
{ partial archive behind.                                                   }
{***************************************************************************}

interface

uses
  System.SysUtils;

type
  TPackEachCancelled = reference to function: Boolean;

/// <summary>Packs each path of ASources (file or folder) into its own ZIP in
/// ADestDir. ACreated receives the number of finished archives. Returns
/// False when cancelled; raises on I/O errors (archives finished before the
/// error stay).</summary>
function PackEachToZip(const ASources: TArray<string>; const ADestDir: string;
  const ACancelled: TPackEachCancelled; out ACreated: Integer): Boolean;

/// <summary>Free archive path for AItemName in ADestDir.</summary>
function PackEachTargetName(const ADestDir, AItemName: string): string;

implementation

uses
  System.Classes, System.IOUtils, System.Zip;

type
  ECancelled = class(Exception);

function PackEachTargetName(const ADestDir, AItemName: string): string;
var
  Base: string;
  N: Integer;
begin
  Base := TPath.Combine(ADestDir, AItemName);
  Result := Base + '.zip';
  N := 2;
  while TFile.Exists(Result) or TDirectory.Exists(Result) do
  begin
    Result := Format('%s (%d).zip', [Base, N]);
    Inc(N);
  end;
end;

procedure CheckCancel(const ACancelled: TPackEachCancelled);
begin
  if Assigned(ACancelled) and ACancelled() then
    raise ECancelled.Create('cancelled');
end;

procedure AddTree(AZip: TZipFile; const ALocal, AEntry: string;
  const ACancelled: TPackEachCancelled);
var
  SR: TSearchRec;
begin
  CheckCancel(ACancelled);
  if not TDirectory.Exists(ALocal) then
  begin
    AZip.Add(ALocal, AEntry);
    Exit;
  end;
  AZip.Add(ALocal, AEntry + '/');
  if FindFirst(TPath.Combine(ALocal, '*'), faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
        AddTree(AZip, TPath.Combine(ALocal, SR.Name), AEntry + '/' + SR.Name,
          ACancelled);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function PackEachToZip(const ASources: TArray<string>; const ADestDir: string;
  const ACancelled: TPackEachCancelled; out ACreated: Integer): Boolean;
var
  Src, Item, Target, Tmp: string;
  Zip: TZipFile;
begin
  ACreated := 0;
  Result := True;
  for Src in ASources do
  begin
    if Assigned(ACancelled) and ACancelled() then
      Exit(False);
    Item := ExtractFileName(ExcludeTrailingPathDelimiter(Src));
    if TFile.Exists(Src) then
      Item := ChangeFileExt(Item, '');
    Target := PackEachTargetName(ADestDir, Item);
    Tmp := Target + '.tmp';
    try
      Zip := TZipFile.Create;
      try
        Zip.Open(Tmp, zmWrite);
        AddTree(Zip, Src, ExtractFileName(ExcludeTrailingPathDelimiter(Src)),
          ACancelled);
        Zip.Close;
      finally
        Zip.Free;
      end;
      TFile.Move(Tmp, Target);
      Inc(ACreated);
    except
      on ECancelled do
      begin
        if TFile.Exists(Tmp) then
          TFile.Delete(Tmp);
        Exit(False);
      end;
      on Exception do
      begin
        if TFile.Exists(Tmp) then
          TFile.Delete(Tmp);
        raise;
      end;
    end;
  end;
end;

end.
