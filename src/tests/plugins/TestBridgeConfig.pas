unit TestBridgeConfig;

{ The server list of mtn.bridge and the consent a server needs before it runs. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBridgeConfig = class
  public
    [Test] procedure TestEmptySettingMeansNoServers;
    [Test] procedure TestServerFieldsAreRead;
    [Test] procedure TestDefaultsAndTimeoutBounds;
    [Test] procedure TestBadListsAreRefused;
    [Test] procedure TestDuplicateNamesAreRefused;
    [Test] procedure TestCommandTextShowsEverythingThatRuns;
    [Test] procedure TestConsentKeyFollowsTheCommand;
    [Test] procedure TestConsentKeyIgnoresTheOrderOfEnvironment;
    [Test] procedure TestApprovalIsPerServerAndExact;
    [Test] procedure TestApprovalOfOneServerKeepsTheOthers;
    [Test] procedure TestAllowListLimitsTools;
    [Test] procedure TestUrlMakesAnHttpServer;
    [Test] procedure TestHttpServerSurvivesTheRoundTrip;
    [Test] procedure TestHttpServerRulesAreEnforced;
    [Test] procedure TestStdioServerRulesAreEnforced;
    [Test] procedure TestHttpConsentKeyFollowsAddressAndHeaders;
    [Test] procedure TestStdioConsentKeyIsUnchanged;
    [Test] procedure TestHttpCommandTextShowsAddressAndHeaders;
    [Test] procedure TestWordsSplitAndJoinBack;
    [Test] procedure TestTargetTextOfBothTransports;
  end;

implementation

uses
  System.SysUtils, uBridgeConfig;

const
  cOne =
    '[{"name":"py-tools","command":"python","args":["srv.py","--fast"],"cwd":"C:\\Tools",' +
    '"env":{"A":"1","B":"2"},"startTimeoutMs":5000,"allow":["find"]}]';

function One: TBridgeServerConfig;
var
  List: TArray<TBridgeServerConfig>;
  Err: string;
begin
  Assert.IsTrue(ParseBridgeServers(cOne, List, Err), Err);
  Result := List[0];
end;

procedure TTestBridgeConfig.TestEmptySettingMeansNoServers;
var
  List: TArray<TBridgeServerConfig>;
  Err: string;
begin
  Assert.IsTrue(ParseBridgeServers('', List, Err));
  Assert.AreEqual<Integer>(0, Length(List));
  Assert.IsTrue(ParseBridgeServers('[]', List, Err));
  Assert.AreEqual<Integer>(0, Length(List));
end;

procedure TTestBridgeConfig.TestServerFieldsAreRead;
var
  S: TBridgeServerConfig;
begin
  S := One;
  Assert.AreEqual('py-tools', S.Name);
  Assert.AreEqual('python', S.Command);
  Assert.AreEqual<Integer>(2, Length(S.Args));
  Assert.AreEqual('--fast', S.Args[1]);
  Assert.AreEqual('C:\Tools', S.Dir);
  Assert.AreEqual<Integer>(2, Length(S.Env));
  Assert.AreEqual('A=1', S.Env[0]);
  Assert.AreEqual(5000, S.StartTimeoutMs);
  Assert.AreEqual<Integer>(1, Length(S.Allow));
end;

procedure TTestBridgeConfig.TestDefaultsAndTimeoutBounds;
var
  List: TArray<TBridgeServerConfig>;
  Err: string;
begin
  Assert.IsTrue(ParseBridgeServers('[{"name":"a","command":"x"},' +
    '{"name":"b","command":"x","startTimeoutMs":1},{"name":"c","command":"x","startTimeoutMs":999999}]',
    List, Err), Err);
  Assert.AreEqual(cDefaultStartTimeoutMs, List[0].StartTimeoutMs);
  Assert.AreEqual(cMinStartTimeoutMs, List[1].StartTimeoutMs);
  Assert.AreEqual(cMaxStartTimeoutMs, List[2].StartTimeoutMs);
  Assert.AreEqual<Integer>(0, Length(List[0].Args));
  Assert.AreEqual('', List[0].Dir);
end;

procedure TTestBridgeConfig.TestBadListsAreRefused;
var
  List: TArray<TBridgeServerConfig>;
  Err: string;
begin
  Assert.IsFalse(ParseBridgeServers('{"name":"a"}', List, Err), 'not an array');
  Assert.IsFalse(ParseBridgeServers('not json', List, Err));
  Assert.IsFalse(ParseBridgeServers('[7]', List, Err), 'entry is not an object');
  Assert.IsFalse(ParseBridgeServers('[{"command":"x"}]', List, Err), 'no name');
  Assert.IsFalse(ParseBridgeServers('[{"name":"Bad Name","command":"x"}]', List, Err), 'bad name');
  Assert.IsFalse(ParseBridgeServers('[{"name":"a"}]', List, Err), 'no command');
  Assert.IsFalse(ParseBridgeServers('[{"name":"a","command":"x","args":[1]}]', List, Err), 'args');
  Assert.IsFalse(ParseBridgeServers('[{"name":"a","command":"x","env":{"K=V":"1"}}]', List, Err), 'env name');
  Assert.IsFalse(ParseBridgeServers('[{"name":"a","command":"x","env":{"K":1}}]', List, Err), 'env value');
  Assert.AreNotEqual('', Err);
  Assert.AreEqual<Integer>(0, Length(List));
end;

procedure TTestBridgeConfig.TestDuplicateNamesAreRefused;
var
  List: TArray<TBridgeServerConfig>;
  Err: string;
begin
  Assert.IsFalse(ParseBridgeServers('[{"name":"a","command":"x"},{"name":"a","command":"y"}]', List, Err));
  Assert.IsTrue(Pos('twice', Err) > 0);
end;

procedure TTestBridgeConfig.TestCommandTextShowsEverythingThatRuns;
var
  S: TBridgeServerConfig;
  Text: string;
begin
  S := One;
  S.Args := ['a b', 'c'];
  Text := BridgeCommandText(S);
  Assert.IsTrue(Pos('python "a b" c', Text) = 1, Text);
  Assert.IsTrue(Pos('C:\Tools', Text) > 0, 'the folder');
  Assert.IsTrue(Pos('env A=1', Text) > 0, 'the environment');
end;

procedure TTestBridgeConfig.TestConsentKeyFollowsTheCommand;
var
  A, B: TBridgeServerConfig;
begin
  A := One;
  B := One;
  Assert.AreEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'the same command, the same key');
  B.Args := ['srv.py', '--slow'];
  Assert.AreNotEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'another argument');
  B := One;
  B.Command := 'python3';
  Assert.AreNotEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'another program');
  B := One;
  B.Dir := 'C:\Other';
  Assert.AreNotEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'another folder');
  B := One;
  B.Env := ['A=1'];
  Assert.AreNotEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'another environment');
