unit TestRcloneLive;

{ The rclone callbacks against the real rclone program and a "local" remote in a
  temporary configuration. Needs rclone in PATH, so the fixture is Manual. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Manual')]
  TTestRcloneLive = class
  private
    FDir: string;
    FConfig: string;
    function RemoteUri(const ASub: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestRootListsTheLocalRemote;
    [Test] procedure TestFolderListsFilesWithSizeAndKind;
    [Test] procedure TestWriteThenReadTextRoundTrips;
    [Test] procedure TestMakeFolderCopyOutAndDelete;
    [Test] procedure TestMissingFileIsNotFound;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON,
{$IFDEF MSWINDOWS} Winapi.Windows,{$ELSE} Posix.Stdlib,{$ENDIF}
  uPluginHostAbi, uVfsTypes, uRcloneVfs;

function UriBuf(const AUri: string): UTF8String;
begin
  Result := UTF8String(AUri);
end;

function List(const AUri: string; out AJson: TJSONArray): Int64;
var
  Cb: TVfsCallbacksCdeclV2;
  Buf: TBytes;
  Neg, More: Int64;
  Uri: UTF8String;
begin
  Cb := RcloneVfsCallbacks;
  SetLength(Buf, 1024 * 1024);
  Uri := UriBuf(AUri);
  AJson := nil;
  Result := Cb.ListDirectory(PAnsiChar(Uri), nil, nil, 0, PAnsiChar(@Buf[0]), Length(Buf), Neg, More);
  if Result = Ord(verOk) then
    AJson := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Buf, 0, Neg)) as TJSONArray;
end;

procedure TTestRcloneLive.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-rclone-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(TPath.Combine(FDir, 'data\sub'));
  TFile.WriteAllText(TPath.Combine(FDir, 'data\a.txt'), 'hello', TEncoding.UTF8);
  FConfig := TPath.Combine(FDir, 'rclone.conf');
  TFile.WriteAllText(FConfig, '[loc]' + sLineBreak + 'type = local' + sLineBreak);
{$IFDEF MSWINDOWS}
  SetEnvironmentVariable('RCLONE_CONFIG', PChar(FConfig));
{$ELSE}
  setenv('RCLONE_CONFIG', PAnsiChar(UTF8String(FConfig)), 1);
{$ENDIF}
  GRcRunTool := DefaultRcRunTool;
end;

procedure TTestRcloneLive.TearDown;
begin
{$IFDEF MSWINDOWS}
  SetEnvironmentVariable('RCLONE_CONFIG', nil);
{$ELSE}
  unsetenv('RCLONE_CONFIG');
{$ENDIF}
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

// loc:C:\...\data as a path of the remote: "loc" is the remote, the rest the folder.
function TTestRcloneLive.RemoteUri(const ASub: string): string;
begin
  Result := 'rclone:///loc/' + StringReplace(TPath.Combine(FDir, 'data'), '\', '%2F', [rfReplaceAll]);
  if ASub <> '' then
    Result := Result + '/' + ASub;
end;

procedure TTestRcloneLive.TestRootListsTheLocalRemote;
var
  Arr: TJSONArray;
begin
  Assert.AreEqual(Int64(Ord(verOk)), List('rclone:///', Arr));
  try
    Assert.AreEqual(1, Arr.Count);
    Assert.AreEqual('loc', (Arr.Items[0] as TJSONObject).GetValue<string>('name'));
  finally
    Arr.Free;
  end;
end;

procedure TTestRcloneLive.TestFolderListsFilesWithSizeAndKind;
var
  Arr: TJSONArray;
  I: Integer;
  O: TJSONObject;
  SawFile, SawDir: Boolean;
begin
  Assert.AreEqual(Int64(Ord(verOk)), List(RemoteUri(''), Arr));
  try
    SawFile := False;
    SawDir := False;
    for I := 0 to Arr.Count - 1 do
    begin
      O := Arr.Items[I] as TJSONObject;
      if O.GetValue<string>('name') = 'a.txt' then
      begin
        SawFile := not O.GetValue<Boolean>('isDir') and (O.GetValue<Int64>('size') > 0);
        Assert.IsTrue(O.GetValue<Int64>('modified') > 0);
      end
      else if O.GetValue<string>('name') = 'sub' then
        SawDir := O.GetValue<Boolean>('isDir');
    end;
    Assert.IsTrue(SawFile, 'a.txt as a file with a size');
    Assert.IsTrue(SawDir, 'sub as a folder');
  finally
    Arr.Free;
  end;
end;

procedure TTestRcloneLive.TestWriteThenReadTextRoundTrips;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
  Buf: TBytes;
  Neg: Int64;
begin
  Cb := RcloneVfsCallbacks;
  Uri := UriBuf(RemoteUri('b.txt'));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.WriteText(PAnsiChar(Uri), PAnsiChar(UTF8String('line one')), nil, nil));
  Assert.AreEqual('line one', TFile.ReadAllText(TPath.Combine(FDir, 'data\b.txt')).Trim);
  SetLength(Buf, 4096);
  Assert.AreEqual(Int64(Ord(verOk)), Cb.ReadText(PAnsiChar(Uri), 1024, nil, nil, PAnsiChar(@Buf[0]), Length(Buf), Neg));
  Assert.AreEqual('line one', TEncoding.UTF8.GetString(Buf, 0, Neg).Trim);
end;

procedure TTestRcloneLive.TestMakeFolderCopyOutAndDelete;
var
  Cb: TVfsCallbacksCdeclV2;
  Dir, Src, Dst: UTF8String;
  IsDir: Int64;
  Target: string;
begin
  Cb := RcloneVfsCallbacks;
  Dir := UriBuf(RemoteUri('made'));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CreateDirectory(PAnsiChar(Dir), nil, nil), 'make folder');
  Assert.IsTrue(TDirectory.Exists(TPath.Combine(FDir, 'data\made')));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Exists(PAnsiChar(Dir), nil, nil, IsDir), 'exists');
  Assert.AreEqual(Int64(1), IsDir);

  Src := UriBuf(RemoteUri('a.txt'));
  Target := TPath.Combine(FDir, 'copy.txt');
  Dst := UTF8String(PathToFileUri(Target));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.CopyItem(PAnsiChar(Src), PAnsiChar(Dst), 0, nil, nil), 'copy out');
  Assert.AreEqual('hello', TFile.ReadAllText(Target).Trim);

  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Dir), 0, nil, nil), 'delete folder');
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(FDir, 'data\made')));
  Assert.AreEqual(Int64(Ord(verOk)), Cb.Delete(PAnsiChar(Src), 0, nil, nil), 'delete file');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDir, 'data\a.txt')));
end;

procedure TTestRcloneLive.TestMissingFileIsNotFound;
var
  Cb: TVfsCallbacksCdeclV2;
  Uri: UTF8String;
  IsDir: Int64;
begin
  Cb := RcloneVfsCallbacks;
  Uri := UriBuf(RemoteUri('nope.txt'));
  Assert.AreEqual(Int64(Ord(verNotFound)), Cb.Exists(PAnsiChar(Uri), nil, nil, IsDir));
end;

end.
