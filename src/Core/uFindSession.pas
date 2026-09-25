unit uFindSession;

{ In-memory find:// sessions for Alt+F7 results as a virtual panel (Stage 14+). }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uFileFind;

type
  TFindSessionData = record
    Id: string;
    RootPath: string;
    Mask: string;
    Hits: TArray<TFindHit>;
  end;

function RegisterFindSession(const ARootPath, AMask: string;
  const AHits: TArray<TFindHit>): string;
function UpdateFindSession(const ASessionId, ARootPath, AMask: string;
  const AHits: TArray<TFindHit>): Boolean;
function TryGetFindSession(const ASessionId: string;
  out AData: TFindSessionData): Boolean;
function TryGetFindSessionFromUri(const AURI: string;
  out AData: TFindSessionData): Boolean;
function FindSessionParentFileUri(const AFindUri: string): string;
function FindSessionTitle(const AFindUri: string): string;

implementation

uses
  uVfsTypes;

var
  GLock: TObject;
  GNextId: Integer;
  GSessions: TDictionary<string, TFindSessionData>;

procedure EnsureStore;
begin
  if GSessions = nil then
  begin
    GSessions := TDictionary<string, TFindSessionData>.Create;
    GNextId := 1;
  end;
end;

function RegisterFindSession(const ARootPath, AMask: string;
  const AHits: TArray<TFindHit>): string;
var
  Data: TFindSessionData;
begin
  TMonitor.Enter(GLock);
  try
    EnsureStore;
    Result := IntToStr(GNextId);
    Inc(GNextId);
    Data.Id := Result;
    Data.RootPath := ExcludeTrailingPathDelimiter(ARootPath);
    Data.Mask := AMask;
    Data.Hits := AHits;
    GSessions.AddOrSetValue(Result, Data);
  finally
    TMonitor.Exit(GLock);
  end;
end;

function UpdateFindSession(const ASessionId, ARootPath, AMask: string;
  const AHits: TArray<TFindHit>): Boolean;
var
  Id: string;
  Data: TFindSessionData;
begin
  Id := Trim(ASessionId);
  if Id = '' then
    Exit(False);
  TMonitor.Enter(GLock);
  try
    EnsureStore;
    if not GSessions.ContainsKey(Id) then
      Exit(False);
    Data.Id := Id;
    Data.RootPath := ExcludeTrailingPathDelimiter(ARootPath);
    Data.Mask := AMask;
    Data.Hits := AHits;
    GSessions.AddOrSetValue(Id, Data);
    Result := True;
  finally
    TMonitor.Exit(GLock);
  end;
end;

function TryGetFindSession(const ASessionId: string;
  out AData: TFindSessionData): Boolean;
begin
  TMonitor.Enter(GLock);
  try
    EnsureStore;
    Result := GSessions.TryGetValue(ASessionId, AData);
  finally
    TMonitor.Exit(GLock);
  end;
end;

function TryGetFindSessionFromUri(const AURI: string;
  out AData: TFindSessionData): Boolean;
var
  Id: string;
begin
  Id := FindSessionIdFromUri(AURI);
  if Id = '' then
    Exit(False);
  Result := TryGetFindSession(Id, AData);
end;

function FindSessionParentFileUri(const AFindUri: string): string;
var
  Data: TFindSessionData;
begin
  Result := '';
  if not TryGetFindSessionFromUri(AFindUri, Data) then
    Exit;
  if Data.RootPath = '' then
    Exit;
  Result := PathToFileUri(Data.RootPath);
end;

function FindSessionTitle(const AFindUri: string): string;
var
  Data: TFindSessionData;
begin
  if TryGetFindSessionFromUri(AFindUri, Data) and (Data.Mask <> '') then
    Result := 'Find:' + Data.Mask
  else
    Result := 'Find';
end;

initialization
  GLock := TObject.Create;
  GSessions := nil;
  GNextId := 1;

finalization
  FreeAndNil(GSessions);
  FreeAndNil(GLock);

end.
