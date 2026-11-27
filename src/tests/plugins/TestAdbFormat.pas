unit TestAdbFormat;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAdbFormat = class
  public
    [Test] procedure TestRootDeviceAndPathAddresses;
    [Test] procedure TestOtherSchemesAndDotSegmentsAreRejected;
    [Test] procedure TestSerialWithSlashSurvivesEncoding;
    [Test] procedure TestFileNamesAreNotPercentDecoded;
    [Test] procedure TestShellQuoteClosesAroundAnApostrophe;
    [Test] procedure TestShellArgsSendOneQuotedScript;
    [Test] procedure TestEveryScriptQuotesItsPaths;
    [Test] procedure TestTransferArgsPassPathsOutsideTheShell;
    [Test] procedure TestDeviceListGivesSerialStateAndModel;
    [Test] procedure TestDeviceListSkipsDaemonMessages;
    [Test] procedure TestStatListingGivesKindSizeAndTime;
    [Test] procedure TestStatListingKeepsOddNamesAndSkipsNoise;
    [Test] procedure TestProblemIsReadFromAdbErrorLinesOnly;
    [Test] procedure TestDaemonNoiseIsStripped;
    [Test] procedure TestSdkProgramsFollowTheVariablesThenTheDefaultFolder;
    [Test] procedure TestSdkProgramsSkipUnsetVariables;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uAdbFormat;

const
  // A space, Cyrillic, an apostrophe and the characters a shell would act on.
  cOddName = 'my '#$0444#$0430#$0439#$043B' it''s $(reboot);`x`&|"*';

function SdkAdb(const ARoot: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ARoot, 'platform-tools'),
    {$IFDEF MSWINDOWS}'adb.exe'{$ELSE}'adb'{$ENDIF});
end;

// The folder the Android tools install the SDK into, under the home variable.
function DefaultSdk(const AHome: string): string;
begin
  Result := TPath.Combine(TPath.Combine(AHome, 'Android'), 'Sdk');
end;

procedure TTestAdbFormat.TestSdkProgramsFollowTheVariablesThenTheDefaultFolder;
var
  Found: TArray<string>;
begin
  Found := AdbSdkPrograms(
    function(AName: string): string
    begin
      Result := 'v_' + AName;
    end);
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual(SdkAdb('v_ANDROID_HOME'), Found[0]);
  Assert.AreEqual(SdkAdb('v_ANDROID_SDK_ROOT'), Found[1]);
  Assert.AreEqual(SdkAdb(DefaultSdk({$IFDEF MSWINDOWS}'v_LOCALAPPDATA'{$ELSE}'v_HOME'{$ENDIF})), Found[2]);
end;

procedure TTestAdbFormat.TestSdkProgramsSkipUnsetVariables;
var
  Found: TArray<string>;
begin
  Found := AdbSdkPrograms(
    function(AName: string): string
    begin
      Result := '';
    end);
  Assert.AreEqual(0, Integer(Length(Found)));
end;

function Addr(const AUri: string): TAdbAddr;
begin
  Assert.IsTrue(ParseAdbUri(AUri, Result), AUri);
end;

procedure TTestAdbFormat.TestRootDeviceAndPathAddresses;
begin
  Assert.AreEqual(Ord(anRoot), Ord(Addr('adb:///').Node));
  Assert.AreEqual(Ord(anFs), Ord(Addr('adb:///emulator-5554').Node));
  Assert.AreEqual('emulator-5554', Addr('adb:///emulator-5554').Serial);
  Assert.AreEqual('/', Addr('adb:///emulator-5554').Path);
  Assert.AreEqual('/', Addr('adb:///emulator-5554/').Path);
  Assert.AreEqual('/sdcard/My Photos', Addr('adb:///192.168.1.5:5555/sdcard/My Photos').Path);
  Assert.AreEqual('192.168.1.5:5555', Addr('adb:///192.168.1.5:5555/sdcard').Serial);
end;

procedure TTestAdbFormat.TestOtherSchemesAndDotSegmentsAreRejected;
var
  A: TAdbAddr;
begin
  Assert.IsFalse(ParseAdbUri('docker:///x', A));
  Assert.IsFalse(ParseAdbUri('file:///C:/Work', A));
  Assert.IsFalse(ParseAdbUri('adb:///dev/sdcard/../data', A));
  Assert.IsFalse(ParseAdbUri('adb:///dev/./sdcard', A));
  Assert.AreEqual(Ord(anInvalid), Ord(A.Node));
