unit TestDockerFormat;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDockerFormat = class
  public
    [Test] procedure TestRootAndTopFolders;
    [Test] procedure TestContainerParts;
    [Test] procedure TestContainerFilePathKeepsSegments;
    [Test] procedure TestKubernetesPath;
    [Test] procedure TestOtherSchemesAndShapesAreRejected;
    [Test] procedure TestNameWithSlashSurvivesEncoding;
    [Test] procedure TestExecArgsForDockerAndKubectl;
    [Test] procedure TestCopyArgsPointTheRightWay;
    [Test] procedure TestInfoLogsRemoveArgs;
    [Test] procedure TestFindListingGivesKindSizeAndTime;
    [Test] procedure TestFindListingFollowsLinkTargets;
    [Test] procedure TestLsListingStripsKindMarks;
    [Test] procedure TestContainerAndPodLists;
    [Test] procedure TestStateRoles;
    [Test] procedure TestJoinFsPath;
  end;

implementation

uses
  System.SysUtils, uDockerFormat;

function Addr(const AUri: string): TDockerAddr;
begin
  Assert.IsTrue(ParseDockerUri(AUri, Result), AUri);
end;

procedure TTestDockerFormat.TestRootAndTopFolders;
begin
  Assert.AreEqual(Ord(dnRoot), Ord(Addr('docker:///').Node));
  Assert.AreEqual(Ord(dnContainers), Ord(Addr('docker:///containers').Node));
  Assert.AreEqual(Ord(dnImages), Ord(Addr('docker:///images/').Node));
  Assert.AreEqual(Ord(dnNamespaces), Ord(Addr('docker:///kubernetes').Node));
  Assert.AreEqual(Ord(dbKube), Ord(Addr('docker:///kubernetes').Backend));
  Assert.AreEqual(Ord(dnImage), Ord(Addr('docker:///images/nginx:latest').Node));
  Assert.AreEqual('nginx:latest', Addr('docker:///images/nginx:latest').Name);
end;

procedure TTestDockerFormat.TestContainerParts;
begin
  Assert.AreEqual(Ord(dnItem), Ord(Addr('docker:///containers/web').Node));
  Assert.AreEqual('web', Addr('docker:///containers/web').Name);
  Assert.AreEqual(Ord(dnInfo), Ord(Addr('docker:///containers/web/info.txt').Node));
  Assert.AreEqual(Ord(dnLogs), Ord(Addr('docker:///containers/web/logs.txt').Node));
  Assert.AreEqual(Ord(dnFs), Ord(Addr('docker:///containers/web/fs').Node));
  Assert.AreEqual('/', Addr('docker:///containers/web/fs').FsPath);
end;

procedure TTestDockerFormat.TestContainerFilePathKeepsSegments;
var
  A: TDockerAddr;
begin
  A := Addr('docker:///containers/web/fs/etc/nginx/nginx.conf');
  Assert.AreEqual(Ord(dnFs), Ord(A.Node));
  Assert.AreEqual('/etc/nginx/nginx.conf', A.FsPath);
  Assert.AreEqual(Ord(dbDocker), Ord(A.Backend));
end;

procedure TTestDockerFormat.TestKubernetesPath;
var
  A: TDockerAddr;
begin
  Assert.AreEqual(Ord(dnPods), Ord(Addr('docker:///kubernetes/prod').Node));
  Assert.AreEqual('prod', Addr('docker:///kubernetes/prod').Ns);
  A := Addr('docker:///kubernetes/prod/api-1/fs/var/log');
  Assert.AreEqual(Ord(dnFs), Ord(A.Node));
  Assert.AreEqual('prod', A.Ns);
  Assert.AreEqual('api-1', A.Name);
  Assert.AreEqual('/var/log', A.FsPath);
  Assert.AreEqual(Ord(dnLogs), Ord(Addr('docker:///kubernetes/prod/api-1/logs.txt').Node));
end;

procedure TTestDockerFormat.TestOtherSchemesAndShapesAreRejected;
var
  A: TDockerAddr;
begin
  Assert.IsFalse(ParseDockerUri('file:///x', A));
  Assert.IsFalse(ParseDockerUri('docker:///volumes', A));
  Assert.IsFalse(ParseDockerUri('docker:///containers/web/other', A));
  Assert.IsFalse(ParseDockerUri('docker:///images/a/b', A));
  Assert.AreEqual(Ord(dnInvalid), Ord(A.Node));
end;

procedure TTestDockerFormat.TestNameWithSlashSurvivesEncoding;
begin
  Assert.AreEqual('library%2Fnginx:1', EncodeSegment('library/nginx:1'));
  Assert.AreEqual('library/nginx:1', Addr('docker:///images/library%2Fnginx:1').Name);
  Assert.AreEqual('a%2F', DecodeSegment('a%252F'));
end;

procedure TTestDockerFormat.TestExecArgsForDockerAndKubectl;
var
  D, K: TDockerAddr;
  Args: TArray<string>;
begin
  D := Addr('docker:///containers/web/fs');
  K := Addr('docker:///kubernetes/prod/api/fs');
  Args := ExecArgs(D, False, ['ls', '/']);
  Assert.AreEqual('exec web ls /', string.Join(' ', Args));
  Args := ExecArgs(D, True, ['sh']);
  Assert.AreEqual('exec -i web sh', string.Join(' ', Args));
  Args := ExecArgs(K, False, ['ls', '/']);
  Assert.AreEqual('exec -n prod api -- ls /', string.Join(' ', Args));
  Assert.AreEqual('kubectl', BackendExe(K.Backend));
  Assert.AreEqual('docker', BackendExe(D.Backend));
