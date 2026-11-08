unit TestCliInfo;

{ uCliInfo: the information switches (--paths, --list-commands, --check-keymap,
  --export-theme, ...) parse from the command line and print the facts they
  name. The keymap checker is tested on texts, without files. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCliInfo = class
  public
    [Test] procedure TestSwitchWithArgument;
    [Test] procedure TestSwitchIgnoresFollowingSwitch;
    [Test] procedure TestPlainPathsAreNotInfoSwitches;
    [Test] procedure TestPathsNameTheConfigFolder;
    [Test] procedure TestListCommandsShowsKeys;
    [Test] procedure TestExportThemeWritesJson;
    [Test] procedure TestExportThemeUnknownIdFails;
    [Test] procedure TestKeymapValid;
    [Test] procedure TestKeymapUnknownActionFails;
    [Test] procedure TestKeymapUnknownKeyFails;
    [Test] procedure TestKeymapNotObjectFails;
    [Test] procedure TestKeymapSharedChordWarns;
    [Test] procedure TestCheckKeymapMissingFileFails;
    [Test] procedure TestShellInitNamesProgramAndCdFile;
    [Test] procedure TestShellInitQuotesApostrophe;
    [Test] procedure TestShellInitUnknownShellFails;
    [Test] procedure TestCdFileOfArgs;
    [Test] procedure TestWriteCdFileHasNoBomAndNoLineBreak;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uCliInfo, uConfigLocation, uThemeRegistry;

function Collect(ACommand: TCliInfoCommand; const AArgument: string;
  out ALines: TArray<string>): Integer;
var
  Lines: TArray<string>;
begin
  Lines := nil;
  Result := RunCliInfo(ACommand, AArgument,
    procedure(const ALine: string)
    begin
      Lines := Lines + [ALine];
    end);
  ALines := Lines;
end;

function AnyStartsWith(const ALines: TArray<string>; const APrefix: string): Boolean;
var
  Line: string;
begin
  for Line in ALines do
    if Line.StartsWith(APrefix) then
      Exit(True);
  Result := False;
end;

procedure TTestCliInfo.TestSwitchWithArgument;
var
  Cmd: TCliInfoCommand;
  Arg: string;
begin
  Assert.IsTrue(CliInfoRequested(['--check-keymap', 'my.json'], Cmd, Arg));
  Assert.AreEqual(Ord(cicCheckKeymap), Ord(Cmd));
  Assert.AreEqual('my.json', Arg);
end;

procedure TTestCliInfo.TestSwitchIgnoresFollowingSwitch;
var
  Cmd: TCliInfoCommand;
  Arg: string;
begin
  Assert.IsTrue(CliInfoRequested(['--export-theme', '--no-mouse'], Cmd, Arg));
  Assert.AreEqual(Ord(cicExportTheme), Ord(Cmd));
  Assert.AreEqual('', Arg);
end;

procedure TTestCliInfo.TestPlainPathsAreNotInfoSwitches;
var
  Cmd: TCliInfoCommand;
  Arg: string;
begin
  Assert.IsFalse(CliInfoRequested(['C:\Tools', '--view', 'a.txt'], Cmd, Arg));
  Assert.AreEqual(Ord(cicNone), Ord(Cmd));
end;

procedure TTestCliInfo.TestPathsNameTheConfigFolder;
var
  Lines: TArray<string>;
begin
  Assert.AreEqual(0, Collect(cicPaths, '', Lines));
  Assert.IsTrue(AnyStartsWith(Lines, 'config' + StringOfChar(' ', 6) + GetConfigDirectory));
  Assert.IsTrue(AnyStartsWith(Lines, 'plugins' + StringOfChar(' ', 5)));
end;

procedure TTestCliInfo.TestListCommandsShowsKeys;
var
  Lines: TArray<string>;
  Line, CopyLine: string;
begin
  Assert.AreEqual(0, Collect(cicListCommands, '', Lines));
  CopyLine := '';
  for Line in Lines do
    if Line.StartsWith('Copy ') then
      CopyLine := Line;
  Assert.IsTrue(CopyLine <> '', 'Copy is listed');
  Assert.IsTrue(CopyLine.Contains('F5'), 'with its key: ' + CopyLine);
end;

procedure TTestCliInfo.TestExportThemeWritesJson;
var
  Lines: TArray<string>;
begin
  Assert.AreEqual(0, Collect(cicExportTheme, DefaultThemeId, Lines));
  Assert.IsTrue(Length(Lines) = 1, 'one JSON document');
  Assert.IsTrue(Lines[0].TrimLeft.StartsWith('{'));
end;

procedure TTestCliInfo.TestExportThemeUnknownIdFails;
var
  Lines: TArray<string>;
begin
  Assert.AreEqual(1, Collect(cicExportTheme, 'no-such-theme-id', Lines));
  Assert.IsTrue(AnyStartsWith(Lines, 'FAIL'));
end;

procedure TTestCliInfo.TestKeymapValid;
var
  Report: TArray<string>;
begin
  Assert.IsTrue(CheckKeymapText('{"bindings":{"Copy":[{"key":"F5"}]}}', Report));
  Assert.IsTrue(AnyStartsWith(Report, 'OK'));
end;

procedure TTestCliInfo.TestKeymapUnknownActionFails;
var
  Report: TArray<string>;
begin
  Assert.IsFalse(CheckKeymapText('{"bindings":{"NoSuchAction":[{"key":"F5"}]}}', Report));
  Assert.IsTrue(AnyStartsWith(Report, 'FAIL unknown action "NoSuchAction"'));
end;

procedure TTestCliInfo.TestKeymapUnknownKeyFails;
var
  Report: TArray<string>;
begin
  Assert.IsFalse(CheckKeymapText('{"bindings":{"Copy":{"key":"NoSuchKey"}}}', Report));
  Assert.IsTrue(AnyStartsWith(Report, 'FAIL Copy: unrecognized key "NoSuchKey"'));
end;

procedure TTestCliInfo.TestKeymapNotObjectFails;
var
  Report: TArray<string>;
begin
  Assert.IsFalse(CheckKeymapText('[1,2]', Report));
  Assert.IsFalse(CheckKeymapText('not json', Report));
  Assert.IsTrue(AnyStartsWith(Report, 'FAIL'));
end;

procedure TTestCliInfo.TestKeymapSharedChordWarns;
var
  Report: TArray<string>;
begin
  // F5 is Copy's key in the built-in profile; giving it to Move as well
  // leaves one chord for two commands of the panels.
  Assert.IsTrue(CheckKeymapText('{"bindings":{"Move":[{"key":"F5"}]}}', Report));
  Assert.IsTrue(AnyStartsWith(Report, 'WARN F5 is bound to both'), string.Join('|', Report));
end;

procedure TTestCliInfo.TestCheckKeymapMissingFileFails;
var
  Lines: TArray<string>;
  Missing: string;
begin
  Missing := TPath.Combine(TPath.GetTempPath, 'mtn2-nokeymap-' + TGUID.NewGuid.ToString + '.json');
  Assert.AreEqual(1, Collect(cicCheckKeymap, Missing, Lines));
  Assert.IsTrue(AnyStartsWith(Lines, 'FAIL'));
end;

procedure TTestCliInfo.TestShellInitNamesProgramAndCdFile;
var
  Lines: TArray<string>;
  Shell, Text: string;
begin
  for Shell in ['bash', 'zsh', 'fish', 'powershell', 'pwsh'] do
  begin
    Assert.IsTrue(ShellInitLines(Shell, 'C:\Tools\mtn2.exe', Lines), Shell);
    Text := string.Join(#10, Lines);
    Assert.IsTrue(Text.Contains('C:\Tools\mtn2.exe'), Shell + ': program');
    Assert.IsTrue(Text.Contains('--cd-file'), Shell + ': switch');
    Assert.IsTrue(Text.Contains('mtn'), Shell + ': function');
  end;
end;

procedure TTestCliInfo.TestShellInitQuotesApostrophe;
var
  Lines: TArray<string>;
begin
  Assert.IsTrue(ShellInitLines('bash', '/opt/it''s/mtn2', Lines));
  Assert.IsTrue(string.Join(#10, Lines).Contains('''/opt/it''\''''s/mtn2'''));
  Assert.IsTrue(ShellInitLines('powershell', 'C:\it''s\mtn2.exe', Lines));
  Assert.IsTrue(string.Join(#10, Lines).Contains('''C:\it''''s\mtn2.exe'''));
end;

procedure TTestCliInfo.TestShellInitUnknownShellFails;
var
  Lines: TArray<string>;
  Out1: TArray<string>;
begin
  Assert.IsFalse(ShellInitLines('cmd', 'x', Lines));
  Assert.AreEqual(1, Collect(cicShellInit, 'cmd', Out1));
  Assert.IsTrue(AnyStartsWith(Out1, 'FAIL'));
  Assert.AreEqual(0, Collect(cicShellInit, 'bash', Out1));
end;

procedure TTestCliInfo.TestCdFileOfArgs;
begin
  Assert.AreEqual('a.txt', CdFileOfArgs(['x', '--cd-file', 'a.txt', 'y']));
  Assert.AreEqual('b.txt', CdFileOfArgs(['--cd-file=b.txt']));
  Assert.AreEqual('', CdFileOfArgs(['--cd-file']));
  Assert.AreEqual('', CdFileOfArgs(['x', 'y']));
end;

procedure TTestCliInfo.TestWriteCdFileHasNoBomAndNoLineBreak;
var
  Path: string;
  Bytes: TBytes;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-cdfile-' + TGUID.NewGuid.ToString + '.txt');
  try
    WriteCdFile(Path, 'D:\Work\project');
    Bytes := TFile.ReadAllBytes(Path);
    Assert.AreEqual(Length('D:\Work\project'), Integer(Length(Bytes)));
    Assert.AreEqual(Ord('D'), Integer(Bytes[0]));
    WriteCdFile('', 'D:\x');
    WriteCdFile(Path, '');
    Assert.AreEqual(Length('D:\Work\project'), Integer(Length(TFile.ReadAllBytes(Path))),
      'an empty argument leaves the file alone');
  finally
    TFile.Delete(Path);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCliInfo);

end.
