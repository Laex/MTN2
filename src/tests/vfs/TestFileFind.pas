unit TestFileFind;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFileFind = class
  public
    [Test] procedure Run;
    [Test] procedure FiltersParseAndApply;
    [Test] procedure ContentSearchDecodesEncodings;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  System.Math,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes,
  uFileFind;

var
  Ev: TEvent;
  Paths: TArray<string>;
  Err: TVfsError;
  ProgressHits: Integer;
  LastDir: string;

procedure WaitFind(const ARoot, AMask: string; ASubdirs: Boolean;
  const AText: string = '');
var
  Tick: Cardinal;
  Opts: TFindOptions;
begin
  SetLength(Paths, 0);
  Err := TVfsError.Ok;
  ProgressHits := 0;
  LastDir := '';
  Ev.ResetEvent;
  Writeln('--- Find root=', ARoot, ' mask=', AMask, ' sub=', ASubdirs);
  Opts := DefaultFindOptions(ARoot, AMask, ASubdirs);
  Opts.ContainingText := AText;
  FindFilesAsync(Opts, nil,
    procedure(AFoundCount: Integer; const ACurrentDir: string)
    begin
      Inc(ProgressHits);
      LastDir := ACurrentDir;
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError)
    begin
      SetLength(Paths, Length(AHits));
      for var H := 0 to High(AHits) do
        Paths[H] := AHits[H].Path;
      Err := AError;
      Ev.SetEvent;
    end);
  Tick := GetTickCount;
  while Ev.WaitFor(50) <> wrSignaled do
  begin
    CheckSynchronize;
    if GetTickCount - Tick > 15000 then
      Assert.Fail('find timed out: ' + ARoot);
  end;
  CheckSynchronize;
  Writeln('  Err=', Ord(Err.Code), ' ', Err.Message, ' count=', Length(Paths),
    ' progress=', ProgressHits);
  var I, ShowN: Integer;
  ShowN := Min(Length(Paths), 8);
  for I := 0 to ShowN - 1 do
    Writeln('    ', Paths[I]);
  if Length(Paths) > ShowN then
    Writeln('    ...');
end;

procedure PutEncoded(const ADir, AName, AText: string; AEnc: TEncoding;
  AWithBom: Boolean);
var
  Bytes: TBytes;
begin
  Bytes := AEnc.GetBytes(AText);
  if AWithBom then
    Bytes := AEnc.GetPreamble + Bytes;
  TFile.WriteAllBytes(TPath.Combine(ADir, AName), Bytes);
end;

var
  Root, Nested, Zipish: string;
  UriInsideZip: string;

{ TTestFileFind }

procedure TTestFileFind.FiltersParseAndApply;
var
  Bytes: Int64;
  Opts: TFindOptions;
  Text: TFindFilterText;
  Err: string;
  T0, Day, When, Parsed: TDateTime;
begin
  Assert.IsTrue(TryParseFindSize('', Bytes) and (Bytes = -1), 'empty size is no bound');
  Assert.IsTrue(TryParseFindSize('512', Bytes) and (Bytes = 512), 'plain bytes');
  Assert.IsTrue(TryParseFindSize('10k', Bytes) and (Bytes = 10 * 1024), 'K suffix');
  Assert.IsTrue(TryParseFindSize('2 MB', Bytes) and (Bytes = 2 * 1024 * 1024), 'M suffix with B');
  Assert.IsFalse(TryParseFindSize('abc', Bytes), 'text is not a size');
  Assert.IsFalse(TryParseFindSize('-5', Bytes), 'negative size');
  Assert.IsTrue(TryParseFindSize('1.5M', Bytes) and (Bytes = 1572864),
    'fractional megabytes');
  Assert.IsFalse(TryParseFindSize('1e20', Bytes), 'a size past the file-size range is rejected');
  Assert.IsFalse(TryParseFindSize('999999999T', Bytes), 'a huge suffix is rejected');

  T0 := EncodeDate(2025, 3, 4) + EncodeTime(10, 30, 0, 0);
  Opts := DefaultFindOptions('C:\x', '*.*');
  Opts.MinSize := 100;
  Opts.MaxSize := 200;
  Assert.IsTrue(FindEntryPassesFilters(Opts, False, 150, T0, 0), 'inside the size range');
  Assert.IsFalse(FindEntryPassesFilters(Opts, False, 99, T0, 0), 'below the range');
  Assert.IsFalse(FindEntryPassesFilters(Opts, False, 201, T0, 0), 'above the range');
  Assert.IsFalse(FindEntryPassesFilters(Opts, True, 0, T0, 0), 'folders drop out while a size bound is set');

  Opts := DefaultFindOptions('C:\x', '*.*');
  Opts.ModifiedFrom := T0;
  Opts.ModifiedTo := T0 + 1;
  Assert.IsTrue(FindEntryPassesFilters(Opts, False, 1, T0 + 0.5, 0), 'inside the date range');
  Assert.IsFalse(FindEntryPassesFilters(Opts, False, 1, T0 - 0.5, 0), 'before the range');
  Assert.IsFalse(FindEntryPassesFilters(Opts, True, 0, T0 + 2, 0), 'folder after the range');

  Opts := DefaultFindOptions('C:\x', '*.*');
  Opts.RequireAttr := faHidden or faReadOnly;
  Assert.IsTrue(FindEntryPassesFilters(Opts, False, 1, T0, faHidden or faReadOnly or faArchive),
    'all required attributes present');
  Assert.IsFalse(FindEntryPassesFilters(Opts, False, 1, T0, faHidden), 'one attribute missing');

  Opts := DefaultFindOptions('C:\x', '*.*');
  Text := Default(TFindFilterText);
  Text.SizeMin := '1K';
  Text.AttrHidden := True;
  Assert.IsTrue(ApplyFindFilterText(Opts, Text, Err), 'valid filters apply');
  Assert.AreEqual(Int64(1024), Opts.MinSize);
  Assert.AreEqual(Int64(-1), Opts.MaxSize);
  Assert.AreEqual(faHidden, Opts.RequireAttr);
  Text.SizeMax := 'oops';
  Assert.IsFalse(ApplyFindFilterText(Opts, Text, Err), 'a bad size is rejected');
  Assert.IsTrue(Err <> '', 'the rejection names the field');

  Day := EncodeDate(2021, 3, 4);
  When := Day + EncodeTime(10, 30, 45, 0);
  Assert.IsTrue(TryParseFindDate('', False, Parsed) and (Parsed = 0), 'empty date is no bound');
  Assert.IsTrue(TryParseFindDate('Mon ' + DateToStr(Day), False, Parsed) and SameDateTime(Parsed, Day),
    'a weekday before the date is ignored');
  Assert.IsTrue(TryParseFindDate('Tue. ' + DateToStr(Day), True, Parsed) and
    SameDateTime(Parsed, Day + 1 - 1 / MSecsPerDay),
    'a weekday and no time is the end of that day when asked');
  Assert.IsTrue(TryParseFindDate('Wed ' + DateToStr(Day) + ' ' + FormatDateTime('hh:nn:ss', When),
    True, Parsed) and SameDateTime(Parsed, When), 'a time after a weekday is kept');
  Assert.IsFalse(TryParseFindDate('Mon', False, Parsed), 'a day of week alone is not a date');
  Assert.IsFalse(TryParseFindDate('yesterday', False, Parsed), 'garbage is not a date');
