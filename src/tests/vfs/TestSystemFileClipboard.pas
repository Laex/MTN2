unit TestSystemFileClipboard;

{ Files on the desktop clipboard (POSIX build): a stand-in xclip script on the
  search path keeps the selection in a folder, one type at a time, as a real
  owner does. On Windows, where the system clipboard does this work, the
  fixture is a no-op. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSystemFileClipboard = class
  private
    FDir: string;
    FOldPath: string;
    procedure InstallFakeXclip;
    function StoredType: string;
    function StoredData: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CopyGoesOutAsGnomeFileList;
    [Test] procedure CutFlagSurvivesTheRoundTrip;
    [Test] procedure KdeGetsAPlainUriList;
    [Test] procedure ForeignUriListIsPasted;
    [Test] procedure ForeignTextIsNotAFileList;
    [Test] procedure ClearEmptiesTheFileList;
    [Test] procedure SequenceFollowsTheClipboard;
    [Test] procedure TextGoesToTheDesktopClipboard;
    [Test] procedure TextGoesToTheTmuxBuffer;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uPlatformPaths, uPlatformProcess, uPlatformFileAttr, uFileAttrTypes, uPlatformInfo,
{$IFDEF POSIX}
  uSystemClipboard,
{$ENDIF}
  uVfsTypes, uWinFileDragDrop;

const
  cFakeXclip =
    '#!/bin/sh'#10 +
    'store="$FAKE_CLIP_DIR"'#10 +
    'mode=in; type=""'#10 +
    'while [ $# -gt 0 ]; do'#10 +
    '  case "$1" in -t) type="$2"; shift;; -o) mode=out;; esac'#10 +
    '  shift'#10 +
    'done'#10 +
    'if [ "$mode" = out ]; then'#10 +
    '  if [ -e "$store/type" ] && [ "$(cat "$store/type")" = "$type" ]; then'#10 +
    '    cat "$store/data"; exit 0'#10 +
    '  fi'#10 +
    '  echo "Error: target $type not available" >&2; exit 1'#10 +
    'fi'#10 +
    'cat > "$store/data"'#10 +
    'printf %s "$type" > "$store/type"'#10;

  cFakeTmux =
    '#!/bin/sh'#10 +
    'printf %s "$*" > "$FAKE_CLIP_DIR/tmux-args"'#10 +
    'cat > "$FAKE_CLIP_DIR/tmux-data"'#10;

procedure TTestSystemFileClipboard.InstallFakeXclip;
var
  Script: string;
  Plan: TFileAttrPlan;
  Err: string;
begin
  Script := TPath.Combine(FDir, 'xclip');
  TFile.WriteAllText(Script, cFakeXclip, TEncoding.ASCII);
  Plan := Default(TFileAttrPlan);
  Plan.ChangeMode := True;
  Plan.Mode := $1ED;
  Assert.IsTrue(ApplyFileAttrOne(Script, Plan, Err), Err);
  FOldPath := GetEnvironmentVariable('PATH');
  // Only the stand-in is on the path: a real wl-copy of the machine must not win.
  PlatformSetEnvironment('PATH', FDir + ':' + FOldPath);
  PlatformSetEnvironment('WAYLAND_DISPLAY', '');
  PlatformSetEnvironment('DISPLAY', ':99');
  PlatformSetEnvironment('XDG_CURRENT_DESKTOP', 'GNOME');
  PlatformSetEnvironment('FAKE_CLIP_DIR', FDir);
end;

function TTestSystemFileClipboard.StoredType: string;
begin
  if TFile.Exists(TPath.Combine(FDir, 'type')) then
    Result := TFile.ReadAllText(TPath.Combine(FDir, 'type'))
  else
    Result := '';
end;

function TTestSystemFileClipboard.StoredData: string;
begin
  Result := TFile.ReadAllText(TPath.Combine(FDir, 'data'), TEncoding.UTF8);
end;

procedure TTestSystemFileClipboard.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-clip-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(FDir);
  FOldPath := '';
  if PlatformPosixPaths then
    InstallFakeXclip;
end;

procedure TTestSystemFileClipboard.TearDown;
begin
  if FOldPath <> '' then
    PlatformSetEnvironment('PATH', FOldPath);
  TDirectory.Delete(FDir, True);
end;

procedure TTestSystemFileClipboard.CopyGoesOutAsGnomeFileList;
var
  A, B: string;
  Paths, Uris, GotPaths, GotUris: TArray<string>;
  Cut: Boolean;
begin
  if not PlatformPosixPaths then
    Exit;
  A := TPath.Combine(FDir, 'a b.txt');
  B := TPath.Combine(FDir, 'b.txt');
  TFile.WriteAllText(A, 'a');
  TFile.WriteAllText(B, 'b');
  Paths := TArray<string>.Create(A, B);
  Uris := TArray<string>.Create(PathToFileUri(A), PathToFileUri(B));
  Assert.IsTrue(ClipboardSetPanelItems(Paths, Uris, False), 'copy accepted');
  Assert.AreEqual('x-special/gnome-copied-files', StoredType, 'type for GTK file managers');
  Assert.AreEqual('copy'#10 + Uris[0] + #10 + Uris[1], StoredData, 'payload');
  Assert.IsTrue(Pos('%20', StoredData) > 0, 'the space is percent-encoded');
  Assert.IsTrue(ClipboardGetPanelItems(GotPaths, GotUris, Cut), 'read back');
  Assert.IsFalse(Cut, 'copy is not cut');
  Assert.AreEqual(2, Integer(Length(GotPaths)), 'both items');
  Assert.AreEqual(A, GotPaths[0], 'path with a space');
end;

procedure TTestSystemFileClipboard.CutFlagSurvivesTheRoundTrip;
var
  A: string;
  Paths, Uris, GotPaths, GotUris: TArray<string>;
  Cut: Boolean;
begin
  if not PlatformPosixPaths then
    Exit;
  A := TPath.Combine(FDir, 'c.txt');
  TFile.WriteAllText(A, 'c');
  Paths := TArray<string>.Create(A);
  Uris := TArray<string>.Create(PathToFileUri(A));
  Assert.IsTrue(ClipboardSetPanelItems(Paths, Uris, True), 'cut accepted');
  Assert.IsTrue(StoredData.StartsWith('cut'#10), 'cut marker for file managers');
  Assert.IsTrue(ClipboardGetPanelItems(GotPaths, GotUris, Cut), 'read back');
  Assert.IsTrue(Cut, 'cut flag kept');
  Assert.IsTrue(ClipboardHasPanelItems, 'items reported');
end;

procedure TTestSystemFileClipboard.KdeGetsAPlainUriList;
var
  A: string;
  Paths, Uris, GotPaths, GotUris: TArray<string>;
  Cut: Boolean;
begin
  if not PlatformPosixPaths then
    Exit;
  PlatformSetEnvironment('XDG_CURRENT_DESKTOP', 'KDE');
  A := TPath.Combine(FDir, 'k.txt');
  TFile.WriteAllText(A, 'k');
  Paths := TArray<string>.Create(A);
  Uris := TArray<string>.Create(PathToFileUri(A));
  Assert.IsTrue(ClipboardSetPanelItems(Paths, Uris, False), 'copy accepted');
  Assert.AreEqual('text/uri-list', StoredType, 'type for KDE');
  Assert.AreEqual(Uris[0] + #13#10, StoredData, 'one URI per line');
  Assert.IsTrue(ClipboardGetPanelItems(GotPaths, GotUris, Cut), 'read back');
  Assert.AreEqual(A, GotPaths[0], 'path');
end;

procedure TTestSystemFileClipboard.ForeignUriListIsPasted;
var
  A: string;
  GotPaths, GotUris: TArray<string>;
  Cut: Boolean;
begin
  if not PlatformPosixPaths then
    Exit;
  A := TPath.Combine(FDir, 'f.txt');
  TFile.WriteAllText(A, 'f');
  TFile.WriteAllText(TPath.Combine(FDir, 'type'), 'text/uri-list', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(FDir, 'data'),
    '# comment'#13#10 + PathToFileUri(A) + #13#10, TEncoding.ASCII);
  Assert.IsTrue(ClipboardGetPanelItems(GotPaths, GotUris, Cut), 'list read');
  Assert.IsFalse(Cut, 'a plain list is a copy');
  Assert.AreEqual(1, Integer(Length(GotPaths)), 'comment skipped');
  Assert.AreEqual(A, GotPaths[0], 'path');
end;

procedure TTestSystemFileClipboard.ForeignTextIsNotAFileList;
var
  GotPaths, GotUris: TArray<string>;
  Cut: Boolean;
begin
  if not PlatformPosixPaths then
    Exit;
  TFile.WriteAllText(TPath.Combine(FDir, 'type'), 'text/plain', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(FDir, 'data'), 'hello', TEncoding.ASCII);
  Assert.IsFalse(ClipboardGetPanelItems(GotPaths, GotUris, Cut), 'text is not a file list');
  Assert.IsFalse(ClipboardHasPanelItems, 'nothing to paste');
end;

procedure TTestSystemFileClipboard.ClearEmptiesTheFileList;
var
  A: string;
  Paths, Uris: TArray<string>;
begin
  if not PlatformPosixPaths then
    Exit;
  A := TPath.Combine(FDir, 'd.txt');
  TFile.WriteAllText(A, 'd');
  Paths := TArray<string>.Create(A);
  Uris := TArray<string>.Create(PathToFileUri(A));
  Assert.IsTrue(ClipboardSetPanelItems(Paths, Uris, True), 'cut accepted');
  Assert.IsTrue(ClipboardHasPanelItems, 'list present');
  ClipboardClearPanelItems;
  Assert.IsFalse(ClipboardHasPanelItems, 'list gone, so a cut cannot be pasted twice');
end;

procedure TTestSystemFileClipboard.SequenceFollowsTheClipboard;
var
  A, B: string;
  Seq1, Seq2, Seq3: Cardinal;
begin
  if not PlatformPosixPaths then
    Exit;
  A := TPath.Combine(FDir, 's1.txt');
  B := TPath.Combine(FDir, 's2.txt');
  TFile.WriteAllText(A, 'a');
  TFile.WriteAllText(B, 'b');
  ClipboardSetPanelItems(TArray<string>.Create(A), TArray<string>.Create(PathToFileUri(A)), False);
  Seq1 := PlatformClipboardSequence;
  Assert.AreEqual(Seq1, PlatformClipboardSequence, 'stable while nothing changes');
  Assert.AreNotEqual(Cardinal(0), Seq1, 'a file list gives a nonzero value');
  ClipboardSetPanelItems(TArray<string>.Create(B), TArray<string>.Create(PathToFileUri(B)), False);
  Seq2 := PlatformClipboardSequence;
  Assert.AreNotEqual(Seq1, Seq2, 'another list, another value');
  TFile.WriteAllText(TPath.Combine(FDir, 'type'), 'text/plain', TEncoding.ASCII);
  Seq3 := PlatformClipboardSequence;
  Assert.AreEqual(Cardinal(0), Seq3, 'foreign content leaves no file list');
end;

procedure TTestSystemFileClipboard.TextGoesToTheDesktopClipboard;
begin
  if not PlatformPosixPaths then
    Exit;
{$IFDEF POSIX}
  PlatformSetEnvironment('TMUX', '');
  Assert.IsTrue(SystemTextClipSet('plain text'), 'accepted');
  Assert.AreEqual('plain text', StoredData, 'payload');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDir, 'tmux-data')), 'no tmux outside tmux');
{$ENDIF}
end;

procedure TTestSystemFileClipboard.TextGoesToTheTmuxBuffer;
var
  Script: string;
  Plan: TFileAttrPlan;
  Err: string;
begin
  if not PlatformPosixPaths then
    Exit;
{$IFDEF POSIX}
  Script := TPath.Combine(FDir, 'tmux');
  TFile.WriteAllText(Script, cFakeTmux, TEncoding.ASCII);
  Plan := Default(TFileAttrPlan);
  Plan.ChangeMode := True;
  Plan.Mode := $1ED;
  Assert.IsTrue(ApplyFileAttrOne(Script, Plan, Err), Err);
  PlatformSetEnvironment('TMUX', FDir + ',1,0');
  try
    Assert.IsTrue(SystemTextClipSet('from tmux'), 'accepted');
  finally
    PlatformSetEnvironment('TMUX', '');
  end;
  Assert.AreEqual('from tmux', TFile.ReadAllText(TPath.Combine(FDir, 'tmux-data'), TEncoding.UTF8),
    'the tmux buffer gets the text');
  Assert.AreEqual('load-buffer -w -', TFile.ReadAllText(TPath.Combine(FDir, 'tmux-args')),
    'the buffer is also sent to the terminal clipboard');
{$ENDIF}
end;


initialization
  TDUnitX.RegisterTestFixture(TTestSystemFileClipboard);

end.
