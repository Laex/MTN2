unit uRipgrepService;

{ The search.files service of the ripgrep plugin (docs/PLUGIN_SERVICES.md): a search for
  text inside files. The worker runs rg with an argument list (no shell), reads the files
  it reports, adds size, times and attributes, applies the size and date bounds and sends
  the hits. While rg runs the worker sends a progress message every few seconds so the host
  does not take the silence for a hang. A missing rg ends the call with -32002 before any
  hit, so the host falls back to its own walk. }

interface

uses
  uPluginHostAbi;

/// <summary>Registers the service with the host; False when the host is too old.</summary>
function RegisterRipgrepService(AHost: PHostApiTable; const APluginId: string): Boolean;

/// <summary>Waits for the running workers to finish; call before the library is released.</summary>
procedure StopRipgrepService;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, uVfsTypes, uPlatformProcess,
  uPluginServiceProvider, uSearchHitsJson, uSearchRequest, uRipgrepFormat;

const
  cServiceName = 'search.files';
  cHitsPerMessage = 500;
  cDefaultMaxResults = 50000;
  cHeartbeatMs = 5000;
  cDescribe =
    '{"protocolVersion":1,"name":"search.files","version":1,"title":"ripgrep",' +
    '"description":"Finds files by their text with ripgrep",' +
    '"inputSchema":{"type":"object","properties":{"root":{"type":"string"},"mask":{"type":"string"},' +
    '"text":{"type":"string"},"regex":{"type":"boolean"},"caseSensitive":{"type":"boolean"},' +
    '"wholeWords":{"type":"boolean"},"files":{"type":"array","items":{"type":"string"}}},' +
    '"required":["root","text"]},' +
    '"capabilities":["name","mask","path","subdirs","case","words","content","regex","encoding",' +
    '"hidden","size","date","files"]}';

var
  GProvider: TServiceProvider;

// rg next to the plugin library wins over the one in the search path.
function RgProgram: string;
var
  Beside: string;
begin
  Result := 'rg';
  Beside := TPath.Combine(ExtractFilePath(GetModuleName(HInstance)),
    {$IFDEF MSWINDOWS}'rg.exe'{$ELSE}'rg'{$ENDIF});
  if TFile.Exists(Beside) then
    Result := Beside;
end;

type
  TBeat = class(TThread)
  private
    FJob: TServiceJob;
    FStop: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AJob: TServiceJob);
    destructor Destroy; override;
    procedure Finish;
  end;

constructor TBeat.Create(AJob: TServiceJob);
begin
  inherited Create(False);
  FJob := AJob;
  FStop := TEvent.Create(nil, True, False, '');
end;

destructor TBeat.Destroy;
begin
  FStop.Free;
  inherited;
end;

procedure TBeat.Execute;
begin
  while FStop.WaitFor(cHeartbeatMs) = wrTimeout do
    FJob.Progress('searching');
end;

procedure TBeat.Finish;
begin
  FStop.SetEvent;
  WaitFor;
end;

procedure Answer(AJob: TServiceJob; const ARequestJson: string);
var
  Req: TSearchRequest;
  Found, Kept: TArray<TSearchHit>;
  Output: string;
  Code: Cardinal;
  Run: TSpawnResult;
  Beat: TBeat;
  I, Max, Sent, N: Integer;
  Hit: TSearchHit;
  Truncated: Boolean;
begin
  if not ParseSearchRequest(ARequestJson, Req) then
  begin
    AJob.ReplyError(-32602, 'bad parameters');
    Exit;
  end;
  // ripgrep reads file contents; a search by name alone is left to the walk or to a file index.
  if Req.Text = '' then
  begin
    AJob.ReplyError(-32002, 'no text to search for');
    Exit;
  end;
  Max := Req.MaxResults;
  if Max <= 0 then
    Max := cDefaultMaxResults;

  Beat := TBeat.Create(AJob);
  try
    Run := PlatformRunCaptured(RgProgram, BuildRgArguments(Req), '', 0, AJob.Token, Output, Code);
  finally
    Beat.Finish;
    Beat.Free;
  end;
  if Run = srCancelled then
    Exit;
  if Run <> srOk then
  begin
    AJob.ReplyError(-32002, 'ripgrep is not available');
    Exit;
  end;
  Found := ParseRgOutput(Output);
  // Exit code 1 is "nothing found"; 2 is an error, which rg also returns when it could not
  // read some file but found others.
  if (Code > 1) and (Length(Found) = 0) then
  begin
    AJob.ReplyError(-32603, 'ripgrep failed');
    Exit;
  end;

  Truncated := False;
  if Length(Found) < Max then
    SetLength(Kept, Length(Found))
  else
    SetLength(Kept, Max);
  N := 0;
  for I := 0 to High(Found) do
  begin
    if AJob.IsCancelled then
      Exit;
    Hit := Found[I];
    if not ReadHitFileInfo(Hit) then
      Continue;
    if SearchRequestHasBounds(Req) and not SearchRequestBoundsPass(Req, False, Hit.Size, Hit.Modified) then
      Continue;
    if N >= Max then
    begin
      Truncated := True;
      Break;
    end;
    Kept[N] := Hit;
    Inc(N);
  end;
  SetLength(Kept, N);

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

function RegisterRipgrepService(AHost: PHostApiTable; const APluginId: string): Boolean;
begin
  FreeAndNil(GProvider);
  GProvider := TServiceProvider.Create(AHost, Answer);
  Result := GProvider.Register(APluginId, cServiceName, cDescribe, 100);
end;

procedure StopRipgrepService;
begin
  FreeAndNil(GProvider);
end;

end.