end;

procedure TTestAdbFormat.TestSerialWithSlashSurvivesEncoding;
begin
  Assert.AreEqual('a%2Fb%25c', EncodeSegment('a/b%c'));
  Assert.AreEqual('a/b%c', Addr('adb:///' + EncodeSegment('a/b%c')).Serial);
end;

procedure TTestAdbFormat.TestFileNamesAreNotPercentDecoded;
begin
  // The panel appends a listed name as it is, so "%2F" in a file name is text.
  Assert.AreEqual('/sdcard/a%2Fb%25', Addr('adb:///dev/sdcard/a%2Fb%25').Path);
end;

procedure TTestAdbFormat.TestShellQuoteClosesAroundAnApostrophe;
begin
  Assert.AreEqual('''a b''', ShellQuote('a b'));
  Assert.AreEqual('''it''\''''s''', ShellQuote('it''s'));
  Assert.AreEqual('''$(reboot);`x`''', ShellQuote('$(reboot);`x`'));
  Assert.AreEqual('''''', ShellQuote(''));
end;

procedure TTestAdbFormat.TestShellArgsSendOneQuotedScript;
var
  Args: TArray<string>;
begin
  Args := ShellArgs('emulator-5554', 'echo hi');
  Assert.AreEqual(4, Integer(Length(Args)));
  Assert.AreEqual('-s|emulator-5554|shell|echo hi', string.Join('|', Args));
end;

procedure TTestAdbFormat.TestEveryScriptQuotesItsPaths;
var
  Path, Quoted: string;

  // Every occurrence of the name must be inside the quoted form.
  procedure Check(const AScript, AQuoted: string);
  begin
    Assert.IsTrue(Pos(AQuoted, AScript) > 0, AScript);
    Assert.AreEqual(0, Pos('$(reboot)', AScript.Replace(AQuoted, '')), AScript);
  end;

begin
  Path := '/sdcard/' + cOddName;
  Quoted := ShellQuote(Path);
  Check(ListScript(Path), ShellQuote(Path + '/'));
  Check(KindScript(Path), Quoted);
  Check(MkdirScript(Path), Quoted);
  Check(RemoveScript(Path), Quoted);
  Check(MoveScript(Path, '/sdcard/new'), Quoted);
  Check(MoveScript('/sdcard/old', Path), Quoted);
  Check(CopyScript(Path, '/sdcard/new', False), Quoted);
  Check(CopyScript(Path, '/sdcard/new', True), ShellQuote(Path + '/.'));
  Check(ReadScript(Path, 0), Quoted);
  Check(ReadScript(Path, 100), Quoted);
end;

procedure TTestAdbFormat.TestTransferArgsPassPathsOutsideTheShell;
begin
  // pull and push talk to the file service of the device: quotes would become
  // part of the name.
  Assert.AreEqual('-s|dev|pull|/sdcard/a b|C:\Temp\a b',
    string.Join('|', PullArgs('dev', '/sdcard/a b', 'C:\Temp\a b', False)));
  Assert.AreEqual('-s|dev|pull|-a|/sdcard/x|C:\Temp\x',
    string.Join('|', PullArgs('dev', '/sdcard/x', 'C:\Temp\x', True)));
  Assert.AreEqual('-s|dev|push|C:\Temp\a b|/sdcard/a b',
    string.Join('|', PushArgs('dev', 'C:\Temp\a b', '/sdcard/a b')));
end;

procedure TTestAdbFormat.TestDeviceListGivesSerialStateAndModel;
var
  D: TAdbDevices;
begin
  D := ParseDeviceList('List of devices attached'#13#10 +
    'emulator-5554          device product:sdk_phone model:Pixel_7 device:emu64 transport_id:1'#13#10 +
    '0123456789ABCDEF       unauthorized usb:1-1 transport_id:2'#13#10 +
    '192.168.1.5:5555       offline'#13#10 +
    '????????????           no permissions (missing udev rules); see [http://x] usb:2-1'#13#10 +
    'adb-1234 (2)._adb-tls-connect._tcp'#9'device model:Tab'#13#10 +
    #13#10);
  Assert.AreEqual(5, Integer(Length(D)));
  Assert.AreEqual('emulator-5554', D[0].Serial);
  Assert.AreEqual('device', D[0].State);
  Assert.AreEqual('Pixel 7', D[0].Model);
  Assert.AreEqual('sdk_phone', D[0].Product);
  Assert.AreEqual('unauthorized', D[1].State);
  Assert.AreEqual('', D[1].Model);
  Assert.AreEqual('offline', D[2].State);
  Assert.AreEqual('no permissions', D[3].State);
  Assert.AreEqual('adb-1234 (2)._adb-tls-connect._tcp', D[4].Serial);
  Assert.AreEqual('device', D[4].State);
end;

procedure TTestAdbFormat.TestDeviceListSkipsDaemonMessages;
begin
  Assert.AreEqual(0, Integer(Length(ParseDeviceList(
    '* daemon not running; starting now at tcp:5037'#10 +
    '* daemon started successfully'#10 +
    'List of devices attached'#10#10))));
  Assert.AreEqual(0, Integer(Length(ParseDeviceList('error: cannot connect to daemon'))));
end;

procedure TTestAdbFormat.TestStatListingGivesKindSizeAndTime;
var
  E: TAdbEntries;
begin
  E := ParseStatListing(
    'S|41f9|4096|1700000000|/sdcard/DCIM'#10 +
    'S|81b0|12|1700000100|/sdcard/note.txt'#10 +
    'S|a1ff|21|1700000200|/sdcard/self'#10 +
    'S|a1ff|5|1700000300|/sdcard/link.txt'#10 +
    'D|/sdcard/self'#10);
  Assert.AreEqual(4, Integer(Length(E)));
  Assert.AreEqual('DCIM', E[0].Name);
  Assert.IsTrue(E[0].IsDir);
  Assert.IsFalse(E[0].IsLink);
  Assert.IsFalse(E[1].IsDir);
  Assert.AreEqual(Int64(12), E[1].Size);
  Assert.AreEqual(Int64(1700000100), E[1].Modified);
  Assert.IsTrue(E[2].IsLink);
  Assert.IsTrue(E[2].IsDir, 'a link to a folder is a folder');
  Assert.IsTrue(E[3].IsLink);
  Assert.IsFalse(E[3].IsDir);
end;

procedure TTestAdbFormat.TestStatListingKeepsOddNamesAndSkipsNoise;
var
  E: TAdbEntries;
begin
  E := ParseStatListing(
    'stat: ''//init'': Permission denied'#10 +
    'S|81b0|1|0|//a|b ' + cOddName + #13#10 +
    'S|81b0|1|0|/d/ lead and trail '#10);
  Assert.AreEqual(2, Integer(Length(E)));
  Assert.AreEqual('a|b ' + cOddName, E[0].Name);
  Assert.AreEqual(' lead and trail ', E[1].Name);
end;

procedure TTestAdbFormat.TestProblemIsReadFromAdbErrorLinesOnly;
begin
  Assert.AreEqual(Ord(apUnauthorized), Ord(AdbProblem(
    'error: device unauthorized.'#10'This adb server''s $ADB_VENDOR_KEYS is not set')));
  Assert.AreEqual(Ord(apUnauthorized), Ord(AdbProblem('adb: error: failed to get feature set: device unauthorized.')));
  Assert.AreEqual(Ord(apOffline), Ord(AdbProblem('error: device offline'#13#10)));
  Assert.AreEqual(Ord(apNotConnected), Ord(AdbProblem('adb: device ''emulator-5554'' not found')));
  Assert.AreEqual(Ord(apNotConnected), Ord(AdbProblem('error: no devices/emulators found')));
  Assert.AreEqual(Ord(apNoPermissions), Ord(AdbProblem('error: insufficient permissions for device')));
  Assert.AreEqual(Ord(apNone), Ord(AdbProblem('ls: x: No such file or directory')));
  Assert.AreEqual(Ord(apNone), Ord(AdbProblem('the log says: device offline')));
end;

procedure TTestAdbFormat.TestDaemonNoiseIsStripped;
begin
  Assert.AreEqual('data'#10, StripDaemonNoise(
    '* daemon not running; starting now at tcp:5037'#13#10'* daemon started successfully'#13#10'data'#10));
  Assert.AreEqual('* a list item'#10, StripDaemonNoise('* a list item'#10));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAdbFormat);

end.