end;

procedure TTestBridgeConfig.TestConsentKeyIgnoresTheOrderOfEnvironment;
var
  A, B: TBridgeServerConfig;
begin
  A := One;
  B := One;
  B.Env := ['B=2', 'A=1'];
  Assert.AreEqual(BridgeConsentKey(A), BridgeConsentKey(B));
end;

procedure TTestBridgeConfig.TestApprovalIsPerServerAndExact;
var
  S, Other: TBridgeServerConfig;
  Approvals: string;
begin
  S := One;
  Assert.IsFalse(BridgeIsApproved('', S), 'nothing approved yet');
  Assert.IsFalse(BridgeIsApproved('not json', S));
  Approvals := BridgeWithApproval('', S);
  Assert.IsTrue(BridgeIsApproved(Approvals, S));
  Other := S;
  Other.Args := ['evil.py'];
  Assert.IsFalse(BridgeIsApproved(Approvals, Other), 'a changed command is asked again');
  Other := S;
  Other.Name := 'other';
  Assert.IsFalse(BridgeIsApproved(Approvals, Other), 'another server');
end;

procedure TTestBridgeConfig.TestApprovalOfOneServerKeepsTheOthers;
var
  A, B: TBridgeServerConfig;
  Approvals: string;
begin
  A := One;
  B := One;
  B.Name := 'second';
  Approvals := BridgeWithApproval('', A);
  Approvals := BridgeWithApproval(Approvals, B);
  Assert.IsTrue(BridgeIsApproved(Approvals, A));
  Assert.IsTrue(BridgeIsApproved(Approvals, B));
  B.Command := 'changed';
  Approvals := BridgeWithApproval(Approvals, B);
  Assert.IsTrue(BridgeIsApproved(Approvals, A), 'the first approval stays');
  Assert.IsTrue(BridgeIsApproved(Approvals, B), 'the new command replaces the old approval');
