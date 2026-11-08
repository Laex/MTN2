unit uWinSysServices;

{ The systemd services as files for svc://, through systemctl. Every call
  returns a Win32-style error number (0 = done); the numbers come from
  uWinSysCodes. }

interface

uses
  System.SysUtils;

type
  TSvcRow = record
    Name: string;
    Display: string;
    State: Cardinal;
    Pid: Cardinal;
  end;
  TSvcRows = TArray<TSvcRow>;

  TSvcAction = (saStart, saStop, saRestart, saPause, saResume);

function ListServices(out ARows: TSvcRows): Cardinal;

/// <summary>The settings and the state of one service as text.</summary>
function ServiceInfoText(const AName: string; out AText: string): Cardinal;

/// <summary>Runs the action through systemctl, which waits for the unit. Pause
/// and resume do not exist in systemd and report ERROR_INVALID_FUNCTION. A call
/// that needs more rights than the user has reports ERROR_ACCESS_DENIED.</summary>
function ControlServiceByName(const AName: string; AAction: TSvcAction;
  ATimeoutMs: Cardinal): Cardinal;

/// <summary>"Running", "Stopped", ... for a service state.</summary>
function ServiceStateName(AState: Cardinal): string;

/// <summary>The row color role of a state: "ok" running, "neutral" stopped, "warn" in between.</summary>
function ServiceStateRole(AState: Cardinal): string;

implementation

uses
  System.Generics.Collections, uPlatformProcess, uWinSysCodes, uWinSysLinux;

const
  cListTimeoutMs = 15000;
  cInfoTimeoutMs = 10000;

function ServiceStateName(AState: Cardinal): string;
begin
  case AState of
    cSvcStopped: Result := 'Stopped';
    cSvcStartPending: Result := 'Starting';
    cSvcStopPending: Result := 'Stopping';
    cSvcRunning: Result := 'Running';
    cSvcContinuePending: Result := 'Reloading';
    cSvcFailed: Result := 'Failed';
  else
    Result := 'Unknown';
  end;
end;

function ServiceStateRole(AState: Cardinal): string;
begin
  case AState of
    cSvcRunning: Result := 'ok';
    cSvcStopped: Result := 'neutral';
  else
    Result := 'warn';
  end;
end;

// Runs systemctl without asking for a password on the terminal the program
// draws on: a command that needs authentication fails instead of waiting.
function Systemctl(const AArgs: TArray<string>; ATimeoutMs: Cardinal; out AOutput: string;
  out ACode: Cardinal): Boolean;
begin
  Result := PlatformRunCaptured('systemctl', ['--no-pager', '--no-ask-password'] + AArgs, '',
    ATimeoutMs, nil, AOutput, ACode) = srOk;
end;

// The main process ids of all services in one call. A failure leaves the PIDs
// at 0: the list is still usable without them.
procedure FillMainPids(var ARows: TSvcRows);
var
  Output: string;
  Code: Cardinal;
  Pids: TArray<TUnitPid>;
  Map: TDictionary<string, Cardinal>;
  P: TUnitPid;
  I: Integer;
begin
  if not Systemctl(['show', '*.service', '-p', 'Id,MainPID'], cListTimeoutMs, Output, Code) or
     (Code <> 0) then
    Exit;
  Pids := ParseMainPids(Output);
  Map := TDictionary<string, Cardinal>.Create;
  try
    for P in Pids do
      Map.AddOrSetValue(P.Name, P.Pid);
    for I := 0 to High(ARows) do
      Map.TryGetValue(ARows[I].Name, ARows[I].Pid);
  finally
    Map.Free;
  end;
end;

function ListServices(out ARows: TSvcRows): Cardinal;
var
  Output: string;
  Code: Cardinal;
  Units: TArray<TUnitRow>;
  U: TUnitRow;
  N: Integer;
begin
  SetLength(ARows, 0);
  if not Systemctl(['list-units', '--type=service', '--all', '--plain', '--no-legend'],
       cListTimeoutMs, Output, Code) or (Code <> 0) then
    Exit(ERROR_FILE_NOT_FOUND);
  Units := ParseUnitList(Output);
  SetLength(ARows, Length(Units));
  N := 0;
  for U in Units do
  begin
    // Units that are not loaded (left over from a removed package) are noise.
    if U.Load = 'not-found' then
      Continue;
    ARows[N].Name := U.Name;
    ARows[N].Display := U.Description;
    ARows[N].State := ServiceStateOfActive(U.Active);
    ARows[N].Pid := 0;
    Inc(N);
  end;
  SetLength(ARows, N);
  FillMainPids(ARows);
  Result := 0;
end;

function ServiceInfoText(const AName: string; out AText: string): Cardinal;
var
  Output: string;
  Code: Cardinal;
  Key: string;
  Value: string;
begin
  AText := '';
  if not Systemctl(['show', AName, '-p', 'Id,Description,LoadState,ActiveState,SubState,' +
       'UnitFileState,FragmentPath,MainPID,ExecStart,User'], cInfoTimeoutMs, Output, Code) or
     (Code <> 0) or (ShowValue(Output, 'LoadState') = '') then
    Exit(ERROR_SERVICE_DOES_NOT_EXIST);
  if ShowValue(Output, 'LoadState') = 'not-found' then
    Exit(ERROR_SERVICE_DOES_NOT_EXIST);
  for Key in ['Id', 'Description', 'LoadState', 'ActiveState', 'SubState', 'UnitFileState',
    'FragmentPath', 'MainPID', 'User', 'ExecStart'] do
  begin
    Value := ShowValue(Output, Key);
    if Value <> '' then
      AText := AText + Key + ': ' + Value + #10;
  end;
  Result := 0;
end;

function ControlServiceByName(const AName: string; AAction: TSvcAction;
  ATimeoutMs: Cardinal): Cardinal;
var
  Verb, Output: string;
  Code: Cardinal;
begin
  case AAction of
    saStart: Verb := 'start';
    saStop: Verb := 'stop';
    saRestart: Verb := 'restart';
  else
    Exit(ERROR_INVALID_FUNCTION);
  end;
  if not Systemctl([Verb, AName], ATimeoutMs, Output, Code) then
    Exit(ERROR_SERVICE_REQUEST_TIMEOUT);
  if Code = 0 then
    Exit(0);
  if (Pos('uthentication', Output) > 0) or (Pos('Access denied', Output) > 0) or
     (Pos('ermission denied', Output) > 0) then
    Result := ERROR_ACCESS_DENIED
  else if Pos('not found', Output) > 0 then
    Result := ERROR_SERVICE_DOES_NOT_EXIST
  else
    Result := ERROR_INVALID_FUNCTION;
end;

end.
