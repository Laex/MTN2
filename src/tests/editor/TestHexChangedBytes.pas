unit TestHexChangedBytes;

{ Bytes edited in the hex editor are flagged until the document is saved; the
  flags follow inserts, deletes and undo. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHexChangedBytes = class
  public
    [Test] procedure TestFlagsFollowEditsAndRestore;
    [Test] procedure TestSaveClearsTheFlags;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uVfsTypes, uEditorDoc;

function OpenDoc(const APath: string): TEditorDoc;
var
  T: UInt64;
begin
  TFile.WriteAllBytes(APath, TBytes.Create(1, 2, 3, 4, 5, 6));
  Result := TEditorDoc.Create;
  Result.OpenAsync(PathToFileUri(APath), True);
  T := TThread.GetTickCount64 + 10000;
  while (not Result.Ready) or Result.Loading do
  begin
    CheckSynchronize(20);
    if TThread.GetTickCount64 > T then
      Assert.Fail('timeout opening the document');
  end;
end;

function Flags(ADoc: TEditorDoc): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to ADoc.ByteCount - 1 do
    if ADoc.ByteChanged(I) then
      Result := Result + '1'
    else
      Result := Result + '0';
end;

procedure TTestHexChangedBytes.TestFlagsFollowEditsAndRestore;
var
  Path, Before: string;
  Doc: TEditorDoc;
  Bytes, Changed: TBytes;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-hexchg-' + TPath.GetGUIDFileName(False));
  Doc := OpenDoc(Path);
  try
    Assert.AreEqual('000000', Flags(Doc), 'nothing is flagged after loading');
    Doc.SetByte(1, $FF);
    Assert.AreEqual('010000', Flags(Doc), 'a typed byte is flagged');
    Bytes := Doc.SnapshotBytes;
    Changed := Doc.SnapshotChanged;
    Before := Flags(Doc);
    Doc.InsertByte(0, 0);
    Assert.AreEqual('1010000', Flags(Doc), 'an inserted byte is flagged and the rest shifts');
    Doc.DeleteByte(0);
    Assert.AreEqual(Before, Flags(Doc), 'deleting the inserted byte brings the flags back');
    Doc.DeleteByte(3);
    Assert.AreEqual('01000', Flags(Doc), 'deleting a byte drops its flag');
    Doc.RestoreBytes(Bytes, True, Changed);
    Assert.AreEqual(Before, Flags(Doc), 'undo restores the flags');
  finally
    Doc.Free;
    TFile.Delete(Path);
  end;
end;

procedure TTestHexChangedBytes.TestSaveClearsTheFlags;
var
  Path: string;
  Doc: TEditorDoc;
  T: UInt64;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-hexchg-' + TPath.GetGUIDFileName(False));
  Doc := OpenDoc(Path);
  try
    Doc.SetByte(2, $AA);
    Assert.AreEqual('001000', Flags(Doc), 'flagged before saving');
    Doc.SaveAsync(True);
    T := TThread.GetTickCount64 + 10000;
    while Doc.Dirty or Doc.Saving do
    begin
      CheckSynchronize(20);
      if TThread.GetTickCount64 > T then
        Assert.Fail('timeout saving the document');
    end;
    Assert.AreEqual('000000', Flags(Doc), 'saved bytes are no longer flagged');
  finally
    Doc.Free;
    TFile.Delete(Path);
  end;
end;

end.
