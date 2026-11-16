unit TestTextExtractService;

{ The text.extract service: the messages of the host, the plugin side that answers
  them, and a content search that reads documents through a provider. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTextExtractService = class
  private
    FDir: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestRequestCarriesPathAndLimit;
    [Test] procedure TestResultParsing;
    [Test] procedure TestServedExtensionsComeFromCapabilities;
    [Test] procedure TestProviderAnswersForItsExtension;
    [Test] procedure TestProviderRejectsOtherExtensions;
    [Test] procedure TestProviderTruncatesTheText;
    [Test] procedure TestBadParametersAreRejected;
    [Test] procedure TestSearchReadsDocumentsThroughTheProvider;
    [Test] procedure TestBuiltInOnlySearchIgnoresTheProvider;
    [Test] procedure TestDocumentsAreAddedToProviderHitsOnce;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  uVfsTypes, uFileFind, uFindRouter, uPluginHostAbi, uPluginServiceHost, uServiceRegistry,
  uTextExtractService, uDocTextService;

const
  cPlugin = 'test.extractor';
  cFinder = 'test.finder2';
  cTextReply =
    '{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"text":"alpha needle omega","truncated":false}}}';

var
  GDone: Boolean;
  GHits: TArray<TFindHit>;
  GFinderPath: string;

function Extractor(AUserData: Pointer; ACall: Int64; AMessageJson: PAnsiChar): Int64; cdecl;
begin
  HostServiceReply(ACall, cTextReply);
  Result := 0;
end;

function Finder(AUserData: Pointer; ACall: Int64; AMessageJson: PAnsiChar): Int64; cdecl;
var
  Hits, Done: UTF8String;
begin
  // Reports a file the walk also finds through its text.
  Hits := UTF8String('{"jsonrpc":"2.0","method":"search.hits","params":{"hits":[{"path":"' +
    StringReplace(GFinderPath, '\', '\\', [rfReplaceAll]) + '"}]}}');
  Done := UTF8String('{"jsonrpc":"2.0","id":1,"result":{"structuredContent":' +
    '{"count":1,"truncated":false}}}');
  HostServiceNotify(ACall, PAnsiChar(Hits));
  HostServiceReply(ACall, PAnsiChar(Done));
  Result := 0;
end;

procedure TTestTextExtractService.Setup;
begin
  PluginServicesUnregister(cPlugin);
  PluginServicesUnregister(cFinder);
  GDone := False;
  SetLength(GHits, 0);
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn_extract_' + IntToStr(TThread.GetTickCount64));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestTextExtractService.TearDown;
begin
  PluginServicesUnregister(cPlugin);
  PluginServicesUnregister(cFinder);
  ServiceRegistry.Pump;
  CheckSynchronize(0);
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

function RegisterExtractor: Int64;
begin
  Result := HostRegisterService(cPlugin, cTextExtractService, 1,
    PAnsiChar(UTF8String('{"capabilities":["ext.zzz"]}')), Extractor, nil, 50);
end;

procedure Search(const ARoot, AText: string; ABuiltInOnly: Boolean);
var
  O: TFindOptions;
  Tick: UInt64;
begin
  O := DefaultFindOptions(ARoot, '*.*', True);
  O.ContainingText := AText;
  O.BuiltInOnly := ABuiltInOnly;
  FindFilesRouted(O, nil,
    procedure(AFound: Integer; const ADir: string)
    begin
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError; ATruncated: Boolean)
    begin
      GHits := AHits;
      GDone := True;
    end);
  Tick := TThread.GetTickCount64;
  while not GDone and (TThread.GetTickCount64 - Tick < 5000) do
  begin
    ServiceRegistry.Pump;
    CheckSynchronize(5);
  end;
  Assert.IsTrue(GDone, 'the search finished');
end;

procedure TTestTextExtractService.TestRequestCarriesPathAndLimit;
var
  Root, Params: TJSONValue;
begin
  Root := TJSONObject.ParseJSONValue(BuildTextExtractRequest('C:\Work\a.docx', 1000, 7));
  try
    Assert.AreEqual('text.extract', TJSONObject(Root).GetValue<string>('method'));
    Assert.AreEqual(7, TJSONObject(Root).GetValue<Integer>('id'));
    Params := TJSONObject(Root).GetValue('params');
    Assert.AreEqual('C:\Work\a.docx', TJSONObject(Params).GetValue<string>('path'));
    Assert.AreEqual(1000, TJSONObject(Params).GetValue<Integer>('maxChars'));
  finally
    Root.Free;
  end;
end;

procedure TTestTextExtractService.TestResultParsing;
var
  Text: string;
  Truncated: Boolean;
begin
  Assert.IsTrue(ParseTextExtractResult(
    '{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"text":"abc","truncated":true}}}',
    Text, Truncated));
  Assert.AreEqual('abc', Text);
  Assert.IsTrue(Truncated);
  Assert.IsFalse(ParseTextExtractResult(
    '{"jsonrpc":"2.0","id":1,"error":{"code":-32002,"message":"no"}}', Text, Truncated));
  Assert.IsFalse(ParseTextExtractResult(
    '{"jsonrpc":"2.0","id":1,"result":{"isError":true,"structuredContent":{"text":"x"}}}',
    Text, Truncated));
  Assert.IsFalse(ParseTextExtractResult('{"jsonrpc":"2.0","id":1,"result":{}}', Text, Truncated));
end;

procedure TTestTextExtractService.TestServedExtensionsComeFromCapabilities;
var
  Info: TServiceProviderInfo;
  Exts: TArray<string>;
begin
  Info := Default(TServiceProviderInfo);
  Info.Capabilities := ['ext.docx', 'name', 'ext.pdf', 'ext.docx', 'ext.'];
  Exts := ServedExtensions([Info]);
  Assert.AreEqual<Integer>(2, Length(Exts));
  Assert.AreEqual('.docx', Exts[0]);
  Assert.AreEqual('.pdf', Exts[1]);
  Assert.AreEqual('ext.docx', ExtensionCapability('.DOCX'));
end;

procedure TTestTextExtractService.TestProviderAnswersForItsExtension;
var
  Path, Json, Msg: string;
  Code: Integer;
  Root: TJSONValue;
begin
  Path := TPath.Combine(FDir, 'logo.svg');
  TFile.WriteAllText(Path, '<svg width="10" height="20"><title>Logo</title></svg>');
  Assert.IsTrue(AnswerTextExtract(BuildTextExtractRequest(Path, 100000, 1), Json, Code, Msg), Msg);
  Root := TJSONObject.ParseJSONValue(Json);
  try
    Assert.IsTrue(Pos('Logo', TJSONObject(Root).GetValue('structuredContent')
      .GetValue<string>('text')) > 0, 'the text of the document');
    Assert.IsFalse(TJSONObject(Root).GetValue('structuredContent').GetValue<Boolean>('truncated'));
  finally
    Root.Free;
  end;
end;

procedure TTestTextExtractService.TestProviderRejectsOtherExtensions;
var
  Path, Json, Msg: string;
  Code: Integer;
begin
  Path := TPath.Combine(FDir, 'plain.txt');
  TFile.WriteAllText(Path, 'text');
  Assert.IsFalse(AnswerTextExtract(BuildTextExtractRequest(Path, 100, 1), Json, Code, Msg));
  Assert.AreEqual(-32002, Code);
  Assert.IsFalse(AnswerTextExtract(BuildTextExtractRequest(TPath.Combine(FDir, 'none.pdf'), 100, 1),
    Json, Code, Msg));
  Assert.AreEqual(-32002, Code, 'a missing file');
end;

procedure TTestTextExtractService.TestProviderTruncatesTheText;
var
  Path, Json, Msg: string;
  Code: Integer;
  Root, Struct: TJSONValue;
begin
  Path := TPath.Combine(FDir, 'logo.svg');
  TFile.WriteAllText(Path, '<svg width="10" height="20"><title>Logo</title></svg>');
  Assert.IsTrue(AnswerTextExtract(BuildTextExtractRequest(Path, 5, 1), Json, Code, Msg), Msg);
  Root := TJSONObject.ParseJSONValue(Json);
  try
    Struct := TJSONObject(Root).GetValue('structuredContent');
    Assert.AreEqual(5, Length(TJSONObject(Struct).GetValue<string>('text')));
    Assert.IsTrue(TJSONObject(Struct).GetValue<Boolean>('truncated'));
  finally
    Root.Free;
  end;
end;

procedure TTestTextExtractService.TestBadParametersAreRejected;
var
  Json, Msg: string;
  Code: Integer;
begin
  Assert.IsFalse(AnswerTextExtract('{"jsonrpc":"2.0","id":1,"method":"text.extract","params":{}}',
    Json, Code, Msg));
  Assert.AreEqual(-32602, Code);
  Assert.IsFalse(AnswerTextExtract('not json', Json, Code, Msg));
  Assert.AreEqual(-32602, Code);
end;

procedure TTestTextExtractService.TestSearchReadsDocumentsThroughTheProvider;
begin
  TFile.WriteAllText(TPath.Combine(FDir, 'a.zzz'), 'nothing to see');
  TFile.WriteAllText(TPath.Combine(FDir, 'b.txt'), 'nothing either');
  Assert.AreEqual<Int64>(0, RegisterExtractor);
  Search(FDir, 'needle', False);
  Assert.AreEqual<Integer>(1, Length(GHits), 'only the document the provider reads');
  Assert.AreEqual('a.zzz', ExtractFileName(GHits[0].Path));
  Assert.AreEqual(1, GHits[0].Line);
end;

procedure TTestTextExtractService.TestBuiltInOnlySearchIgnoresTheProvider;
begin
  TFile.WriteAllText(TPath.Combine(FDir, 'a.zzz'), 'nothing to see');
  Assert.AreEqual<Int64>(0, RegisterExtractor);
  Search(FDir, 'needle', True);
  Assert.AreEqual<Integer>(0, Length(GHits));
end;

procedure TTestTextExtractService.TestDocumentsAreAddedToProviderHitsOnce;
begin
  // The finder lists a.zzz; the walk reads the same file through the extractor and
  // must not list it twice, while c.zzz is only found by the walk.
  TFile.WriteAllText(TPath.Combine(FDir, 'a.zzz'), 'nothing to see');
  TFile.WriteAllText(TPath.Combine(FDir, 'c.zzz'), 'nothing here');
  GFinderPath := TPath.Combine(FDir, 'a.zzz');
  Assert.AreEqual<Int64>(0, RegisterExtractor);
  Assert.AreEqual<Int64>(0, HostRegisterService(cFinder, 'search.files', 1,
    PAnsiChar(UTF8String('{"capabilities":["name","mask","subdirs","folders","case","words","content"]}')),
    Finder, nil, 100));
  Search(FDir, 'needle', False);
  Assert.AreEqual<Integer>(2, Length(GHits), 'the finder hit and the other document, each once');
end;

end.
