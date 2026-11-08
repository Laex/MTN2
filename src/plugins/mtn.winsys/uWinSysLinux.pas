unit uWinSysLinux;

{ Pure text helpers of the Linux side of the system plugin: the numbers a
  service state is shown with, the fields of /proc/<pid>/stat and the lines of
  systemctl output. Nothing here touches the system, so the unit is tested on
  its own. }

interface

uses
  System.SysUtils;

const
  // The Win32 service states the panel code is written against.
  cSvcStopped = 1;
  cSvcStartPending = 2;
  cSvcStopPending = 3;
  cSvcRunning = 4;
  cSvcContinuePending = 5;
  cSvcPausePending = 6;
  cSvcPaused = 7;
  /// <summary>A unit systemd marks failed; Windows has no such state.</summary>
  cSvcFailed = 100;

type
  TProcStat = record
    Ok: Boolean;
    Comm: string;
    State: Char;
    ParentPid: Cardinal;
    Threads: Cardinal;
    /// <summary>Start time in clock ticks after boot.</summary>
    StartTicks: Int64;
    RssPages: Int64;
  end;

  TUnitRow = record
    Name: string;
    Load: string;
    Active: string;
    Sub: string;
    Description: string;
  end;

/// <summary>Reads the text of /proc/<pid>/stat. The name sits in parentheses
/// and may hold spaces and parentheses itself, so the last ")" ends it.</summary>
function ParseProcStat(const AText: string): TProcStat;

/// <summary>The rows of "systemctl list-units --type=service --plain
/// --no-legend": unit, load, active and sub state, then the description.</summary>
function ParseUnitList(const AText: string): TArray<TUnitRow>;

/// <summary>The Win32 service state an ActiveState of systemd stands for.</summary>
function ServiceStateOfActive(const AActive: string): Cardinal;

type
  TUnitPid = record
    Name: string;
    Pid: Cardinal;
  end;

/// <summary>The units with a main process in the blocks of "systemctl show -p
/// Id,MainPID": a block is a run of lines ended by an empty line. A unit
/// whose MainPID is 0 or missing has no process and is left out.</summary>
function ParseMainPids(const AText: string): TArray<TUnitPid>;

/// <summary>The value after the key on its line of "systemctl show" output; empty when
/// there is none.</summary>
function ShowValue(const AText, AKey: string): string;

implementation

uses
  System.Generics.Collections;

function ParseProcStat(const AText: string): TProcStat;
var
  Open, Close: Integer;
  Rest: TArray<string>;
  V: Int64;

  function Field(AIndex: Integer): string;
  begin
    if AIndex < Length(Rest) then
      Result := Rest[AIndex]
    else
      Result := '';
  end;

begin
  Result := Default(TProcStat);
  Open := Pos('(', AText);
  Close := AText.LastIndexOf(')') + 1;
  if (Open = 0) or (Close <= Open) then
    Exit;
  Result.Comm := Copy(AText, Open + 1, Close - Open - 1);
  Rest := Trim(Copy(AText, Close + 1, MaxInt)).Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(Rest) < 22 then
    Exit;
  if Field(0) <> '' then
    Result.State := Field(0)[1];
  if TryStrToInt64(Field(1), V) then
    Result.ParentPid := Cardinal(V);
  if TryStrToInt64(Field(17), V) then
    Result.Threads := Cardinal(V);
  if TryStrToInt64(Field(19), V) then
    Result.StartTicks := V;
  if TryStrToInt64(Field(21), V) then
    Result.RssPages := V;
  Result.Ok := True;
end;

function ParseUnitList(const AText: string): TArray<TUnitRow>;
var
  Line, Rest: string;
  Words: TArray<string>;
  N, P: Integer;
  Row: TUnitRow;
begin
  SetLength(Result, 0);
  for Line in AText.Replace(#13, '').Split([#10]) do
  begin
    Rest := Trim(Line);
    // A failed unit is marked with a bullet in front of its name.
    if Rest.StartsWith(#$25CF) or Rest.StartsWith('*') then
      Rest := Trim(Copy(Rest, 2, MaxInt));
    if Rest = '' then
      Continue;
    // The description holds spaces, so only the first four words are cut off.
    Words := nil;
    while (Length(Words) < 4) and (Rest <> '') do
    begin
      P := Pos(' ', Rest);
      if P = 0 then
        P := Length(Rest) + 1;
      Words := Words + [Copy(Rest, 1, P - 1)];
      Rest := TrimLeft(Copy(Rest, P + 1, MaxInt));
    end;
    if Length(Words) < 4 then
      Continue;
    Row.Name := Words[0];
    Row.Load := Words[1];
    Row.Active := Words[2];
    Row.Sub := Words[3];
    Row.Description := Rest;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := Row;
  end;
end;

function ServiceStateOfActive(const AActive: string): Cardinal;
begin
  if AActive = 'active' then
    Result := cSvcRunning
  else if AActive = 'activating' then
    Result := cSvcStartPending
  else if AActive = 'deactivating' then
    Result := cSvcStopPending
  else if AActive = 'reloading' then
    Result := cSvcContinuePending
  else if AActive = 'failed' then
    Result := cSvcFailed
  else
    Result := cSvcStopped;
end;

function ParseMainPids(const AText: string): TArray<TUnitPid>;
var
  Line, Name: string;
  Pid: Cardinal;
  List: TList<TUnitPid>;

  procedure Flush;
  var
    Item: TUnitPid;
  begin
    if (Name <> '') and (Pid <> 0) then
    begin
      Item.Name := Name;
      Item.Pid := Pid;
      List.Add(Item);
    end;
    Name := '';
    Pid := 0;
  end;

begin
  List := TList<TUnitPid>.Create;
  try
    Name := '';
    Pid := 0;
    for Line in AText.Replace(#13, '').Split([#10]) do
      if Line = '' then
        Flush
      else if Line.StartsWith('Id=') then
        Name := Copy(Line, 4, MaxInt)
      else if Line.StartsWith('MainPID=') then
        Pid := Cardinal(StrToIntDef(Copy(Line, 9, MaxInt), 0));
    Flush;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ShowValue(const AText, AKey: string): string;
var
  Line, Prefix: string;
begin
  Result := '';
  Prefix := AKey + '=';
  for Line in AText.Replace(#13, '').Split([#10]) do
    if Line.StartsWith(Prefix) then
      Exit(Copy(Line, Length(Prefix) + 1, MaxInt));
end;

end.
