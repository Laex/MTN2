unit uWinSysRegistry;

{ The registry does not exist here: reg:// is not registered, and these calls
  only keep the shared code of the plugin compiling. Every call reports that
  the path is missing. }

interface

uses
  System.SysUtils;

type
  TRegRow = record
    Name: string;
    IsKey: Boolean;
    Size: Int64;
    Modified: Int64;
  end;
  TRegRows = TArray<TRegRow>;

  TRegPathKind = (rpHiveList, rpKey, rpValue);

function RegListPath(const ASegments: TArray<string>; out ARows: TRegRows): Cardinal;
function RegPathInfo(const ASegments: TArray<string>; out AKind: TRegPathKind): Cardinal;
function RegReadValue(const ASegments: TArray<string>; out AType: Cardinal;
  out AData: TBytes): Cardinal;
function RegWriteValue(const ASegments: TArray<string>; AType: Cardinal;
  const AData: TBytes): Cardinal;
function RegDeletePath(const ASegments: TArray<string>): Cardinal;
function RegCreateKeyPath(const ASegments: TArray<string>): Cardinal;

implementation

uses
  uWinSysCodes;

function RegListPath(const ASegments: TArray<string>; out ARows: TRegRows): Cardinal;
begin
  SetLength(ARows, 0);
  Result := ERROR_PATH_NOT_FOUND;
end;

function RegPathInfo(const ASegments: TArray<string>; out AKind: TRegPathKind): Cardinal;
begin
  AKind := rpHiveList;
  Result := ERROR_PATH_NOT_FOUND;
end;

function RegReadValue(const ASegments: TArray<string>; out AType: Cardinal;
  out AData: TBytes): Cardinal;
begin
  AType := 0;
  SetLength(AData, 0);
  Result := ERROR_PATH_NOT_FOUND;
end;

function RegWriteValue(const ASegments: TArray<string>; AType: Cardinal;
  const AData: TBytes): Cardinal;
begin
  Result := ERROR_PATH_NOT_FOUND;
end;

function RegDeletePath(const ASegments: TArray<string>): Cardinal;
begin
  Result := ERROR_PATH_NOT_FOUND;
end;

function RegCreateKeyPath(const ASegments: TArray<string>): Cardinal;
begin
  Result := ERROR_PATH_NOT_FOUND;
end;

end.
