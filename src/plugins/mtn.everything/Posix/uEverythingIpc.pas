unit uEverythingIpc;

{ Everything exists on Windows only: here a search is never available. }

interface

uses
  uEverythingFormat;

function EverythingSearch(const AQuery: string; AMaxResults: Integer; out AItems: TEvItems;
  out AError: string): Boolean;

implementation

function EverythingSearch(const AQuery: string; AMaxResults: Integer; out AItems: TEvItems;
  out AError: string): Boolean;
begin
  AItems := nil;
  AError := 'Everything is available on Windows only';
  Result := False;
end;

end.