end;

procedure TTestFileFind.ContentSearchDecodesEncodings;
const
  Needle = #$041F#$0440#$0438#$0432#$0435#$0442; // Russian "hello"
var
  Dir, Body: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2_find_enc_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    Body := 'first line' + #10 + 'second line ' + Needle + ' and more text to read' + #10;
    PutEncoded(Dir, 'utf8.txt', Body, TEncoding.UTF8, False);
    PutEncoded(Dir, 'utf8bom.txt', Body, TEncoding.UTF8, True);
    PutEncoded(Dir, 'utf16le.txt', Body, TEncoding.Unicode, True);
    PutEncoded(Dir, 'utf16be.txt', Body, TEncoding.BigEndianUnicode, True);
    PutEncoded(Dir, 'cp1251.txt', Body, TEncoding.GetEncoding(1251), False);
    PutEncoded(Dir, 'cp866.txt', Body, TEncoding.GetEncoding(866), False);
    PutEncoded(Dir, 'other.txt', 'nothing to see here', TEncoding.UTF8, False);
    Ev := TEvent.Create(nil, True, False, '');
    try
      WaitFind(Dir, '*.txt', False, Needle);
    finally
      Ev.Free;
    end;
    Assert.AreEqual(6, Integer(Length(Paths)));
    for var P in Paths do
      Assert.IsFalse(SameText('other.txt', ExtractFileName(P)));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestFileFind.Run;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    Root := TPath.Combine(TPath.GetTempPath, 'mtn2-find-smoke');
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
    Nested := TPath.Combine(Root, 'sub');
    ForceDirectories(Nested);
    TFile.WriteAllText(TPath.Combine(Root, 'a.pas'), 'x');
    TFile.WriteAllText(TPath.Combine(Root, 'b.txt'), 'y');
    TFile.WriteAllText(TPath.Combine(Nested, 'c.pas'), 'z');
    TFile.WriteAllText(TPath.Combine(Nested, 'readme.md'), 'm');

    WaitFind(Root, '*.pas', True);
    Assert.IsTrue(Length(Paths) = 2, '*.pas with subfolders finds a.pas and sub\c.pas');
    WaitFind(Root, '*.pas', False);
    Assert.IsTrue(Length(Paths) = 1, '*.pas without subfolders finds only a.pas');
    WaitFind(Root, '*.*', True);
    Assert.IsTrue(Length(Paths) = 4, '*.* with subfolders finds every file');
    WaitFind(Root + '_missing', '*.*', True);
    Assert.IsTrue(Length(Paths) = 0, 'missing root finds nothing');

    // Simulate what Dual Panel does for archive URI (bug surface).
    UriInsideZip := PathToFileUri(TPath.Combine(Root, 'fake.zip')) + '!/docs';
    Zipish := FileUriToPath(UriInsideZip);
    System.Writeln('--- Archive URI round-trip');
    System.Writeln('  URI=', UriInsideZip);
    System.Writeln('  FileUriToPath=', Zipish);
    System.Writeln('  ExistsDir=', TDirectory.Exists(Zipish));
    WaitFind(Zipish, '*.*', True);

    // Correct root when inside zip should be archive base dir (parent of zip).
    WaitFind(TPath.GetDirectoryName(ArchiveBasePath(UriInsideZip)), '*.pas', True);
  finally
    Ev.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFileFind);

end.
