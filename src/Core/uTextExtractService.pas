unit uTextExtractService;

{ The host side of the text.extract service (docs/PLUGIN_SERVICES.md): a provider turns a
  document (docx, pdf, ...) into plain text. A content search uses it so such files are
  searched by their text instead of their bytes. The provider lists the extensions it
  serves as capabilities "ext.<extension>". }

interface

uses
  uVfsTypes, uFileFind, uServiceRegistry;

const
  cTextExtractService = 'text.extract';

/// <summary>The request of one extraction; AMaxChars bounds the text returned.</summary>
function BuildTextExtractRequest(const APath: string; AMaxChars, AId: Integer): string;

/// <summary>The text of a response; False for an error response or a malformed one.</summary>
function ParseTextExtractResult(const AMessageJson: string; out AText: string;
  out ATruncated: Boolean): Boolean;

/// <summary>.DOCX -> ext.docx</summary>
function ExtensionCapability(const AExt: string): string;

/// <summary>The extensions (lower case, with the dot) the providers list.</summary>
function ServedExtensions(const AProviders: TArray<TServiceProviderInfo>): TArray<string>;

/// <summary>An extractor that calls the providers of the service; nil when none serves
/// an extension. Main thread: the registry is read here. Extract itself may run on any
/// thread and ends with False when ACancel is set.</summary>
function CreateServiceTextExtractor(ACancel: IJobCancelToken): ITextExtractor;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.JSON, uJsonRpc,
  uPluginServiceHost;

const
  cExtractSilenceMs = 30000;
  cExtractMaxChars = 4 * 1024 * 1024;
  cCancelPollMs = 100;

function BuildTextExtractRequest(const APath: string; AMaxChars, AId: Integer): string;
var
  P: TJSONObject;
begin
  P := TJSONObject.Create;
  try
    P.AddPair('path', APath);
    P.AddPair('maxChars', TJSONNumber.Create(AMaxChars));
    Result := BuildRpcRequest(RpcIntId(AId), cTextExtractService, P.ToJSON);
  finally
    P.Free;
  end;
end;

function ParseTextExtractResult(const AMessageJson: string; out AText: string;
  out ATruncated: Boolean): Boolean;
var
  Root, Res, Struct: TJSONValue;
begin
  Result := False;
  AText := '';
  ATruncated := False;
  Root := TJSONObject.ParseJSONValue(AMessageJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Res := TJSONObject(Root).GetValue('result');
    if not (Res is TJSONObject) then
      Exit;
    if TJSONObject(Res).GetValue<Boolean>('isError', False) then
      Exit;
    Struct := TJSONObject(Res).GetValue('structuredContent');
    if not (Struct is TJSONObject) or (TJSONObject(Struct).GetValue('text') = nil) then
      Exit;
    AText := TJSONObject(Struct).GetValue<string>('text', '');
    ATruncated := TJSONObject(Struct).GetValue<Boolean>('truncated', False);
    Result := True;
  finally
    Root.Free;
  end;
end;

function ExtensionCapability(const AExt: string): string;
begin
  Result := 'ext.' + LowerCase(AExt).TrimLeft(['.']);
end;

function ServedExtensions(const AProviders: TArray<TServiceProviderInfo>): TArray<string>;
var
  Info: TServiceProviderInfo;
  Cap, Ext: string;
  Known: Boolean;
  I: Integer;
begin
  SetLength(Result, 0);
  for Info in AProviders do
    for Cap in Info.Capabilities do
    begin
      if not Cap.StartsWith('ext.') or (Length(Cap) <= 4) then
        Continue;
      Ext := '.' + Copy(Cap, 5, MaxInt);
      Known := False;
      for I := 0 to High(Result) do
        if Result[I] = Ext then
          Known := True;
      if not Known then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Ext;
      end;
    end;
end;

type
  /// <summary>One extraction in flight; shared by the walk thread that waits and the
  /// main-thread callbacks, so it outlives whichever ends first.</summary>
  TExtractCall = class
  public
    Done: TEvent;
    Ok: Boolean;
    Text: string;
    Job: Int64;
    constructor Create;
    destructor Destroy; override;
  end;

  TServiceTextExtractor = class(TInterfacedObject, ITextExtractor)
  private
    FExts: TArray<string>;
    FCancel: IJobCancelToken;
  public
    constructor Create(const AExts: TArray<string>; ACancel: IJobCancelToken);
    function Serves(const AExt: string): Boolean;
    function Extract(const APath: string; out AText: string): Boolean;
  end;

constructor TExtractCall.Create;
begin
  inherited Create;
  Done := TEvent.Create(nil, True, False, '');
end;

destructor TExtractCall.Destroy;
begin
  Done.Free;
  inherited;
end;

constructor TServiceTextExtractor.Create(const AExts: TArray<string>;
  ACancel: IJobCancelToken);
begin
  inherited Create;
  FExts := AExts;
  FCancel := ACancel;
end;

function TServiceTextExtractor.Serves(const AExt: string): Boolean;
var
  E, Lower: string;
begin
  Result := False;
  Lower := LowerCase(AExt);
  for E in FExts do
    if E = Lower then
      Exit(True);
end;

function TServiceTextExtractor.Extract(const APath: string; out AText: string): Boolean;
var
  Call: TExtractCall;
  Ext: string;
  Abandoned: Boolean;
begin
  AText := '';
  Abandoned := False;
  Ext := ExtractFileExt(APath);
  Call := TExtractCall.Create;
  TThread.Queue(nil,
    procedure
    var
      Plugin: string;
      Code: Integer;
    begin
      if not ServiceRegistry.PickProvider(cTextExtractService,
           [ExtensionCapability(Ext)], Plugin) then
      begin
        Call.Done.SetEvent;
        Exit;
      end;
      Code := ServiceCallAsync(cTextExtractService, Plugin,
        BuildTextExtractRequest(APath, cExtractMaxChars, 1), cExtractSilenceMs,
        procedure(AJobId: Int64; const AMessageJson: string)
        var
          Msg: TRpcMessage;
          ParseCode: Integer;
          Truncated: Boolean;
        begin
          if not TryParseRpcMessage(AMessageJson, Msg, ParseCode) or
             (Msg.Kind <> rkResponse) then
            Exit;
          Call.Ok := ParseTextExtractResult(AMessageJson, Call.Text, Truncated);
          Call.Done.SetEvent;
        end, Call.Job);
      if Code <> 0 then
        Call.Done.SetEvent;
    end);

  try
    while Call.Done.WaitFor(cCancelPollMs) = wrTimeout do
      if JobCancelRequested(FCancel) then
      begin
        Abandoned := True;
        TThread.Queue(nil,
          procedure
          begin
            if Call.Job <> 0 then
              ServiceCancel(Call.Job);
          end);
        Exit(False);
      end;
    Result := Call.Ok;
    if Result then
      AText := Call.Text;
  finally
    // After a cancel the main thread may still touch Call, so that object is left alone.
    if not Abandoned then
      Call.Free;
  end;
end;

function CreateServiceTextExtractor(ACancel: IJobCancelToken): ITextExtractor;
var
  Exts: TArray<string>;
begin
  Exts := ServedExtensions(ServiceRegistry.Providers(cTextExtractService));
  if Length(Exts) = 0 then
    Exit(nil);
  Result := TServiceTextExtractor.Create(Exts, ACancel);
end;

end.
