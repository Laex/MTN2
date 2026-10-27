unit TestFollowTail;

{ Follow mode of the viewer document (uEditorDoc): a file that grows is picked
  up, whole or streamed, and a partial last line is completed in place. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFollowTail = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestStreamedFileIndexesAppendedLines;
    [Test] procedure TestStreamedPartialLastLineIsCompleted;
    [Test] procedure TestWholeFilePicksUpAppendedLines;
    [Test] procedure TestBinaryFileCannotBeFollowed;
    [Test] procedure TestFollowEndsWithTheDocument;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uPlatformInfo, uVfsTypes, uEditorDoc;

var
  GTempDir: string;

procedure WriteText(const APath, AText: string; AAppend: Boolean);
var
  FS: TFileStream;
  Bytes: TBytes;
begin
  Bytes := TEncoding.ASCII.GetBytes(AText);
  if AAppend then
  begin
    FS := TFileStream.Create(APath, fmOpenWrite or fmShareDenyNone);
    FS.Seek(0, soEnd);
  end
  else
    FS := TFileStream.Create(APath, fmCreate);
  try
    if Length(Bytes) > 0 then
      FS.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    FS.Free;
  end;
end;

// A text file over the whole-buffer limit, so that it is streamed. Returns the
// number of lines; the last one has no line break when ATrailingNewline is False.
function MakeBigLog(const APath: string; ATrailingNewline: Boolean): Integer;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    Result := 0;
    while SB.Length < cEditorMaxBytes + 4096 do
    begin
      SB.Append(Format('row %.8d abcdefghij 0123456789', [Result]));
      SB.Append(#10);
      Inc(Result);
    end;
    if not ATrailingNewline then
    begin
      SB.Length := SB.Length - 1;
    end;
    WriteText(APath, SB.ToString, False);
  finally
    SB.Free;
  end;
end;

function OpenAndWait(const APath: string): TEditorDoc;
var
  Tick: UInt64;
begin
  Result := TEditorDoc.Create;
  Result.OpenAsync(PathToFileUri(APath));
  Tick := PlatformTickCount64;
  while (not Result.Ready) or Result.Loading or Result.Indexing do
  begin
    CheckSynchronize(20);
    if PlatformTickCount64 - Tick > 60000 then
      Assert.Fail('timeout opening ' + APath);
  end;
  CheckSynchronize(0);
end;

// Pumps the main-thread queue until the document has ALines lines.
function WaitForLines(ADoc: TEditorDoc; ALines: Integer): Boolean;
var
  Tick: UInt64;
begin
  Tick := PlatformTickCount64;
  while ADoc.LineCount < ALines do
  begin
    CheckSynchronize(20);
    if PlatformTickCount64 - Tick > 15000 then
      Exit(False);
  end;
  Result := True;
end;

procedure TTestFollowTail.SetupFixture;
begin
  GTempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestFollowTail');
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
  TDirectory.CreateDirectory(GTempDir);
end;

procedure TTestFollowTail.TearDownFixture;
begin
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
end;

procedure TTestFollowTail.TestStreamedFileIndexesAppendedLines;
var
  Path: string;
  Doc: TEditorDoc;
  Lines: Integer;
begin
  Path := TPath.Combine(GTempDir, 'streamed.log');
  Lines := MakeBigLog(Path, True);
  Doc := OpenAndWait(Path);
  try
    Assert.IsTrue(Doc.Streaming, 'the file is streamed');
    Assert.AreEqual(Lines, Doc.LineCount);
    Doc.Follow := True;
    Assert.IsTrue(Doc.Follow, 'a streamed local text file can be followed');
    WriteText(Path, 'tail one' + #10 + 'tail two' + #10, True);
    Assert.IsTrue(WaitForLines(Doc, Lines + 2), 'the appended lines are indexed');
    Assert.AreEqual('tail one', Doc.GetLine(Lines));
    Assert.AreEqual('tail two', Doc.GetLine(Lines + 1));
    WriteText(Path, 'tail three' + #10, True);
    Assert.IsTrue(WaitForLines(Doc, Lines + 3), 'a second append is indexed too');
    Assert.AreEqual('tail three', Doc.GetLine(Lines + 2));
  finally
    Doc.Free;
  end;
end;

procedure TTestFollowTail.TestStreamedPartialLastLineIsCompleted;
var
  Path, Before: string;
  Doc: TEditorDoc;
  Lines: Integer;
begin
  Path := TPath.Combine(GTempDir, 'partial.log');
  Lines := MakeBigLog(Path, False);
  Doc := OpenAndWait(Path);
  try
    Before := Doc.GetLine(Lines - 1);
    Doc.Follow := True;
    Assert.IsTrue(Doc.Follow);
    WriteText(Path, '-done' + #10 + 'next' + #10, True);
    Assert.IsTrue(WaitForLines(Doc, Lines + 1), 'the line after the completed one appears');
    Assert.AreEqual(Before + '-done', Doc.GetLine(Lines - 1),
      'the partial last line is read again with its new end');
    Assert.AreEqual('next', Doc.GetLine(Lines));
  finally
    Doc.Free;
  end;
end;

procedure TTestFollowTail.TestWholeFilePicksUpAppendedLines;
var
  Path: string;
  Doc: TEditorDoc;
  Lines: Integer;
begin
  Path := TPath.Combine(GTempDir, 'whole.log');
  WriteText(Path, 'one' + #10 + 'two' + #10, False);
  Doc := OpenAndWait(Path);
  try
    Assert.IsFalse(Doc.Streaming, 'a small file is read whole');
    Lines := Doc.LineCount;
    Doc.Follow := True;
    Assert.IsTrue(Doc.Follow);
    WriteText(Path, 'three' + #10, True);
    Assert.IsTrue(WaitForLines(Doc, Lines + 1), 'the file is read again');
    Assert.AreEqual('three', Doc.GetLine(Lines - 1));
  finally
    Doc.Free;
  end;
end;

procedure TTestFollowTail.TestBinaryFileCannotBeFollowed;
var
  Path: string;
  Doc: TEditorDoc;
  FS: TFileStream;
  Bytes: TBytes;
begin
  Path := TPath.Combine(GTempDir, 'data.bin');
  Bytes := TBytes.Create(Ord('M'), Ord('Z'), 0, Ord('P'), Ord('E'), 0, 1, 2, 3);
  FS := TFileStream.Create(Path, fmCreate);
  try
    FS.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    FS.Free;
  end;
  Doc := OpenAndWait(Path);
  try
    Assert.IsFalse(Doc.CanFollow, 'a binary file is not followed');
    Doc.Follow := True;
    Assert.IsFalse(Doc.Follow, 'the request is refused');
  finally
    Doc.Free;
  end;
end;

procedure TTestFollowTail.TestFollowEndsWithTheDocument;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Path := TPath.Combine(GTempDir, 'closed.log');
  WriteText(Path, 'one' + #10, False);
  Doc := OpenAndWait(Path);
  try
    Doc.Follow := True;
    Assert.IsTrue(Doc.Follow);
    Doc.Close;
    Assert.IsFalse(Doc.Follow, 'closing the document ends follow mode');
    Assert.IsFalse(Doc.CanFollow);
  finally
    Doc.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFollowTail);

end.
