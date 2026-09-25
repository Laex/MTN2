unit uShellAssoc;

{ Platform shell file associations (open handler probe + open).
  Host/UI code uses only this unit — Windows today, other OS later. }

interface

type
  /// <summary>Result of asking the OS for an "open" handler for an extension.</summary>
  TShellOpenQuery = record
    Available: Boolean;
    AppName: string;
    Command: string;
    class function None: TShellOpenQuery; static;
  end;

/// <summary>Normalize to lowercase ".ext" (accepts "pdf", ".PDF", or a file name).</summary>
function NormalizeFileExtension(const AExtOrName: string): string;

/// <summary>Ask the OS whether an open action is registered for the extension.</summary>
function QueryShellOpen(const AExtension: string): TShellOpenQuery;

function HasShellOpen(const AExtension: string): Boolean;

/// <summary>Open a local file via the platform shell. Returns False on failure.</summary>
function ShellOpenFile(const AFilePath: string): Boolean;

/// <summary>Open a local file for editing: the OS "edit" verb, Notepad when
/// the type registers none. Returns False on failure.</summary>
function ShellEditFile(const AFilePath: string): Boolean;

/// <summary>Show the OS shell context menu for a local file or folder at screen coords.
/// AOwnerHwnd must be the host window (SetForegroundWindow / menu routing).</summary>
function ShellShowContextMenu(const AFilePath: string; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;

/// <summary>Alt+Enter: the OS "Properties" window for local files / folders
/// (one path, or a combined sheet for several). Non-modal: returns as soon
/// as the window is up. False if nothing could be shown.</summary>
function ShellShowProperties(const APaths: TArray<string>; AOwnerHwnd: NativeUInt): Boolean;

/// <summary>Run a command or file as a separate OS process (FAR Shift+Enter).
/// Does not attach to ConPTY; console apps get their own console window.</summary>
function ShellRunDetached(const ACommand, AWorkingDir: string): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils
{$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, Winapi.ShlObj, Winapi.ActiveX
{$ENDIF}
  ;

class function TShellOpenQuery.None: TShellOpenQuery;
begin
  Result.Available := False;
  Result.AppName := '';
  Result.Command := '';
end;

function NormalizeFileExtension(const AExtOrName: string): string;
var
  S: string;
begin
  S := Trim(AExtOrName);
  if S = '' then
    Exit('');
  // File name → extension; bare "pdf" → ".pdf".
  if (Pos(PathDelim, S) > 0) or (Pos('/', S) > 0) or (Pos('.', S) > 1) then
    S := TPath.GetExtension(S)
  else if (Length(S) > 0) and (S[1] <> '.') then
    S := '.' + S;
  Result := LowerCase(S);
end;

{$IFDEF MSWINDOWS}
const
  // Minimal AssocQueryString surface (avoid full ShLwApi dependency drift).
  ASSOCF_NONE                 = $00000000;
  ASSOCF_INIT_DEFAULTTOSTAR   = $00000004;
  ASSOCF_NOTRUNCATE           = $00000020;
  ASSOCSTR_COMMAND            = 1;
  ASSOCSTR_EXECUTABLE         = 2;
  ASSOCSTR_FRIENDLYAPPNAME    = 4;

function AssocQueryStringW(Flags: DWORD; Str: DWORD; pszAssoc, pszExtra,
  pszOut: PWideChar; var pcchOut: DWORD): HRESULT; stdcall;
  external 'shlwapi.dll' name 'AssocQueryStringW';

function QueryAssocString(const AAssoc: string; AStr: DWORD): string;
var
  Buf: array[0..2047] of WideChar;
  Len: DWORD;
  Hr: HRESULT;
begin
  Result := '';
  Len := Length(Buf);
  FillChar(Buf[0], SizeOf(Buf), 0);
  Hr := AssocQueryStringW(ASSOCF_NOTRUNCATE or ASSOCF_INIT_DEFAULTTOSTAR,
    AStr, PWideChar(AAssoc), 'open', @Buf[0], Len);
  if Succeeded(Hr) and (Len > 0) then
    Result := Trim(string(PWideChar(@Buf[0])));
end;

function QueryShellOpen(const AExtension: string): TShellOpenQuery;
var
  Ext, Exe, Cmd, App: string;
begin
  Result := TShellOpenQuery.None;
  Ext := NormalizeFileExtension(AExtension);
  if Ext = '' then
    Exit;

  Exe := QueryAssocString(Ext, ASSOCSTR_EXECUTABLE);
  Cmd := QueryAssocString(Ext, ASSOCSTR_COMMAND);
  App := QueryAssocString(Ext, ASSOCSTR_FRIENDLYAPPNAME);

  // Available when the shell reports a non-empty open command or executable.
  Result.Available := (Exe <> '') or (Cmd <> '');
  Result.AppName := App;
  if Cmd <> '' then
    Result.Command := Cmd
  else
    Result.Command := Exe;
end;

function ShellOpenFile(const AFilePath: string): Boolean;
var
  Path, Dir: string;
  Code: HINST;
  DirP: PChar;
begin
  Path := Trim(AFilePath);
  Result := False;
  if Path = '' then
    Exit;
  // Working directory = folder that contains the file (FAR-style).
  Dir := ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(Path));
  if Dir <> '' then
    DirP := PChar(Dir)
  else
    DirP := nil;
  // ShellExecute returns value > 32 on success.
  Code := ShellExecute(0, 'open', PChar(Path), nil, DirP, SW_SHOWNORMAL);
  Result := NativeInt(Code) > 32;
end;

function TryCreateDetachedProcess(const ACmdLine, AWorkingDir: string): Boolean; forward;

function ShellEditFile(const AFilePath: string): Boolean;
var
  Path, Dir: string;
  Code: HINST;
  DirP: PChar;
begin
  Path := Trim(AFilePath);
  Result := False;
  if Path = '' then
    Exit;
  Dir := ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(Path));
  if Dir <> '' then
    DirP := PChar(Dir)
  else
    DirP := nil;
  Code := ShellExecute(0, 'edit', PChar(Path), nil, DirP, SW_SHOWNORMAL);
  Result := NativeInt(Code) > 32;
  // Most types (.pas, .log, .json, ...) register no "edit" verb.
  if not Result then
    Result := TryCreateDetachedProcess('notepad.exe "' + Path + '"', Dir);
