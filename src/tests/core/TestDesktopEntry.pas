unit TestDesktopEntry;

{ uDesktopEntry: the text of the menu entries, and installing and removing them
  below a data folder. Everything runs in a temp folder. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDesktopEntry = class
  private
    FRoot: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ExecArgumentIsQuotedOnlyWhenNeeded;
    [Test] procedure ExecArgumentEscapesReservedCharacters;
    [Test] procedure SdlEntryNamesTheWindowClass;
    [Test] procedure TuiEntryRunsInATerminal;
    [Test] procedure InstallWritesEntryAndIcon;
    [Test] procedure SecondInstallChangesNothing;
    [Test] procedure MovedProgramRewritesItsOwnEntry;
    [Test] procedure ForeignEntryIsKept;
    [Test] procedure RemoveKeepsTheIconForTheOtherEntry;
    [Test] procedure RemoveDeletesIconWithTheLastEntry;
    [Test] procedure RemoveLeavesForeignEntry;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uDesktopEntry;

const
  cExe = '/opt/mtn2/mtn2-sdl';

function Icon: TBytes;
begin
  Result := TBytes.Create(1, 2, 3, 4);
end;

function EntryPath(const ARoot, AId: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ARoot, 'applications'), AId + '.desktop');
end;

function IconPath(const ARoot: string): string;
begin
  Result := TPath.Combine(ARoot, 'icons/hicolor/256x256/apps/mtn2.png');
end;

procedure TTestDesktopEntry.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-desktop-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(FRoot);
end;

procedure TTestDesktopEntry.TearDown;
begin
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TTestDesktopEntry.ExecArgumentIsQuotedOnlyWhenNeeded;
begin
  Assert.AreEqual('/opt/mtn2/mtn2-sdl', DesktopExecArgument('/opt/mtn2/mtn2-sdl'));
  Assert.AreEqual('"/home/me/my tools/mtn2-sdl"', DesktopExecArgument('/home/me/my tools/mtn2-sdl'));
end;

procedure TTestDesktopEntry.ExecArgumentEscapesReservedCharacters;
begin
  Assert.AreEqual('"/a\"b"', DesktopExecArgument('/a"b'));
  Assert.AreEqual('"/a\$b"', DesktopExecArgument('/a$b'));
  Assert.AreEqual('"/a\`b"', DesktopExecArgument('/a`b'));
  Assert.AreEqual('"/a\\b"', DesktopExecArgument('/a\b'));
  Assert.AreEqual('/a%%b', DesktopExecArgument('/a%b'), 'a percent sign is doubled');
end;

procedure TTestDesktopEntry.SdlEntryNamesTheWindowClass;
var
  Text: string;