end;

procedure TTestBridgeConfig.TestAllowListLimitsTools;
var
  S: TBridgeServerConfig;
begin
  S := One;
  Assert.IsTrue(BridgeToolAllowed(S, 'find'));
  Assert.IsTrue(BridgeToolAllowed(S, 'FIND'));
  Assert.IsFalse(BridgeToolAllowed(S, 'delete'));
  S.Allow := nil;
  Assert.IsTrue(BridgeToolAllowed(S, 'delete'), 'an empty list allows all');
end;

function Http(const AUrl: string): TBridgeServerConfig;
begin
  Result := Default(TBridgeServerConfig);
  Result.Name := 'web';
  Result.Transport := btHttp;
  Result.Url := AUrl;
  Result.StartTimeoutMs := cDefaultStartTimeoutMs;
end;

procedure TTestBridgeConfig.TestUrlMakesAnHttpServer;
var
  List: TArray<TBridgeServerConfig>;
  Err: string;
begin
  Assert.IsTrue(ParseBridgeServers(
    '[{"name":"web","url":"https://example.org/rpc","headers":{"X-Token":"t1"}}]', List, Err), Err);
  Assert.IsTrue(List[0].Transport = btHttp);
  Assert.AreEqual('https://example.org/rpc', List[0].Url);
  Assert.AreEqual<Integer>(1, Length(List[0].Headers));
  Assert.AreEqual('X-Token=t1', List[0].Headers[0]);
end;

procedure TTestBridgeConfig.TestHttpServerSurvivesTheRoundTrip;
var
  S: TBridgeServerConfig;
  Back: TArray<TBridgeServerConfig>;
  Err: string;
begin
  S := Http('http://localhost:8080/rpc');
  S.Headers := ['X-A=1', 'X-B=two words'];
  S.Allow := ['find'];
  Assert.IsTrue(ParseBridgeServers(BridgeServersToJson([S, One]), Back, Err), Err);
  Assert.AreEqual<Integer>(2, Length(Back));
  Assert.AreEqual(BridgeConsentKey(S), BridgeConsentKey(Back[0]));
  Assert.AreEqual(BridgeConsentKey(One), BridgeConsentKey(Back[1]));
  Assert.AreEqual('X-B=two words', Back[0].Headers[1]);
  Assert.AreEqual('find', Back[0].Allow[0]);
end;

procedure TTestBridgeConfig.TestHttpServerRulesAreEnforced;
var
  S: TBridgeServerConfig;
  Err: string;
begin
  Assert.IsTrue(ValidateBridgeServer(Http('http://host/x'), Err), Err);
  Assert.IsFalse(ValidateBridgeServer(Http('ftp://host/x'), Err), 'scheme');
  Assert.IsFalse(ValidateBridgeServer(Http('http://'), Err), 'no host');
  Assert.IsFalse(ValidateBridgeServer(Http('http://user:pw@host/x'), Err), 'credentials in the address');
  Assert.IsFalse(ValidateBridgeServer(Http('http://host/a b'), Err), 'blank in the address');
  S := Http('http://host/x');
  S.Command := 'prog';
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'a program with an address');
  S := Http('http://host/x');
  S.Headers := ['no-equals'];
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'header without a value');
  S.Headers := ['Bad Name=1'];
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'header name with a blank');
  S.Headers := ['X-A=1'#13#10'Evil=2'];
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'line break in a header');
end;