end;

const
  cShellContextCmdFirst = 1;
  cShellContextCmdLast  = $7FFF;

function ShellShowContextMenu(const AFilePath: string; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
var
  Path: string;
  ItemIdList: PItemIDList;
  ParentFolder: IShellFolder;
  RelPidl: PItemIDList;
  ContextMenu: IContextMenu;
  ParentObj, MenuObj: Pointer;
  Menu: HMENU;
  Cmd: UINT;
  InvokeInfo: TCMInvokeCommandInfo;
  OwnerWnd: HWND;
  ShellAttrs: ULONG;
begin
  Result := False;
  Path := Trim(AFilePath);
  OwnerWnd := HWND(AOwnerHwnd);
  if (Path = '') or (OwnerWnd = 0) then
    Exit;
  if not (TFile.Exists(Path) or TDirectory.Exists(Path)) then
    Exit;

  ItemIdList := nil;
  ShellAttrs := 0;
  if Failed(SHParseDisplayName(PChar(Path), nil, ItemIdList, 0, ShellAttrs)) then
    Exit;
  try
    ParentObj := nil;
    if Failed(SHBindToParent(ItemIdList, IShellFolder, ParentObj, RelPidl)) then
      Exit;
    ParentFolder := IShellFolder(ParentObj);
    MenuObj := nil;
    if Failed(ParentFolder.GetUIObjectOf(0, 1, RelPidl, IID_IContextMenu, nil, MenuObj)) then
      Exit;
    ContextMenu := IContextMenu(MenuObj);

    Menu := CreatePopupMenu;
    if Menu = 0 then
      Exit;
    try
      if Failed(ContextMenu.QueryContextMenu(Menu, 0, cShellContextCmdFirst,
        cShellContextCmdLast, CMF_NORMAL or CMF_EXPLORE)) then
        Exit;

      SetForegroundWindow(OwnerWnd);
      Cmd := UINT(TrackPopupMenu(Menu, TPM_RETURNCMD or TPM_LEFTALIGN or
        TPM_RIGHTBUTTON, AScreenX, AScreenY, 0, OwnerWnd, nil));
      if Cmd <> 0 then
      begin
        FillChar(InvokeInfo, SizeOf(InvokeInfo), 0);
        InvokeInfo.cbSize := SizeOf(InvokeInfo);
        InvokeInfo.fMask := CMIC_MASK_UNICODE;
        InvokeInfo.hwnd := OwnerWnd;
        InvokeInfo.lpVerb := MAKEINTRESOURCEA(Cmd - cShellContextCmdFirst);
        InvokeInfo.nShow := SW_SHOWNORMAL;
        ContextMenu.InvokeCommand(InvokeInfo);
      end;
      Result := True;
    finally
      DestroyMenu(Menu);
    end;
  finally
    CoTaskMemFree(ItemIdList);
  end;
  PostMessage(OwnerWnd, WM_NULL, 0, 0);
end;

function ShellShowProperties(const APaths: TArray<string>; AOwnerHwnd: NativeUInt): Boolean;
var
  Paths: TArray<string>;
  Path: string;
  Pidls: TArray<PItemIDList>;
  Pidl, DesktopPidl: PItemIDList;
  ShellAttrs: ULONG;
  DataObj: Pointer;
  I, N: Integer;
begin
  Result := False;
  SetLength(Paths, 0);
  for Path in APaths do
    if (Trim(Path) <> '') and (TFile.Exists(Path) or TDirectory.Exists(Path)) then
      Paths := Paths + [Trim(Path)];
  if Length(Paths) = 0 then
    Exit;
  if Length(Paths) = 1 then
    Exit(SHObjectProperties(HWND(AOwnerHwnd), SHOP_FILEPATH, PChar(Paths[0]), nil));

  // Several items (possibly from different folders, e.g. Ctrl+B flat view):
  // absolute PIDLs are relative to the desktop, so a data object rooted at
  // the desktop's empty PIDL carries them all to the multi-file sheet.
  SetLength(Pidls, Length(Paths));
  N := 0;
  DesktopPidl := nil;
  try
    for I := 0 to High(Paths) do
    begin
      Pidl := nil;
      ShellAttrs := 0;
      if Succeeded(SHParseDisplayName(PChar(Paths[I]), nil, Pidl, 0, ShellAttrs)) then
      begin
        Pidls[N] := Pidl;
        Inc(N);
      end;
    end;
    if N = 0 then
      Exit;
    if Failed(SHGetSpecialFolderLocation(0, CSIDL_DESKTOP, DesktopPidl)) then
      Exit;
    DataObj := nil;
    if Failed(SHCreateDataObject(DesktopPidl, N, PItemIDList(@Pidls[0]), nil,
      IDataObject, DataObj)) then
      Exit;
    Result := Succeeded(SHMultiFileProperties(IDataObject(DataObj), 0));
    IDataObject(DataObj)._Release;
  finally
    for I := 0 to N - 1 do
      CoTaskMemFree(Pidls[I]);
    if DesktopPidl <> nil then
      CoTaskMemFree(DesktopPidl);
  end;
end;

function TryCreateDetachedProcess(const ACmdLine, AWorkingDir: string): Boolean;
var
  Si: TStartupInfo;
  Pi: TProcessInformation;
  Line, Cwd: string;
  CwdP: PChar;
begin
  Result := False;
  if Trim(ACmdLine) = '' then
    Exit;
  FillChar(Si, SizeOf(Si), 0);
  FillChar(Pi, SizeOf(Pi), 0);
  Si.cb := SizeOf(Si);
  Si.dwFlags := STARTF_USESHOWWINDOW;
  Si.wShowWindow := SW_SHOWNORMAL;
  // CreateProcess may write to the command-line buffer.
  Line := ACmdLine;
  UniqueString(Line);
  if Trim(AWorkingDir) <> '' then
  begin
    Cwd := ExcludeTrailingPathDelimiter(AWorkingDir);
    UniqueString(Cwd);
    CwdP := PChar(Cwd);
  end
  else
    CwdP := nil;
  // CREATE_NEW_CONSOLE: own console for console apps; GUI apps ignore it.
  // Do not wait — close handles immediately (detached from Host / ConPTY).
  if not CreateProcess(nil, PChar(Line), nil, nil, False,
    CREATE_NEW_CONSOLE or CREATE_UNICODE_ENVIRONMENT, nil, CwdP, Si, Pi) then
    Exit;
  CloseHandle(Pi.hThread);
  CloseHandle(Pi.hProcess);
  Result := True;
end;

function ShellRunDetached(const ACommand, AWorkingDir: string): Boolean;
var
  Cmd, Path, Dir: string;
  Code: HINST;
  DirP: PChar;
begin
  Cmd := Trim(ACommand);
  Result := False;
  if Cmd = '' then
    Exit;

  // Single existing file/folder → shell open (associations, Explorer).
  Path := Cmd;
  if (Length(Path) >= 2) and (Path[1] = '"') and (Path[Length(Path)] = '"') then
    Path := Copy(Path, 2, Length(Path) - 2);
  if ((Length(Path) >= 2) and (Path[2] = ':')) or Path.StartsWith('\\') then
  begin
    if TFile.Exists(Path) or TDirectory.Exists(Path) then
    begin
      Dir := ExcludeTrailingPathDelimiter(Trim(AWorkingDir));
      if Dir = '' then
        Dir := ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(Path));
      if Dir <> '' then
        DirP := PChar(Dir)
      else
        DirP := nil;
      Code := ShellExecute(0, 'open', PChar(Path), nil, DirP, SW_SHOWNORMAL);
      Exit(NativeInt(Code) > 32);
    end;
  end;

  // Arbitrary command: own console process; fallback via cmd for builtins/.bat.
  Result := TryCreateDetachedProcess(Cmd, AWorkingDir);
  if not Result then
    Result := TryCreateDetachedProcess('cmd.exe /c ' + Cmd, AWorkingDir);
