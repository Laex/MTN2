unit uRcloneFormat;

{ Pure helpers of the rclone plugin: addresses, the command lines handed to the
  rclone program and the parsers of its output.

    rclone:///                  the configured remotes
    rclone:///<remote>          the root of a remote
    rclone:///<remote>/<path>   a folder or file of the remote }

interface

type
  TRcNode = (rnInvalid, rnRoot, rnPath);

  TRcAddr = record
    Node: TRcNode;
    /// <summary>The remote name without the colon.</summary>
    Remote: string;
    /// <summary>The path inside the remote, no leading slash; empty for the remote root.</summary>
    Path: string;
  end;

  TRcEntry = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    /// <summary>Seconds since 1970-01-01 UTC; 0 when unknown.</summary>
    Modified: Int64;
  end;
  TRcEntries = TArray<TRcEntry>;

const
  cRcloneExe = 'rclone';

function RcEncode(const AText: string): string;
function RcDecode(const AText: string): string;

function ParseRcloneUri(const AUri: string; out AAddr: TRcAddr): Boolean;
function RcloneUri(const ARemote, APath: string): string;
/// <summary>The address in the form rclone takes: "remote:path".</summary>
function RemoteSpec(const AAddr: TRcAddr): string;

/// <summary>The lines of "rclone listremotes": names without the trailing colon.</summary>
function ParseRemotes(const AOutput: string): TArray<string>;
/// <summary>The array printed by "rclone lsjson"; entries that cannot be read are skipped.</summary>
function ParseLsJson(const AOutput: string): TRcEntries;
/// <summary>The object printed by "rclone lsjson --stat".</summary>
function ParseStatJson(const AOutput: string; out AEntry: TRcEntry): Boolean;
/// <summary>Seconds since 1970 UTC of an ISO 8601 stamp as rclone prints it
/// ("2024-05-01T10:20:30.123456789Z" or with a zone offset); 0 when it is not one.</summary>
function ParseRcTime(const AStamp: string): Int64;
/// <summary>Free and total bytes from the object printed by "rclone about --json"; -1 when absent.</summary>
function ParseAboutJson(const AOutput: string; out AFree, ATotal: Int64): Boolean;

function ListArgs(const AAddr: TRcAddr): TArray<string>;
function StatArgs(const AAddr: TRcAddr): TArray<string>;
function CatArgs(const AAddr: TRcAddr; AMaxBytes: Int64): TArray<string>;
function CopyToArgs(const AFromSpec, AToSpec: string; AMove: Boolean): TArray<string>;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.DateUtils;

function RcEncode(const AText: string): string;
begin
  Result := AText.Replace('%', '%25').Replace('/', '%2F');
end;

function RcDecode(const AText: string): string;
var
  I: Integer;
  Code: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    Code := Copy(AText, I, 3);
    if (AText[I] = '%') and SameText(Code, '%2F') then
    begin
      Result := Result + '/';
      Inc(I, 3);
    end
    else if (AText[I] = '%') and (Code = '%25') then
    begin
      Result := Result + '%';
      Inc(I, 3);
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

function ParseRcloneUri(const AUri: string; out AAddr: TRcAddr): Boolean;
const
  cPrefix = 'rclone:///';
var
  Parts: TArray<string>;
  I, J: Integer;
begin
  AAddr := Default(TRcAddr);
  Result := SameText(Copy(AUri, 1, Length(cPrefix)), cPrefix);
  if not Result then
    Exit;
  Parts := Copy(AUri, Length(cPrefix) + 1, MaxInt).Split(['/']);
  I := 0;
  while (I <= High(Parts)) and (Parts[I] = '') do
    Inc(I);
  if I > High(Parts) then
  begin
    AAddr.Node := rnRoot;
    Exit;
  end;
  AAddr.Node := rnPath;
  AAddr.Remote := RcDecode(Parts[I]);
  Inc(I);
  for J := I to High(Parts) do
    if Parts[J] <> '' then
    begin
      if AAddr.Path <> '' then
        AAddr.Path := AAddr.Path + '/';
      AAddr.Path := AAddr.Path + RcDecode(Parts[J]);
    end;
  Result := AAddr.Remote <> '';
  if not Result then
    AAddr := Default(TRcAddr);
end;

function RcloneUri(const ARemote, APath: string): string;
var
  Seg: string;
begin
  Result := 'rclone:///' + RcEncode(ARemote);
  for Seg in APath.Split(['/']) do
    if Seg <> '' then
      Result := Result + '/' + RcEncode(Seg);
end;

function RemoteSpec(const AAddr: TRcAddr): string;
begin
  Result := AAddr.Remote + ':' + AAddr.Path;
end;

function IsLogLine(const ALine: string): Boolean;
begin
  Result := (Length(ALine) > 20) and (ALine[5] = '/') and (ALine[8] = '/') and
    (ALine[11] = ' ') and (ALine[14] = ':') and (ALine[17] = ':') and
    CharInSet(ALine[1], ['0'..'9']);
end;

// rclone writes notices to the stream the output is read from; they must not reach a parser.
function StripLogLines(const AOutput: string): string;
var
  Line: string;
  Kept: TStringList;
begin
  Kept := TStringList.Create;
  try
    for Line in AOutput.Replace(#13, '').Split([#10]) do
      if not IsLogLine(Line) then
        Kept.Add(Line);
    Result := Kept.Text;
  finally
    Kept.Free;
  end;
end;

function ParseRemotes(const AOutput: string): TArray<string>;
var
  Line, Name: string;
  N: Integer;
begin
  SetLength(Result, 0);
  N := 0;
  for Line in StripLogLines(AOutput).Split([#10]) do
  begin
    Name := Line.Trim;
    if Name.EndsWith(':') then
      Name := Copy(Name, 1, Length(Name) - 1);
    if Name = '' then
      Continue;
    SetLength(Result, N + 1);
    Result[N] := Name;
    Inc(N);
  end;
end;

function ParseRcTime(const AStamp: string): Int64;
var
  Stamp: string;
  P, Q: Integer;
  Moment: TDateTime;
begin
  Result := 0;
  Stamp := AStamp.Trim;
  // ISO8601ToDate reads up to millisecond digits; rclone prints nanoseconds.
  P := Pos('.', Stamp);
  if P > 0 then
  begin
    Q := P + 1;
    while (Q <= Length(Stamp)) and CharInSet(Stamp[Q], ['0'..'9']) do
      Inc(Q);
    Stamp := Copy(Stamp, 1, P - 1) + Copy(Stamp, Q, MaxInt);
  end;
  if Stamp = '' then
    Exit;
  try
    Moment := ISO8601ToDate(Stamp, True);
    Result := DateTimeToUnix(Moment, True);
  except
    Result := 0;
  end;
  if Result < 0 then
    Result := 0;
end;

// A listed entry always has a name; the stat of a folder itself can come back with an empty one.
function EntryOf(const AObj: TJSONObject; ARequireName: Boolean; out AEntry: TRcEntry): Boolean;
var
  Stamp: string;
  Size: Int64;
begin
  AEntry := Default(TRcEntry);
  Result := AObj.TryGetValue<string>('Name', AEntry.Name) and
    (not ARequireName or (AEntry.Name <> ''));
  if not Result then
    Exit;
  if not AObj.TryGetValue<Boolean>('IsDir', AEntry.IsDir) then
    AEntry.IsDir := False;
  // A folder or a backend without sizes reports -1.
  if AObj.TryGetValue<Int64>('Size', Size) and (Size > 0) then
    AEntry.Size := Size;
  if AObj.TryGetValue<string>('ModTime', Stamp) then
    AEntry.Modified := ParseRcTime(Stamp);
end;

function ParseLsJson(const AOutput: string): TRcEntries;
var
  Root: TJSONValue;
  Item: TJSONValue;
  Entry: TRcEntry;
  N: Integer;
begin
  SetLength(Result, 0);
  Root := TJSONObject.ParseJSONValue(StripLogLines(AOutput));
  try
    if not (Root is TJSONArray) then
      Exit;
    N := 0;
    for Item in TJSONArray(Root) do
      if (Item is TJSONObject) and EntryOf(TJSONObject(Item), True, Entry) then
      begin
        SetLength(Result, N + 1);
        Result[N] := Entry;
        Inc(N);
      end;
  finally
    Root.Free;
  end;
end;

function ParseStatJson(const AOutput: string; out AEntry: TRcEntry): Boolean;
var
  Root: TJSONValue;
begin
  AEntry := Default(TRcEntry);
  Root := TJSONObject.ParseJSONValue(StripLogLines(AOutput));
  try
    Result := (Root is TJSONObject) and EntryOf(TJSONObject(Root), False, AEntry);
  finally
    Root.Free;
  end;
end;

function ParseAboutJson(const AOutput: string; out AFree, ATotal: Int64): Boolean;
var
  Root: TJSONValue;
begin
  AFree := -1;
  ATotal := -1;
  Root := TJSONObject.ParseJSONValue(StripLogLines(AOutput));
  try
    Result := Root is TJSONObject;
    if not Result then
      Exit;
    if not TJSONObject(Root).TryGetValue<Int64>('free', AFree) then
      AFree := -1;
    if not TJSONObject(Root).TryGetValue<Int64>('total', ATotal) then
      ATotal := -1;
    Result := (AFree >= 0) or (ATotal >= 0);
  finally
    Root.Free;
  end;
end;

// Prompts for a configuration password would wait for input that never comes.
function Base(const AVerb: string): TArray<string>;
begin
  Result := [AVerb, '--ask-password=false'];
end;

function ListArgs(const AAddr: TRcAddr): TArray<string>;
begin
  Result := Base('lsjson') + ['--no-mimetype', RemoteSpec(AAddr)];
end;

function StatArgs(const AAddr: TRcAddr): TArray<string>;
begin
  Result := Base('lsjson') + ['--stat', '--no-mimetype', RemoteSpec(AAddr)];
end;

function CatArgs(const AAddr: TRcAddr; AMaxBytes: Int64): TArray<string>;
begin
  Result := Base('cat');
  if AMaxBytes > 0 then
    Result := Result + ['--count', IntToStr(AMaxBytes)];
  Result := Result + [RemoteSpec(AAddr)];
end;

function CopyToArgs(const AFromSpec, AToSpec: string; AMove: Boolean): TArray<string>;
begin
  if AMove then
    Result := Base('moveto')
  else
    Result := Base('copyto');
  Result := Result + [AFromSpec, AToSpec];
end;

end.
