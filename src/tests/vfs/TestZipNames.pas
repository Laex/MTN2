unit TestZipNames;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestZipNames = class
  public
    [Test] procedure Run;
    [Test] procedure Utf8NamesWithoutFlagAreDecoded;
    [Test] procedure OemNamesWithoutFlagStayOem;
    [Test] procedure ValidUtf8Check;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Zip,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  uZipNames;

{ TTestZipNames }

procedure TTestZipNames.Run;
begin
  Assert.IsTrue(NormZipName('\foo\bar\') = 'foo/bar', 'strips slashes and uses /');
  Assert.IsTrue(NormZipName('///a///') = 'a', 'trims leading and trailing slashes');
  Assert.IsTrue(NormZipName('') = '', 'empty stays empty');
  Assert.IsTrue(IsUnsafeZipName(''), 'empty is unsafe');
  Assert.IsTrue(IsUnsafeZipName('../x'), 'parent prefix is unsafe');
  Assert.IsTrue(IsUnsafeZipName('..'), 'dot-dot is unsafe');
  Assert.IsTrue(IsUnsafeZipName('a/../b'), 'embedded parent is unsafe');
  Assert.IsTrue(IsUnsafeZipName('C:evil'), 'drive colon is unsafe');
  Assert.IsTrue(not IsUnsafeZipName('dir/file.txt'), 'normal entry is safe');
  Assert.IsTrue(not IsUnsafeZipName('foo/..'), 'trailing .. without slash is unchanged');
  Assert.IsTrue(ZipWriteAllowed(nil), 'no segments is outer zip');
  Assert.IsTrue(ZipWriteAllowed(TArray<string>.Create('inner.txt')), 'one segment is outer zip');
  Assert.IsTrue(not ZipWriteAllowed(TArray<string>.Create('inner.zip', 'a')),
    'two segments is nested');

  System.Writeln('Prefix matching');
  var Rest: string;
  Assert.IsTrue(ZipRestAfterPrefix('a/b/c', 'a/', Rest) and (Rest = 'b/c'),
    'rest after a/');
  Assert.IsTrue(not ZipRestAfterPrefix('x/y', 'a/', Rest), 'outside prefix is miss');
  Assert.IsTrue(not ZipRestAfterPrefix('a/', 'a/', Rest), 'exact prefix rest is empty');
  Assert.IsTrue(ZipRestAfterPrefix('file.txt', '', Rest) and (Rest = 'file.txt'),
    'empty prefix keeps name');
  Assert.IsTrue(not ZipRestAfterPrefix('', '', Rest), 'empty name is miss');
  Assert.IsTrue(ZipNameEqualsOrUnder('dir/file', 'dir'), 'child is under dir');
  Assert.IsTrue(ZipNameEqualsOrUnder('dir', 'dir'), 'exact name matches');
  Assert.IsTrue(not ZipNameEqualsOrUnder('dir2/x', 'dir'), 'dir2 is not under dir');
  Assert.IsTrue(not ZipNameEqualsOrUnder('dir', ''), 'empty prefix is not under');
end;

function ZipNamesOf(const ARawName: TBytes; AWriteEnc: TEncoding): string;
var
  Path: string;
  W, R: TZipFile;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2_zipnames_' + TGUID.NewGuid.ToString + '.zip');
  W := TZipFile.Create;
  try
    W.Open(Path, zmWrite);
    W.UTF8Support := False;
    W.Encoding := AWriteEnc;
    W.Add(TBytes.Create(1), AWriteEnc.GetString(ARawName));
  finally
    W.Free;
  end;
  try
    R := NewReadZipFile;
    try
      R.Open(Path, zmRead);
      Result := R.FileNames[0];
    finally
      R.Free;
    end;
  finally
    TFile.Delete(Path);
  end;
end;

procedure TTestZipNames.Utf8NamesWithoutFlagAreDecoded;
var
  Name: string;
begin
  Name := string.Create([#$0417, #$0430, #$0434, #$0430, #$043D, #$0438, #$0435]);
  Assert.AreEqual(Name + '/a.txt',
    ZipNamesOf(TEncoding.UTF8.GetBytes(Name + '/a.txt'), TEncoding.UTF8),
    'valid UTF-8 bytes without the flag read as UTF-8');
end;

procedure TTestZipNames.OemNamesWithoutFlagStayOem;
var
  Raw: TBytes;
begin
  // 0x80 0x81 0x82 is not valid UTF-8: such a name is an OEM-encoded one.
  Raw := TBytes.Create(Ord('a'), $80, $81, $82);
  Assert.AreEqual(TEncoding.GetEncoding(
    {$IFDEF MSWINDOWS}GetOEMCP{$ELSE}437{$ENDIF}).GetString(Raw),
    ZipNamesOf(Raw, TEncoding.GetEncoding(
      {$IFDEF MSWINDOWS}GetOEMCP{$ELSE}437{$ENDIF})),
    'invalid UTF-8 bytes fall back to the OEM page');
end;

procedure TTestZipNames.ValidUtf8Check;
var
  A: array[0..3] of Byte;
begin
  A[0] := $D0; A[1] := $97;
  Assert.IsTrue(IsValidUtf8(@A[0], 2), 'two-byte sequence');
  Assert.IsFalse(IsValidUtf8(@A[0], 1), 'truncated sequence');
  A[0] := $C0; A[1] := $80;
  Assert.IsFalse(IsValidUtf8(@A[0], 2), 'overlong lead byte');
  A[0] := $41;
  Assert.IsTrue(IsValidUtf8(@A[0], 1), 'ASCII');
  Assert.IsTrue(IsValidUtf8(nil, 0), 'empty');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestZipNames);

end.
