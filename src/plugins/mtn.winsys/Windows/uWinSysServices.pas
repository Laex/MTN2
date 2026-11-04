unit uWinSysServices;

{ Windows services as files for svc://. Every call returns a Win32 error code
  (0 = done). }

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

/// <summary>Runs the action and waits (up to ATimeoutMs) for the service to reach the
/// matching state. Returns WAIT_TIMEOUT-like ERROR_SERVICE_REQUEST_TIMEOUT when it does not.</summary>
function ControlServiceByName(const AName: string; AAction: TSvcAction;
  ATimeoutMs: Cardinal): Cardinal;

/// <summary>"Running", "Stopped", ... for a SERVICE_xxx state.</summary>
function ServiceStateName(AState: Cardinal): string;

/// <summary>The row color role of a state: "ok" running, "neutral" stopped, "warn" in between.</summary>
function ServiceStateRole(AState: Cardinal): string;

implementation

uses
  Winapi.Windows, Winapi.WinSvc;

function ServiceStateName(AState: Cardinal): string;
begin
  case AState of
    SERVICE_STOPPED: Result := 'Stopped';
    SERVICE_START_PENDING: Result := 'Starting';
    SERVICE_STOP_PENDING: Result := 'Stopping';
    SERVICE_RUNNING: Result := 'Running';
    SERVICE_CONTINUE_PENDING: Result := 'Resuming';
    SERVICE_PAUSE_PENDING: Result := 'Pausing';
    SERVICE_PAUSED: Result := 'Paused';
  else
    Result := 'Unknown';
  end;
end;

function ServiceStateRole(AState: Cardinal): string;
begin
  case AState of
    SERVICE_RUNNING: Result := 'ok';
    SERVICE_STOPPED: Result := 'neutral';
  else
    Result := 'warn';
  end;
end;

function StartTypeName(AType: DWORD): string;
begin
  case AType of
    SERVICE_BOOT_START: Result := 'Boot';
    SERVICE_SYSTEM_START: Result := 'System';
    SERVICE_AUTO_START: Result := 'Automatic';
    SERVICE_DEMAND_START: Result := 'Manual';
    SERVICE_DISABLED: Result := 'Disabled';
  else
    Result := 'Unknown';
  end;
end;

function ListServices(out ARows: TSvcRows): Cardinal;
var
  SCM: SC_HANDLE;
  Buf: TBytes;
  Needed, Returned, Resume: DWORD;
  Item: LPENUM_SERVICE_STATUS_PROCESSW;
  I, Count: Integer;
  Ok: BOOL;
begin
  SetLength(ARows, 0);
  SCM := OpenSCManager(nil, nil, SC_MANAGER_ENUMERATE_SERVICE);
  if SCM = 0 then
    Exit(GetLastError);
  try
    Resume := 0;
    Count := 0;
    SetLength(Buf, 64 * 1024);
    repeat
      Needed := 0;
      Returned := 0;
      Ok := EnumServicesStatusEx(SCM, SC_ENUM_PROCESS_INFO, SERVICE_WIN32,
        SERVICE_STATE_ALL, @Buf[0], Length(Buf), @Needed, @Returned, @Resume, nil);
      if not Ok and (GetLastError <> ERROR_MORE_DATA) then
        Exit(GetLastError);
      Item := LPENUM_SERVICE_STATUS_PROCESSW(@Buf[0]);
      SetLength(ARows, Count + Integer(Returned));
      for I := 0 to Integer(Returned) - 1 do
      begin
        ARows[Count].Name := Item^.lpServiceName;
        ARows[Count].Display := Item^.lpDisplayName;
        ARows[Count].State := Item^.ServiceStatus.dwCurrentState;
        ARows[Count].Pid := Item^.ServiceStatus.dwProcessId;
        Inc(Count);
        Inc(Item);
      end;
    until Ok;
    Result := 0;
  finally
    CloseServiceHandle(SCM);
  end;
end;

function OpenService_(ASCM: SC_HANDLE; const AName: string; AAccess: DWORD): SC_HANDLE;
begin
  Result := OpenService(ASCM, PChar(AName), AAccess);
end;

function QueryStatus(AService: SC_HANDLE; out AStatus: SERVICE_STATUS_PROCESS): Boolean;
var
  Needed: DWORD;
begin
  Result := QueryServiceStatusEx(AService, SC_STATUS_PROCESS_INFO, @AStatus,
    SizeOf(AStatus), Needed);
end;

function ServiceInfoText(const AName: string; out AText: string): Cardinal;
var
  SCM: SC_HANDLE;
  Svc: SC_HANDLE;
  Buf: TBytes;
  Needed: DWORD;
  Cfg: PQueryServiceConfigW;
  Desc: LPSERVICE_DESCRIPTIONW;
  Status: SERVICE_STATUS_PROCESS;
  Lines: TStringBuilder;
