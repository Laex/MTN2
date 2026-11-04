unit uWinSysVfs;

{ The version 2 VFS callbacks for reg://, proc:// and svc://. Each call turns
  the address into a kind (registry, processes, services) and path segments,
  runs the operation in the matching unit and maps the Win32 error code to a
  result code of the plugin ABI.

    reg:///                      the five hives
    reg:///HKEY_.../Key/Sub      keys are folders, values are files
    proc:///                     one file per process, "name.exe (pid)"
    svc:///                      one file per service, by its short name

  F3 on a value, process or service shows its details; F4 on a value edits it;
  Delete removes a key, value or ends a process. }

interface

uses
  uPluginHostAbi;

type
  /// <summary>Gets the folder address and a JSON object {row name: color role}
  /// after a listing of svc:///. Called on the thread that listed.</summary>
  TRowColorsEvent = procedure(const AFolderUri, AJson: string);

var
  GOnServiceColors: TRowColorsEvent;

function WinSysVfsCallbacks: TVfsCallbacksCdeclV2;

implementation

uses
  System.SysUtils, System.JSON, Winapi.Windows, uWinSysFormat, uWinSysRegistry,
  uWinSysProcess, uWinSysServices;

function ResultOf(ACtx: PVfsOpContext; AErr: Cardinal): Int64;
var
  Text: UTF8String;
begin
  case AErr of
    0: Exit(Ord(verOk));
    ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, cErrorNotFound,
    ERROR_INVALID_PARAMETER, ERROR_SERVICE_DOES_NOT_EXIST:
      Result := Ord(verNotFound);
    ERROR_ACCESS_DENIED, ERROR_PRIVILEGE_NOT_HELD:
      Result := Ord(verAccessDenied);
    ERROR_ALREADY_EXISTS:
      Result := Ord(verAlreadyExists);
  else
    Result := Ord(verIOError);
  end;
  if (ACtx <> nil) and Assigned(ACtx^.SetErrorText) then
  begin
    Text := UTF8String(SysErrorMessage(AErr));
    ACtx^.SetErrorText(ACtx, PAnsiChar(Text));
  end;
end;

function Fail(ACtx: PVfsOpContext; ACode: TVfsCdeclResult; const AText: string): Int64;
var
  Text: UTF8String;
begin
  if (ACtx <> nil) and Assigned(ACtx^.SetErrorText) and (AText <> '') then
  begin
    Text := UTF8String(AText);
    ACtx^.SetErrorText(ACtx, PAnsiChar(Text));
  end;
  Result := Ord(ACode);
end;

function UriOf(AURI: PAnsiChar): string;
begin
  Result := string(UTF8String(AURI));
end;

procedure PutBytes(const ABytes: TBytes; ABuf: PByte; ABufSize: Int64; ATerminate: Boolean;
  out ANegotiated: Int64; out AFits: Boolean);
var
  Need: Int64;
begin
  Need := Length(ABytes);
  if ATerminate then
    Inc(Need);
  AFits := Need <= ABufSize;
  // Fitting: the length of the data alone (no terminator); otherwise the size to ask for.
  if AFits then
    ANegotiated := Length(ABytes)
  else
    ANegotiated := Need;
  if not AFits then
    Exit;
  if Length(ABytes) > 0 then
    Move(ABytes[0], ABuf^, Length(ABytes));
  if ATerminate then
    ABuf[Length(ABytes)] := 0;
end;

function EntryJson(const AName: string; AIsDir: Boolean; ASize, AModified: Int64): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('size', TJSONNumber.Create(ASize));
  Result.AddPair('isDir', TJSONBool.Create(AIsDir));
  Result.AddPair('isLink', TJSONBool.Create(False));
  Result.AddPair('isHidden', TJSONBool.Create(False));
  if AModified > 0 then
    Result.AddPair('modified', TJSONNumber.Create(AModified));
end;

