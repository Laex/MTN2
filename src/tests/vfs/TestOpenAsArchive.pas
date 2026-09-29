unit TestOpenAsArchive;

{ Opening a file as an archive whatever its extension (Ctrl+PgDn): a ZIP
  signature is recognised by content, and the built-in ZIP lists a file
  named .docx through its "!/" root like any .zip. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestOpenAsArchive = class
  public
    [Test] procedure TestZipSignature;
    [Test] procedure TestZipListsUnderAnyName;
    [Test] procedure TestRouting;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, System.Zip,
  uVfsTypes, uVfsRegistry, uFileVfs, uZipVfs;

function WorkDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-open-as-archive');
  TDirectory.CreateDirectory(Result);
end;

function MakeZip(const AName: string; AWithEntry: Boolean): string;
var
  Z: TZipFile;
begin
  Result := TPath.Combine(WorkDir, AName);
  if TFile.Exists(Result) then
    TFile.Delete(Result);
  Z := TZipFile.Create;
  try
    Z.Open(Result, zmWrite);
    if AWithEntry then
      Z.Add(TEncoding.UTF8.GetBytes('<doc/>'), 'word/document.xml');
    Z.Close;
  finally
    Z.Free;
  end;
end;

procedure TTestOpenAsArchive.TestZipSignature;
var
  Plain: string;
begin
  Assert.IsTrue(FileHasZipSignature(MakeZip('report.docx', True)), 'a ZIP named .docx');
  Assert.IsTrue(FileHasZipSignature(MakeZip('empty.odt', False)), 'an empty ZIP');
  Plain := TPath.Combine(WorkDir, 'plain.docx');
  TFile.WriteAllText(Plain, 'not a zip at all');
  Assert.IsFalse(FileHasZipSignature(Plain), 'text named .docx');
  TFile.WriteAllText(Plain, 'PK');
  Assert.IsFalse(FileHasZipSignature(Plain), 'shorter than a signature');
  Assert.IsFalse(FileHasZipSignature(TPath.Combine(WorkDir, 'missing.docx')), 'missing file');
end;

procedure TTestOpenAsArchive.TestZipListsUnderAnyName;
var
  Vfs: IVirtualFileSystem;
  Done: TEvent;
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  Deadline: TDateTime;
  Found: Boolean;
  E: TVfsEntry;
begin
  Vfs := CreateDefaultVfs;
  Done := TEvent.Create(nil, True, False, '');
  try
    Vfs.ListDirectoryAsync(EnsureArchiveRootUri(PathToFileUri(MakeZip('report.docx', True))),
      nil,
      procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
      begin
        Items := AItems;
        Err := AError;
        Done.SetEvent;
      end);
    Deadline := Now + 10 / SecsPerDay;
    while (Done.WaitFor(20) <> wrSignaled) and (Now < Deadline) do
      CheckSynchronize;
    CheckSynchronize;
    Assert.IsTrue(Done.WaitFor(0) = wrSignaled, 'listing finishes');
  finally
    Done.Free;
  end;
  Assert.IsTrue(Err.Code = vecOk, 'lists: ' + Err.Message);
  Found := False;
  for E in Items do
    if SameText(E.Name, 'word') then
      Found := True;
  Assert.IsTrue(Found, 'the docx root shows its word folder');
end;

procedure TTestOpenAsArchive.TestRouting;
var
  Doc, Folder: string;
begin
  Doc := MakeZip('report.docx', True);
  Assert.IsTrue(IsZipArchiveUri(EnsureArchiveRootUri(PathToFileUri(Doc))),
    'a ZIP named .docx goes to the built-in ZIP');
  // A folder named "Wow!" makes a "!/" in the URI of its files.
  Folder := TPath.Combine(WorkDir, 'Wow!');
  TDirectory.CreateDirectory(Folder);
  TFile.WriteAllText(TPath.Combine(Folder, 'file.txt'), 'x');
  Assert.IsFalse(IsZipArchiveUri(PathToFileUri(TPath.Combine(Folder, 'file.txt'))),
    'a file in a folder ending in ! stays on the file system');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestOpenAsArchive);

end.
