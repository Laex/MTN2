unit TestEditorDownloadQuestion;

{ A remote file too large to be read whole is copied to a temporary file to
  be viewed. A document told to ask first waits for the answer before the copy. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorDownloadQuestion = class
  public
    [Test] procedure TestCopyWaitsForTheAnswer;
    [Test] procedure TestRefusalEndsTheLoadWithoutCopy;
    [Test] procedure TestCopyStartsAtOnceWhenNotAsked;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uTextEncoding, uVfsTypes, uEditorDoc;

const
  cBigUri = 'xbig://host/dir/big.bin';

type
  /// <summary>Refuses every whole-file read as too large and counts the copies
  /// asked of it; a copy never ends.</summary>
  TTooLargeVfs = class(TInterfacedObject, IVirtualFileSystem)
  public
    Copies: Integer;
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

procedure TTooLargeVfs.ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsListCallback);
begin
end;

procedure TTooLargeVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
end;

procedure TTooLargeVfs.CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsBoolCallback);
begin
end;

procedure TTooLargeVfs.CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
begin
  Inc(Copies);
end;

procedure TTooLargeVfs.MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
begin
end;

procedure TTooLargeVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
end;

procedure TTooLargeVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  QueueBytes(AOnDone, nil, TVfsError.Make(vecNotSupported, 'File too large', AURI));
end;

procedure TTooLargeVfs.WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
end;

procedure TTooLargeVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
end;

procedure TTooLargeVfs.GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsFreeSpaceCallback);
begin
end;

// The refusal of the read arrives on the main thread, which a console
// program pumps itself.
procedure Pump;
var
  Tick: UInt64;
begin
  Tick := TThread.GetTickCount64 + 200;
  while TThread.GetTickCount64 < Tick do
    CheckSynchronize(10);
end;

procedure TTestEditorDownloadQuestion.TestCopyWaitsForTheAnswer;
var
  Vfs: TTooLargeVfs;
  Keep: IVirtualFileSystem;
  Doc: TEditorDoc;
begin
  Vfs := TTooLargeVfs.Create;
  Keep := Vfs;
  Doc := TEditorDoc.Create(Keep);
  try
    Doc.AskBeforeDownload := True;
    Doc.OpenAsync(cBigUri);
    Pump;
    Assert.IsTrue(Doc.DownloadPending, 'the load waits for the answer');
    Assert.IsTrue(Doc.Loading, 'still loading while it waits');
    Assert.AreEqual(0, Vfs.Copies, 'nothing is copied before the answer');
    Assert.AreEqual(Int64(cEditorMaxBytes), Doc.LoadLimitBytes, 'the limit the file exceeds');
    Doc.AnswerDownload(True);
    Assert.IsFalse(Doc.DownloadPending);
    Assert.AreEqual(1, Vfs.Copies, 'the copy starts with the answer');
  finally
    Doc.Free;
  end;
end;

procedure TTestEditorDownloadQuestion.TestRefusalEndsTheLoadWithoutCopy;
var
  Vfs: TTooLargeVfs;
  Keep: IVirtualFileSystem;
  Doc: TEditorDoc;
begin
  Vfs := TTooLargeVfs.Create;
  Keep := Vfs;
  Doc := TEditorDoc.Create(Keep);
  try
    Doc.AskBeforeDownload := True;
    Doc.OpenAsync(cBigUri);
    Pump;
    Doc.AnswerDownload(False);
    Assert.IsFalse(Doc.Loading, 'the load is over');
    Assert.IsFalse(Doc.Ready);
    Assert.AreNotEqual('', Doc.Error, 'the document says why it is empty');
    Assert.AreEqual(0, Vfs.Copies, 'nothing is copied');
  finally
    Doc.Free;
  end;
end;

procedure TTestEditorDownloadQuestion.TestCopyStartsAtOnceWhenNotAsked;
var
  Vfs: TTooLargeVfs;
  Keep: IVirtualFileSystem;
  Doc: TEditorDoc;
begin
  Vfs := TTooLargeVfs.Create;
  Keep := Vfs;
  Doc := TEditorDoc.Create(Keep);
  try
    Doc.OpenAsync(cBigUri);
    Pump;
    Assert.IsFalse(Doc.DownloadPending);
    Assert.AreEqual(1, Vfs.Copies, 'the copy starts without a question');
  finally
    Doc.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorDownloadQuestion);

end.