/// <summary>Adds a panel column cell (see cPanelColumnsJson in the plugin project)
/// to AEntry's "extra" object, creating the object on the first cell.</summary>
procedure AddCell(const AEntry: TJSONObject; const AColumn, AText: string);
var
  Extra: TJSONObject;
begin
  Extra := AEntry.GetValue('extra') as TJSONObject;
  if Extra = nil then
  begin
    Extra := TJSONObject.Create;
    AEntry.AddPair('extra', Extra);
  end;
  Extra.AddPair(AColumn, AText);
end;

/// <summary>As AddCell for a number: the text is shown, the value sorts.</summary>
procedure AddNumberCell(const AEntry: TJSONObject; const AColumn: string; AValue: Int64);
var
  Extra, Cell: TJSONObject;
begin
  Extra := AEntry.GetValue('extra') as TJSONObject;
  if Extra = nil then
  begin
    Extra := TJSONObject.Create;
    AEntry.AddPair('extra', Extra);
  end;
  Cell := TJSONObject.Create;
  Cell.AddPair('t', IntToStr(AValue));
  Cell.AddPair('n', TJSONNumber.Create(AValue));
  Extra.AddPair(AColumn, Cell);
end;

function ListRegistry(const ASegs: TArray<string>; const AArr: TJSONArray): Cardinal;
var
  Rows: TRegRows;
  R: TRegRow;
begin
  Result := RegListPath(ASegs, Rows);
  if Result <> 0 then
    Exit;
  for R in Rows do
    AArr.AddElement(EntryJson(R.Name, R.IsKey, R.Size, R.Modified));
end;

function ListProcessRows(const AArr: TJSONArray): Cardinal;
var
  Rows: TProcRows;
  R: TProcRow;
  Entry: TJSONObject;
begin
  Result := ListProcesses(Rows);
  if Result <> 0 then
    Exit;
  for R in Rows do
  begin
    Entry := EntryJson(MakeProcessName(R.Exe, R.Pid), False, R.WorkingSet, R.Started);
    AddNumberCell(Entry, 'pid', R.Pid);
    AddNumberCell(Entry, 'ppid', R.ParentPid);
    AddNumberCell(Entry, 'threads', R.Threads);
    AArr.AddElement(Entry);
  end;
end;

function ListServiceRows(const AFolderUri: string; const AArr: TJSONArray): Cardinal;
var
  Rows: TSvcRows;
  R: TSvcRow;
  Colors: TJSONObject;
  Name: string;
  Entry: TJSONObject;
begin
  Result := ListServices(Rows);
  if Result <> 0 then
    Exit;
  Colors := TJSONObject.Create;
  try
    for R in Rows do
    begin
      Name := EncodeSegment(R.Name);
      Entry := EntryJson(Name, False, 0, 0);
      AddCell(Entry, 'state', ServiceStateName(R.State));
      AddCell(Entry, 'display', R.Display);
      if R.Pid <> 0 then
        AddNumberCell(Entry, 'pid', R.Pid);
      AArr.AddElement(Entry);
      Colors.AddPair(Name, ServiceStateRole(R.State));
    end;
    if Assigned(GOnServiceColors) then
      GOnServiceColors(AFolderUri, Colors.ToJSON);
  finally
    Colors.Free;
  end;
end;

function VfsListDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  Uri: string;
  Kind: TWinSysKind;
  Segs: TArray<string>;
  Arr: TJSONArray;
  Err: Cardinal;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiatedSize := 0;
  AMore := 0;
  try
    Uri := UriOf(AURI);
    if not ParseWinSysUri(Uri, Kind, Segs) then
      Exit(Ord(verInvalidURI));
    Arr := TJSONArray.Create;
    try
      case Kind of
        wkReg: Err := ListRegistry(Segs, Arr);
        wkProc:
          if Length(Segs) = 0 then
            Err := ListProcessRows(Arr)
          else
            Err := ERROR_PATH_NOT_FOUND;
        wkSvc:
          if Length(Segs) = 0 then
            Err := ListServiceRows(Uri, Arr)
          else
            Err := ERROR_PATH_NOT_FOUND;
      else
        Err := ERROR_PATH_NOT_FOUND;
      end;
      if Err <> 0 then
        Exit(ResultOf(ACtx, Err));
      // The whole listing goes in one page; a bigger one is asked again with a bigger buffer.
      if AOffset > 0 then
        Exit(Ord(verOk));
      Bytes := TEncoding.UTF8.GetBytes(Arr.ToJSON);
    finally
      Arr.Free;
    end;
    PutBytes(Bytes, PByte(ABuf), ABufSize, True, ANegotiatedSize, Fits);
    if not Fits then
      Exit(Ord(verNeedsBiggerBuffer));
    Result := Ord(verOk);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function ProcessExists(APid: Cardinal): Boolean;