begin
  AText := '';
  SCM := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if SCM = 0 then
    Exit(GetLastError);
  try
    Svc := OpenService_(SCM, AName, SERVICE_QUERY_CONFIG or SERVICE_QUERY_STATUS);
    if Svc = 0 then
      Exit(GetLastError);
    try
      Lines := TStringBuilder.Create;
      try
        Lines.Append('Name:         ').Append(AName).Append(#10);
        Needed := 0;
        QueryServiceConfig(Svc, nil, 0, Needed);
        if Needed > 0 then
        begin
          SetLength(Buf, Needed);
          Cfg := PQueryServiceConfigW(@Buf[0]);
          if QueryServiceConfig(Svc, Cfg, Needed, Needed) then
          begin
            Lines.Append('Display name: ').Append(Cfg^.lpDisplayName).Append(#10);
            Lines.Append('Start type:   ').Append(StartTypeName(Cfg^.dwStartType)).Append(#10);
            Lines.Append('Command:      ').Append(Cfg^.lpBinaryPathName).Append(#10);
            if (Cfg^.lpServiceStartName <> nil) and (Cfg^.lpServiceStartName^ <> #0) then
              Lines.Append('Account:      ').Append(Cfg^.lpServiceStartName).Append(#10);
            if (Cfg^.lpDependencies <> nil) and (Cfg^.lpDependencies^ <> #0) then
              Lines.Append('Depends on:   ').Append(Cfg^.lpDependencies).Append(#10);
          end;
        end;
        if QueryStatus(Svc, Status) then
        begin
          Lines.Append('State:        ').Append(ServiceStateName(Status.dwCurrentState)).Append(#10);
          if Status.dwProcessId <> 0 then
            Lines.Append('Process ID:   ').Append(UIntToStr(Status.dwProcessId)).Append(#10);
        end;
        Needed := 0;
        QueryServiceConfig2(Svc, SERVICE_CONFIG_DESCRIPTION, nil, 0, @Needed);
        if Needed > 0 then
        begin
          SetLength(Buf, Needed);
          if QueryServiceConfig2(Svc, SERVICE_CONFIG_DESCRIPTION, @Buf[0], Needed, @Needed) then
          begin
            Desc := LPSERVICE_DESCRIPTIONW(@Buf[0]);
            if (Desc^.lpDescription <> nil) and (Desc^.lpDescription^ <> #0) then
              Lines.Append(#10).Append(Desc^.lpDescription).Append(#10);
          end;
        end;
        AText := Lines.ToString;
        Result := 0;
      finally
        Lines.Free;
      end;
    finally
      CloseServiceHandle(Svc);
    end;
  finally
    CloseServiceHandle(SCM);
  end;
end;

// Polls until the service is in AState or the time is over.
function WaitForState(AService: SC_HANDLE; AState: DWORD; ATimeoutMs: Cardinal): Boolean;
var
  Status: SERVICE_STATUS_PROCESS;
  Started: UInt64;
begin
  Started := GetTickCount64;
  repeat
    if QueryStatus(AService, Status) and (Status.dwCurrentState = AState) then
      Exit(True);
    Sleep(200);
  until GetTickCount64 - Started > ATimeoutMs;
  Result := False;
end;

function StopAndWait(AService: SC_HANDLE; ATimeoutMs: Cardinal): Cardinal;
var
  Status: SERVICE_STATUS;
  Cur: SERVICE_STATUS_PROCESS;
begin
  if QueryStatus(AService, Cur) and (Cur.dwCurrentState = SERVICE_STOPPED) then
    Exit(0);
  if not ControlService(AService, SERVICE_CONTROL_STOP, Status) then
    Exit(GetLastError);
  if WaitForState(AService, SERVICE_STOPPED, ATimeoutMs) then
    Result := 0
  else
    Result := ERROR_SERVICE_REQUEST_TIMEOUT;
end;

function StartAndWait(AService: SC_HANDLE; ATimeoutMs: Cardinal): Cardinal;
var
  Cur: SERVICE_STATUS_PROCESS;
  NoArgs: LPCWSTR;
begin
  if QueryStatus(AService, Cur) and (Cur.dwCurrentState = SERVICE_RUNNING) then
    Exit(0);
  NoArgs := nil;
  if not StartService(AService, 0, NoArgs) then
    Exit(GetLastError);
  if WaitForState(AService, SERVICE_RUNNING, ATimeoutMs) then
    Result := 0
  else
    Result := ERROR_SERVICE_REQUEST_TIMEOUT;
end;

function ControlServiceByName(const AName: string; AAction: TSvcAction;
  ATimeoutMs: Cardinal): Cardinal;
var
  SCM, Svc: SC_HANDLE;
  Status: SERVICE_STATUS;
begin
  SCM := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if SCM = 0 then
    Exit(GetLastError);
  try
    Svc := OpenService_(SCM, AName, SERVICE_START or SERVICE_STOP or
      SERVICE_PAUSE_CONTINUE or SERVICE_QUERY_STATUS);
    if Svc = 0 then
      Exit(GetLastError);
    try
      case AAction of
        saStart:
          Result := StartAndWait(Svc, ATimeoutMs);
        saStop:
          Result := StopAndWait(Svc, ATimeoutMs);
        saRestart:
          begin
            Result := StopAndWait(Svc, ATimeoutMs);
            if Result = 0 then
              Result := StartAndWait(Svc, ATimeoutMs);
          end;
        saPause:
          if ControlService(Svc, SERVICE_CONTROL_PAUSE, Status) then
            Result := 0
          else
            Result := GetLastError;
        saResume:
          if ControlService(Svc, SERVICE_CONTROL_CONTINUE, Status) then
            Result := 0
          else
            Result := GetLastError;
      else
        Result := ERROR_INVALID_FUNCTION;
      end;
    finally
      CloseServiceHandle(Svc);
    end;
  finally
    CloseServiceHandle(SCM);
  end;
end;

end.
