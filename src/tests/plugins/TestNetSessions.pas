unit TestNetSessions;

{ The saved sessions of the network plugin (uNetSessions) and how their
  secrets are sealed (uNetSecrets). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNetSessions = class
  public
    [Test] procedure TestAddFindAndNamesAreCaseInsensitive;
    [Test] procedure TestNamesAreMadeSafeForAnAddress;
    [Test] procedure TestUpdateRenamesAndRefusesTakenNames;
    [Test] procedure TestDeleteRemovesTheSession;
    [Test] procedure TestUniqueNameCountsUp;
    [Test] procedure TestJsonRoundTripKeepsEverythingButSecretsWithoutSaveFlag;
    [Test] procedure TestSavedPasswordIsSealedInTheJson;
    [Test] procedure TestFindForServerMatchesProtocolHostPortAndUser;
    [Test] procedure TestBadJsonGivesAnEmptyList;
    [Test] procedure TestSealedSecretOpensOnlyWhatWeSealed;
  end;

implementation

uses
  System.SysUtils, System.Character, uNetTypes, uNetSessions, uNetSecrets;

function Make(const AName: string; AProto: TNetProtocol = npFtp): TNetSession;
begin
  Result := DefaultNetSession;
  Result.Name := AName;
  Result.Protocol := AProto;
  Result.Host := AName + '.example.org';
  Result.User := 'user';
end;

procedure TTestNetSessions.TestAddFindAndNamesAreCaseInsensitive;
var
  St: TNetSessionStore;
  S: TNetSession;
begin
  St := TNetSessionStore.Create;
  try
    Assert.IsTrue(St.Add(Make('Work')));
    Assert.IsFalse(St.Add(Make('WORK')), 'a name is taken whatever its case');
    Assert.IsFalse(St.Add(Make('  ')), 'an empty name is refused');
    Assert.IsTrue(St.Find('work', S));
    Assert.AreEqual('Work', S.Name);
    Assert.IsFalse(St.Find('home', S));
    Assert.AreEqual(1, St.Count);
  finally
    St.Free;
  end;
end;

procedure TTestNetSessions.TestNamesAreMadeSafeForAnAddress;
begin
  Assert.AreEqual('a_b_c', SanitizeSessionName(' a/b\c '));
  Assert.AreEqual('x_y', SanitizeSessionName('x'#10'y'));
  Assert.AreEqual('Мой сервер', SanitizeSessionName('Мой сервер'));
end;

procedure TTestNetSessions.TestUpdateRenamesAndRefusesTakenNames;
var
  St: TNetSessionStore;
  S: TNetSession;
begin
  St := TNetSessionStore.Create;
  try
    St.Add(Make('a'));
    St.Add(Make('b'));
    S := Make('c');
    Assert.IsTrue(St.Update('a', S), 'a rename');
    Assert.IsFalse(St.Find('a', S));
    Assert.IsTrue(St.Find('c', S));
    Assert.IsFalse(St.Update('c', Make('b')), 'another session has that name');
    Assert.IsFalse(St.Update('nobody', Make('z')));
    Assert.IsTrue(St.Update('c', Make('C')), 'the same name in another case is the same session');
    Assert.AreEqual(2, St.Count);
  finally
    St.Free;
  end;
end;

procedure TTestNetSessions.TestDeleteRemovesTheSession;
var
  St: TNetSessionStore;
begin
  St := TNetSessionStore.Create;
  try
    St.Add(Make('a'));
    Assert.IsTrue(St.Delete('A'));
    Assert.IsFalse(St.Delete('a'));
    Assert.AreEqual(0, St.Count);
  finally
    St.Free;
  end;
end;

procedure TTestNetSessions.TestUniqueNameCountsUp;
var
  St: TNetSessionStore;
begin
  St := TNetSessionStore.Create;
  try
    Assert.AreEqual('New', St.UniqueName('New'));
    St.Add(Make('New'));
    Assert.AreEqual('New (2)', St.UniqueName('New'));
    St.Add(Make('New (2)'));
    Assert.AreEqual('New (3)', St.UniqueName('New'));
    Assert.AreEqual('Session', St.UniqueName(''));
  finally
    St.Free;
  end;
end;

procedure TTestNetSessions.TestJsonRoundTripKeepsEverythingButSecretsWithoutSaveFlag;
var
  A, B: TNetSessionStore;
  S, T: TNetSession;
begin
  A := TNetSessionStore.Create;
  B := TNetSessionStore.Create;
  try
    S := Make('Full', npS3);
    S.Port := 9000;
    S.Auth := naKey;
    S.KeyFile := 'C:\keys\id';
    S.RootPath := '/bucket';
    S.Proxy := 'socks5h://p:1080';
    S.Encoding := 'windows-1251';
    S.Region := 'eu-west-1';
    S.Endpoint := '/dav';
    S.PathStyle := False;
    S.Passive := False;
    S.ImplicitTls := True;
    S.VerifyCert := False;
    S.TimeoutSec := 77;
    S.HostKeySha256 := 'abc';
    S.Password := 'secret';
    S.KeyPassphrase := 'pass';
    S.SavePassword := False;
    A.Add(S);
    B.Load(A.ToJson);
    Assert.AreEqual(1, B.Count);
    Assert.IsTrue(B.Find('Full', T));
    Assert.IsTrue(T.Protocol = npS3);
    Assert.AreEqual(9000, T.Port);
    Assert.IsTrue(T.Auth = naKey);
    Assert.AreEqual('C:\keys\id', T.KeyFile);
    Assert.AreEqual('/bucket', T.RootPath);
    Assert.AreEqual('socks5h://p:1080', T.Proxy);
    Assert.AreEqual('windows-1251', T.Encoding);
    Assert.AreEqual('eu-west-1', T.Region);
    Assert.AreEqual('/dav', T.Endpoint);
    Assert.IsFalse(T.PathStyle);
    Assert.IsFalse(T.Passive);
    Assert.IsTrue(T.ImplicitTls);
    Assert.IsFalse(T.VerifyCert);
    Assert.AreEqual(77, T.TimeoutSec);
    Assert.AreEqual('abc', T.HostKeySha256);
    Assert.AreEqual('', T.Password, 'a password that was not to be saved is not in the file');
    Assert.AreEqual('', T.KeyPassphrase);
    Assert.IsTrue(Pos('secret', A.ToJson) = 0);
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TTestNetSessions.TestSavedPasswordIsSealedInTheJson;
var
  A, B: TNetSessionStore;
  S, T: TNetSession;
  Json: string;
begin
  if not SecretsAvailable then
    Assert.Pass('SKIP: this system keeps no saved secrets');
  A := TNetSessionStore.Create;
  B := TNetSessionStore.Create;
  try
    S := Make('Keep');
    S.Password := 'pa55word-unique';
    S.KeyPassphrase := 'phrase-unique';
    S.SavePassword := True;
    A.Add(S);
    Json := A.ToJson;
    Assert.IsTrue(Pos('pa55word-unique', Json) = 0, 'the password is not written in the clear');
    Assert.IsTrue(Pos('phrase-unique', Json) = 0);
    B.Load(Json);
    Assert.IsTrue(B.Find('Keep', T));
    Assert.AreEqual('pa55word-unique', T.Password);
    Assert.AreEqual('phrase-unique', T.KeyPassphrase);
    Assert.IsTrue(T.SavePassword);
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TTestNetSessions.TestFindForServerMatchesProtocolHostPortAndUser;
var
  St: TNetSessionStore;
  S, Found: TNetSession;
begin
  St := TNetSessionStore.Create;
  try
    S := Make('one');
    S.Host := 'h.example.org';
    S.Port := 2121;
    S.User := 'bob';
    St.Add(S);
    Assert.IsTrue(St.FindForServer(npFtp, 'H.example.org', 2121, 'bob', Found));
    Assert.AreEqual('one', Found.Name);
    Assert.IsTrue(St.FindForServer(npFtp, 'h.example.org', 0, '', Found), 'port and user may be left out');
    Assert.IsFalse(St.FindForServer(npFtp, 'h.example.org', 21, 'bob', Found), 'another port');
    Assert.IsFalse(St.FindForServer(npFtp, 'h.example.org', 2121, 'alice', Found), 'another user');
    Assert.IsFalse(St.FindForServer(npSftp, 'h.example.org', 2121, 'bob', Found), 'another protocol');
  finally
    St.Free;
  end;
end;

procedure TTestNetSessions.TestBadJsonGivesAnEmptyList;
var
  St: TNetSessionStore;
begin
  St := TNetSessionStore.Create;
  try
    St.Add(Make('x'));
    St.Load('not json at all');
    Assert.AreEqual(0, St.Count);
    St.Load('{"name":"object instead of array"}');
    Assert.AreEqual(0, St.Count);
    St.Load('[{"name":"ok","protocol":"ftp","host":"h"},{"protocol":"ftp"},{"name":"bad","protocol":"nonsense"}]');
    Assert.AreEqual(1, St.Count, 'unusable entries are skipped');
    St.Load('');
    Assert.AreEqual(0, St.Count);
  finally
    St.Free;
  end;
end;

procedure TTestNetSessions.TestSealedSecretOpensOnlyWhatWeSealed;
var
  Sealed, Plain: string;
begin
  if not SecretsAvailable then
    Assert.Pass('SKIP: this system keeps no saved secrets');
  Sealed := ProtectSecret('hello');
  Assert.IsTrue(Sealed <> '');
  Assert.IsTrue(Pos('hello', Sealed) = 0);
  Assert.IsTrue(UnprotectSecret(Sealed, Plain));
  Assert.AreEqual('hello', Plain);
  Assert.IsFalse(UnprotectSecret('hello', Plain), 'plain text is not a sealed secret');
  Assert.IsFalse(UnprotectSecret(Copy(Sealed, 1, 12) + 'AAAA', Plain), 'a damaged one is refused');
  Assert.AreEqual('', ProtectSecret(''), 'an empty secret is not sealed');
  Assert.IsFalse(UnprotectSecret('', Plain));
  Plain := 'пароль ' + Char.ConvertFromUtf32($1F600);
  Assert.IsTrue(UnprotectSecret(ProtectSecret(Plain), Sealed));
  Assert.AreEqual(Plain, Sealed);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNetSessions);

end.
