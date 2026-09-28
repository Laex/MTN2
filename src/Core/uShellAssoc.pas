unit uShellAssoc;

{ Platform shell file associations (open handler probe + open).
  Host/UI code uses only this unit - Windows today, other OS later. }

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

/// <summary>Open a URL (https://..., mailto:...) with the OS default handler,
/// e.g. the default browser. Returns False on failure.</summary>
function ShellOpenUrl(const AUrl: string): Boolean;

/// <summary>Show the OS shell context menu for a local file or folder at screen coords.
/// AOwnerHwnd must be the host window (SetForegroundWindow / menu routing).</summary>
function ShellShowContextMenu(const AFilePath: string; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
/// <summary>Same for several local files / folders (the panel selection):
/// one folder's items get that folder's menu, items from several folders
/// the desktop's (Explorer's multi-folder menu).</summary>
function ShellShowContextMenuFor(const APaths: TArray<string>; AScreenX, AScreenY: Integer;
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
  // File name -> extension; bare "pdf" -> ".pdf".
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

function ShellOpenUrl(const AUrl: string): Boolean;
var
  Url: string;
  Code: HINST;
begin
  Url := Trim(AUrl);
  Result := False;
  if Url = '' then
    Exit;
  Code := ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
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
begin
  Result := ShellShowContextMenuFor([AFilePath], AScreenX, AScreenY, AOwnerHwnd);
end;

function RunShellContextMenu(const AContextMenu: IContextMenu; AScreenX, AScreenY: Integer;
  AOwnerWnd: HWND): Boolean;
var
  Menu: HMENU;
  Cmd: UINT;
  InvokeInfo: TCMInvokeCommandInfo;
begin
  Result := False;
  Menu := CreatePopupMenu;
  if Menu = 0 then
    Exit;
  try
    if Failed(AContextMenu.QueryContextMenu(Menu, 0, cShellContextCmdFirst,
      cShellContextCmdLast, CMF_NORMAL or CMF_EXPLORE)) then
      Exit;
    SetForegroundWindow(AOwnerWnd);
    Cmd := UINT(TrackPopupMenu(Menu, TPM_RETURNCMD or TPM_LEFTALIGN or
      TPM_RIGHTBUTTON, AScreenX, AScreenY, 0, AOwnerWnd, nil));
    if Cmd <> 0 then
    begin
      FillChar(InvokeInfo, SizeOf(InvokeInfo), 0);
      InvokeInfo.cbSize := SizeOf(InvokeInfo);
      InvokeInfo.fMask := CMIC_MASK_UNICODE;
      InvokeInfo.hwnd := AOwnerWnd;
      InvokeInfo.lpVerb := MAKEINTRESOURCEA(Cmd - cShellContextCmdFirst);
      InvokeInfo.nShow := SW_SHOWNORMAL;
      AContextMenu.InvokeCommand(InvokeInfo);
    end;
    Result := True;
  finally
    DestroyMenu(Menu);
  end;
  PostMessage(AOwnerWnd, WM_NULL, 0, 0);
end;

function ShellShowContextMenuFor(const APaths: TArray<string>; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
var
  Paths: TArray<string>;
  Path, Dir: string;
  Abs, Rel: TArray<PItemIDList>;
  Pidl: PItemIDList;
  ShellAttrs: ULONG;
  Folder: IShellFolder;
  FolderObj, MenuObj: Pointer;
  SameDir: Boolean;
  I, N: Integer;
  OwnerWnd: HWND;
begin
  Result := False;
  OwnerWnd := HWND(AOwnerHwnd);
  if OwnerWnd = 0 then
    Exit;
  SetLength(Paths, 0);
  for Path in APaths do
    if (Trim(Path) <> '') and (TFile.Exists(Trim(Path)) or TDirectory.Exists(Trim(Path))) then
      Paths := Paths + [Trim(Path)];
  if Length(Paths) = 0 then
    Exit;

  SetLength(Abs, Length(Paths));
  N := 0;
  try
    for I := 0 to High(Paths) do
    begin
      Pidl := nil;
      ShellAttrs := 0;
      if Succeeded(SHParseDisplayName(PChar(Paths[I]), nil, Pidl, 0, ShellAttrs)) then
      begin
        Abs[N] := Pidl;
        Inc(N);
      end;
    end;
    if N = 0 then
      Exit;

    // Items of one folder: that folder's menu over their relative ids, as
    // Explorer does. Items from several folders (Ctrl+B flat view): the
    // desktop folder accepts absolute ids for all of them.
    Dir := ExtractFileDir(Paths[0]);
    SameDir := True;
    for I := 1 to High(Paths) do
      if not SameText(ExtractFileDir(Paths[I]), Dir) then
      begin
        SameDir := False;
        Break;
      end;

    MenuObj := nil;
    if SameDir then
    begin
      FolderObj := nil;
      if Failed(SHBindToParent(Abs[0], IShellFolder, FolderObj, Pidl)) then
        Exit;
      Folder := IShellFolder(FolderObj);
      SetLength(Rel, N);
      for I := 0 to N - 1 do
        Rel[I] := ILFindLastID(Abs[I]);
      if Failed(Folder.GetUIObjectOf(OwnerWnd, N, Rel[0], IID_IContextMenu, nil, MenuObj)) then
        Exit;
    end
    else
    begin
      if Failed(SHGetDesktopFolder(Folder)) then
        Exit;
      if Failed(Folder.GetUIObjectOf(OwnerWnd, N, Abs[0], IID_IContextMenu, nil, MenuObj)) then
        Exit;
    end;
    Result := RunShellContextMenu(IContextMenu(MenuObj), AScreenX, AScreenY, OwnerWnd);
  finally
    for I := 0 to N - 1 do
      CoTaskMemFree(Abs[I]);
  end;
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
  // Do not wait - close handles immediately (detached from Host / ConPTY).
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

  // Single existing file/folder -> shell open (associations, Explorer).
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

function ShellShowContextMenuFor(const APaths: TArray<string>; AScreenX, AScreenY: Integer;
  AOwnerHwnd: NativeUInt): Boolean;
begin
  Result := False;
end;

function ShellShowProperties(const APaths: TArray<string>; AOwnerHwnd: NativeUInt): Boolean;
begin
  // Future: platform file manager properties (if any).
  Result := False;
end;

function ShellOpenUrl(const AUrl: string): Boolean;
begin
  // Future: xdg-open / open(1).
  Result := False;
  if AUrl = '' then
    Exit;
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