end;
{$ELSE}

function QueryShellOpen(const AExtension: string): TShellOpenQuery;
begin
  // Future: Linux xdg-mime / macOS Launch Services.
  Result := TShellOpenQuery.None;
  NormalizeFileExtension(AExtension); // keep signature used
end;

function ShellOpenFile(const AFilePath: string): Boolean;
begin
  // Future: xdg-open / open(1).
  Result := False;
  if AFilePath = '' then
    Exit;
end;

function ShellEditFile(const AFilePath: string): Boolean;
begin
  // Future: $VISUAL / $EDITOR, xdg-open.
  Result := False;
  if AFilePath = '' then
    Exit;
end;

function ShellShowContextMenu(const AFilePath: string; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
begin
  // Future: platform file context menu.
  Result := False;
end;

function ShellShowProperties(const APaths: TArray<string>; AOwnerHwnd: NativeUInt): Boolean;
begin
  // Future: platform file manager properties (if any).
  Result := False;
end;

function ShellRunDetached(const ACommand, AWorkingDir: string): Boolean;
begin
  // Future: posix_spawn / open(1) detached.
  Result := False;
  if ACommand = '' then
    Exit;
end;
{$ENDIF}

function HasShellOpen(const AExtension: string): Boolean;
begin
  Result := QueryShellOpen(AExtension).Available;
end;

end.
