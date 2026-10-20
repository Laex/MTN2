unit uNetCurlApi;

{ Dynamic binding to libcurl (easy interface only). The library is loaded from
  the plugin folder (libcurl-x64.dll, libcurl-4.dll or libcurl.dll next to the
  plugin on Windows, libcurl.so.4 on Linux); nothing is linked statically, so
  the plugin loads and reports a clear error when the library is missing.

  Option and info numbers are the ones of curl.h: option = base + number, with
  the base set by the argument type (long 0, object pointer 10000, function
  pointer 20000, curl_off_t 30000). Variadic curl_easy_setopt is called through
  three typed views of the same entry point; every argument is an integer or a
  pointer, which the Win64 and SysV x64 conventions pass identically. }

interface

type
  PCurl = Pointer;
  PCurlSlist = Pointer;
  CURLcode = Integer;
  // C "long": 32 bits on Windows, 64 bits on Linux.
  {$IFDEF MSWINDOWS}
  TCurlLong = Integer;
  {$ELSE}
  TCurlLong = Int64;
  {$ENDIF}

  TCurlWriteFn = function(ABuffer: Pointer; ASize, ACount: NativeUInt;
    AUserData: Pointer): NativeUInt; cdecl;
  TCurlSeekFn = function(AUserData: Pointer; AOffset: Int64; AOrigin: Integer): Integer; cdecl;
  TCurlXferInfoFn = function(AUserData: Pointer; ADlTotal, ADlNow, AUlTotal,
    AUlNow: Int64): Integer; cdecl;

  PCurlKhKey = ^TCurlKhKey;
  TCurlKhKey = record
    Key: PAnsiChar;
    Len: NativeUInt;
    KeyType: Integer;
  end;
  TCurlSshKeyFn = function(AEasy: PCurl; AKnownKey, AFoundKey: PCurlKhKey;
    AMatch: Integer; AUserData: Pointer): Integer; cdecl;

