unit TestListExport;

{ Layouts and field selection of the saved item list (Files > Export list). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestListExport = class
  public
    [Test] procedure TextLayoutAlignsColumnsAndRightAlignsSize;
    [Test] procedure TextLayoutWithoutHeaderStartsWithFirstItem;
    [Test] procedure FieldsComeOutInFixedOrder;
    [Test] procedure MarkdownTableEscapesPipesAndAlignsSize;
    [Test] procedure CsvQuotesSpecialCharacters;
    [Test] procedure AutoFormatFollowsFileExtension;
    [Test] procedure ExplicitFormatWinsOverExtension;
    [Test] procedure OnlyCsvGetsByteOrderMark;
    [Test] procedure DatesAreLocaleIndependent;
    [Test] procedure NoFieldsOrNoItemsGiveEmptyText;
    [Test] procedure ParseFormatRadioAndResolvePath;
    [Test] procedure TitlesComeFromTheCaller;
    [Test] procedure ConfigSurvivesTheSettingsText;
    [Test] procedure DamagedSettingsTextGivesDefaults;
  end;

implementation

uses
  System.SysUtils,
  uListExport;

function MakeItem(const AName, APath: string; ASize: Int64;
  AIsDir: Boolean = False): TListExportItem;
begin
  Result.Name := AName;
  Result.FullPath := APath;
  Result.Size := ASize;
  Result.IsDir := AIsDir;
  Result.Ext := ExtractFileExt(AName);
  Result.Modified := EncodeDate(2026, 3, 7) + EncodeTime(14, 5, 9, 0);
  Result.Created := 0;
  Result.Accessed := 0;
  Result.Attr := 'A';
  Result.TypeName := 'File';
end;

function Config(AFormat: TListExportFormat; AHeader: Boolean;
  AFields: TListExportFields): TListExportConfig;
begin
  Result.Format := AFormat;
  Result.Header := AHeader;
  Result.Fields := AFields;
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.TrimRight([#13, #10]).Split([sLineBreak]);
end;

procedure TTestListExport.TextLayoutAlignsColumnsAndRightAlignsSize;
var
  L: TArray<string>;
begin
  L := Lines(FormatItemList(
    [MakeItem('a.txt', 'C:\d\a.txt', 5), MakeItem('long name.bin', 'C:\d\long name.bin', 12345)],
    Config(lefText, True, [lxfName, lxfSize]), 'list.txt', DefaultListExportTitles));
  Assert.IsTrue(Length(L) = 3);
  Assert.AreEqual('Name' + StringOfChar(' ', 12) + 'Size', L[0]);
  Assert.AreEqual('a.txt' + StringOfChar(' ', 14) + '5', L[1]);
  Assert.AreEqual('long name.bin  12345', L[2]);
end;

procedure TTestListExport.TextLayoutWithoutHeaderStartsWithFirstItem;
var
  L: TArray<string>;
begin
  L := Lines(FormatItemList([MakeItem('a.txt', 'C:\d\a.txt', 5)],
    Config(lefText, False, [lxfPath]), 'list.txt', DefaultListExportTitles));
  Assert.IsTrue(Length(L) = 1);
  Assert.AreEqual('C:\d\a.txt', L[0]);
end;

procedure TTestListExport.FieldsComeOutInFixedOrder;
var
  L: TArray<string>;
begin
  L := Lines(FormatItemList([MakeItem('a.txt', 'C:\d\a.txt', 5)],
    Config(lefCsv, True, [lxfAttr, lxfName, lxfExt, lxfType]), 'list.csv', DefaultListExportTitles));
  Assert.AreEqual('Name,Ext,Type,Attr', L[0]);
  Assert.AreEqual('a.txt,txt,File,A', L[1]);
end;

procedure TTestListExport.MarkdownTableEscapesPipesAndAlignsSize;
var
  L: TArray<string>;
begin
  L := Lines(FormatItemList([MakeItem('a|b.txt', 'C:\d\a|b.txt', 5)],
    Config(lefMarkdown, False, [lxfName, lxfSize]), 'list.md', DefaultListExportTitles));
  Assert.IsTrue(Length(L) = 3, 'a Markdown table always has its header');
  Assert.AreEqual('| Name | Size |', L[0]);
  Assert.AreEqual('| --- | ---: |', L[1]);
  Assert.AreEqual('| a\|b.txt | 5 |', L[2]);
end;

procedure TTestListExport.CsvQuotesSpecialCharacters;
var
  L: TArray<string>;
begin
  L := Lines(FormatItemList([MakeItem('a,"b".txt', 'C:\d\a.txt', 5)],
    Config(lefCsv, False, [lxfName, lxfSize]), 'list.csv', DefaultListExportTitles));
  Assert.IsTrue(Length(L) = 1);
  Assert.AreEqual('"a,""b"".txt",5', L[0]);
end;

procedure TTestListExport.AutoFormatFollowsFileExtension;
begin
  Assert.IsTrue(ResolveListExportFormat(lefAuto, 'x.md') = lefMarkdown);
  Assert.IsTrue(ResolveListExportFormat(lefAuto, 'X.MARKDOWN') = lefMarkdown);
  Assert.IsTrue(ResolveListExportFormat(lefAuto, 'x.csv') = lefCsv);
  Assert.IsTrue(ResolveListExportFormat(lefAuto, 'x.txt') = lefText);
  Assert.IsTrue(ResolveListExportFormat(lefAuto, 'x') = lefText);
end;

procedure TTestListExport.ExplicitFormatWinsOverExtension;
begin
  Assert.IsTrue(ResolveListExportFormat(lefText, 'x.csv') = lefText);
  Assert.IsTrue(ResolveListExportFormat(lefCsv, 'x.md') = lefCsv);
end;

procedure TTestListExport.OnlyCsvGetsByteOrderMark;
begin
  Assert.IsTrue(ListExportNeedsBom(lefAuto, 'x.csv'));
  Assert.IsTrue(ListExportNeedsBom(lefCsv, 'x.txt'));
  Assert.IsFalse(ListExportNeedsBom(lefAuto, 'x.md'));
  Assert.IsFalse(ListExportNeedsBom(lefText, 'x.csv'));
end;

procedure TTestListExport.DatesAreLocaleIndependent;
var
  L: TArray<string>;
  Item: TListExportItem;
begin
  Item := MakeItem('a.txt', 'C:\d\a.txt', 5);
  Item.Created := 0;
  L := Lines(FormatItemList([Item],
    Config(lefCsv, False, [lxfModified, lxfCreated]), 'list.csv', DefaultListExportTitles));
  Assert.AreEqual('2026-03-07 14:05:09,', L[0], 'an unset date stays empty');
end;

procedure TTestListExport.NoFieldsOrNoItemsGiveEmptyText;
begin
  Assert.AreEqual('', FormatItemList([MakeItem('a', 'C:\a', 1)],
    Config(lefText, True, []), 'x.txt', DefaultListExportTitles));
  Assert.AreEqual('', FormatItemList(nil,
    Config(lefText, True, [lxfName]), 'x.txt', DefaultListExportTitles));
end;

procedure TTestListExport.ParseFormatRadioAndResolvePath;
const
{$IFDEF MSWINDOWS}
  CAbsFile = 'C:\out\list.txt';
  CPanelDir = 'D:\panel';
  CDocsDir = 'E:\docs';
{$ELSE}
  CAbsFile = '/out/list.txt';
  CPanelDir = '/panel';
  CDocsDir = '/docs';
{$ENDIF}
begin
  Assert.IsTrue(ParseListExportFormatRadio('fmt_text') = lefText, 'text');
  Assert.IsTrue(ParseListExportFormatRadio('fmt_md') = lefMarkdown, 'md');
  Assert.IsTrue(ParseListExportFormatRadio('fmt_csv') = lefCsv, 'csv');
  Assert.IsTrue(ParseListExportFormatRadio('other') = lefAuto, 'auto');
  Assert.AreEqual(CAbsFile,
    ResolveExportListPath(CAbsFile, CPanelDir, CDocsDir), 'abs');
  Assert.AreEqual(IncludeTrailingPathDelimiter(CPanelDir) + 'list.txt',
    ResolveExportListPath('list.txt', CPanelDir, CDocsDir), 'panel');
  Assert.AreEqual(IncludeTrailingPathDelimiter(CDocsDir) + 'list.txt',
    ResolveExportListPath('list.txt', '', CDocsDir), 'fallback');
end;

procedure TTestListExport.TitlesComeFromTheCaller;
var
  T: TListExportTitles;
  L: TArray<string>;
begin
  T := DefaultListExportTitles;
  T[lxfName] := 'Title';
  L := Lines(FormatItemList([MakeItem('a.txt', 'C:\d.txt', 5)],
    Config(lefCsv, True, [lxfName]), 'list.csv', T));
  Assert.AreEqual('Title', L[0]);
end;

procedure TTestListExport.ConfigSurvivesTheSettingsText;
var
  Cfg, Back: TListExportConfig;
begin
  Cfg := Config(lefMarkdown, False, [lxfPath, lxfAttr, lxfAccessed]);
  Back := ListExportConfigFromText(ListExportConfigToText(Cfg));
  Assert.IsTrue(Back.Format = lefMarkdown, 'format');
  Assert.IsFalse(Back.Header, 'header');
  Assert.IsTrue(Back.Fields = [lxfPath, lxfAttr, lxfAccessed], 'fields');
end;

procedure TTestListExport.DamagedSettingsTextGivesDefaults;
var
  Def, Back: TListExportConfig;
begin
  Def := DefaultListExportConfig;
  Back := ListExportConfigFromText('');
  Assert.IsTrue(Back.Format = Def.Format);
  Assert.IsTrue(Back.Fields = Def.Fields);
  Back := ListExportConfigFromText('csv;True;nothing');
  Assert.IsTrue(Back.Fields = Def.Fields, 'no known field keeps the defaults');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestListExport);

end.
