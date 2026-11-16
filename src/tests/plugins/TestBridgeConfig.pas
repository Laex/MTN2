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

end.