const
  CURLE_OK = 0;
  CURLE_UNSUPPORTED_PROTOCOL = 1;
  CURLE_FAILED_INIT = 2;
  CURLE_URL_MALFORMAT = 3;
  CURLE_COULDNT_RESOLVE_PROXY = 5;
  CURLE_COULDNT_RESOLVE_HOST = 6;
  CURLE_COULDNT_CONNECT = 7;
  CURLE_WEIRD_SERVER_REPLY = 8;
  CURLE_REMOTE_ACCESS_DENIED = 9;
  CURLE_FTP_ACCEPT_FAILED = 10;
  CURLE_FTP_WEIRD_PASS_REPLY = 11;
  CURLE_FTP_WEIRD_PASV_REPLY = 13;
  CURLE_FTP_WEIRD_227_FORMAT = 14;
  CURLE_FTP_CANT_GET_HOST = 15;
  CURLE_HTTP2 = 16;
  CURLE_FTP_COULDNT_SET_TYPE = 17;
  CURLE_PARTIAL_FILE = 18;
  CURLE_FTP_COULDNT_RETR_FILE = 19;
  CURLE_QUOTE_ERROR = 21;
  CURLE_HTTP_RETURNED_ERROR = 22;
  CURLE_WRITE_ERROR = 23;
  CURLE_UPLOAD_FAILED = 25;
  CURLE_READ_ERROR = 26;
  CURLE_OUT_OF_MEMORY = 27;
  CURLE_OPERATION_TIMEDOUT = 28;
  CURLE_FTP_PORT_FAILED = 30;
  CURLE_FTP_COULDNT_USE_REST = 31;
  CURLE_RANGE_ERROR = 33;
  CURLE_SSL_CONNECT_ERROR = 35;
  CURLE_BAD_DOWNLOAD_RESUME = 36;
  CURLE_FILE_COULDNT_READ_FILE = 37;
  CURLE_ABORTED_BY_CALLBACK = 42;
  CURLE_BAD_FUNCTION_ARGUMENT = 43;
  CURLE_GOT_NOTHING = 52;
  CURLE_SEND_ERROR = 55;
  CURLE_RECV_ERROR = 56;
  CURLE_SSL_CERTPROBLEM = 58;
  CURLE_SSL_CIPHER = 59;
  CURLE_PEER_FAILED_VERIFICATION = 60;
  CURLE_USE_SSL_FAILED = 64;
  CURLE_LOGIN_DENIED = 67;
  CURLE_REMOTE_DISK_FULL = 70;
  CURLE_REMOTE_FILE_EXISTS = 73;
  CURLE_SSL_CACERT_BADFILE = 77;
  CURLE_REMOTE_FILE_NOT_FOUND = 78;
  CURLE_SSH = 79;
  CURLE_SSL_ISSUER_ERROR = 83;
  CURLE_FTP_BAD_FILE_LIST = 87;

  CURL_GLOBAL_DEFAULT = 3;

  CURLOPT_PORT = 3;
  CURLOPT_TIMEOUT = 13;
  CURLOPT_INFILESIZE = 14;
  CURLOPT_LOW_SPEED_LIMIT = 19;
  CURLOPT_LOW_SPEED_TIME = 20;
  CURLOPT_RESUME_FROM = 21;
  CURLOPT_VERBOSE = 41;
  CURLOPT_NOPROGRESS = 43;
  CURLOPT_NOBODY = 44;
  CURLOPT_DIRLISTONLY = 48;
  CURLOPT_UPLOAD = 46;
  CURLOPT_POST = 47;
  CURLOPT_APPEND = 50;
  CURLOPT_FAILONERROR = 45;
  CURLOPT_FOLLOWLOCATION = 52;
  CURLOPT_POSTFIELDSIZE = 60;
  CURLOPT_SSL_VERIFYPEER = 64;
  CURLOPT_FILETIME = 69;
  CURLOPT_HTTPGET = 80;
  CURLOPT_SSL_VERIFYHOST = 81;
  CURLOPT_FTP_USE_EPSV = 85;
  CURLOPT_BUFFERSIZE = 98;
  CURLOPT_NOSIGNAL = 99;
  CURLOPT_PROXYTYPE = 101;
  CURLOPT_UNRESTRICTED_AUTH = 105;
  CURLOPT_FTP_USE_EPRT = 106;
  CURLOPT_HTTPAUTH = 107;
  CURLOPT_FTP_CREATE_MISSING_DIRS = 110;
  CURLOPT_FTP_RESPONSE_TIMEOUT = 112;
  CURLOPT_USE_SSL = 119;
  CURLOPT_FTPSSLAUTH = 129;
  CURLOPT_FTP_SKIP_PASV_IP = 137;
  CURLOPT_NEW_FILE_PERMS = 159;
  CURLOPT_FTP_FILEMETHOD = 138;
  CURLOPT_CONNECTTIMEOUT = 78;
  CURLOPT_SSH_AUTH_TYPES = 151;
  CURLOPT_TCP_KEEPALIVE = 213;
  CURLOPT_TCP_KEEPIDLE = 214;
  CURLOPT_TCP_KEEPINTVL = 215;
  CURLOPT_SSL_OPTIONS = 216;
  CURLOPT_SSH_COMPRESSION = 268;
  CURLOPT_UPLOAD_BUFFERSIZE = 280;

  CURLOPT_WRITEDATA = 10001;
  CURLOPT_URL = 10002;
  CURLOPT_PROXY = 10004;
  CURLOPT_USERPWD = 10005;
  CURLOPT_RANGE = 10007;
  CURLOPT_READDATA = 10009;
  CURLOPT_ERRORBUFFER = 10010;
  CURLOPT_POSTFIELDS = 10015;
  CURLOPT_USERAGENT = 10018;
  CURLOPT_FTPPORT = 10017;
  CURLOPT_HTTPHEADER = 10023;
  CURLOPT_KEYPASSWD = 10026;
  CURLOPT_QUOTE = 10028;
  CURLOPT_HEADERDATA = 10029;
  CURLOPT_CUSTOMREQUEST = 10036;
  CURLOPT_POSTQUOTE = 10039;
  CURLOPT_XFERINFODATA = 10057;
  CURLOPT_CAINFO = 10065;
  CURLOPT_ACCEPT_ENCODING = 10102;
  CURLOPT_COPYPOSTFIELDS = 10165;
  CURLOPT_SSH_PUBLIC_KEYFILE = 10152;
  CURLOPT_SSH_PRIVATE_KEYFILE = 10153;
  CURLOPT_SSH_KNOWNHOSTS = 10183;
  CURLOPT_SSH_KEYDATA = 10185;
  CURLOPT_SEEKDATA = 10168;
  CURLOPT_USERNAME = 10173;
  CURLOPT_PASSWORD = 10174;
  CURLOPT_AWS_SIGV4 = 10305;

  CURLOPT_WRITEFUNCTION = 20011;
  CURLOPT_READFUNCTION = 20012;
  CURLOPT_HEADERFUNCTION = 20079;
  CURLOPT_SSH_KEYFUNCTION = 20184;
  CURLOPT_SEEKFUNCTION = 20167;
  CURLOPT_XFERINFOFUNCTION = 20219;

  CURLOPT_INFILESIZE_LARGE = 30115;
  CURLOPT_RESUME_FROM_LARGE = 30116;
  CURLOPT_POSTFIELDSIZE_LARGE = 30120;

  CURLINFO_RESPONSE_CODE = $200002;
  CURLINFO_FILETIME = $20000E;
  CURLINFO_FILETIME_T = $60000E;
  CURLINFO_CONTENT_LENGTH_DOWNLOAD_T = $60000F;
  CURLINFO_SIZE_DOWNLOAD_T = $600008;
  CURLINFO_OS_ERRNO = $20002D;

  CURLUSESSL_NONE = 0;
  CURLUSESSL_TRY = 1;
  CURLUSESSL_CONTROL = 2;
  CURLUSESSL_ALL = 3;

  CURLFTPAUTH_DEFAULT = 0;
  CURLFTPAUTH_SSL = 1;
  CURLFTPAUTH_TLS = 2;

  CURLFTPMETHOD_MULTICWD = 1;
  CURLFTPMETHOD_NOCWD = 2;
  CURLFTPMETHOD_SINGLECWD = 3;

  CURLFTP_CREATE_DIR = 1;

  CURLAUTH_BASIC = 1;
  CURLAUTH_DIGEST = 2;
  CURLAUTH_NTLM = 8;
  CURLAUTH_NEGOTIATE = 4;
  CURLAUTH_ANY = -17; // all bits but CURLAUTH_NTLM_WB, as the signed long curl takes

  CURLSSH_AUTH_PUBLICKEY = 1;
  CURLSSH_AUTH_PASSWORD = 2;
  CURLSSH_AUTH_HOST = 4;
  CURLSSH_AUTH_KEYBOARD = 8;
  CURLSSH_AUTH_AGENT = 16;
  CURLSSH_AUTH_DEFAULT = -1;

  CURLSSLOPT_NATIVE_CA = 16;

  CURLPROXY_HTTP = 0;
  CURLPROXY_SOCKS4 = 4;
  CURLPROXY_SOCKS5 = 5;
  CURLPROXY_SOCKS5_HOSTNAME = 7;

  CURLKHMATCH_OK = 0;
  CURLKHMATCH_MISMATCH = 1;
  CURLKHMATCH_MISSING = 2;

  CURLKHSTAT_FINE_ADD_TO_FILE = 0;
  CURLKHSTAT_FINE = 1;
  CURLKHSTAT_REJECT = 2;

  CURL_READFUNC_ABORT = $10000000;
  CURL_READFUNC_PAUSE = $10000001;

