unit uConsoleLaunch;

{ Enter on a console program in a file panel (a console-subsystem .exe, a
  .bat / .cmd, a .ps1): where it runs and with what command line.

  - The background console (Ctrl+O), when its shell is cmd / PowerShell /
    pwsh and nothing runs in it: the program's output stays under the panels,
    as with a command typed in the command line.
  - Otherwise (a WSL / Git Bash / SSH console, or a command still running in
    it): a new terminal tab with cmd, or PowerShell for a .ps1. The tab's
    shell outlives the program, so its output stays on screen.
  - Anything else (GUI programs, documents) is not a console launch: the
    Windows shell opens it (ShellExecute). }

interface

type
  TLaunchFileKind = (lfkOther, lfkConsoleExe, lfkBatch, lfkPowerShell);
  TConsoleLaunchTarget = (cltShellOpen, cltConsole, cltTerminal);

/// <summary>By extension; a .exe / .com only when its PE header says the
/// console subsystem. An unreadable file is lfkOther.</summary>
function DetectLaunchFileKind(const APath: string): TLaunchFileKind;
/// <summary>AConsoleBusy: a command still runs in the background console's
/// shell.</summary>
function ChooseConsoleLaunch(AKind: TLaunchFileKind; const AConsoleProfileId: string;
  AConsoleBusy: Boolean): TConsoleLaunchTarget;
/// <summary>The shell of a new terminal tab for AKind.</summary>
function TerminalProfileForLaunch(AKind: TLaunchFileKind): string;
/// <summary>The line to type into a AProfileId shell (cmd / PowerShell /
/// pwsh) to run APath.</summary>
function BuildConsoleLaunchLine(const APath: string; AKind: TLaunchFileKind;
  const AProfileId: string): string;

implementation

uses
  System.SysUtils, System.Classes, uShellProfiles;

const
  cImageSubsystemWindowsCui = 3;

function PeSubsystem(const APath: string): Integer;
var
  S: TFileStream;
  Mz: Word;
  PeOffset: Cardinal;
  Sig: Cardinal;
  Subsystem: Word;
begin
  Result := -1;
  try
    S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if (S.Read(Mz, 2) <> 2) or (Mz <> $5A4D) then // 'MZ'
        Exit;
      S.Position := $3C;
      if S.Read(PeOffset, 4) <> 4 then
        Exit;
      S.Position := PeOffset;
      if (S.Read(Sig, 4) <> 4) or (Sig <> $00004550) then // 'PE'#0#0
        Exit;
      // Optional header: after the 4-byte signature and the 20-byte file
      // header; Subsystem is at offset 68 in both PE32 and PE32+.
      S.Position := PeOffset + 4 + 20 + 68;
      if S.Read(Subsystem, 2) <> 2 then
        Exit;
      Result := Subsystem;
    finally
      S.Free;
    end;
  except
    Result := -1;
  end;
end;

function DetectLaunchFileKind(const APath: string): TLaunchFileKind;
var
  Ext: string;
begin
  Result := lfkOther;
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext = '.bat') or (Ext = '.cmd') then
    Result := lfkBatch
  else if Ext = '.ps1' then
    Result := lfkPowerShell
  else if ((Ext = '.exe') or (Ext = '.com')) and
          (PeSubsystem(APath) = cImageSubsystemWindowsCui) then
    Result := lfkConsoleExe;
end;

function IsWindowsShell(const AProfileId: string): Boolean;
var
  Id: string;
begin
  Id := NormalizeShellProfileId(AProfileId);
  Result := (Id = cShellProfileCmd) or (Id = cShellProfilePowerShell) or
    (Id = cShellProfilePwsh);
end;

function ChooseConsoleLaunch(AKind: TLaunchFileKind; const AConsoleProfileId: string;
  AConsoleBusy: Boolean): TConsoleLaunchTarget;
begin
  if AKind = lfkOther then
    Result := cltShellOpen
  else if IsWindowsShell(AConsoleProfileId) and not AConsoleBusy then
    Result := cltConsole
  else
    Result := cltTerminal;
end;

function TerminalProfileForLaunch(AKind: TLaunchFileKind): string;
begin
  if AKind = lfkPowerShell then
    Result := cShellProfilePowerShell
  else
    Result := cShellProfileCmd;
end;

function BuildConsoleLaunchLine(const APath: string; AKind: TLaunchFileKind;
  const AProfileId: string): string;
var
  Id: string;
begin
  Id := NormalizeShellProfileId(AProfileId);
  if (Id = cShellProfilePowerShell) or (Id = cShellProfilePwsh) then
    // Call operator on a single-quoted literal: no variable expansion, and
    // a quote in the path doubles.
    Result := '& ''' + StringReplace(APath, '''', '''''', [rfReplaceAll]) + ''''
  else if AKind = lfkPowerShell then
    Result := 'powershell -NoLogo -File "' + APath + '"'
  else
    Result := '"' + APath + '"';
end;

end.