procedure TTestBridgeConfig.TestStdioServerRulesAreEnforced;
var
  S: TBridgeServerConfig;
  Err: string;
begin
  S := One;
  Assert.IsTrue(ValidateBridgeServer(S, Err), Err);
  S.Url := 'http://host/x';
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'an address with a program');
  S := One;
  S.Headers := ['X-A=1'];
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'headers with a program');
  S := One;
  S.Command := '  ';
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'no program');
  S := One;
  S.Env := ['NOVALUE'];
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'environment entry without a name and value');
  S := One;
  S.Name := 'Bad Name';
  Assert.IsFalse(ValidateBridgeServer(S, Err), 'name');
end;

procedure TTestBridgeConfig.TestHttpConsentKeyFollowsAddressAndHeaders;
var
  A, B: TBridgeServerConfig;
begin
  A := Http('http://host/x');
  B := Http('http://host/y');
  Assert.AreNotEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'another address');
  B := A;
  B.Headers := ['X-A=1'];
  Assert.AreNotEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'another header');
  B := A;
  B.Allow := ['find'];
  B.StartTimeoutMs := 5000;
  Assert.AreEqual(BridgeConsentKey(A), BridgeConsentKey(B), 'the tool filter and the timeout do not matter');
end;

procedure TTestBridgeConfig.TestStdioConsentKeyIsUnchanged;
var
  S: TBridgeServerConfig;
  Approved: string;
begin
  // The key of a program is computed from the program, arguments, folder and environment
  // alone, so an approval stays valid whatever the address fields hold.
  S := One;
  Approved := BridgeWithApproval('', S);
  Assert.IsTrue(BridgeIsApproved(Approved, S));
  S.Transport := btStdio;
  S.Url := '';
  Assert.IsTrue(BridgeIsApproved(Approved, S));
  Assert.AreEqual<Integer>(64, Length(BridgeConsentKey(S)), 'a SHA-256 in hex');
end;

procedure TTestBridgeConfig.TestHttpCommandTextShowsAddressAndHeaders;
var
  S: TBridgeServerConfig;
  Text: string;
begin
  S := Http('https://example.org/rpc');
  S.Headers := ['X-A=1'];
  Text := BridgeCommandText(S);
  Assert.IsTrue(Pos('POST https://example.org/rpc', Text) > 0, Text);
  Assert.IsTrue(Pos('X-A=1', Text) > 0, Text);
end;

procedure TTestBridgeConfig.TestWordsSplitAndJoinBack;
var
  Words, Back: TArray<string>;
  I: Integer;
begin
  Words := BridgeSplitWords('one "two words" three');
  Assert.AreEqual<Integer>(3, Length(Words));
  Assert.AreEqual('two words', Words[1]);
  Assert.AreEqual<Integer>(0, Length(BridgeSplitWords('   ')));
  Words := ['plain', 'with space', 'quote"inside', 'trail\', 'C:\Program Files\x\', ''];
  Back := BridgeSplitWords(BridgeJoinWords(Words));
  Assert.AreEqual<Integer>(Length(Words), Length(Back));
  for I := 0 to High(Words) do
    Assert.AreEqual(Words[I], Back[I]);
end;

procedure TTestBridgeConfig.TestTargetTextOfBothTransports;
begin
  Assert.AreEqual('http://host/x', BridgeTargetText(Http('http://host/x')));
  Assert.IsTrue(Pos('python', BridgeTargetText(One)) = 1);
  Assert.IsTrue(Pos('srv.py', BridgeTargetText(One)) > 0);
end;

end.
