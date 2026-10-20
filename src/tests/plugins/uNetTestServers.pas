unit uNetTestServers;

{ Local servers for the network plugin tests: FTP, FTPS, SFTP, WebDAV and S3
  started as child processes from the scripts in netservers\. The tests run
  only when the environment names a Python with the needed packages
  (MTN2_NET_TEST_PYTHON) and a libcurl to load (MTN2_CURL_DLL); otherwise they
  report a skip. MTN2_NET_TEST_KEYS additionally enables the login with a key
  file, for a libcurl whose libssh2 is known to handle keys. }

interface

uses
  System.SysUtils, System.Classes;

type
  TNetTestServer = class
  private
    FProcess: NativeUInt;
    FPort: Integer;
  public
    constructor Create(const AScript: string; const AArgs: array of string; APort: Integer);
    destructor Destroy; override;
    property Port: Integer read FPort;
  end;

/// <summary>Empty when the tests can run; otherwise the reason they cannot.</summary>
function NetTestUnavailable: string;
function NetTestScriptDir: string;
/// <summary>Loads libcurl for the tests (named by MTN2_CURL_DLL).</summary>
function NetTestLoadCurl(out AError: string): Boolean;
function PortAccepts(APort: Integer): Boolean;
function TestFixtureText: string;
/// <summary>Fills ARoot with the folder tree every server serves.</summary>
procedure BuildServedTree(const ARoot: string);

implementation

uses
  System.IOUtils, Winapi.Windows, Winapi.Winsock2, uNetCurlApi;

const
  cHelloText = 'hello world'#13#10;

function TestFixtureText: string;
begin
  Result := cHelloText;
end;

function NetTestUnavailable: string;
begin
  if GetEnvironmentVariable('MTN2_NET_TEST_PYTHON') = '' then
    Exit('MTN2_NET_TEST_PYTHON is not set');
  if not FileExists(GetEnvironmentVariable('MTN2_NET_TEST_PYTHON')) then
    Exit('MTN2_NET_TEST_PYTHON does not name a file');
  if GetEnvironmentVariable('MTN2_CURL_DLL') = '' then
    Exit('MTN2_CURL_DLL is not set');
  Result := '';
end;

function NetTestScriptDir: string;
var
  Dir: string;
begin
  // The tests run from their group folder or from the build folder; look upward.
  Dir := ExtractFilePath(ParamStr(0));
  while Dir <> '' do
  begin
    if DirectoryExists(TPath.Combine(Dir, 'netservers')) then
      Exit(TPath.Combine(Dir, 'netservers'));
    if DirectoryExists(TPath.Combine(TPath.Combine(Dir, 'plugins'), 'netservers')) then
      Exit(TPath.Combine(TPath.Combine(Dir, 'plugins'), 'netservers'));
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if (Length(Dir) <= 3) then
      Break;
  end;
  Result := GetEnvironmentVariable('MTN2_NET_TEST_SCRIPTS');
end;

function NetTestLoadCurl(out AError: string): Boolean;
begin
  Result := LoadCurl('', AError);
end;

function PortAccepts(APort: Integer): Boolean;
var
  WsaData: TWSAData;
  Sock: TSocket;
  Addr: TSockAddrIn;
begin
  Result := False;
  if WSAStartup($0202, WsaData) <> 0 then
    Exit;
  try
    Sock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if Sock = INVALID_SOCKET then
      Exit;
    try
      FillChar(Addr, SizeOf(Addr), 0);
      Addr.sin_family := AF_INET;
      Addr.sin_port := htons(APort);
      Addr.sin_addr.S_addr := inet_addr('127.0.0.1');
      Result := connect(Sock, PSockAddr(@Addr)^, SizeOf(Addr)) = 0;
    finally
      closesocket(Sock);
    end;
  finally
    WSACleanup;
  end;
end;

constructor TNetTestServer.Create(const AScript: string; const AArgs: array of string;
  APort: Integer);
var
  CmdLine, Arg: string;
  SI: TStartupInfo;
  PI: TProcessInformation;
  I: Integer;
begin
  inherited Create;
  FPort := APort;
  CmdLine := '"' + GetEnvironmentVariable('MTN2_NET_TEST_PYTHON') + '" "' +
    TPath.Combine(NetTestScriptDir, AScript) + '"';
  for Arg in AArgs do
    CmdLine := CmdLine + ' "' + Arg + '"';
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  if not CreateProcess(nil, PChar(CmdLine), nil, nil, False, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    raise Exception.Create('Cannot start ' + AScript + ': ' + SysErrorMessage(GetLastError));
  CloseHandle(PI.hThread);
  FProcess := PI.hProcess;
  for I := 1 to 200 do
  begin
    if PortAccepts(APort) then
      Exit;
    Sleep(100);
  end;
  raise Exception.Create(AScript + ' did not start listening on port ' + IntToStr(APort));
end;

destructor TNetTestServer.Destroy;
begin
  if FProcess <> 0 then
  begin
    TerminateProcess(FProcess, 0);
    CloseHandle(FProcess);
  end;
  inherited Destroy;
end;

procedure BuildServedTree(const ARoot: string);
begin
  TDirectory.CreateDirectory(TPath.Combine(ARoot, 'docs'));
  TDirectory.CreateDirectory(TPath.Combine(ARoot, 'empty'));
  TFile.WriteAllText(TPath.Combine(ARoot, 'hello.txt'), cHelloText, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ARoot, 'docs\a.txt'), 'A file', TEncoding.ASCII);
end;

end.