type
  TCurlApi = record
    GlobalInit: function(AFlags: TCurlLong): CURLcode; cdecl;
    GlobalCleanup: procedure; cdecl;
    EasyInit: function: PCurl; cdecl;
    EasyCleanup: procedure(AHandle: PCurl); cdecl;
    EasyReset: procedure(AHandle: PCurl); cdecl;
    EasyPerform: function(AHandle: PCurl): CURLcode; cdecl;
    EasyStrError: function(ACode: CURLcode): PAnsiChar; cdecl;
    // curl_easy_setopt and curl_easy_getinfo are variadic: the same entry
    // point seen with the argument type each option takes.
    SetOptLong: function(AHandle: PCurl; AOption: Integer; AValue: TCurlLong): CURLcode; cdecl;
    SetOptPtr: function(AHandle: PCurl; AOption: Integer; AValue: Pointer): CURLcode; cdecl;
    SetOptOff: function(AHandle: PCurl; AOption: Integer; AValue: Int64): CURLcode; cdecl;
    GetInfo: function(AHandle: PCurl; AInfo: Integer; AOut: Pointer): CURLcode; cdecl;
    SlistAppend: function(AList: PCurlSlist; AText: PAnsiChar): PCurlSlist; cdecl;
    SlistFreeAll: procedure(AList: PCurlSlist); cdecl;
    Version: function: PAnsiChar; cdecl;
  end;

var
  Curl: TCurlApi;

/// <summary>Loads libcurl once. AFolder is searched first (the plugin folder);
/// the environment variable MTN2_CURL_DLL names a library to use instead.
/// False, with AError set, when no usable library is found.</summary>
function LoadCurl(const AFolder: string; out AError: string): Boolean;
function CurlLoaded: Boolean;
procedure UnloadCurl;
/// <summary>"libcurl/8.x ..." of the loaded library; '' when not loaded.</summary>
function CurlVersionText: string;
/// <summary>True when the version text lists the library ("libssh2").</summary>
function CurlHasFeature(const AName: string): Boolean;

implementation

uses
  System.SysUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ELSE}, Posix.Dlfcn{$ENDIF};

var
  GModule: NativeUInt = 0;
  GLoadError: string = '';
  GTried: Boolean = False;

