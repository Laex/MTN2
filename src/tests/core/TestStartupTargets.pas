unit TestStartupTargets;

{ uStartupTargets: the folders and files named on the command line, the --view
  and --edit forms, and the line handed to a window that is already open. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStartupTargets = class
  public
    [Test] procedure PlainPathsOpenInOrder;
    [Test] procedure RelativePathIsMadeAbsolute;
    [Test] procedure ViewAndEditTakeTheNextArgument;
    [Test] procedure ViewAndEditTakeAValueAfterEquals;
    [Test] procedure ShortEditSwitchIsEdit;
    [Test] procedure OtherSwitchesAreNotTargets;
    [Test] procedure FileNameMayStartWithADash;
    [Test] procedure EncodedTargetsComeBack;
    [Test] procedure EmptyLineMeansNoTargets;
    [Test] procedure UnknownPiecesAreDropped;
  end;

implementation

uses
  System.SysUtils, uStartupTargets;

function Parse(const AArgs: array of string): TStartupTargets;
var
  Parser: TStartupTargetParser;
  Arg: string;
begin
  Parser := Default(TStartupTargetParser);
  for Arg in AArgs do
    Parser.Take(Arg);
  Result := Parser.Targets;
end;

procedure TTestStartupTargets.PlainPathsOpenInOrder;
var
  T: TStartupTargets;
begin
  T := Parse(['/data/one', '/data/two']);
  Assert.AreEqual(2, Integer(Length(T)));
  Assert.AreEqual(ExpandFileName('/data/one'), T[0].Path);
  Assert.AreEqual(ExpandFileName('/data/two'), T[1].Path);
  Assert.IsTrue(T[0].Mode = smOpen);
  Assert.IsTrue(T[1].Mode = smOpen);
end;

procedure TTestStartupTargets.RelativePathIsMadeAbsolute;
var
  T: TStartupTargets;
begin
  T := Parse(['notes.txt']);
  Assert.AreEqual(1, Integer(Length(T)));
  Assert.AreEqual(ExpandFileName('notes.txt'), T[0].Path);
  Assert.AreNotEqual('notes.txt', T[0].Path, 'a window that is already open has another current folder');
end;

procedure TTestStartupTargets.ViewAndEditTakeTheNextArgument;
var
  T: TStartupTargets;
begin
  T := Parse(['--view', '/data/a.txt', '--edit', '/data/b.txt', '/data/folder']);
  Assert.AreEqual(3, Integer(Length(T)));
  Assert.IsTrue(T[0].Mode = smView);
  Assert.AreEqual(ExpandFileName('/data/a.txt'), T[0].Path);
  Assert.IsTrue(T[1].Mode = smEdit);
  Assert.AreEqual(ExpandFileName('/data/b.txt'), T[1].Path);
  Assert.IsTrue(T[2].Mode = smOpen, 'the mode applies to one file only');
end;

procedure TTestStartupTargets.ViewAndEditTakeAValueAfterEquals;
var
  T: TStartupTargets;
begin
  T := Parse(['--view=/data/a.txt', '--edit=/data/b.txt']);
  Assert.AreEqual(2, Integer(Length(T)));
  Assert.IsTrue(T[0].Mode = smView);
  Assert.AreEqual(ExpandFileName('/data/a.txt'), T[0].Path);
  Assert.IsTrue(T[1].Mode = smEdit);
  Assert.AreEqual(ExpandFileName('/data/b.txt'), T[1].Path);
end;

procedure TTestStartupTargets.ShortEditSwitchIsEdit;
var
  T: TStartupTargets;
begin
  T := Parse(['-e', '/data/a.txt']);
  Assert.AreEqual(1, Integer(Length(T)));
  Assert.IsTrue(T[0].Mode = smEdit);
end;

procedure TTestStartupTargets.OtherSwitchesAreNotTargets;
var
  Parser: TStartupTargetParser;
begin
  Parser := Default(TStartupTargetParser);
  Assert.IsFalse(Parser.Take('--no-mouse'), 'a host switch is left to the host');
  Assert.IsFalse(Parser.Take('--colors=256'));
  Assert.IsFalse(Parser.Take(''));
  Assert.IsTrue(Parser.Take('/data/one'));
  Assert.AreEqual(1, Integer(Length(Parser.Targets)));
end;

procedure TTestStartupTargets.FileNameMayStartWithADash;
var
  T: TStartupTargets;
begin
  T := Parse(['--edit', '-odd.txt']);
  Assert.AreEqual(1, Integer(Length(T)));
  Assert.AreEqual(ExpandFileName('-odd.txt'), T[0].Path);
  Assert.IsTrue(T[0].Mode = smEdit);
end;

procedure TTestStartupTargets.EncodedTargetsComeBack;
var
  T, Back: TStartupTargets;
  I: Integer;
begin
  T := Parse(['/data/one', '--view', '/data/a b.txt', '--edit=/data/My Projects/c.txt']);
  Back := DecodeStartupTargets(EncodeStartupTargets(T));
  Assert.AreEqual(Integer(Length(T)), Integer(Length(Back)));
  for I := 0 to High(T) do
  begin
    Assert.AreEqual(T[I].Path, Back[I].Path);
    Assert.IsTrue(T[I].Mode = Back[I].Mode);
  end;
end;

procedure TTestStartupTargets.EmptyLineMeansNoTargets;
begin
  Assert.AreEqual('', EncodeStartupTargets(nil));
  Assert.AreEqual(0, Integer(Length(DecodeStartupTargets(''))),
    'a start without paths only raises the window');
end;

procedure TTestStartupTargets.UnknownPiecesAreDropped;
var
  Back: TStartupTargets;
begin
  Back := DecodeStartupTargets('O/data/one'#31'?junk'#31'V');
  Assert.AreEqual(1, Integer(Length(Back)));
  Assert.AreEqual('/data/one', Back[0].Path);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStartupTargets);

end.
