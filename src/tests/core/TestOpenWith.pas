unit TestOpenWith;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestOpenWith = class
  public
    [Test] procedure TestEntryReadsNameExecAndFlags;
    [Test] procedure TestEntryIgnoresActionGroups;
    [Test] procedure TestHiddenEntryIsFlagged;
    [Test] procedure TestNonApplicationEntryIsRejected;
    [Test] procedure TestMimeCacheListsAppsOfTheType;
    [Test] procedure TestSingleFileCodeStartsOneRunPerFile;
    [Test] procedure TestListCodeTakesAllFiles;
    [Test] procedure TestExecWithoutFileCodeGetsFilesAppended;
    [Test] procedure TestQuotedExecWordsAndEscapedPercent;
    [Test] procedure TestPathsWithQuotesAreShellQuoted;
  end;

implementation

uses
  System.SysUtils, uOpenWith;

procedure TTestOpenWith.TestEntryReadsNameExecAndFlags;
var
  E: TOpenWithEntry;
begin
  Assert.IsTrue(ParseOpenWithEntry('[Desktop Entry]'#10'Type=Application'#10 +
    'Name=Editor'#10'Name[ru]=Redaktor'#10'Exec=ed %F'#10'Terminal=true'#10, E));
  Assert.AreEqual('Editor', E.Name);
  Assert.AreEqual('ed %F', E.Exec);
  Assert.IsTrue(E.Terminal);
  Assert.IsFalse(E.Hidden);
end;

procedure TTestOpenWith.TestEntryIgnoresActionGroups;
var
  E: TOpenWithEntry;
begin
  Assert.IsTrue(ParseOpenWithEntry('[Desktop Entry]'#10'Name=Viewer'#10'Exec=view %f'#10 +
    '[Desktop Action new]'#10'Name=New'#10'Exec=view --new'#10, E));
  Assert.AreEqual('Viewer', E.Name);
  Assert.AreEqual('view %f', E.Exec);
end;

procedure TTestOpenWith.TestHiddenEntryIsFlagged;
var
  E: TOpenWithEntry;
begin
  Assert.IsTrue(ParseOpenWithEntry('[Desktop Entry]'#10'Name=X'#10'Exec=x'#10'NoDisplay=true'#10, E));
  Assert.IsTrue(E.Hidden);
end;

procedure TTestOpenWith.TestNonApplicationEntryIsRejected;
var
  E: TOpenWithEntry;
begin
  Assert.IsFalse(ParseOpenWithEntry('[Desktop Entry]'#10'Type=Link'#10'Name=X'#10'Exec=x'#10, E));
  Assert.IsFalse(ParseOpenWithEntry('Name=X'#10'Exec=x'#10, E), 'no group header');
  Assert.IsFalse(ParseOpenWithEntry('[Desktop Entry]'#10'Name=X'#10, E), 'no Exec');
end;

procedure TTestOpenWith.TestMimeCacheListsAppsOfTheType;
var
  Apps: TArray<string>;
begin
  Apps := MimeCacheApps('[MIME Cache]'#10'text/plain=a.desktop;b.desktop;'#10 +
    'text/x-c=c.desktop;'#10, 'text/plain');
  Assert.AreEqual(2, Integer(Length(Apps)));
  Assert.AreEqual('a.desktop', Apps[0]);
  Assert.AreEqual('b.desktop', Apps[1]);
  Assert.AreEqual(0, Integer(Length(MimeCacheApps('text/plain=a.desktop;', 'text/pl'))),
    'a type is matched whole');
end;

procedure TTestOpenWith.TestSingleFileCodeStartsOneRunPerFile;
begin
  Assert.AreEqual('''view'' ''/a''', OpenWithExecToCommand('view %f', 'V', ['/a']));
  Assert.AreEqual('( ''view'' ''/a'' ; ''view'' ''/b'' )',
    OpenWithExecToCommand('view %u', 'V', ['/a', '/b']));
end;

procedure TTestOpenWith.TestListCodeTakesAllFiles;
begin
  Assert.AreEqual('''ed'' ''/a'' ''/b''', OpenWithExecToCommand('ed %F', 'E', ['/a', '/b']));
end;

procedure TTestOpenWith.TestExecWithoutFileCodeGetsFilesAppended;
begin
  Assert.AreEqual('''tool'' ''--fast'' ''/a''', OpenWithExecToCommand('tool --fast', 'T', ['/a']));
end;

procedure TTestOpenWith.TestQuotedExecWordsAndEscapedPercent;
begin
  Assert.AreEqual('''/opt/My App/run'' ''100%'' ''--icon-less'' ''/a''',
    OpenWithExecToCommand('"/opt/My App/run" 100%% %i --icon-less %f', 'M', ['/a']));
end;

procedure TTestOpenWith.TestPathsWithQuotesAreShellQuoted;
begin
  Assert.AreEqual('''/it''\''''s''', ShellQuoteWord('/it''s'));
  Assert.AreEqual('''ed'' ''/it''\''''s''',
    OpenWithExecToCommand('ed %f', 'E', ['/it''s']));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestOpenWith);

end.
