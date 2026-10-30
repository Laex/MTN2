unit uFindSession;

{ In-memory find:// sessions for Alt+F7 results as a virtual panel. }

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
/// <summary>True when APath is a hit of the session or a folder holding one
/// (an operation on it changes the results).</summary>
function FindSessionTouchesPath(const ASessionId, APath: string): Boolean;
/// <summary>Hit paths of the session that are APaths or lie under them
/// (an empty path selects every hit).</summary>
function FindSessionHitsUnder(const ASessionId: string;
  const APaths: array of string): TArray<string>;
/// <summary>Drops the hits with the given paths; returns how many went.</summary>
function RemoveFindSessionHits(const ASessionId: string;
  const APaths: TArray<string>): Integer;
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

function FindSessionTouchesPath(const ASessionId, APath: string): Boolean;
var
  Data: TFindSessionData;
  Dir, Hit: string;
  I: Integer;
begin
  if (APath = '') or not TryGetFindSession(ASessionId, Data) then
    Exit(False);
  Dir := LowerCase(IncludeTrailingPathDelimiter(APath));
  for I := 0 to High(Data.Hits) do
  begin
    Hit := LowerCase(Data.Hits[I].Path);
    if (Hit = LowerCase(APath)) or Hit.StartsWith(Dir) then
      Exit(True);
  end;
  Result := False;
end;

function FindSessionHitsUnder(const ASessionId: string;
  const APaths: array of string): TArray<string>;
var
  Data: TFindSessionData;
  Hit, P, Dir: string;
  I, N: Integer;
  Match: Boolean;
begin
  SetLength(Result, 0);
  if not TryGetFindSession(ASessionId, Data) then
    Exit;
  SetLength(Result, Length(Data.Hits));
  N := 0;
  for I := 0 to High(Data.Hits) do
  begin
    Hit := LowerCase(Data.Hits[I].Path);
    Match := False;
    for P in APaths do
    begin
      Dir := LowerCase(IncludeTrailingPathDelimiter(P));
      if (P = '') or (Hit = LowerCase(P)) or Hit.StartsWith(Dir) then
      begin
        Match := True;
        Break;
      end;
    end;
    if Match then
    begin
      Result[N] := Data.Hits[I].Path;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function RemoveFindSessionHits(const ASessionId: string;
  const APaths: TArray<string>): Integer;
var
  Data: TFindSessionData;
  Gone: TDictionary<string, Boolean>;
  Kept: TArray<TFindHit>;
  P: string;
  I, N: Integer;
begin
  Result := 0;
  if (Length(APaths) = 0) or not TryGetFindSession(ASessionId, Data) then
    Exit;
  Gone := TDictionary<string, Boolean>.Create;
  try
    for P in APaths do
      Gone.AddOrSetValue(LowerCase(P), True);
    SetLength(Kept, Length(Data.Hits));
    N := 0;
    for I := 0 to High(Data.Hits) do
      if not Gone.ContainsKey(LowerCase(Data.Hits[I].Path)) then
      begin
        Kept[N] := Data.Hits[I];
        Inc(N);
      end;
  finally
    Gone.Free;
  end;
  Result := Length(Data.Hits) - N;
  if Result = 0 then
    Exit;
  SetLength(Kept, N);
  UpdateFindSession(ASessionId, Data.RootPath, Data.Mask, Kept);
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
