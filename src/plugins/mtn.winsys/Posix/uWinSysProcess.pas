unit uWinSysProcess;

{ The running processes as files for proc://, read from /proc. Every call
  returns a Win32-style error number (0 = done); the numbers come from
  uWinSysCodes. }

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

/// <summary>The details of one process as text: program, command line, parent,
/// threads, memory, start time.</summary>
function ProcessInfoText(APid: Cardinal; out AText: string): Cardinal;

/// <summary>Asks the process to end (SIGTERM); a program may ignore it.</summary>
function TerminateProcessById(APid: Cardinal): Cardinal;

implementation

uses
  System.Classes, System.DateUtils, Posix.Base, Posix.Errno, Posix.Signal, Posix.SysTypes, Posix.Unistd,
  uWinSysCodes, uWinSysLinux;

const
  cPageSize = 4096;
  cClockTicksPerSecond = 100;

// /proc files report a size of zero, so they are read until the end.
function ReadProcText(const APath: string; out AText: string): Boolean;
var
  Stream: TFileStream;
  Bytes: TBytes;
  Got, Total: Integer;
begin
  AText := '';
  Result := False;
  try
    Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, 8192);
      Total := 0;
      repeat
        if Total = Length(Bytes) then
          SetLength(Bytes, Length(Bytes) * 2);
        Got := Stream.Read(Bytes[Total], Length(Bytes) - Total);
        Inc(Total, Got);
      until (Got <= 0) or (Total >= 1 shl 20);
      AText := TEncoding.UTF8.GetString(Bytes, 0, Total);
      Result := True;
    finally
      Stream.Free;
    end;
  except
    AText := '';
  end;
end;

function BootTime: Int64;
var
  Text, Line: string;
begin
  Result := 0;
  if not ReadProcText('/proc/stat', Text) then
    Exit;
  for Line in Text.Split([#10]) do
    if Line.StartsWith('btime ') then
      Exit(StrToInt64Def(Trim(Copy(Line, 7, MaxInt)), 0));
end;

function LinkTarget(const APath: string): string;
var
  Buf: array[0..4095] of AnsiChar;
  Path: UTF8String;
  N: ssize_t;
begin
  Result := '';
  Path := UTF8String(APath);
  N := readlink(MarshaledAString(Path), @Buf[0], SizeOf(Buf) - 1);
  if N > 0 then
  begin
    Buf[N] := #0;
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
  end;
end;

function ListProcesses(out ARows: TProcRows): Cardinal;
var
  SR: TSearchRec;
  Pid: Int64;
  Text: string;
  Stat: TProcStat;
  Boot: Int64;
  Row: TProcRow;
  N: Integer;
begin
  SetLength(ARows, 0);
  Boot := BootTime;
  if FindFirst('/proc/*', faDirectory, SR) <> 0 then
    Exit(ERROR_PATH_NOT_FOUND);
  try
    repeat
      if not TryStrToInt64(SR.Name, Pid) then
        Continue;
      // A process may end between the listing and the read.
      if not ReadProcText('/proc/' + SR.Name + '/stat', Text) then
        Continue;
      Stat := ParseProcStat(Text);
      if not Stat.Ok then
        Continue;
      Row := Default(TProcRow);
      Row.Pid := Cardinal(Pid);
      Row.ParentPid := Stat.ParentPid;
      Row.Threads := Stat.Threads;
      Row.Exe := Stat.Comm;
      Row.WorkingSet := Stat.RssPages * cPageSize;
      if Boot > 0 then
        Row.Started := Boot + Stat.StartTicks div cClockTicksPerSecond;
      N := Length(ARows);
      SetLength(ARows, N + 1);
      ARows[N] := Row;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  Result := 0;
end;

function ProcessInfoText(APid: Cardinal; out AText: string): Cardinal;
var
  Base, Stat, Status, Cmd, Line: string;
  Info: TProcStat;
  Boot: Int64;
begin
  AText := '';
  Base := '/proc/' + IntToStr(APid) + '/';
  if not ReadProcText(Base + 'stat', Stat) then
    Exit(ERROR_PATH_NOT_FOUND);
  Info := ParseProcStat(Stat);
  if not Info.Ok then
    Exit(ERROR_PATH_NOT_FOUND);
  AText := 'Name: ' + Info.Comm + #10 + 'PID: ' + IntToStr(APid) + #10 +
    'Parent PID: ' + IntToStr(Info.ParentPid) + #10 +
    'Threads: ' + IntToStr(Info.Threads) + #10 +
    'State: ' + Info.State + #10 +
    'Resident memory: ' + IntToStr(Info.RssPages * cPageSize) + ' bytes' + #10;
  Boot := BootTime;
  if Boot > 0 then
    AText := AText + 'Started: ' + DateTimeToStr(UnixToDateTime(
      Boot + Info.StartTicks div cClockTicksPerSecond, False)) + #10;
  if ReadProcText(Base + 'status', Status) then
    for Line in Status.Split([#10]) do
      if Line.StartsWith('Uid:') then
        AText := AText + 'User id: ' + Trim(Copy(Line, 5, MaxInt)) + #10;
  AText := AText + 'Program: ' + LinkTarget(Base + 'exe') + #10 +
    'Folder: ' + LinkTarget(Base + 'cwd') + #10;
  if ReadProcText(Base + 'cmdline', Cmd) then
    AText := AText + 'Command line: ' + Trim(Cmd.Replace(#0, ' ')) + #10;
  Result := 0;
end;

function TerminateProcessById(APid: Cardinal): Cardinal;
begin
  if kill(pid_t(APid), SIGTERM) = 0 then
    Exit(0);
  case GetLastError of
    EPERM: Result := ERROR_ACCESS_DENIED;
    ESRCH: Result := ERROR_PATH_NOT_FOUND;
  else
    Result := ERROR_INVALID_PARAMETER;
  end;
end;

end.
