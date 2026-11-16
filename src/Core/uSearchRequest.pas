unit uSearchRequest;

{ The provider side of a search.files request (docs/PLUGIN_SERVICES.md): the parameters of the
  request as a record, and the size and date bounds a provider applies to the files it finds. }

interface

type
  TSearchRequest = record
    Root, Mask: string;
    /// <summary>Text to look for inside files; '' = a search by name only.</summary>
    Text: string;
    Regex, CaseSensitive, WholeWords, Subdirs, IncludeFolders, Hidden: Boolean;
    /// <summary>Encoding name of the files' text; '' = detect.</summary>
    Encoding: string;
    /// <summary>Bytes; -1 = no bound.</summary>
    MinSize, MaxSize: Int64;
    /// <summary>ISO 8601 local time as sent; '' = no bound.</summary>
    ModifiedFrom, ModifiedTo: string;
    /// <summary>0 = the provider's own limit.</summary>
    MaxResults: Integer;
  end;

/// <summary>Reads the params of a search.files request message. False when the message
/// has no params object or no root.</summary>
function ParseSearchRequest(const ARequestJson: string; out ARequest: TSearchRequest): Boolean;

/// <summary>Whether the request has a size or date bound the provider must check itself.</summary>
function SearchRequestHasBounds(const ARequest: TSearchRequest): Boolean;

/// <summary>AModified is local time as ISO 8601 (yyyy-mm-ddThh:nn:ss), '' when unknown.
/// Size bounds do not apply to folders.</summary>
function SearchRequestBoundsPass(const ARequest: TSearchRequest; AIsDir: Boolean; ASize: Int64;
  const AModified: string): Boolean;

/// <summary>The masks of a mask text, split at ";" and ","; blanks are left out.</summary>
function SplitSearchMasks(const AMask: string): TArray<string>;

implementation

uses
  System.SysUtils, System.JSON;

function JsonStr(AObj: TJSONObject; const AName: string): string;
begin
  if not AObj.TryGetValue<string>(AName, Result) then
    Result := '';
end;

function JsonBool(AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
begin
  if not AObj.TryGetValue<Boolean>(AName, Result) then
    Result := ADefault;
end;

function JsonInt(AObj: TJSONObject; const AName: string; ADefault: Int64): Int64;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if not ((V is TJSONNumber) and TryStrToInt64(TJSONNumber(V).Value, Result)) then
    Result := ADefault;
end;

function ParseSearchRequest(const ARequestJson: string; out ARequest: TSearchRequest): Boolean;
var
  Root, Params: TJSONValue;
  P: TJSONObject;
begin
  ARequest := Default(TSearchRequest);
  ARequest.MinSize := -1;
  ARequest.MaxSize := -1;
  Result := False;
  Root := TJSONObject.ParseJSONValue(ARequestJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Params := TJSONObject(Root).GetValue('params');
    if not (Params is TJSONObject) then
      Exit;
    P := TJSONObject(Params);
    ARequest.Root := JsonStr(P, 'root');
    if ARequest.Root = '' then
      Exit;
    ARequest.Mask := JsonStr(P, 'mask');
    ARequest.Text := JsonStr(P, 'text');
    ARequest.Regex := JsonBool(P, 'regex', False);
    ARequest.Subdirs := JsonBool(P, 'subdirs', True);
    ARequest.CaseSensitive := JsonBool(P, 'caseSensitive', False);
    ARequest.WholeWords := JsonBool(P, 'wholeWords', False);
    ARequest.IncludeFolders := JsonBool(P, 'includeFolders', False);
    ARequest.Hidden := JsonBool(P, 'hidden', True);
    ARequest.Encoding := JsonStr(P, 'encoding');
    ARequest.MinSize := JsonInt(P, 'minSize', -1);
    ARequest.MaxSize := JsonInt(P, 'maxSize', -1);
    ARequest.ModifiedFrom := JsonStr(P, 'modifiedFrom');
    ARequest.ModifiedTo := JsonStr(P, 'modifiedTo');
    ARequest.MaxResults := Integer(JsonInt(P, 'maxResults', 0));
    Result := True;
  finally
    Root.Free;
  end;
end;

function SearchRequestHasBounds(const ARequest: TSearchRequest): Boolean;
begin
  Result := (ARequest.MinSize >= 0) or (ARequest.MaxSize >= 0) or
    (ARequest.ModifiedFrom <> '') or (ARequest.ModifiedTo <> '');
end;

function SearchRequestBoundsPass(const ARequest: TSearchRequest; AIsDir: Boolean; ASize: Int64;
  const AModified: string): Boolean;
begin
  Result := False;
  if not AIsDir then
  begin
    if (ARequest.MinSize >= 0) and (ASize < ARequest.MinSize) then
      Exit;
    if (ARequest.MaxSize >= 0) and (ASize > ARequest.MaxSize) then
      Exit;
  end;
  if AModified <> '' then
  begin
    if (ARequest.ModifiedFrom <> '') and (AModified < ARequest.ModifiedFrom) then
      Exit;
    if (ARequest.ModifiedTo <> '') and (AModified > ARequest.ModifiedTo) then
      Exit;
  end;
  Result := True;
end;

function SplitSearchMasks(const AMask: string): TArray<string>;
var
  Parts: TArray<string>;
  Part: string;
begin
  SetLength(Result, 0);
  Parts := StringReplace(AMask, ',', ';', [rfReplaceAll]).Split([';']);
  for Part in Parts do
    if Trim(Part) <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(Part);
    end;
end;

end.
