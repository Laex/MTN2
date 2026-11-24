unit uEverythingService;

{ The search.files service of the Everything plugin (docs/PLUGIN_SERVICES.md): a request is
  answered from the Everything index. The worker runs the query, reads the size, times and
  attributes of each found file (the query returns names only), applies the size and date
  bounds, sends the hits in messages of at most 500 and then the response. Everything that
  is not running ends the call with -32002 before any hit, so the host falls back to its
  own walk. }

interface

uses
  uPluginHostAbi;

/// <summary>Registers the service with the host; False when the host is too old.</summary>
function RegisterEverythingService(AHost: PHostApiTable; const APluginId: string): Boolean;

/// <summary>Waits for the running workers to finish; call before the library is released.</summary>
procedure StopEverythingService;

implementation

uses
  System.SysUtils, uPluginServiceProvider, uSearchHitsJson, uSearchRequest, uEverythingFormat, uEverythingIpc;

const
  cServiceName = 'search.files';
  cHitsPerMessage = 500;
  cDefaultMaxResults = 50000;
  cDescribe =
    '{"protocolVersion":1,"name":"search.files","version":1,"title":"Everything",' +
    '"description":"Finds files and folders by name with the Everything index",' +
    '"inputSchema":{"type":"object","properties":{"root":{"type":"string"},"mask":{"type":"string"},' +
    '"subdirs":{"type":"boolean"},"caseSensitive":{"type":"boolean"}},"required":["root"]},' +
    '"capabilities":["name","mask","path","subdirs","case","words","folders","size","date","list"]}';

var
  GProvider: TServiceProvider;

procedure Answer(AJob: TServiceJob; const ARequestJson: string);
var
  Req: TSearchRequest;
  Items: TEvItems;
  Kept: TArray<TSearchHit>;
  Hit: TSearchHit;
  Err: string;
  I, Max, Sent, N: Integer;
  Truncated: Boolean;
begin
  if not ParseSearchRequest(ARequestJson, Req) then
  begin
    AJob.ReplyError(-32602, 'bad parameters');
    Exit;
  end;
  Max := Req.MaxResults;
  if Max <= 0 then
    Max := cDefaultMaxResults;
  if not EverythingSearch(BuildEverythingQuery(Req), cDefaultMaxResults, Items, Err) then
  begin
    AJob.ReplyError(-32002, Err);
    Exit;
  end;
  // A network share is not in the index unless the user added it; an empty answer there
  // ends the call with an error so the host lists the names with its own walk.
  if (Length(Items) = 0) and EverythingRootIsRemote(Req.Root) then
  begin
    AJob.ReplyError(-32002, 'the folder is not indexed by Everything');
    Exit;
  end;
  Truncated := Length(Items) >= cDefaultMaxResults;

  SetLength(Kept, 0);
  for I := 0 to High(Items) do
  begin
    if AJob.IsCancelled then
      Exit;
    Hit := NewSearchHit(ItemPath(Items[I]), Items[I].IsDir);
    if not ReadHitFileInfo(Hit) then
      Continue; // gone since Everything indexed it
    if SearchRequestHasBounds(Req) and not SearchRequestBoundsPass(Req, Hit.IsDir, Hit.Size, Hit.Modified) then
      Continue;
    if Length(Kept) >= Max then
    begin
      Truncated := True;
      Break;
    end;
    SetLength(Kept, Length(Kept) + 1);
    Kept[High(Kept)] := Hit;
  end;

  Sent := 0;
  while Sent < Length(Kept) do
  begin
    if AJob.IsCancelled then
      Exit;
    N := Length(Kept) - Sent;
    if N > cHitsPerMessage then
      N := cHitsPerMessage;
    AJob.Notify(BuildSearchHitsMessage(Kept, Sent, N));
    Inc(Sent, N);
  end;
  if AJob.IsCancelled then
    Exit;
  AJob.ReplyResult('{"content":[{"type":"text","text":"' + IntToStr(Length(Kept)) +
    ' found"}],"structuredContent":{"count":' + IntToStr(Length(Kept)) +
    ',"truncated":' + LowerCase(BoolToStr(Truncated, True)) + '}}');
end;

function RegisterEverythingService(AHost: PHostApiTable; const APluginId: string): Boolean;
begin
  FreeAndNil(GProvider);
  GProvider := TServiceProvider.Create(AHost, Answer);
  Result := GProvider.Register(APluginId, cServiceName, cDescribe, 50);
end;

procedure StopEverythingService;
begin
  FreeAndNil(GProvider);
end;

end.
