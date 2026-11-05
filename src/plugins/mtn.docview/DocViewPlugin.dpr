library DocViewPlugin;

{ Native MTN2 plugin: F3 on a docx, xlsx, pptx, pdf, svg or SQLite file shows
  its text in the built-in viewer. The text is written to a file in the temp
  folder and the host opens that file; F4 still edits the original. A file the
  extractors cannot read is left to the host. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Hash,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uDocText in 'uDocText.pas';

const
  cPluginId = 'mtn.docview';
  cExtensions = '.docx,.xlsx,.pptx,.pdf,.svg,.sqlite,.sqlite3,.db,.db3';
  cModeView = 1;
  cModeQuick = 4;
  cQuickMaxBytes = 16 * 1024 * 1024;
  cPriority = 50;
  cMaxBytes = 64 * 1024 * 1024;
  cTempFolder = 'mtn2-docview';
  cKeepDays = 1;

var
  GHostApi: THostApiTable;

{ file:///C:/dir/a%20b.pdf -> C:\dir\a b.pdf; '' for any other URI. }
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

{ The text of the file at APath; '' when it has none. }
function ExtractText(const APath: string): string;
var
  Ext: string;
  Bytes: TBytes;
begin
  Result := '';
  Ext := LowerCase(ExtractFileExt(APath));
  if (Ext = '.docx') or (Ext = '.xlsx') or (Ext = '.pptx') then
    Result := OfficeText(APath)
  else if (Ext = '.sqlite') or (Ext = '.sqlite3') or (Ext = '.db') or (Ext = '.db3') then
    Result := SqliteText(APath)
  else if TFile.GetSize(APath) <= cMaxBytes then
  begin
    Bytes := TFile.ReadAllBytes(APath);
    if Ext = '.pdf' then
      Result := PdfText(Bytes)
    else if Ext = '.svg' then
      Result := SvgText(TEncoding.UTF8.GetString(Bytes));
  end;
end;

{ The text of the file at APath as a file in the temp folder; '' when it cannot be made. }
function RenderToTemp(const AUri, APath: string): string;
var
  Text, Dir: string;
begin
  Result := '';
  Dir := TPath.Combine(TPath.GetTempPath, cTempFolder);
  TDirectory.CreateDirectory(Dir);
  Result := TPath.Combine(Dir, Format('%s-%s.txt', [TPath.GetFileNameWithoutExtension(APath),
    Copy(THashMD5.GetHashString(AUri), 1, 8)]));
  if TFile.Exists(Result) and (TFile.GetLastWriteTime(Result) >= TFile.GetLastWriteTime(APath)) then
    Exit;
  Text := ExtractText(APath);
  if Trim(Text) = '' then
    Exit('');
  TFile.WriteAllText(Result, Text, TEncoding.UTF8);
end;

function OnDocument(AUserData: Pointer; AUri, AMode, ARedirect: PAnsiChar;
  ARedirectCap: Int64): Int64; cdecl;
var
  Uri, Path, Target, TargetUri: string;
  Bytes: UTF8String;
  Quick: Boolean;
begin
  Result := 0;
  try
    if (AUri = nil) or (AMode = nil) or (ARedirect = nil) then
      Exit;
    // F4 stays with the built-in editor.
    Quick := SameText(string(AMode), 'quick');
    if not Quick and not SameText(string(AMode), 'view') then
      Exit;
    Uri := UTF8ToString(AUri);
    Path := UriToPath(Uri);
    if (Path = '') or not TFile.Exists(Path) then
      Exit;
    // Quick View runs while the panel is painted, so a big file waits for F3.
    if Quick and (TFile.GetSize(Path) > cQuickMaxBytes) then
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
    cModeView or cModeQuick, @OnDocument, nil, cPriority);
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
