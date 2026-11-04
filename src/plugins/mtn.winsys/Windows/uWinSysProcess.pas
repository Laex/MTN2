unit uWinSysProcess;

{ The running processes as files for proc://. Every call returns a Win32 error
  code (0 = done). }

interface

uses
  System.SysUtils;

type
  TProcRow = record
    Pid: Cardinal;
    ParentPid: Cardinal;
    Threads: Cardinal;
    Exe: string;
    WorkingSet: Int64;
    Started: Int64;
  end;
  TProcRows = TArray<TProcRow>;

function ListProcesses(out ARows: TProcRows): Cardinal;

/// <summary>The details of one process as text: path, parent, threads, memory, times.</summary>
function ProcessInfoText(APid: Cardinal; out AText: string): Cardinal;

/// <summary>Ends the process at once (TerminateProcess).</summary>
function TerminateProcessById(APid: Cardinal): Cardinal;

implementation

uses
  Winapi.Windows, Winapi.TlHelp32, Winapi.PsAPI, uWinSysFormat;

function QueryImageName(AProcess: THandle; AFlags: DWORD; AName: PWideChar;
  var ASize: DWORD): BOOL; stdcall;
  external kernel32 name 'QueryFullProcessImageNameW';

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function FileTimeTicks(const AFt: TFileTime): UInt64;
begin
  Result := (UInt64(AFt.dwHighDateTime) shl 32) or AFt.dwLowDateTime;
end;

function LocalUnix(const AFt: TFileTime): Int64;
var
  Local: TFileTime;
begin
  if (AFt.dwLowDateTime = 0) and (AFt.dwHighDateTime = 0) then
    Exit(0);
  if not FileTimeToLocalFileTime(AFt, Local) then
    Local := AFt;
  Result := FileTimeToUnixSeconds(FileTimeTicks(Local));
end;

procedure FillDetails(var ARow: TProcRow);
var
  H: THandle;
  Create, Exit_, Kernel, User: TFileTime;
  Mem: TProcessMemoryCountersEx;
begin
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, ARow.Pid);
  if H = 0 then
    Exit;
  try
    if GetProcessTimes(H, Create, Exit_, Kernel, User) then
      ARow.Started := LocalUnix(Create);
    FillChar(Mem, SizeOf(Mem), 0);
    Mem.cb := SizeOf(Mem);
    if GetProcessMemoryInfo(H, PPROCESS_MEMORY_COUNTERS(@Mem), SizeOf(Mem)) then
      ARow.WorkingSet := Mem.WorkingSetSize;
  finally
    CloseHandle(H);
  end;
end;

function ListProcesses(out ARows: TProcRows): Cardinal;
var
  Snap: THandle;
  Entry: TProcessEntry32;
  List: TProcRows;
  Count: Integer;
  Row: TProcRow;
begin
  SetLength(ARows, 0);
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then
    Exit(GetLastError);
  try
    Entry.dwSize := SizeOf(Entry);
    if not Process32First(Snap, Entry) then
      Exit(GetLastError);
    Count := 0;
    SetLength(List, 256);
    repeat
      Row := Default(TProcRow);
      Row.Pid := Entry.th32ProcessID;
      Row.ParentPid := Entry.th32ParentProcessID;
      Row.Threads := Entry.cntThreads;
      Row.Exe := Entry.szExeFile;
      if Row.Pid <> 0 then
        FillDetails(Row);
      if Row.Exe = '' then
        Row.Exe := '[unknown]';
      if Count = Length(List) then
        SetLength(List, Count * 2);
      List[Count] := Row;
      Inc(Count);
    until not Process32Next(Snap, Entry);
    SetLength(List, Count);
    ARows := List;
    Result := 0;
  finally
    CloseHandle(Snap);
  end;
end;

function Megabytes(ABytes: UInt64): string;
begin
  Result := FormatFloat('#,##0.0', ABytes / (1024 * 1024)) + ' MB';
end;

function ParentName(APid: Cardinal): string;
var
  Rows: TProcRows;
  R: TProcRow;
begin
  Result := '';
  if (ListProcesses(Rows) <> 0) then
    Exit;
  for R in Rows do
    if R.Pid = APid then
      Exit(R.Exe);
end;

