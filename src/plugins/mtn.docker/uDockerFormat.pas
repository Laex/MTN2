unit uDockerFormat;

{ Pure helpers of the Docker plugin: addresses, the command lines handed to the
  docker and kubectl programs, and the parsers of their text output.

    docker:///                                        containers, images, kubernetes
    docker:///containers/<name>                       info.txt, logs.txt, fs
    docker:///containers/<name>/fs/<path>             the container's files
    docker:///images/<repo:tag>                       one file per image
    docker:///kubernetes/<namespace>/<pod>            info.txt, logs.txt, fs
    docker:///kubernetes/<namespace>/<pod>/fs/<path>  the pod's files }

interface

type
  TDockerBackend = (dbDocker, dbKube);

  TDockerNode = (dnInvalid, dnRoot, dnContainers, dnImages, dnImage, dnNamespaces, dnPods,
    dnItem, dnInfo, dnLogs, dnFs);

  TDockerAddr = record
    Backend: TDockerBackend;
    Node: TDockerNode;
    /// <summary>The namespace of a pod (empty for Docker).</summary>
    Ns: string;
    /// <summary>The container, pod or image name.</summary>
    Name: string;
    /// <summary>The absolute path inside the container or pod (dnFs).</summary>
    FsPath: string;
  end;

  TFsEntry = record
    Name: string;
    IsDir: Boolean;
    IsLink: Boolean;
    Size: Int64;
    /// <summary>Seconds since 1970-01-01 UTC; 0 when unknown.</summary>
    Modified: Int64;
  end;
  TFsEntries = TArray<TFsEntry>;

  TContainerRow = record
    Name: string;
    State: string;
    Image: string;
  end;
  TContainerRows = TArray<TContainerRow>;

const
  cDocker = 'docker';
  cKubectl = 'kubectl';
  cKubeDir = 'kubernetes';
  cInfoFile = 'info.txt';
  cLogsFile = 'logs.txt';
  cFsDir = 'fs';
  cLogTail = 2000;

/// <summary>Splits docker:/// ... into its parts; False for another scheme or a
/// shape that no node has.</summary>
function ParseDockerUri(const AUri: string; out AAddr: TDockerAddr): Boolean;

/// <summary>%2F for "/" and %25 for "%" so a name stays one path segment.</summary>
function EncodeSegment(const AText: string): string;
function DecodeSegment(const AText: string): string;

/// <summary>The program that serves the backend.</summary>
function BackendExe(ABackend: TDockerBackend): string;

/// <summary>The arguments that run ACommand inside the container or pod.</summary>
function ExecArgs(const AAddr: TDockerAddr; AKeepStdin: Boolean;
  const ACommand: TArray<string>): TArray<string>;

/// <summary>The arguments of "cp" between the container or pod and a local path.</summary>
function CopyArgs(const AAddr: TDockerAddr; AFromContainer: Boolean;
  const ALocalPath: string): TArray<string>;

/// <summary>The arguments that print the details of the item (info.txt).</summary>
function InfoArgs(const AAddr: TDockerAddr): TArray<string>;

/// <summary>The arguments that print the tail of the log (logs.txt).</summary>
function LogsArgs(const AAddr: TDockerAddr): TArray<string>;

/// <summary>The arguments that remove the container, image or pod.</summary>
function RemoveArgs(const AAddr: TDockerAddr): TArray<string>;

/// <summary>Output of "find -printf %y|%Y|%s|%T@|%f": one entry per line.</summary>
function ParseFindListing(const AText: string): TFsEntries;

/// <summary>Output of "ls -1AF" (the fallback for a container without GNU find).</summary>
function ParseLsListing(const AText: string): TFsEntries;

/// <summary>Output of "docker ps -a --format {{.Names}}|{{.State}}|{{.Image}}".</summary>
function ParseContainerList(const AText: string): TContainerRows;

/// <summary>Lines of "kubectl get ... -o name" with the "kind/" prefix removed.</summary>
function ParseKubeNames(const AText: string): TArray<string>;

/// <summary>Pod lines "name phase" of "kubectl get pods --no-headers -o custom-columns".</summary>
function ParsePodList(const AText: string): TContainerRows;

/// <summary>Row color role of a container state or pod phase: "ok", "neutral" or "warn".</summary>
function StateRole(const AState: string): string;

/// <summary>Child of a path inside a container: "/" + "a" = "/a", "/x" + "a" = "/x/a".</summary>
function JoinFsPath(const ADir, AName: string): string;

implementation

uses
  System.SysUtils;

function EncodeSegment(const AText: string): string;
begin
  Result := AText.Replace('%', '%25').Replace('/', '%2F');
end;

function DecodeSegment(const AText: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '%') and (I + 2 <= Length(AText)) and
       ((Copy(AText, I, 3) = '%2F') or (Copy(AText, I, 3) = '%25')) then
    begin
      if Copy(AText, I, 3) = '%2F' then
        Result := Result + '/'
      else
        Result := Result + '%';
      Inc(I, 3);
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

function SplitUri(const AUri: string; out ASegs: TArray<string>): Boolean;
const
  cPrefix = 'docker:///';
var
  Parts: TArray<string>;
  I, N: Integer;
begin
  Result := SameText(Copy(AUri, 1, Length(cPrefix)), cPrefix);
  if not Result then
    Exit;
  Parts := Copy(AUri, Length(cPrefix) + 1, MaxInt).Split(['/']);
  SetLength(ASegs, Length(Parts));
  N := 0;
  for I := 0 to High(Parts) do
    if Parts[I] <> '' then
    begin
      ASegs[N] := DecodeSegment(Parts[I]);
      Inc(N);
    end;
  SetLength(ASegs, N);
end;

function FsPathOf(const ASegs: TArray<string>; AFrom: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := AFrom to High(ASegs) do
    Result := Result + '/' + ASegs[I];
  if Result = '' then
    Result := '/';
end;

// The part of a container or pod folder: info.txt, logs.txt, fs or fs/<path>.
function ItemPart(const ASegs: TArray<string>; AFrom: Integer; var AAddr: TDockerAddr): Boolean;
begin
  Result := True;
  if Length(ASegs) = AFrom then
    AAddr.Node := dnItem
  else if SameText(ASegs[AFrom], cInfoFile) and (Length(ASegs) = AFrom + 1) then
    AAddr.Node := dnInfo
  else if SameText(ASegs[AFrom], cLogsFile) and (Length(ASegs) = AFrom + 1) then
    AAddr.Node := dnLogs
  else if ASegs[AFrom] = cFsDir then
  begin
    AAddr.Node := dnFs;
    AAddr.FsPath := FsPathOf(ASegs, AFrom + 1);
  end
  else
    Result := False;
end;

function ParseDockerUri(const AUri: string; out AAddr: TDockerAddr): Boolean;
var
  Segs: TArray<string>;
begin
  AAddr := Default(TDockerAddr);
  AAddr.Node := dnInvalid;
  if not SplitUri(AUri, Segs) then
    Exit(False);
  Result := True;
  if Length(Segs) = 0 then
  begin
    AAddr.Node := dnRoot;
    Exit;
  end;
  if Segs[0] = 'containers' then
  begin
    if Length(Segs) = 1 then
      AAddr.Node := dnContainers
    else
    begin
      AAddr.Name := Segs[1];
      Result := ItemPart(Segs, 2, AAddr);
    end;
  end
  else if Segs[0] = 'images' then
  begin
    if Length(Segs) = 1 then
      AAddr.Node := dnImages
    else if Length(Segs) = 2 then
    begin
      AAddr.Node := dnImage;
      AAddr.Name := Segs[1];
    end
    else
      Result := False;
  end
  else if Segs[0] = cKubeDir then
  begin
    AAddr.Backend := dbKube;
    if Length(Segs) = 1 then
      AAddr.Node := dnNamespaces
    else
    begin
      AAddr.Ns := Segs[1];
      if Length(Segs) = 2 then
        AAddr.Node := dnPods
      else
      begin
        AAddr.Name := Segs[2];
        Result := ItemPart(Segs, 3, AAddr);
      end;
    end;
  end
  else
    Result := False;
  if not Result then
    AAddr.Node := dnInvalid;
end;

function BackendExe(ABackend: TDockerBackend): string;
begin
  if ABackend = dbKube then
    Result := cKubectl
  else
    Result := cDocker;
end;

function ExecArgs(const AAddr: TDockerAddr; AKeepStdin: Boolean;
  const ACommand: TArray<string>): TArray<string>;
var
  Head: TArray<string>;
begin
  if AAddr.Backend = dbKube then
  begin
    Head := ['exec'];
    if AKeepStdin then
      Head := Head + ['-i'];
    Head := Head + ['-n', AAddr.Ns, AAddr.Name, '--'];
  end
  else
  begin
    Head := ['exec'];
    if AKeepStdin then
      Head := Head + ['-i'];
    Head := Head + [AAddr.Name];
  end;
  Result := Head + ACommand;
end;

function CopyArgs(const AAddr: TDockerAddr; AFromContainer: Boolean;
  const ALocalPath: string): TArray<string>;
var
  Remote: string;
begin
  if AAddr.Backend = dbKube then
    Remote := AAddr.Ns + '/' + AAddr.Name + ':' + AAddr.FsPath
  else
    Remote := AAddr.Name + ':' + AAddr.FsPath;
  if AFromContainer then
    Result := ['cp', Remote, ALocalPath]
  else
    Result := ['cp', ALocalPath, Remote];
end;

function InfoArgs(const AAddr: TDockerAddr): TArray<string>;
begin
  if AAddr.Backend = dbKube then
    Result := ['describe', 'pod', '-n', AAddr.Ns, AAddr.Name]
  else if AAddr.Node = dnImage then
    Result := ['image', 'inspect', AAddr.Name]
  else
    Result := ['inspect', AAddr.Name];
end;

function LogsArgs(const AAddr: TDockerAddr): TArray<string>;
begin
  if AAddr.Backend = dbKube then
    Result := ['logs', '--tail=' + IntToStr(cLogTail), '-n', AAddr.Ns, AAddr.Name]
  else
    Result := ['logs', '--tail', IntToStr(cLogTail), AAddr.Name];
end;

function RemoveArgs(const AAddr: TDockerAddr): TArray<string>;
begin
  if AAddr.Backend = dbKube then
    Result := ['delete', 'pod', '-n', AAddr.Ns, AAddr.Name]
  else if AAddr.Node = dnImage then
    Result := ['rmi', AAddr.Name]
  else
    Result := ['rm', '-f', AAddr.Name];
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13, '').Split([#10]);
end;

function ParseFindListing(const AText: string): TFsEntries;
var
  Line: string;
  Parts: TArray<string>;
  Entry: TFsEntry;
  N, P: Integer;
  Stamp: string;
begin
  SetLength(Result, 0);
  N := 0;
  for Line in Lines(AText) do
  begin
    // type of the entry | type of its target | size | seconds since 1970 | name
    Parts := Line.Split(['|']);
    if (Length(Parts) < 5) or (Parts[0] = '') or (Parts[4] = '') then
      Continue;
    Entry := Default(TFsEntry);
    // A bar inside the name belongs to the name.
    Entry.Name := string.Join('|', Copy(Parts, 4, Length(Parts)));
    Entry.IsLink := Parts[0] = 'l';
    Entry.IsDir := (Parts[1] = 'd') or ((Parts[1] = '') and (Parts[0] = 'd'));
    Entry.Size := StrToInt64Def(Parts[2], 0);
    Stamp := Parts[3];
    P := Pos('.', Stamp);
    if P > 0 then
      Stamp := Copy(Stamp, 1, P - 1);
    Entry.Modified := StrToInt64Def(Stamp, 0);
    SetLength(Result, N + 1);
    Result[N] := Entry;
    Inc(N);
  end;
end;

function ParseLsListing(const AText: string): TFsEntries;
var
  Line, Name: string;
  Entry: TFsEntry;
  N: Integer;
begin
  SetLength(Result, 0);
  N := 0;
  for Line in Lines(AText) do
  begin
    Name := Line;
    if Name = '' then
      Continue;
    Entry := Default(TFsEntry);
    // -F appends / to a folder, @ to a link and * = | > to other kinds.
    if CharInSet(Name[Length(Name)], ['/', '@', '*', '=', '|', '>']) then
    begin
      Entry.IsDir := Name[Length(Name)] = '/';
      Entry.IsLink := Name[Length(Name)] = '@';
      Name := Copy(Name, 1, Length(Name) - 1);
      if Name = '' then
        Continue;
    end;
    Entry.Name := Name;
    SetLength(Result, N + 1);
    Result[N] := Entry;
    Inc(N);
  end;
end;

function ParseContainerList(const AText: string): TContainerRows;
var
  Line: string;
  Parts: TArray<string>;
  N: Integer;
begin
  SetLength(Result, 0);
  N := 0;
  for Line in Lines(AText) do
  begin
    Parts := Line.Split(['|']);
    if (Length(Parts) < 2) or (Parts[0] = '') then
      Continue;
    SetLength(Result, N + 1);
    Result[N].Name := Parts[0];
    Result[N].State := Parts[1];
    if Length(Parts) > 2 then
      Result[N].Image := Parts[2];
    Inc(N);
  end;
end;

function ParseKubeNames(const AText: string): TArray<string>;
var
  Line, Name: string;
  P, N: Integer;
begin
  SetLength(Result, 0);
  N := 0;
  for Line in Lines(AText) do
  begin
    Name := Trim(Line);
    P := Pos('/', Name);
    if P > 0 then
      Name := Copy(Name, P + 1, MaxInt);
    if Name = '' then
      Continue;
    SetLength(Result, N + 1);
    Result[N] := Name;
    Inc(N);
  end;
end;

function ParsePodList(const AText: string): TContainerRows;
var
  Line: string;
  Parts: TArray<string>;
  N: Integer;
begin
  SetLength(Result, 0);
  N := 0;
  for Line in Lines(AText) do
  begin
    Parts := Trim(Line).Split([' '], TStringSplitOptions.ExcludeEmpty);
    if Length(Parts) < 2 then
      Continue;
    SetLength(Result, N + 1);
    Result[N].Name := Parts[0];
    Result[N].State := Parts[1];
    Inc(N);
  end;
end;

function StateRole(const AState: string): string;
begin
  if SameText(AState, 'running') or SameText(AState, 'Succeeded') then
    Result := 'ok'
  else if SameText(AState, 'exited') or SameText(AState, 'created') or SameText(AState, 'Completed') then
    Result := 'neutral'
  else
    Result := 'warn';
end;

function JoinFsPath(const ADir, AName: string): string;
begin
  if ADir = '/' then
    Result := '/' + AName
  else
    Result := ADir + '/' + AName;
end;

end.