end;

procedure TTestDockerFormat.TestCopyArgsPointTheRightWay;
var
  D, K: TDockerAddr;
begin
  D := Addr('docker:///containers/web/fs/etc/hosts');
  K := Addr('docker:///kubernetes/prod/api/fs/etc/hosts');
  Assert.AreEqual('cp web:/etc/hosts C:\x\hosts', string.Join(' ', CopyArgs(D, True, 'C:\x\hosts')));
  Assert.AreEqual('cp C:\x\hosts web:/etc/hosts', string.Join(' ', CopyArgs(D, False, 'C:\x\hosts')));
  Assert.AreEqual('cp prod/api:/etc/hosts /tmp/h', string.Join(' ', CopyArgs(K, True, '/tmp/h')));
end;

procedure TTestDockerFormat.TestInfoLogsRemoveArgs;
var
  C, I, P: TDockerAddr;
begin
  C := Addr('docker:///containers/web');
  I := Addr('docker:///images/nginx:1');
  P := Addr('docker:///kubernetes/prod/api');
  Assert.AreEqual('inspect web', string.Join(' ', InfoArgs(C)));
  Assert.AreEqual('image inspect nginx:1', string.Join(' ', InfoArgs(I)));
  Assert.AreEqual('describe pod -n prod api', string.Join(' ', InfoArgs(P)));
  Assert.AreEqual('logs --tail 2000 web', string.Join(' ', LogsArgs(C)));
  Assert.AreEqual('logs --tail=2000 -n prod api', string.Join(' ', LogsArgs(P)));
  Assert.AreEqual('rm -f web', string.Join(' ', RemoveArgs(C)));
  Assert.AreEqual('rmi nginx:1', string.Join(' ', RemoveArgs(I)));
  Assert.AreEqual('delete pod -n prod api', string.Join(' ', RemoveArgs(P)));
end;

procedure TTestDockerFormat.TestFindListingGivesKindSizeAndTime;
var
  E: TFsEntries;
begin
  E := ParseFindListing('d|d|4096|1700000000.1234567890|etc' + #10 + 'f|f|12|1700000100.0|a b.txt' + #10);
  Assert.AreEqual(2, Integer(Length(E)));
  Assert.IsTrue(E[0].IsDir);
  Assert.AreEqual('etc', E[0].Name);
  Assert.AreEqual(Int64(1700000000), E[0].Modified);
  Assert.IsFalse(E[1].IsDir);
  Assert.AreEqual(Int64(12), E[1].Size);
  Assert.AreEqual('a b.txt', E[1].Name);
end;

procedure TTestDockerFormat.TestFindListingFollowsLinkTargets;
var
  E: TFsEntries;
begin
  E := ParseFindListing('l|d|7|1.0|lib' + #13#10 + 'l|f|7|1.0|sh' + #13#10 + 'f|f|1|1.0|x|y' + #13#10);
  Assert.AreEqual(3, Integer(Length(E)));
  Assert.IsTrue(E[0].IsLink and E[0].IsDir, 'a link to a folder opens as a folder');
  Assert.IsTrue(E[1].IsLink and not E[1].IsDir);
  Assert.AreEqual('x|y', E[2].Name, 'a bar inside the name stays');
end;

procedure TTestDockerFormat.TestLsListingStripsKindMarks;
var
  E: TFsEntries;
begin
  E := ParseLsListing('bin/' + #10 + 'run.sh*' + #10 + 'lib@' + #10 + 'plain' + #10);
  Assert.AreEqual(4, Integer(Length(E)));
  Assert.IsTrue(E[0].IsDir);
  Assert.AreEqual('bin', E[0].Name);
  Assert.AreEqual('run.sh', E[1].Name);
  Assert.IsFalse(E[1].IsDir);
  Assert.IsTrue(E[2].IsLink);
  Assert.AreEqual('plain', E[3].Name);
end;

procedure TTestDockerFormat.TestContainerAndPodLists;
var
  C: TContainerRows;
  N: TArray<string>;
begin
  C := ParseContainerList('web|running|nginx:1' + #10 + 'db|exited|postgres' + #10 + 'junk' + #10);
  Assert.AreEqual(2, Integer(Length(C)));
  Assert.AreEqual('web', C[0].Name);
  Assert.AreEqual('exited', C[1].State);
  Assert.AreEqual('postgres', C[1].Image);
  C := ParsePodList('api-1   Running' + #10 + 'job-2 Succeeded' + #10);
  Assert.AreEqual(2, Integer(Length(C)));
  Assert.AreEqual('Succeeded', C[1].State);
  N := ParseKubeNames('namespace/default' + #10 + 'namespace/kube-system' + #10);
  Assert.AreEqual(2, Integer(Length(N)));
  Assert.AreEqual('kube-system', N[1]);
end;

procedure TTestDockerFormat.TestStateRoles;
begin
  Assert.AreEqual('ok', StateRole('running'));
  Assert.AreEqual('ok', StateRole('Running'));
  Assert.AreEqual('neutral', StateRole('exited'));
  Assert.AreEqual('warn', StateRole('paused'));
  Assert.AreEqual('warn', StateRole('Pending'));
end;

procedure TTestDockerFormat.TestJoinFsPath;
begin
  Assert.AreEqual('/a', JoinFsPath('/', 'a'));
  Assert.AreEqual('/x/a', JoinFsPath('/x', 'a'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDockerFormat);

end.
