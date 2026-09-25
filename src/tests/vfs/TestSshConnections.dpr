program TestSshConnections;

uses
  System.SysUtils, System.IOUtils,
  uSshConnections in '..\..\Core\uSshConnections.pas';

procedure TestCrudRoundtrip;
var
  TempFile: string;
  A, B: TSshConnection;
  Fetched: TSshConnection;
  All: TArray<TSshConnection>;
begin
  TempFile := TPath.Combine(TPath.GetTempPath, 'mtn2_test_sshconnections.json');
  if TFile.Exists(TempFile) then
    TFile.Delete(TempFile);
  SshConnectionsUsePath(TempFile);
  try
    All := SshConnectionsGet;
    Assert(Length(All) = 0, 'Expected empty store initially');

    A := SshConnectionAdd('Prod Web', 'web.example.com', 2222, 'deploy', 'C:\keys\id_ed25519');
    Assert(A.Id <> '', 'Add did not assign an id');

    All := SshConnectionsGet;
    Assert(Length(All) = 1, 'Expected 1 connection after add');
    Assert(All[0].Name = 'Prod Web', 'Name mismatch after add');
    Assert(All[0].Port = 2222, 'Port mismatch after add');

    Assert(SshConnectionsFindById(A.Id, Fetched), 'FindById failed for known id');
    Assert(Fetched.Host = 'web.example.com', 'Host mismatch on fetch');

    Fetched.Name := 'Prod Web (renamed)';
    Fetched.Port := 22;
    Assert(SshConnectionUpdate(Fetched), 'Update failed');
    Assert(SshConnectionsFindById(A.Id, Fetched), 'FindById failed after update');
    Assert(Fetched.Name = 'Prod Web (renamed)', 'Update did not persist name');
    Assert(Fetched.Port = 22, 'Update did not persist port');

    B := SshConnectionAdd('Bastion', '10.0.0.1', 0, 'root', '');
    All := SshConnectionsGet;
    Assert(Length(All) = 2, 'Expected 2 connections after second add');

    Assert(SshConnectionsFindByTarget('web.example.com', 22, 'deploy', Fetched),
      'FindByTarget failed for known host/port/user');
    Assert(Fetched.Id = A.Id, 'FindByTarget returned wrong connection');

    Assert(SshConnectionsFindByTarget('10.0.0.1', 22, 'root', Fetched),
      'FindByTarget failed for default-port connection (Port=0 -> 22)');
    Assert(Fetched.Id = B.Id, 'FindByTarget (default port) returned wrong connection');

    Assert(not SshConnectionsFindByTarget('nowhere.example.com', 22, 'x', Fetched),
      'FindByTarget should fail for unknown host');

    Assert(SshConnectionDelete(A.Id), 'Delete failed for known id');
    All := SshConnectionsGet;
    Assert(Length(All) = 1, 'Expected 1 connection after delete');
    Assert(not SshConnectionsFindById(A.Id, Fetched), 'Deleted id should no longer resolve');

    Assert(not SshConnectionDelete('nonexistent-id'), 'Delete should fail for unknown id');

    // Reload from disk (same path) into a fresh in-memory state, to prove
    // persistence -- SshConnectionsResetForTests would clear the path
    // override too and read the real default config instead.
    SshConnectionsUsePath(TempFile);
    All := SshConnectionsGet;
    Assert(Length(All) = 1, 'Expected 1 connection after reload from disk');
    Assert(All[0].Id = B.Id, 'Reloaded connection id mismatch');
  finally
    if TFile.Exists(TempFile) then
      TFile.Delete(TempFile);
    SshConnectionsResetForTests;
  end;
  Writeln('OK: TestCrudRoundtrip passed');
end;

procedure TestConnectionArgs;
var
  Conn: TSshConnection;
  Args: TArray<string>;
begin
  Conn := Default(TSshConnection);
  Conn.Host := 'host.example.com';
  Conn.User := 'bob';
  Conn.Port := 2222;
  Conn.IdentityFile := 'C:\keys\id';
  Args := SshConnectionArgs(Conn, '-p');
  Assert(Length(Args) = 5, 'Expected 5 args (port pair + identity pair + host)');
  Assert(Args[0] = '-p', 'Port flag mismatch');
  Assert(Args[1] = '2222', 'Port value mismatch');
  Assert(Args[2] = '-i', 'Identity flag mismatch');
  Assert(Args[3] = 'C:\keys\id', 'Identity value mismatch');
  Assert(Args[4] = 'bob@host.example.com', 'Host arg mismatch');

  Conn := Default(TSshConnection);
  Conn.Host := 'plain.example.com';
  Args := SshConnectionArgs(Conn, '-P');
  Assert(Length(Args) = 1, 'Expected bare host-only arg when port/identity/user unset');
  Assert(Args[0] = 'plain.example.com', 'Bare host arg mismatch');

  Writeln('OK: TestConnectionArgs passed');
end;

begin
  try
    Writeln('Running SshConnections tests...');
    TestCrudRoundtrip;
    TestConnectionArgs;
    Writeln('ALL SshConnections tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
