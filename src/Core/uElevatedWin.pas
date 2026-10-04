unit uElevatedWin;

{ Win32 plumbing shared by the administrator helper and its client: the two
  pipes (requests, replies), who is on the other end of a pipe, the account
  SID that may open them, and blocking framed reads and writes. Requests and
  replies use separate pipes: a blocking read on one handle would hold up a
  write on the same handle from another thread. }

interface

uses
  System.SysUtils, Winapi.Windows;

/// <summary>\\.\pipe\mtn2-elev-NAME.req (program to helper) or .rep (helper
/// to program).</summary>
function ElevatedPipePath(const AName: string; AReplies: Boolean): string;
/// <summary>SID of the account this process runs as, in S-1-5-... text form.</summary>
function CurrentUserSidText: string;
/// <summary>Process that opened the pipe from the client side (0 if unknown).</summary>
function PipeClientPid(APipe: THandle): Cardinal;
/// <summary>Process that created the pipe (0 if unknown).</summary>
function PipeServerPid(APipe: THandle): Cardinal;
/// <summary>Full path of the program image of process APid ('' if it cannot
/// be read).</summary>
function ProcessImagePath(APid: Cardinal): string;
/// <summary>Creates one server end of a pipe that only ASid (and the helper
/// itself) can open; nothing else can create a second instance of the name.
/// INVALID_HANDLE_VALUE on failure.</summary>
function CreateSecuredPipe(const APath, ASid: string; AReplies: Boolean): THandle;
/// <summary>Reads until one whole framed message is in hand. ABuffer keeps the
/// bytes of the next message between calls. False when the pipe is closed or
/// the message is malformed.</summary>
function ReadFramedMessage(APipe: THandle; var ABuffer: TBytes;
  out APayload: TBytes): Boolean;
/// <summary>Writes the framed payload completely.</summary>
function WriteFramedMessage(APipe: THandle; const APayload: TBytes): Boolean;

implementation

uses
  uElevatedProtocol;

const
  cProcessQueryLimitedInformation = $1000;
  cPipeRejectRemoteClients = $8;

type
  TSidAndAttrs = record
    Sid: Pointer;
    Attributes: DWORD;
  end;

function GetNamedPipeClientProcessIdW(APipe: THandle; out APid: ULONG): BOOL; stdcall;
  external kernel32 name 'GetNamedPipeClientProcessId';
function GetNamedPipeServerProcessIdW(APipe: THandle; out APid: ULONG): BOOL; stdcall;
  external kernel32 name 'GetNamedPipeServerProcessId';
function QueryFullProcessImageNameW(AProcess: THandle; AFlags: DWORD;
  ABuffer: PWideChar; var ASize: DWORD): BOOL; stdcall;
  external kernel32 name 'QueryFullProcessImageNameW';
function ConvertSidToStringSidW(ASid: Pointer; out AText: PWideChar): BOOL; stdcall;
  external advapi32 name 'ConvertSidToStringSidW';
function ConvertStringSecurityDescriptorToSecurityDescriptorW(const AText: PWideChar;
  ARevision: DWORD; out ADescriptor: Pointer; ASize: PULONG): BOOL; stdcall;
  external advapi32 name 'ConvertStringSecurityDescriptorToSecurityDescriptorW';

function ElevatedPipePath(const AName: string; AReplies: Boolean): string;
begin
  Result := '\\.\pipe\mtn2-elev-' + AName;
  if AReplies then
    Result := Result + '.rep'
  else
    Result := Result + '.req';
end;

function CurrentUserSidText: string;
var
  Token: THandle;
  Size: DWORD;
  Buf: TBytes;
  Text: PWideChar;
begin
  Result := '';
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    Exit;
  try
    Size := 0;
    GetTokenInformation(Token, TokenUser, nil, 0, Size);
    if Size = 0 then
      Exit;
    SetLength(Buf, Size);
    if not GetTokenInformation(Token, TokenUser, @Buf[0], Size, Size) then
      Exit;
    if ConvertSidToStringSidW(TSidAndAttrs(Pointer(@Buf[0])^).Sid, Text) then
    begin
      Result := Text;
      LocalFree(HLOCAL(Text));
    end;
  finally
    CloseHandle(Token);
  end;
end;

function PipeClientPid(APipe: THandle): Cardinal;
var
  Pid: ULONG;
begin
  if GetNamedPipeClientProcessIdW(APipe, Pid) then
    Result := Pid
  else
    Result := 0;
end;

function PipeServerPid(APipe: THandle): Cardinal;
var
  Pid: ULONG;
begin
  if GetNamedPipeServerProcessIdW(APipe, Pid) then
    Result := Pid
  else
    Result := 0;
end;

function ProcessImagePath(APid: Cardinal): string;
var
  H: THandle;
  Buf: array[0..1023] of WideChar;
  Size: DWORD;
begin
  Result := '';
  H := OpenProcess(cProcessQueryLimitedInformation, False, APid);
  if H = 0 then
    Exit;
  try
    Size := Length(Buf);
    if QueryFullProcessImageNameW(H, 0, @Buf[0], Size) then
      SetString(Result, PWideChar(@Buf[0]), Size);
  finally
    CloseHandle(H);
  end;
end;

function CreateSecuredPipe(const APath, ASid: string; AReplies: Boolean): THandle;
var
  Sddl: string;
  Descriptor: Pointer;
  Attrs: TSecurityAttributes;
  OpenMode: DWORD;
begin
  Result := INVALID_HANDLE_VALUE;
  if ASid = '' then
    Exit;
  // Protected DACL: full access for the one account, nobody else. The label
  // lets the program (a lower integrity level than the helper) open the pipe.
  Sddl := 'D:P(A;;GA;;;' + ASid + ')S:(ML;;NW;;;ME)';
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PWideChar(Sddl), 1,
    Descriptor, nil) then
    Exit;
  try
    Attrs.nLength := SizeOf(Attrs);
    Attrs.lpSecurityDescriptor := Descriptor;
    Attrs.bInheritHandle := False;
    if AReplies then
      OpenMode := PIPE_ACCESS_OUTBOUND
    else
      OpenMode := PIPE_ACCESS_INBOUND;
    Result := CreateNamedPipe(PChar(APath),
      OpenMode or FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT or cPipeRejectRemoteClients,
      1, 64 * 1024, 64 * 1024, 0, @Attrs);
  finally
    LocalFree(HLOCAL(Descriptor));
  end;
end;

function ReadFramedMessage(APipe: THandle; var ABuffer: TBytes;
  out APayload: TBytes): Boolean;
var
  Chunk: array[0..65535] of Byte;
  Got: DWORD;
  Invalid: Boolean;
  Old: Integer;
begin
  while True do
  begin
    if TryTakeFrame(ABuffer, APayload, Invalid) then
      Exit(True);
    if Invalid then
      Exit(False);
    if not ReadFile(APipe, Chunk, SizeOf(Chunk), Got, nil) or (Got = 0) then
      Exit(False);
    Old := Length(ABuffer);
    SetLength(ABuffer, Old + Integer(Got));
    Move(Chunk[0], ABuffer[Old], Got);
  end;
end;

function WriteFramedMessage(APipe: THandle; const APayload: TBytes): Boolean;
var
  Data: TBytes;
  Done, Wrote: DWORD;
begin
  Data := FrameBytes(APayload);
  Done := 0;
  while Done < DWORD(Length(Data)) do
  begin
    if not WriteFile(APipe, Data[Done], DWORD(Length(Data)) - Done, Wrote, nil) or
       (Wrote = 0) then
      Exit(False);
    Inc(Done, Wrote);
  end;
  Result := True;
end;

end.
