library CsvPlugin;

{ Native MTN2 plugin: F3 on a .csv or .tsv file shows it as an aligned table in
  the built-in viewer instead of raw text. The delimiter (comma, semicolon,
  tab or bar) is detected from the first records, the first record is the
  header, and a big file is shown by its first rows. The table is written to a
  text file in the temp folder and the host opens that file in its viewer; F4
  still edits the original file. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.Math,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uCsvTable in 'uCsvTable.pas';

const
  cPluginId = 'mtn.csv';
  cExtensions = '.csv,.tsv';
  cModeView = 1;
  cPriority = 50;
  cMaxBytes = 32 * 1024 * 1024;
  cMaxRows = 200000;
  cMaxCellWidth = 60;
  cTempFolder = 'mtn2-csv';
  cKeepDays = 1;

var
  GHostApi: THostApiTable;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..255] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHostApi.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

{ file:///C:/dir/a%20b.csv -> C:\dir\a b.csv; '' for any other URI. }
function UriToPath(const AUri: string): string;
const
  cPrefix = 'file:///';
var
  Raw: UTF8String;
  Bytes: TBytes;
  I, N: Integer;
begin
  Result := '';
  if not SameText(Copy(AUri, 1, Length(cPrefix)), cPrefix) then
    Exit;
  Raw := UTF8String(Copy(AUri, Length(cPrefix) + 1, MaxInt));
  SetLength(Bytes, Length(Raw));
  N := 0;
  I := 1;
  while I <= Length(Raw) do
  begin
    if (Raw[I] = '%') and (I + 2 <= Length(Raw)) and
       CharInSet(Raw[I + 1], ['0'..'9', 'a'..'f', 'A'..'F']) and
       CharInSet(Raw[I + 2], ['0'..'9', 'a'..'f', 'A'..'F']) then
    begin
      Bytes[N] := StrToInt('$' + string(Raw[I + 1]) + string(Raw[I + 2]));
      Inc(I, 3);
    end
    else
    begin
      Bytes[N] := Ord(Raw[I]);
      Inc(I);
    end;
    Inc(N);
  end;
  SetLength(Bytes, N);
  Result := StringReplace(TEncoding.UTF8.GetString(Bytes), '/', '\', [rfReplaceAll]);
end;

procedure RemoveOldTempFiles;
var
  F: string;
begin
  try
    if not TDirectory.Exists(TPath.Combine(TPath.GetTempPath, cTempFolder)) then
      Exit;
    for F in TDirectory.GetFiles(TPath.Combine(TPath.GetTempPath, cTempFolder)) do
      if Now - TFile.GetLastWriteTime(F) > cKeepDays then
        TFile.Delete(F);
  except
    // A file another program holds open stays for the next time.
  end;
end;

{ The start of the file, ended at a line break when the file is longer than
  cMaxBytes; ACut tells that the end of the file is not in the text. }
function ReadStart(const APath: string; out ACut: Boolean): TBytes;
var
  Stream: TFileStream;
  Want, I: Integer;
begin
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    ACut := Stream.Size > cMaxBytes;
    Want := Integer(Min(Stream.Size, Int64(cMaxBytes)));
    SetLength(Result, Want);
    if Want > 0 then
      Stream.ReadBuffer(Result[0], Want);
  finally
    Stream.Free;
  end;
  if ACut then
  begin
    I := High(Result);
    while (I > 0) and (Result[I] <> 10) do
      Dec(I);
    if I > 0 then
      SetLength(Result, I + 1);
  end;
end;

{ The table of the file at APath as a text file in the temp folder; '' when it
  cannot be made. }
function RenderToTemp(const AUri, APath: string): string;
var
  Bytes: TBytes;
  Text, Table, Dir: string;
  BytesCut: Boolean;
  Info: TCsvTableInfo;
begin
  Result := '';
  Dir := TPath.Combine(TPath.GetTempPath, cTempFolder);
  TDirectory.CreateDirectory(Dir);
  Result := TPath.Combine(Dir, Format('%s-%s.txt', [TPath.GetFileNameWithoutExtension(APath),
    Copy(THashMD5.GetHashString(AUri), 1, 8)]));
  if TFile.Exists(Result) and (TFile.GetLastWriteTime(Result) >= TFile.GetLastWriteTime(APath)) then
    Exit;
  Bytes := ReadStart(APath, BytesCut);
  Text := DecodeCsvBytes(Bytes);
  Table := RenderCsvTable(Text, #0, cMaxCellWidth, cMaxRows, Info);
  if Info.Rows = 0 then
    Exit('');
  if BytesCut or Info.RowsCut then
    Table := Table + #13#10 + Format(Tr('note.cut',
      '... only the first %d rows of the file are shown'), [Info.Rows]) + #13#10;
  TFile.WriteAllText(Result, Table, TEncoding.UTF8);
end;

function OnDocument(AUserData: Pointer; AUri, AMode, ARedirect: PAnsiChar;
  ARedirectCap: Int64): Int64; cdecl;
var
  Uri, Path, Target, TargetUri: string;
  Bytes: UTF8String;
begin
  Result := 0;
  try
    if (AUri = nil) or (AMode = nil) or (ARedirect = nil) then
      Exit;
    // F4 stays with the built-in editor.
    if not SameText(string(AMode), 'view') then
      Exit;
    Uri := UTF8ToString(AUri);
    Path := UriToPath(Uri);
    if (Path = '') or not TFile.Exists(Path) then
      Exit;
    Target := RenderToTemp(Uri, Path);
    if Target = '' then
      Exit;
    TargetUri := 'file:///' + StringReplace(Target, '\', '/', [rfReplaceAll]);
    Bytes := UTF8String(TargetUri);
    if Length(Bytes) + 1 > ARedirectCap then
      Exit;
    Move(PAnsiChar(Bytes)^, ARedirect^, Length(Bytes) + 1);
    Result := 2;
  except
    // Never let an exception cross into the host; the built-in viewer runs.
    Result := 0;
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  PluginId, Extensions: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 2) or
     not Assigned(AHostApi.RegisterDocumentProvider) then
    Exit(-1);
  GHostApi := AHostApi^;
  RemoveOldTempFiles;
  PluginId := UTF8String(cPluginId);
  Extensions := UTF8String(cExtensions);
  Result := GHostApi.RegisterDocumentProvider(PAnsiChar(PluginId), PAnsiChar(Extensions),
    cModeView, @OnDocument, nil, cPriority);
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
