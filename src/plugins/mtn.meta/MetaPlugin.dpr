library MetaPlugin;

{ Native MTN2 plugin: a status line segment with the metadata of the file under
  the panel cursor - the size and the camera of an image, the tags of an MP3
  file, the version of an executable. A worker thread reads the file; the
  segment is set on the main thread through PostToMain. }

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uMetaFormat in 'uMetaFormat.pas',
  uMetaReader in 'uMetaReader.pas';

const
  cPluginId = 'mtn.meta';
  cSegmentId = 'meta';
  cPollMs = 400;

type
  TMetaWorker = class(TThread)
  private
    FWake: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Wake;
  end;

var
  GHostApi: THostApiTable;
  GLock: TCriticalSection;
  GCursorUri: string;
  GPendingText: string;
  GWorker: TMetaWorker;

procedure SetSegment(const AText: string);
var
  Id, Seg, Text: UTF8String;
begin
  if not Assigned(GHostApi.SetStatusSegment) then
    Exit;
  Id := UTF8String(cPluginId);
  Seg := UTF8String(cSegmentId);
  Text := UTF8String(AText);
  GHostApi.SetStatusSegment(PAnsiChar(Id), PAnsiChar(Seg), PAnsiChar(Text));
end;

// The address of the row under the cursor in the active panel.
function CursorOf(const APanelInfo: string): string;
var
  Root, Side: TJSONValue;
  Active: string;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(APanelInfo);
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := Root.GetValue<TJSONValue>(Active, nil);
    if Side is TJSONObject then
      Side.TryGetValue<string>('cursor', Result);
  finally
    Root.Free;
  end;
end;

{ Main thread: PanelInfo is read here only. }
procedure MainTick(AUserData: Pointer); cdecl;
var
  Buf: UTF8String;
  Len: Int64;
  Uri: string;
begin
  try
    if not Assigned(GHostApi.PanelInfo) then
      Exit;
    Len := GHostApi.PanelInfo(nil, 0);
    if Len <= 0 then
      Exit;
    SetLength(Buf, Len + 1);
    Len := GHostApi.PanelInfo(PAnsiChar(Buf), Length(Buf));
    if (Len <= 0) or (Len >= Length(Buf)) then
      Exit;
    Uri := CursorOf(UTF8ToString(PAnsiChar(Buf)));
    GLock.Enter;
    try
      GCursorUri := Uri;
    finally
      GLock.Leave;
    end;
  except
  end;
end;

procedure MainApply(AUserData: Pointer); cdecl;
var
  Text: string;
begin
  try
    GLock.Enter;
    try
      Text := GPendingText;
    finally
      GLock.Leave;
    end;
    SetSegment(Text);
  except
  end;
end;

procedure PostToMain(ACallback: THostMainCallback);
var
  Id: UTF8String;
begin
  if not Assigned(GHostApi.PostToMain) then
    Exit;
  Id := UTF8String(cPluginId);
  GHostApi.PostToMain(PAnsiChar(Id), ACallback, nil);
end;

constructor TMetaWorker.Create;
begin
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TMetaWorker.Destroy;
begin
  FWake.Free;
  inherited;
end;

procedure TMetaWorker.Wake;
begin
  FWake.SetEvent;
end;

procedure TMetaWorker.Execute;
var
  Uri, LastUri, Path, Text, LastText: string;
begin
  LastUri := #0;
  LastText := #0;
  while not Terminated do
  begin
    PostToMain(MainTick);
    FWake.WaitFor(cPollMs);
    if Terminated then
      Break;
    GLock.Enter;
    try
      Uri := GCursorUri;
    finally
      GLock.Leave;
    end;
    if Uri = LastUri then
      Continue;
    LastUri := Uri;
    Text := '';
    if Uri.StartsWith('file:', True) then
    begin
      Path := FileUriToPath(Uri);
      if Path <> '' then
        Text := DescribeFile(Path);
    end;
    if Terminated then
      Break;
    if Text <> LastText then
    begin
      LastText := Text;
      GLock.Enter;
      try
        GPendingText := Text;
      finally
        GLock.Leave;
      end;
      PostToMain(MainApply);
    end;
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
begin
  if AHostApi = nil then
    Exit(-1);
  GHostApi := AHostApi^;
  if not (Assigned(GHostApi.SetStatusSegment) and Assigned(GHostApi.PanelInfo) and
     Assigned(GHostApi.PostToMain)) then
    Exit(-1);
  GLock := TCriticalSection.Create;
  GWorker := TMetaWorker.Create;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  if Assigned(GWorker) then
  begin
    GWorker.Terminate;
    GWorker.Wake;
    GWorker.WaitFor;
    FreeAndNil(GWorker);
  end;
  SetSegment('');
  FreeAndNil(GLock);
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
