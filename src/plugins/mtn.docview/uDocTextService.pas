unit uDocTextService;

{ The text.extract service of the document viewer plugin: one document in, its plain
  text out (docs/PLUGIN_SERVICES.md). The extensions it serves are listed as the
  capabilities "ext.<extension>". }

interface

uses
  uPluginHostAbi, uPluginServiceProvider;

const
  cDocExtensions = '.docx,.xlsx,.pptx,.pdf,.svg,.sqlite,.sqlite3,.db,.db3';
  cDefaultMaxChars = 4 * 1024 * 1024;

/// <summary>The text of the file at APath; '' when it has none or the extension is not
/// one of cDocExtensions.</summary>
function ExtractDocumentText(const APath: string): string;

/// <summary>Answers one request message. True: AResultJson is the "result" member;
/// False: ACode and AMessage describe the error.</summary>
function AnswerTextExtract(const ARequestJson: string; out AResultJson: string;
  out ACode: Integer; out AMessage: string): Boolean;

function DescribeTextExtract: string;

/// <summary>Offers the service; False when the host is too old for services.</summary>
function RegisterTextExtractService(AHost: PHostApiTable; const APluginId: string): Boolean;
procedure StopTextExtractService;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, uDocText;

const
  cServiceName = 'text.extract';
  cMaxBytes = 64 * 1024 * 1024;
  cPriority = 50;

var
  GProvider: TServiceProvider;

function ExtractDocumentText(const APath: string): string;
var
  Ext: string;
  Bytes: TBytes;
begin
  Result := '';
  Ext := LowerCase(ExtractFileExt(APath));
  if Pos(Ext + ',', cDocExtensions + ',') = 0 then
    Exit;
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

function AnswerTextExtract(const ARequestJson: string; out AResultJson: string;
  out ACode: Integer; out AMessage: string): Boolean;
var
  Root, Params: TJSONValue;
  Path, Text: string;
  MaxChars: Integer;
  Truncated: Boolean;
  Struct, Res, Item: TJSONObject;
  Content: TJSONArray;
begin
  Result := False;
  AResultJson := '';
  Path := '';
  MaxChars := cDefaultMaxChars;
  Root := TJSONObject.ParseJSONValue(ARequestJson);
  try
    if Root is TJSONObject then
    begin
      Params := TJSONObject(Root).GetValue('params');
      if Params is TJSONObject then
      begin
        Path := TJSONObject(Params).GetValue<string>('path', '');
        MaxChars := TJSONObject(Params).GetValue<Integer>('maxChars', cDefaultMaxChars);
      end;
    end;
  finally
    Root.Free;
  end;
  if (Path = '') or (MaxChars < 1) then
  begin
    ACode := -32602;
    AMessage := 'path and maxChars are needed';
    Exit;
  end;
  if (Pos(LowerCase(ExtractFileExt(Path)) + ',', cDocExtensions + ',') = 0) or
     not TFile.Exists(Path) then
  begin
    ACode := -32002;
    AMessage := 'not a document this plugin reads';
    Exit;
  end;
  Text := ExtractDocumentText(Path);
  Truncated := Length(Text) > MaxChars;
  if Truncated then
    Text := Copy(Text, 1, MaxChars);
  Struct := TJSONObject.Create;
  Item := TJSONObject.Create;
  Content := TJSONArray.Create;
  Res := TJSONObject.Create;
  try
    Struct.AddPair('text', Text);
    Struct.AddPair('truncated', TJSONBool.Create(Truncated));
    Item.AddPair('type', 'text');
    Item.AddPair('text', IntToStr(Length(Text)) + ' characters');
    Content.AddElement(Item);
    Res.AddPair('content', Content);
    Res.AddPair('structuredContent', Struct);
    Res.AddPair('isError', TJSONBool.Create(False));
    AResultJson := Res.ToJSON;
  finally
    Res.Free;
  end;
  Result := True;
end;

function DescribeTextExtract: string;
var
  Caps: string;
  Ext: string;
begin
  Caps := '';
  for Ext in cDocExtensions.Split([',']) do
  begin
    if Caps <> '' then
      Caps := Caps + ',';
    Caps := Caps + '"ext.' + Copy(Ext, 2, MaxInt) + '"';
  end;
  Result :=
    '{"protocolVersion":1,"name":"text.extract","version":1,"title":"Document text",' +
    '"description":"Returns the plain text of a document (docx, xlsx, pptx, pdf, svg, SQLite)",' +
    '"inputSchema":{"type":"object","properties":{"path":{"type":"string"},' +
    '"maxChars":{"type":"integer"}},"required":["path"]},"capabilities":[' + Caps + ']}';
end;

function RegisterTextExtractService(AHost: PHostApiTable; const APluginId: string): Boolean;
begin
  FreeAndNil(GProvider);
  GProvider := TServiceProvider.Create(AHost,
    procedure(AJob: TServiceJob; const ARequestJson: string)
    var
      ResultJson, Msg: string;
      Code: Integer;
    begin
      if AnswerTextExtract(ARequestJson, ResultJson, Code, Msg) then
        AJob.ReplyResult(ResultJson)
      else
        AJob.ReplyError(Code, Msg);
    end);
  Result := GProvider.Register(APluginId, cServiceName, DescribeTextExtract, cPriority);
  if not Result then
    FreeAndNil(GProvider);
end;

procedure StopTextExtractService;
begin
  FreeAndNil(GProvider);
end;

end.
