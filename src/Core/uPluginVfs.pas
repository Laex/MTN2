unit uPluginVfs;

{ Read access to the virtual file system for plugins (permission "vfs.read").
  The calls are asynchronous: the plugin starts one and its callback runs once on
  the main thread, with a status and the result. A plugin that was unloaded in
  the meantime hears nothing. The plugin passes any URI the program understands
  (file:///, archives, sftp://, a scheme another plugin serves). }

interface

uses
  System.SysUtils;

const
  cPluginVfsOk: Integer = 0;
  cPluginVfsNotFound: Integer = 1;
  cPluginVfsAccessDenied: Integer = 2;
  cPluginVfsNotSupported: Integer = 3;
  cPluginVfsCancelled: Integer = 4;
  cPluginVfsIoError: Integer = 5;
  cPluginVfsInvalidUri: Integer = 6;
  /// <summary>Returned by the start calls (no callback follows): the plugin has
  /// not been granted "vfs.read".</summary>
  cPluginVfsNoPermission: Integer = -2;
  /// <summary>Largest read the host does for a plugin.</summary>
  cPluginVfsMaxRead = 64 * 1024 * 1024;
  cPluginVfsDefaultRead = 2 * 1024 * 1024;
  cPluginVfsMaxEntries = 100000;

type
  TPluginVfsTextDone = reference to procedure(AStatus: Integer; const AText: string);
  TPluginVfsDataDone = reference to procedure(AStatus: Integer; const AData: TBytes);

/// <summary>Lists a folder. The text is JSON: uri, and entries of name, uri, dir,
/// size and modified (seconds since 1970, local time). 0 = started,
/// cPluginVfsNoPermission, -1 = bad arguments.</summary>
function PluginVfsList(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
/// <summary>Whether the URI exists. The text is JSON: exists and dir.</summary>
function PluginVfsExists(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
/// <summary>Reads a whole file; AMaxBytes of 0 or less means the default of 2 MB, the
/// most is 64 MB. A larger file ends with cPluginVfsNotSupported.</summary>
function PluginVfsRead(const APluginId, AUri: string; AMaxBytes: Int64;
  const ADone: TPluginVfsDataDone): Integer;

/// <summary>Replaces the file system the calls use (tests); nil restores the default.</summary>
procedure SetPluginVfs(const AVfs: IInterface);

implementation

uses
  System.Classes, System.JSON, System.DateUtils,
  uVfsTypes, uVfsRegistry, uPluginPermissions, uPluginServices;

var
  GVfs: IVirtualFileSystem;

procedure SetPluginVfs(const AVfs: IInterface);
begin
  if AVfs = nil then
    GVfs := nil
  else
    Supports(AVfs, IVirtualFileSystem, GVfs);
end;

function Vfs: IVirtualFileSystem;
begin
  if GVfs = nil then
    GVfs := CreateDefaultVfs;
  Result := GVfs;
end;

function StatusOf(const AError: TVfsError): Integer;
begin
  case AError.Code of
    vecOk: Result := cPluginVfsOk;
    vecNotFound: Result := cPluginVfsNotFound;
    vecAccessDenied: Result := cPluginVfsAccessDenied;
    vecNotSupported, vecAlreadyExists: Result := cPluginVfsNotSupported;
    vecCancelled: Result := cPluginVfsCancelled;
    vecInvalidURI: Result := cPluginVfsInvalidUri;
  else
    Result := cPluginVfsIoError;
  end;
end;

/// <summary>Runs ABody on the main thread on a later pass of the message loop (so the
/// plugin always gets its callback after the start call returned), unless the plugin
/// was unloaded since AGen was read.</summary>
procedure DeliverLater(const AId: string; AGen: Integer; const ABody: TProc);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      if PluginGenerationOf(AId) <> AGen then
        Exit;
      try
        ABody();
      except
        // A faulty plugin callback must not break the message loop.
      end;
    end);
end;

function Allowed(const APluginId, AUri: string): Boolean;
begin
  Result := (Trim(APluginId) <> '') and (Trim(AUri) <> '');
end;

function ListToJson(const AUri: string; const AItems: TArray<TVfsEntry>): string;
var
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  E: TVfsEntry;
  Count: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('uri', AUri);
    Arr := TJSONArray.Create;
    Root.AddPair('entries', Arr);
    Count := 0;
    for E in AItems do
    begin
      if Count >= cPluginVfsMaxEntries then
        Break;
      Item := TJSONObject.Create;
      Item.AddPair('name', E.Name);
      if E.TargetURI <> '' then
        Item.AddPair('uri', E.TargetURI)
      else
        Item.AddPair('uri', JoinVfsUri(AUri, E.Name));
      Item.AddPair('dir', TJSONBool.Create(E.IsDirectory));
      Item.AddPair('size', TJSONNumber.Create(E.Size));
      Item.AddPair('modified', TJSONNumber.Create(DateTimeToUnix(E.ModificationTime, False)));
      Arr.AddElement(Item);
      Inc(Count);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function PluginVfsList(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
var
  Id: string;
  Gen: Integer;
  Uri: string;
begin
  if not Allowed(APluginId, AUri) or not Assigned(ADone) then
    Exit(-1);
  if not PluginHasPermission(APluginId, cPermVfsRead) then
    Exit(cPluginVfsNoPermission);
  Id := APluginId;
  Uri := Trim(AUri);
  Gen := PluginGenerationOf(Id);
  Vfs.ListDirectoryAsync(Uri, nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    var
      Status: Integer;
      Json: string;
    begin
      Status := StatusOf(AError);
      Json := '';
      if Status = cPluginVfsOk then
        Json := ListToJson(Uri, AItems);
      DeliverLater(Id, Gen,
        procedure
        begin
          ADone(Status, Json);
        end);
    end);
  Result := 0;
end;

function PluginVfsExists(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
var
  Id: string;
  Gen: Integer;
begin
  if not Allowed(APluginId, AUri) or not Assigned(ADone) then
    Exit(-1);
  if not PluginHasPermission(APluginId, cPermVfsRead) then
    Exit(cPluginVfsNoPermission);
  Id := APluginId;
  Gen := PluginGenerationOf(Id);
  Vfs.ExistsAsync(Trim(AUri), nil,
    procedure(const AExists, AIsDirectory: Boolean; const AError: TVfsError)
    var
      Obj: TJSONObject;
      Status: Integer;
      Json: string;
    begin
      Status := StatusOf(AError);
      Json := '';
      if Status = cPluginVfsOk then
      begin
        Obj := TJSONObject.Create;
        try
          Obj.AddPair('exists', TJSONBool.Create(AExists));
          Obj.AddPair('dir', TJSONBool.Create(AExists and AIsDirectory));
          Json := Obj.ToJSON;
        finally
          Obj.Free;
        end;
      end;
      DeliverLater(Id, Gen,
        procedure
        begin
          ADone(Status, Json);
        end);
    end);
  Result := 0;
end;

function PluginVfsRead(const APluginId, AUri: string; AMaxBytes: Int64;
  const ADone: TPluginVfsDataDone): Integer;
var
  Id: string;
  Gen: Integer;
begin
  if not Allowed(APluginId, AUri) or not Assigned(ADone) then
    Exit(-1);
  if not PluginHasPermission(APluginId, cPermVfsRead) then
    Exit(cPluginVfsNoPermission);
  if AMaxBytes <= 0 then
    AMaxBytes := cPluginVfsDefaultRead;
  if AMaxBytes > cPluginVfsMaxRead then
    AMaxBytes := cPluginVfsMaxRead;
  Id := APluginId;
  Gen := PluginGenerationOf(Id);
  Vfs.ReadBytesAsync(Trim(AUri), AMaxBytes, nil,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    var
      Status: Integer;
      Bytes: TBytes;
    begin
      Status := StatusOf(AError);
      Bytes := nil;
      if Status = cPluginVfsOk then
        Bytes := ABytes;
      DeliverLater(Id, Gen,
        procedure
        begin
          ADone(Status, Bytes);
        end);
    end);
  Result := 0;
end;

end.
