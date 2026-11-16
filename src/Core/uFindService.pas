unit uFindService;

{ The pure half of searching through a service provider (docs/PLUGIN_SERVICES.md,
  section "search.files"): which dialog options a provider may serve, the
  capability words a request needs, the request message, the reading of the
  provider's hits and final result, and the filters the host applies to hits
  whose provider does not honor them. No registry, no disk, no threads. }

interface

uses
  System.SysUtils, uFileFind;

const
  cSearchFilesService = 'search.files';
  cSearchHitsMethod = 'search.hits';
  /// <summary>The most hits one search.hits message may carry.</summary>
  cSearchHitsPerMessage = 500;

type
  /// <summary>What the final response of search.files says.</summary>
  TSearchFilesResult = record
    Count: Integer;
    Truncated: Boolean;
    /// <summary>The call ended with an error (a JSON-RPC error or isError).</summary>
    Failed: Boolean;
    ErrorCode: Integer;
    ErrorText: string;
  end;

/// <summary>Whether a provider may serve the options at all. False for what the
/// contract leaves to the built-in walk: a byte pattern, files inside archives,
/// attribute filters and a root that is not a local path.</summary>
function FindOptionsServable(const AOptions: TFindOptions): Boolean;

/// <summary>The capability words a provider must list to serve the options.
/// Size and date bounds are not among them: the host applies those to the hits.</summary>
function FindServiceNeeds(const AOptions: TFindOptions): TArray<string>;

/// <summary>The JSON-RPC request of search.files for the options.</summary>
function BuildSearchFilesRequest(const AOptions: TFindOptions; AId: Integer): string;

/// <summary>The hits of one search.hits notification. False when the message is
/// not a search.hits notification with a hits array; entries without a path
/// are left out.</summary>
function TryParseSearchHits(const AMessageJson: string; out AHits: TArray<TFindHit>): Boolean;

/// <summary>Reads the final response of a call.</summary>
function ParseSearchFilesResult(const AResponseJson: string): TSearchFilesResult;

/// <summary>Whether the host must still test the hit against the size and date
/// bounds of the options.</summary>
function FindHitNeedsBoundCheck(const AOptions: TFindOptions): Boolean;

/// <summary>True when the hit passes the size and date bounds. A hit that lacks
/// the datum a bound needs is passed.</summary>
function FindHitWithinBounds(const AOptions: TFindOptions; const AHit: TFindHit): Boolean;

implementation

uses
  System.JSON, System.DateUtils, System.IOUtils, uJsonRpc, uVfsTypes, uTextEncoding;

function IsLocalRoot(const APath: string): Boolean;
begin
  Result := False;
  if (APath = '') or (Pos('://', APath) > 0) then
    Exit;
  Result := TPath.IsPathRooted(APath);
end;

function FindOptionsServable(const AOptions: TFindOptions): Boolean;
begin
  Result := (AOptions.HexBytes = '') and not AOptions.SearchArchives and
    (AOptions.RequireAttr = 0) and (AOptions.ForbidAttr = 0) and
    (Pos('@', AOptions.Mask) = 0) and
    IsLocalRoot(Trim(AOptions.RootPath));
end;

function FindServiceNeeds(const AOptions: TFindOptions): TArray<string>;
var
  List: TArray<string>;

  procedure Add(const AWord: string);
  begin
    SetLength(List, Length(List) + 1);
    List[High(List)] := AWord;
  end;

begin
  SetLength(List, 0);
  Add('name');
  Add('mask');
  if not AOptions.Subdirs then
    Add('subdirs');
  if AOptions.SearchFolders then
    Add('folders');
  if AOptions.ContainingText <> '' then
  begin
    Add('content');
    if AOptions.CaseSensitive then
      Add('case');
    if AOptions.WholeWords then
      Add('words');
    if AOptions.UseRegex then
      Add('regex');
    if AOptions.ForceEncoding then
      Add('encoding');
  end;
  Result := List;
end;

