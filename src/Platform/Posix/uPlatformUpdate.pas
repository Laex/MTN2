unit uPlatformUpdate;

{ OS services the self-updater needs (Posix build). The Windows build lives
  in Platform\Windows; each project puts exactly one of the two directories on
  its unit search path. }

interface

/// <summary>Version of the program: the first line of the file "version" next
/// to it ("1.2.3" or "1.2.3.45"); '' when there is none.</summary>
function PlatformFileVersion(const AExeFile: string): string;

/// <summary>Ending of the release package name for this platform
/// (-win64.zip, -linux-x64.tar.gz).</summary>
function PlatformUpdateAssetSuffix: string;

/// <summary>Name of the program file a package must hold at its top level.</summary>
function PlatformUpdateMainFile: string;

/// <summary>Unpacks APackage into the existing folder AStagingDir; the top
/// folder of a tar.gz package is dropped. Refuses entries that would land
/// outside AStagingDir.</summary>
function PlatformUnpackPackage(const APackage, AStagingDir: string;
  out AError: string): Boolean;

/// <summary>Renames or moves a file, also across volumes. With AReplace an
/// existing destination is overwritten; without it the move fails instead.</summary>
function PlatformMoveFile(const ASource, ADest: string; AReplace: Boolean;
  out AError: string): Boolean;

/// <summary>True when the program was installed by a package manager, which
/// updates it itself: the self-updater then stays out of the way.</summary>
function PlatformUpdatesManagedByPackage(const AAppDir: string): Boolean;

/// <summary>True when a file can be created in ADir.</summary>
function PlatformCanWriteToDir(const ADir: string): Boolean;

function PlatformCurrentProcessId: Cardinal;

/// <summary>Arranges for AExeFile to run with AArguments (space separated) in
/// its own folder once this program has left the terminal: the program that
/// owns the terminal calls PlatformExecPendingStart at its very end, and the
/// new image replaces the current process, keeping the terminal.</summary>
function PlatformStartProcess(const AExeFile, AArguments: string;
  out AError: string): Boolean;

/// <summary>Runs the program PlatformStartProcess arranged, replacing this
/// process; returns only when there is none or it cannot be started.</summary>
procedure PlatformExecPendingStart;

/// <summary>Waits until the process has exited or ATimeoutMs passed.</summary>
procedure PlatformWaitForProcess(APid: Cardinal; ATimeoutMs: Cardinal);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Posix.Base, Posix.Unistd,
  Posix.Signal, Posix.Errno, uPlatformProcess;

function c_execv(APath: MarshaledAString; AArgv: Pointer): Integer; cdecl;
  external libc name 'execv';
function c_chdir(APath: MarshaledAString): Integer; cdecl; external libc name 'chdir';
function c_rename(AOld, ANew: MarshaledAString): Integer; cdecl;
  external libc name 'rename';

var
  GPendingExe: string;
  GPendingArgs: string;

function PlatformUpdateAssetSuffix: string;
begin
  Result := '-linux-x64.tar.gz';
end;

function PlatformUpdateMainFile: string;
begin
  Result := 'mtn2-tui';
end;

// The package is read through tar: its listing is checked first, then the
// archive is unpacked with the top folder stripped, so an entry that is
// absolute or climbs out of the staging folder is refused before any file
// is written.
function PlatformUnpackPackage(const APackage, AStagingDir: string;
  out AError: string): Boolean;
var
  Output, Entry: string;
  Code: Cardinal;