function PriorityName(AClass: DWORD): string;
begin
  case AClass of
    IDLE_PRIORITY_CLASS: Result := 'Idle';
    BELOW_NORMAL_PRIORITY_CLASS: Result := 'Below normal';
    NORMAL_PRIORITY_CLASS: Result := 'Normal';
    ABOVE_NORMAL_PRIORITY_CLASS: Result := 'Above normal';
    HIGH_PRIORITY_CLASS: Result := 'High';
    REALTIME_PRIORITY_CLASS: Result := 'Realtime';
  else
    Result := '';
  end;
end;

function ProcessInfoText(APid: Cardinal; out AText: string): Cardinal;
var
  Rows: TProcRows;
  Row, R: TProcRow;
  Found: Boolean;
  H: THandle;
  Path: array[0..32767] of WideChar;
  PathLen: DWORD;
  Mem: TProcessMemoryCountersEx;
  Create, Exit_, Kernel, User: TFileTime;
  Handles, Session: DWORD;
  Wow: BOOL;
  Lines: TStringBuilder;
  Priority, Parent: string;
begin
  AText := '';
  Result := ListProcesses(Rows);
  if Result <> 0 then
    Exit;
  Found := False;
  Row := Default(TProcRow);
  for R in Rows do
    if R.Pid = APid then
    begin
      Row := R;
      Found := True;
      Break;
    end;
  if not Found then
    Exit(cErrorNotFound);
  Lines := TStringBuilder.Create;
  try
    Lines.Append('Name:            ').Append(Row.Exe).Append(#10);
    Lines.Append('PID:             ').Append(UIntToStr(Row.Pid)).Append(#10);
    Lines.Append('Parent PID:      ').Append(UIntToStr(Row.ParentPid));
    Parent := ParentName(Row.ParentPid);
    if Parent <> '' then
      Lines.Append(' (').Append(Parent).Append(')');
    Lines.Append(#10);
    Lines.Append('Threads:         ').Append(UIntToStr(Row.Threads)).Append(#10);
    H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, APid);
    if H = 0 then
      Lines.Append('Details:         not available (access denied)').Append(#10)
    else
      try
        PathLen := Length(Path);
        if QueryImageName(H, 0, @Path[0], PathLen) then
          Lines.Append('Path:            ').Append(PWideChar(@Path[0])).Append(#10);
        Priority := PriorityName(GetPriorityClass(H));
        if Priority <> '' then
          Lines.Append('Priority:        ').Append(Priority).Append(#10);
        Wow := False;
        if IsWow64Process(H, Wow) then
          if Wow then
            Lines.Append('Platform:        32-bit on 64-bit Windows').Append(#10);
        if ProcessIdToSessionId(APid, Session) then
          Lines.Append('Session:         ').Append(UIntToStr(Session)).Append(#10);
        if GetProcessHandleCount(H, Handles) then
          Lines.Append('Handles:         ').Append(UIntToStr(Handles)).Append(#10);
        FillChar(Mem, SizeOf(Mem), 0);
        Mem.cb := SizeOf(Mem);
        if GetProcessMemoryInfo(H, PPROCESS_MEMORY_COUNTERS(@Mem), SizeOf(Mem)) then
        begin
          Lines.Append('Working set:     ').Append(Megabytes(Mem.WorkingSetSize)).Append(#10);
          Lines.Append('Peak working set:').Append(' ').Append(Megabytes(Mem.PeakWorkingSetSize)).Append(#10);
          Lines.Append('Private bytes:   ').Append(Megabytes(Mem.PrivateUsage)).Append(#10);
        end;
        if GetProcessTimes(H, Create, Exit_, Kernel, User) then
        begin
          Lines.Append('Started:         ').Append(FormatDateTime('yyyy-mm-dd hh:nn:ss',
            EncodeDate(1970, 1, 1) + LocalUnix(Create) / 86400)).Append(#10);
          Lines.Append('CPU time:        ').Append(FormatFloat('0.00',
            (FileTimeTicks(Kernel) + FileTimeTicks(User)) / 10000000)).Append(' s').Append(#10);
        end;
      finally
        CloseHandle(H);
      end;
    AText := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

function TerminateProcessById(APid: Cardinal): Cardinal;
var
  H: THandle;
begin
  if (APid = 0) or (APid = GetCurrentProcessId) then
    Exit(ERROR_ACCESS_DENIED);
  H := OpenProcess(PROCESS_TERMINATE, False, APid);
  if H = 0 then
    Exit(GetLastError);
  try
    if TerminateProcess(H, 1) then
      Result := 0
    else
      Result := GetLastError;
  finally
    CloseHandle(H);
  end;
end;

end.