var
  Rows: TProcRows;
  R: TProcRow;
begin
  Result := False;
  if ListProcesses(Rows) <> 0 then
    Exit;
  for R in Rows do
    if R.Pid = APid then
      Exit(True);
end;

function ServiceExists(const AName: string): Boolean;
var
  Rows: TSvcRows;
  R: TSvcRow;
begin
  Result := False;
  if ListServices(Rows) <> 0 then
    Exit;
  for R in Rows do
    if SameText(R.Name, AName) then
      Exit(True);
end;

function VfsExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
  PathKind: TRegPathKind;
  Pid: Cardinal;
  Err: Cardinal;
begin
  AIsDirectory := 0;
  try
    if not ParseWinSysUri(UriOf(AURI), Kind, Segs) then
      Exit(Ord(verInvalidURI));
    case Kind of
      wkReg:
        begin
          Err := RegPathInfo(Segs, PathKind);
          if Err <> 0 then
            Exit(ResultOf(nil, Err));
          if PathKind <> rpValue then
            AIsDirectory := 1;
          Result := Ord(verOk);
        end;
      wkProc:
        if Length(Segs) = 0 then
        begin
          AIsDirectory := 1;
          Result := Ord(verOk);
        end
        else if (Length(Segs) = 1) and ParseProcessName(Segs[0], Pid) and ProcessExists(Pid) then
          Result := Ord(verOk)
        else
          Result := Ord(verNotFound);
      wkSvc:
        if Length(Segs) = 0 then
        begin
          AIsDirectory := 1;
          Result := Ord(verOk);
        end
        else if (Length(Segs) = 1) and ServiceExists(Segs[0]) then
          Result := Ord(verOk)
        else
          Result := Ord(verNotFound);
    else
      Result := Ord(verInvalidURI);
    end;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

// The text F3 shows for a value, a process or a service.
function ItemText(const AUri: string; out AText: string): Cardinal;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
  RegType: Cardinal;
  Data: TBytes;
  Pid: Cardinal;
begin
  AText := '';
  if not ParseWinSysUri(AUri, Kind, Segs) then
    Exit(ERROR_PATH_NOT_FOUND);
  case Kind of
    wkReg:
      begin
        Result := RegReadValue(Segs, RegType, Data);
        if Result = 0 then
          AText := FormatRegValue(RegType, Data);
      end;
    wkProc:
      if (Length(Segs) = 1) and ParseProcessName(Segs[0], Pid) then
        Result := ProcessInfoText(Pid, AText)
      else
        Result := ERROR_PATH_NOT_FOUND;
    wkSvc:
      if Length(Segs) = 1 then
        Result := ServiceInfoText(Segs[0], AText)
      else
        Result := ERROR_PATH_NOT_FOUND;
  else
    Result := ERROR_PATH_NOT_FOUND;
  end;
end;

function ReadItem(AURI: PAnsiChar; AMaxBytes: Int64; ACtx: PVfsOpContext; ABuf: PByte;
  ABufSize: Int64; ATerminate: Boolean; out ANegotiated: Int64): Int64;
var
  Text: string;
  Err: Cardinal;
  Bytes: TBytes;
  Fits: Boolean;
