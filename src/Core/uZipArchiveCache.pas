unit uZipArchiveCache;

{***************************************************************************}
{ Shared ZIP archive helpers for VFS ZIP mounts.                            }
{***************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Zip, System.Generics.Collections, System.Generics.Defaults,
  uVfsTypes, uVfsUtils;

type
  TZipLayer = class
  public
    Zip: TZipFile;
    OwnStream: TStream; // nil for outermost (file-backed)
    destructor Destroy; override;
  end;

  TVfsEntryComparer = class(TComparer<TVfsEntry>)
  public
    function Compare(const Left, Right: TVfsEntry): Integer; override;
  end;

implementation

destructor TZipLayer.Destroy;
begin
  Zip.Free;
  OwnStream.Free;
  inherited Destroy;
end;

function TVfsEntryComparer.Compare(const Left, Right: TVfsEntry): Integer;
begin
  if Left.IsDirectory <> Right.IsDirectory then
  begin
    if Left.IsDirectory then
      Exit(-1);
    Exit(1);
  end;
  Result := CompareNaturalText(Left.Name, Right.Name);
end;

end.