function CurlLoaded: Boolean;
begin
  Result := GModule <> 0;
end;

function Bind(const AName: AnsiString; out AProc: Pointer): Boolean;
begin
  {$IFDEF MSWINDOWS}
  AProc := GetProcAddress(GModule, PAnsiChar(AName));
  {$ELSE}
  AProc := dlsym(GModule, PAnsiChar(AName));
  {$ENDIF}
  Result := AProc <> nil;
end;

function TryLoadFile(const APath: string): NativeUInt;
begin
  {$IFDEF MSWINDOWS}
  // Dependencies (OpenSSL, libssh2, zlib...) are looked up next to the library.
  Result := LoadLibraryEx(PChar(APath), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
  {$ELSE}
  Result := NativeUInt(dlopen(PAnsiChar(AnsiString(APath)), RTLD_NOW));
  {$ENDIF}
end;

function BindAll: Boolean;
var
  P: Pointer;

  function B(const AName: AnsiString; var ADest): Boolean;
  begin
    Result := Bind(AName, P);
    Pointer(ADest) := P;
  end;

begin
  Result := B('curl_global_init', Curl.GlobalInit) and
    B('curl_global_cleanup', Curl.GlobalCleanup) and
    B('curl_easy_init', Curl.EasyInit) and
    B('curl_easy_cleanup', Curl.EasyCleanup) and
    B('curl_easy_reset', Curl.EasyReset) and
    B('curl_easy_perform', Curl.EasyPerform) and
    B('curl_easy_strerror', Curl.EasyStrError) and
    B('curl_easy_setopt', Curl.SetOptLong) and
    B('curl_easy_setopt', Curl.SetOptPtr) and
    B('curl_easy_setopt', Curl.SetOptOff) and
    B('curl_easy_getinfo', Curl.GetInfo) and
    B('curl_slist_append', Curl.SlistAppend) and
    B('curl_slist_free_all', Curl.SlistFreeAll) and
    B('curl_version', Curl.Version);
end;

function LoadCurl(const AFolder: string; out AError: string): Boolean;
var
  Names: TArray<string>;
  Name, Path, Env: string;
begin
  AError := '';
  if GModule <> 0 then
    Exit(True);
  if GTried then
  begin
    AError := GLoadError;
    Exit(False);
  end;
  GTried := True;
  Env := GetEnvironmentVariable('MTN2_CURL_DLL');
  if Env <> '' then
    Names := [Env]
  else
  begin
    {$IFDEF MSWINDOWS}
    Names := ['libcurl-x64.dll', 'libcurl-4.dll', 'libcurl.dll'];
    {$ELSE}
    Names := ['libcurl.so.4', 'libcurl.so'];
    {$ENDIF}
  end;
  for Name in Names do
  begin
    if (Env <> '') or (AFolder = '') then
      Path := Name
    else
      Path := IncludeTrailingPathDelimiter(AFolder) + Name;
    {$IFDEF MSWINDOWS}
    if (Env = '') and not FileExists(Path) then
      Continue;
    {$ENDIF}
    GModule := TryLoadFile(Path);
    if GModule <> 0 then
      Break;
  end;
  {$IFNDEF MSWINDOWS}
  // On Linux the system library is the normal place for libcurl.
  if GModule = 0 then
    for Name in Names do
    begin
      GModule := TryLoadFile(Name);
      if GModule <> 0 then
        Break;
    end;
  {$ENDIF}
  if GModule = 0 then
  begin
    GLoadError := 'libcurl was not found next to the plugin';
    AError := GLoadError;
    Exit(False);
  end;
  if not BindAll then
  begin
    {$IFDEF MSWINDOWS}
    FreeLibrary(GModule);
    {$ELSE}
    dlclose(GModule);
    {$ENDIF}
    GModule := 0;
    GLoadError := 'the libcurl found is not usable (functions are missing)';
    AError := GLoadError;
    Exit(False);
  end;
  Curl.GlobalInit(CURL_GLOBAL_DEFAULT);
  Result := True;
end;

procedure UnloadCurl;
begin
  if GModule = 0 then
    Exit;
  Curl.GlobalCleanup;
  FillChar(Curl, SizeOf(Curl), 0);
  {$IFDEF MSWINDOWS}
  FreeLibrary(GModule);
  {$ELSE}
  dlclose(GModule);
  {$ENDIF}
  GModule := 0;
  GTried := False;
end;

function CurlVersionText: string;
begin
  if GModule = 0 then
    Exit('');
  Result := string(AnsiString(Curl.Version()));
end;

function CurlHasFeature(const AName: string): Boolean;
begin
  Result := Pos(LowerCase(AName), LowerCase(CurlVersionText)) > 0;
end;

end.