begin
  ANegotiated := 0;
  try
    Err := ItemText(UriOf(AURI), Text);
    if Err <> 0 then
      Exit(ResultOf(ACtx, Err));
    Bytes := TEncoding.UTF8.GetBytes(Text);
    if (AMaxBytes > 0) and (Length(Bytes) > AMaxBytes) then
      SetLength(Bytes, AMaxBytes);
    PutBytes(Bytes, ABuf, ABufSize, ATerminate, ANegotiated, Fits);
    if Fits then
      Result := Ord(verOk)
    else
      Result := Ord(verNeedsBiggerBuffer);
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PAnsiChar; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  Result := ReadItem(AURI, AMaxBytes, ACtx, PByte(ABuf), ABufSize, True, ANegotiatedSize);
end;

function VfsReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext; ABuf: PByte; ABufSize: Int64;
  out ANegotiatedSize: Int64): Int64; cdecl;
begin
  Result := ReadItem(AURI, AMaxBytes, ACtx, ABuf, ABufSize, False, ANegotiatedSize);
end;

function VfsWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
  OldType, NewType: Cardinal;
  OldData, NewData: TBytes;
begin
  try
    if not ParseWinSysUri(UriOf(AURI), Kind, Segs) then
      Exit(Ord(verInvalidURI));
    if Kind <> wkReg then
      Exit(Fail(ACtx, verNotSupported, 'Only registry values can be edited'));
    if Length(Segs) < 2 then
      Exit(Fail(ACtx, verNotSupported, 'A hive cannot be written'));
    // A value that is not there yet is made as a string; an existing one keeps its type.
    if RegReadValue(Segs, OldType, OldData) <> 0 then
      OldType := cRegSz;
    if not ParseRegValueText(string(UTF8String(AText)), OldType, NewType, NewData) then
      Exit(Fail(ACtx, verIOError, 'The text does not fit the type of the value (' +
        RegTypeName(OldType) + ')'));
    Result := ResultOf(ACtx, RegWriteValue(Segs, NewType, NewData));
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
  Pid: Cardinal;
begin
  try
    if not ParseWinSysUri(UriOf(AURI), Kind, Segs) then
      Exit(Ord(verInvalidURI));
    case Kind of
      wkReg:
        Result := ResultOf(ACtx, RegDeletePath(Segs));
      wkProc:
        if (Length(Segs) = 1) and ParseProcessName(Segs[0], Pid) then
          Result := ResultOf(ACtx, TerminateProcessById(Pid))
        else
          Result := Ord(verNotFound);
    else
      Result := Fail(ACtx, verNotSupported, 'A service is not deleted here: use the Services entries of the Plugins menu');
    end;
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsCreateDirectory(AURI: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
begin
  try
    if not ParseWinSysUri(UriOf(AURI), Kind, Segs) then
      Exit(Ord(verInvalidURI));
    if Kind <> wkReg then
      Exit(Fail(ACtx, verNotSupported, 'Only registry keys can be created'));
    Result := ResultOf(ACtx, RegCreateKeyPath(Segs));
  except
    on E: Exception do
      Result := Fail(ACtx, verIOError, E.Message);
  end;
end;

function VfsCopyItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := Fail(ACtx, verNotSupported, 'Copying is not supported here');
end;

function VfsGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AFree, ATotal: Int64): Int64; cdecl;
begin
  AFree := 0;
  ATotal := 0;
  Result := Ord(verNotSupported);
end;

function WinSysVfsCallbacks: TVfsCallbacksCdeclV2;
begin
  Result := Default(TVfsCallbacksCdeclV2);
  Result.ListDirectory := VfsListDirectory;
  Result.Delete := VfsDelete;
  Result.CreateDirectory := VfsCreateDirectory;
  Result.CopyItem := VfsCopyItem;
  Result.MoveItem := VfsCopyItem;
  Result.ReadText := VfsReadText;
  Result.ReadBytes := VfsReadBytes;
  Result.WriteText := VfsWriteText;
  Result.Exists := VfsExists;
  Result.GetFreeSpace := VfsGetFreeSpace;
end;

end.