function IsoTime(ATime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', ATime);
end;

function BuildSearchFilesRequest(const AOptions: TFindOptions; AId: Integer): string;
var
  P: TJSONObject;
  Root: string;
begin
  Root := ExcludeTrailingPathDelimiter(Trim(AOptions.RootPath));
  if (Length(Root) = 2) and (Root[2] = ':') then
    Root := Root + PathDelim;
  P := TJSONObject.Create;
  try
    P.AddPair('root', Root);
    P.AddPair('mask', AOptions.Mask);
    P.AddPair('text', AOptions.ContainingText);
    P.AddPair('regex', TJSONBool.Create(AOptions.UseRegex));
    P.AddPair('caseSensitive', TJSONBool.Create(AOptions.CaseSensitive));
    P.AddPair('wholeWords', TJSONBool.Create(AOptions.WholeWords));
    P.AddPair('subdirs', TJSONBool.Create(AOptions.Subdirs));
    P.AddPair('includeFolders', TJSONBool.Create(AOptions.SearchFolders));
    P.AddPair('hidden', TJSONBool.Create(True));
    if AOptions.ForceEncoding then
      P.AddPair('encoding', TextEncodingName(AOptions.Encoding));
    if AOptions.MinSize >= 0 then
      P.AddPair('minSize', TJSONNumber.Create(AOptions.MinSize));
    if AOptions.MaxSize >= 0 then
      P.AddPair('maxSize', TJSONNumber.Create(AOptions.MaxSize));
    if AOptions.ModifiedFrom > 0 then
      P.AddPair('modifiedFrom', IsoTime(AOptions.ModifiedFrom));
    if AOptions.ModifiedTo > 0 then
      P.AddPair('modifiedTo', IsoTime(AOptions.ModifiedTo));
    if AOptions.MaxResults > 0 then
      P.AddPair('maxResults', TJSONNumber.Create(AOptions.MaxResults))
    else
      P.AddPair('maxResults', TJSONNumber.Create(cFindMaxResults));
    Result := BuildRpcRequest(RpcIntId(AId), cSearchFilesService, P.ToJSON);
  finally
    P.Free;
  end;
end;

// yyyy-mm-dd, optionally followed by Thh:nn:ss; a zone or fraction after the seconds is ignored.
function TryParseIsoLocal(const AText: string; out ATime: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi, S: Word;

  function Num(AFrom, ALen: Integer; out AValue: Word): Boolean;
  var
    V: Integer;
  begin
    Result := (Length(AText) >= AFrom + ALen - 1) and
      TryStrToInt(Copy(AText, AFrom, ALen), V) and (V >= 0);
    if Result then
      AValue := Word(V);
  end;

begin
  Result := False;
  H := 0;
  Mi := 0;
  S := 0;
  if not (Num(1, 4, Y) and Num(6, 2, Mo) and Num(9, 2, D)) then
    Exit;
  if (Length(AText) >= 19) and CharInSet(AText[11], ['T', ' ']) then
    if not (Num(12, 2, H) and Num(15, 2, Mi) and Num(18, 2, S)) then
      Exit;
  Result := TryEncodeDateTime(Y, Mo, D, H, Mi, S, 0, ATime);
end;

function TryParseSearchHits(const AMessageJson: string; out AHits: TArray<TFindHit>): Boolean;
var
  Msg: TRpcMessage;
  Err: Integer;
  Params, Item: TJSONValue;
  Hits: TJSONArray;
  I: Integer;
  Obj: TJSONObject;
  Hit: TFindHit;
  Path, Text: string;
  Num: Int64;
  Moment: TDateTime;
begin
  SetLength(AHits, 0);
  Result := False;
  if not TryParseRpcMessage(AMessageJson, Msg, Err) or (Msg.Kind <> rkNotification) or
     (Msg.Method <> cSearchHitsMethod) then
    Exit;
  Params := TJSONObject.ParseJSONValue(Msg.ParamsJson);
  try
    if not (Params is TJSONObject) or
       not (TJSONObject(Params).GetValue('hits') is TJSONArray) then
      Exit;
    Hits := TJSONArray(TJSONObject(Params).GetValue('hits'));
    Result := True;
    for I := 0 to Hits.Count - 1 do
    begin
      Item := Hits.Items[I];
      if not (Item is TJSONObject) then
        Continue;
      Obj := TJSONObject(Item);
      if not Obj.TryGetValue<string>('path', Path) or (Path = '') then
        Continue;
      Hit := Default(TFindHit);
      Hit.Path := Path;
      Hit.Entry := Default(TVfsEntry);
      Hit.Entry.Name := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
      Hit.Entry.Extension := ExtractFileExt(Hit.Entry.Name);
      Obj.TryGetValue<Boolean>('isDir', Hit.Entry.IsDirectory);
      Hit.Entry.Size := -1;
      if (Obj.GetValue('size') is TJSONNumber) and
         TryStrToInt64(TJSONNumber(Obj.GetValue('size')).Value, Num) and not Hit.Entry.IsDirectory then
        Hit.Entry.Size := Num;
      if Obj.TryGetValue<string>('modified', Text) and TryParseIsoLocal(Text, Moment) then
        Hit.Entry.ModificationTime := Moment;
      if (Obj.GetValue('line') is TJSONNumber) and
         TryStrToInt64(TJSONNumber(Obj.GetValue('line')).Value, Num) and (Num > 0) then
        Hit.Line := Integer(Num);
      if Obj.TryGetValue<string>('snippet', Text) then
        Hit.Snippet := Text;
      if Obj.TryGetValue<string>('created', Text) and TryParseIsoLocal(Text, Moment) then
        Hit.Entry.CreationTime := Moment;
      if Obj.TryGetValue<string>('accessed', Text) and TryParseIsoLocal(Text, Moment) then
        Hit.Entry.AccessTime := Moment;
      if (Obj.GetValue('attributes') is TJSONNumber) and
         TryStrToInt64(TJSONNumber(Obj.GetValue('attributes')).Value, Num) then
      begin
        Hit.Entry.IsReadOnly := (Num and $1) <> 0;
        Hit.Entry.IsHidden := (Num and $2) <> 0;
        Hit.Entry.IsSystem := (Num and $4) <> 0;
        Hit.Entry.IsArchive := (Num and $20) <> 0;
        Hit.Entry.IsLink := (Num and $400) <> 0;
      end;
      Hit.HasEntry := True;
      SetLength(AHits, Length(AHits) + 1);
      AHits[High(AHits)] := Hit;
    end;
  finally
    Params.Free;
  end;
end;

function ParseSearchFilesResult(const AResponseJson: string): TSearchFilesResult;
var
  Msg: TRpcMessage;
  Err: Integer;
  Res, Structured: TJSONValue;
  Flag: Boolean;
  Num: Int64;
begin
  Result := Default(TSearchFilesResult);
  if not TryParseRpcMessage(AResponseJson, Msg, Err) or (Msg.Kind <> rkResponse) then
  begin
    Result.Failed := True;
    Result.ErrorCode := cRpcInternalError;
    Result.ErrorText := 'not a response';
    Exit;
  end;
  if Msg.IsError then
  begin
    Result.Failed := True;
    Result.ErrorCode := Msg.ErrorCode;
    Result.ErrorText := Msg.ErrorMessage;
    Exit;
  end;
  Res := TJSONObject.ParseJSONValue(Msg.ResultJson);
  try
    if not (Res is TJSONObject) then
      Exit;
    if TJSONObject(Res).TryGetValue<Boolean>('isError', Flag) and Flag then
    begin
      Result.Failed := True;
      Result.ErrorCode := cRpcInternalError;
      Result.ErrorText := 'the provider reported an error';
    end;
    Structured := TJSONObject(Res).GetValue('structuredContent');
    if Structured is TJSONObject then
    begin
      if (TJSONObject(Structured).GetValue('count') is TJSONNumber) and
         TryStrToInt64(TJSONNumber(TJSONObject(Structured).GetValue('count')).Value, Num) then
        Result.Count := Integer(Num);
      if TJSONObject(Structured).TryGetValue<Boolean>('truncated', Flag) then
        Result.Truncated := Flag;
    end;
  finally
    Res.Free;
  end;
end;

function FindHitNeedsBoundCheck(const AOptions: TFindOptions): Boolean;
begin
  Result := (AOptions.MinSize >= 0) or (AOptions.MaxSize >= 0) or
    (AOptions.ModifiedFrom > 0) or (AOptions.ModifiedTo > 0);
end;

function FindHitWithinBounds(const AOptions: TFindOptions; const AHit: TFindHit): Boolean;
begin
  Result := True;
  if not AHit.HasEntry then
    Exit;
  if not AHit.Entry.IsDirectory and (AHit.Entry.Size >= 0) then
  begin
    if (AOptions.MinSize >= 0) and (AHit.Entry.Size < AOptions.MinSize) then
      Exit(False);
    if (AOptions.MaxSize >= 0) and (AHit.Entry.Size > AOptions.MaxSize) then
      Exit(False);
  end;
  if AHit.Entry.ModificationTime > 0 then
  begin
    if (AOptions.ModifiedFrom > 0) and (AHit.Entry.ModificationTime < AOptions.ModifiedFrom) then
      Exit(False);
    if (AOptions.ModifiedTo > 0) and (AHit.Entry.ModificationTime > AOptions.ModifiedTo) then
      Exit(False);
  end;
end;

end.
