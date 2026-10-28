unit uGitRepo;

{ Finds the git working tree of a folder and runs "git status" in it. The
  process runs with a hidden window, no input and a time limit, and polls the
  caller's cancel flag so that unloading the plugin never waits for git. }

interface

uses
  System.SysUtils, uGitStatus;

type
  TGitReadResult = (grOk, grNotRepo, grError);

/// <summary>True when ADir or one of its parents holds a ".git" folder or file.</summary>
function IsInsideGitWorkTree(const ADir: string): Boolean;

/// <summary>Runs git status in ADir. grNotRepo = ADir is not in a working tree (or
/// git refused it); grError = git could not be run or ran too long.</summary>
function ReadGitStatus(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AStatus: TGitStatus): TGitReadResult;

implementation

uses
  System.IOUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

const
  cGitTimeoutMs = 8000;

function IsInsideGitWorkTree(const ADir: string): Boolean;
var
  Dir, Parent: string;
begin
  Result := False;
  Dir := ADir;
  while Dir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, '.git')) or
       TFile.Exists(TPath.Combine(Dir, '.git')) then
      Exit(True);
    Parent := TPath.GetDirectoryName(Dir);
    if (Parent = Dir) or (Parent = '') then
      Break;
    Dir := Parent;
  end;
end;

{$IFDEF MSWINDOWS}
function RunGit(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AOutput: string; out AExitCode: Cardinal): Boolean;
var
  Sa: TSecurityAttributes;
  OutRead, OutWrite, InRead, InWrite: THandle;
  Si: TStartupInfo;
  Pi: TProcessInformation;
  CmdLine: string;
  Buf: array[0..16383] of Byte;
  Bytes: TBytes;
  Avail, Got: Cardinal;
  Started: UInt64;
  Done: Boolean;

  procedure Drain;
  begin
    while PeekNamedPipe(OutRead, nil, 0, nil, @Avail, nil) and (Avail > 0) do
    begin
      if not ReadFile(OutRead, Buf, SizeOf(Buf), Got, nil) or (Got = 0) then
        Break;
      SetLength(Bytes, Length(Bytes) + Integer(Got));
      Move(Buf[0], Bytes[Length(Bytes) - Integer(Got)], Got);
    end;
  end;

begin
  Result := False;
  AOutput := '';
  AExitCode := 1;
  Sa := Default(TSecurityAttributes);
  Sa.nLength := SizeOf(Sa);
  Sa.bInheritHandle := True;
  if not CreatePipe(OutRead, OutWrite, @Sa, 0) then
    Exit;
  if not CreatePipe(InRead, InWrite, @Sa, 0) then
  begin
    CloseHandle(OutRead);
    CloseHandle(OutWrite);
    Exit;
  end;
  SetHandleInformation(OutRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(InWrite, HANDLE_FLAG_INHERIT, 0);
  try
    Si := Default(TStartupInfo);
    Si.cb := SizeOf(Si);
    Si.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Si.wShowWindow := SW_HIDE;
    Si.hStdInput := InRead;
    Si.hStdOutput := OutWrite;
    Si.hStdError := OutWrite;
    Pi := Default(TProcessInformation);
    CmdLine := 'git --no-optional-locks status --porcelain=v2 --branch';
    UniqueString(CmdLine);
    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(ADir), Si, Pi) then
      Exit;
    // The child owns its ends now; closing ours lets a read see the end of the output.
    CloseHandle(OutWrite);
    OutWrite := 0;
    CloseHandle(InRead);
    InRead := 0;
    CloseHandle(InWrite);
    InWrite := 0;
    try
      Started := GetTickCount64;
      repeat
        Drain;
        Done := WaitForSingleObject(Pi.hProcess, 20) = WAIT_OBJECT_0;
        if not Done and ((GetTickCount64 - Started > cGitTimeoutMs) or
           (Assigned(ACancelled) and ACancelled())) then
        begin
          TerminateProcess(Pi.hProcess, 1);
          Exit;
        end;
      until Done;
      Drain;
      GetExitCodeProcess(Pi.hProcess, AExitCode);
      AOutput := TEncoding.UTF8.GetString(Bytes);
      Result := True;
    finally
      CloseHandle(Pi.hThread);
      CloseHandle(Pi.hProcess);
    end;
  finally
    CloseHandle(OutRead);
    if OutWrite <> 0 then
      CloseHandle(OutWrite);
    if InRead <> 0 then
      CloseHandle(InRead);
    if InWrite <> 0 then
      CloseHandle(InWrite);
  end;
end;
{$ENDIF}

function ReadGitStatus(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AStatus: TGitStatus): TGitReadResult;
{$IFDEF MSWINDOWS}
var
  Text: string;
  Code: Cardinal;
begin
  AStatus := Default(TGitStatus);
  if not IsInsideGitWorkTree(ADir) then
    Exit(grNotRepo);
  if not RunGit(ADir, ACancelled, Text, Code) then
    Exit(grError);
  if (Code <> 0) or not ParseGitStatus(Text, AStatus) then
    Exit(grNotRepo);
  Result := grOk;
end;
{$ELSE}
begin
  AStatus := Default(TGitStatus);
  Result := grError;
end;
{$ENDIF}

end.