begin
  Result := False;
  AError := '';
  if (PlatformRunCaptured('tar', ['-tzf', APackage], '', 120000, nil, Output, Code) <> srOk) or
     (Code <> 0) then
  begin
    AError := 'cannot read the package: ' + Trim(Output);
    Exit;
  end;
  for Entry in Output.Split([#10]) do
    if (Entry <> '') and (Entry.StartsWith('/') or (Entry = '..') or
       Entry.StartsWith('../') or Entry.Contains('/../') or Entry.EndsWith('/..')) then
    begin
      AError := 'unsafe path in package: ' + Entry;
      Exit;
    end;
  if (PlatformRunCaptured('tar', ['-xzf', APackage, '-C', AStagingDir, '--strip-components=1',
       '--no-same-owner'], '', 600000, nil, Output, Code) <> srOk) or (Code <> 0) then
  begin
    AError := 'cannot unpack the package: ' + Trim(Output);
    Exit;
  end;
  Result := True;
end;

function PlatformFileVersion(const AExeFile: string): string;
var
  FileName: string;
  Lines: TStringList;
begin
  Result := '';
  FileName := TPath.Combine(ExtractFileDir(AExeFile), 'version');
  if not TFile.Exists(FileName) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    if Lines.Count > 0 then
      Result := Trim(Lines[0]);
  finally
    Lines.Free;
  end;
end;

function PlatformMoveFile(const ASource, ADest: string; AReplace: Boolean;
  out AError: string): Boolean;
begin
  AError := '';
  if (not AReplace) and TFile.Exists(ADest) then
  begin
    AError := SysErrorMessage(EEXIST);
    Exit(False);
  end;
  // rename() replaces an existing destination in one step, so a reader never
  // sees a missing or half-written file; it only fails across volumes.
  if AReplace and (c_rename(MarshaledAString(UTF8String(ASource)),
    MarshaledAString(UTF8String(ADest))) = 0) then
    Exit(True);
  try
    if AReplace and TFile.Exists(ADest) then
      TFile.Delete(ADest);
    TFile.Move(ASource, ADest);
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

// The package builds put an empty file named no-self-update next to the program.
function PlatformUpdatesManagedByPackage(const AAppDir: string): Boolean;
begin
  Result := TFile.Exists(TPath.Combine(AAppDir, 'no-self-update'));
end;

function PlatformCanWriteToDir(const ADir: string): Boolean;
var
  Probe: string;
begin
  Probe := TPath.Combine(ADir, '.mtn2-write-probe-' + IntToStr(getpid));
  try
    TFile.WriteAllText(Probe, '');
    TFile.Delete(Probe);
    Result := True;
  except
    Result := False;
  end;
end;

function PlatformCurrentProcessId: Cardinal;
begin
  Result := getpid;
end;

function PlatformStartProcess(const AExeFile, AArguments: string;
  out AError: string): Boolean;
begin
  AError := '';
  GPendingExe := AExeFile;
  GPendingArgs := AArguments;
  Result := True;
end;

procedure PlatformExecPendingStart;
var
  Parts: TArray<string>;
  Store: TArray<UTF8String>;
  Argv: TArray<MarshaledAString>;
  Dir: UTF8String;
  I: Integer;
begin
  if GPendingExe = '' then
    Exit;
  Parts := GPendingArgs.Split([' '], TStringSplitOptions.ExcludeEmpty);
  SetLength(Store, Length(Parts) + 1);
  SetLength(Argv, Length(Parts) + 2);
  Store[0] := UTF8String(GPendingExe);
  Argv[0] := MarshaledAString(Store[0]);
  for I := 0 to High(Parts) do
  begin
    Store[I + 1] := UTF8String(Parts[I]);
    Argv[I + 1] := MarshaledAString(Store[I + 1]);
  end;
  Argv[High(Argv)] := nil;
  Dir := UTF8String(ExtractFileDir(GPendingExe));
  c_chdir(MarshaledAString(Dir));
  c_execv(MarshaledAString(Store[0]), @Argv[0]);
end;

procedure PlatformWaitForProcess(APid: Cardinal; ATimeoutMs: Cardinal);
var
  Waited: Cardinal;
begin
  // A restart replaces the process in place, so the "previous instance" is
  // this one.
  if APid = Cardinal(getpid) then
    Exit;
  Waited := 0;
  // Signal 0 only checks that the process exists.
  while (kill(APid, 0) = 0) and (Waited < ATimeoutMs) do
  begin
    Sleep(50);
    Inc(Waited, 50);
  end;
end;

end.