begin
  Text := DesktopEntryText(dekSdl, cExe);
  Assert.IsTrue(Text.StartsWith('[Desktop Entry]'#10), 'it is a desktop entry');
  Assert.IsTrue(Text.Contains('Exec=' + cExe + ' %F'#10), 'it passes the paths it is given');
  Assert.IsTrue(Text.Contains('StartupWMClass=mtn2-sdl'#10), 'the taskbar finds the window');
  Assert.IsTrue(Text.Contains('Terminal=false'#10));
  Assert.IsTrue(Text.Contains('Icon=mtn2'#10));
  Assert.IsTrue(Text.Contains(cGeneratedMarker), 'it is marked as written by the program');
end;

procedure TTestDesktopEntry.TuiEntryRunsInATerminal;
var
  Text: string;
begin
  Text := DesktopEntryText(dekTui, '/opt/mtn2/mtn2-tui');
  Assert.IsTrue(Text.Contains('Terminal=true'#10), 'the desktop starts it in a terminal');
  Assert.IsFalse(Text.Contains('StartupWMClass'), 'a terminal program has no window class of its own');
end;

procedure TTestDesktopEntry.InstallWritesEntryAndIcon;
var
  Detail: string;
begin
  Assert.IsTrue(InstallDesktopEntry(dekSdl, FRoot, cExe, Icon, Detail) = derInstalled);
  Assert.IsTrue(TFile.Exists(EntryPath(FRoot, 'mtn2-sdl')), 'the entry is there');
  Assert.AreEqual(DesktopEntryText(dekSdl, cExe),
    TFile.ReadAllText(EntryPath(FRoot, 'mtn2-sdl'), TEncoding.UTF8));
  Assert.IsTrue(TFile.Exists(IconPath(FRoot)), 'and the icon');
  Assert.AreEqual(4, Integer(Length(TFile.ReadAllBytes(IconPath(FRoot)))));
end;

procedure TTestDesktopEntry.SecondInstallChangesNothing;
var
  Detail: string;
begin
  InstallDesktopEntry(dekSdl, FRoot, cExe, Icon, Detail);
  Assert.IsTrue(InstallDesktopEntry(dekSdl, FRoot, cExe, Icon, Detail) = derUpToDate);
end;

procedure TTestDesktopEntry.MovedProgramRewritesItsOwnEntry;
var
  Detail: string;
begin
  InstallDesktopEntry(dekSdl, FRoot, cExe, Icon, Detail);
  Assert.IsTrue(InstallDesktopEntry(dekSdl, FRoot, '/home/me/mtn2/mtn2-sdl', Icon, Detail) = derInstalled);
  Assert.IsTrue(TFile.ReadAllText(EntryPath(FRoot, 'mtn2-sdl'), TEncoding.UTF8)
    .Contains('Exec=/home/me/mtn2/mtn2-sdl %F'), 'the new place is written');
end;

procedure TTestDesktopEntry.ForeignEntryIsKept;
var
  Detail, Mine: string;
begin
  Mine := '[Desktop Entry]'#10'Name=My own'#10;
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'applications'));
  TFile.WriteAllText(EntryPath(FRoot, 'mtn2-sdl'), Mine, TEncoding.UTF8);
  Assert.IsTrue(InstallDesktopEntry(dekSdl, FRoot, cExe, Icon, Detail) = derForeignKept);
  Assert.AreEqual(Mine, TFile.ReadAllText(EntryPath(FRoot, 'mtn2-sdl'), TEncoding.UTF8),
    'a file somebody else wrote is not touched');
  Assert.IsFalse(TFile.Exists(IconPath(FRoot)), 'and no icon is added for it');
end;

procedure TTestDesktopEntry.RemoveKeepsTheIconForTheOtherEntry;
var
  Detail: string;
begin
  InstallDesktopEntry(dekSdl, FRoot, cExe, Icon, Detail);
  InstallDesktopEntry(dekTui, FRoot, '/opt/mtn2/mtn2-tui', Icon, Detail);
  Assert.IsTrue(RemoveDesktopEntry(dekSdl, FRoot, Detail) = derRemoved);
  Assert.IsFalse(TFile.Exists(EntryPath(FRoot, 'mtn2-sdl')));
  Assert.IsTrue(TFile.Exists(EntryPath(FRoot, 'mtn2-tui')));
  Assert.IsTrue(TFile.Exists(IconPath(FRoot)), 'the other entry still uses the icon');
end;

procedure TTestDesktopEntry.RemoveDeletesIconWithTheLastEntry;
var
  Detail: string;
begin
  InstallDesktopEntry(dekSdl, FRoot, cExe, Icon, Detail);
  Assert.IsTrue(RemoveDesktopEntry(dekSdl, FRoot, Detail) = derRemoved);
  Assert.IsFalse(TFile.Exists(IconPath(FRoot)));
  Assert.IsTrue(RemoveDesktopEntry(dekSdl, FRoot, Detail) = derNothingToRemove);
end;

procedure TTestDesktopEntry.RemoveLeavesForeignEntry;
var
  Detail: string;
begin
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'applications'));
  TFile.WriteAllText(EntryPath(FRoot, 'mtn2-sdl'), '[Desktop Entry]'#10'Name=My own'#10, TEncoding.UTF8);
  Assert.IsTrue(RemoveDesktopEntry(dekSdl, FRoot, Detail) = derForeignKept);
  Assert.IsTrue(TFile.Exists(EntryPath(FRoot, 'mtn2-sdl')));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDesktopEntry);

end.
