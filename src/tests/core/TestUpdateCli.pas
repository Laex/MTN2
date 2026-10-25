unit TestUpdateCli;

{ uUpdateCli: the channel names of --update and the refusal of an unknown one.
  The download itself is covered by the updater tests. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUpdateCli = class
  public
    [Test] procedure ChannelNames;
    [Test] procedure UnknownChannelIsRefusedBeforeAnythingIsDone;
  end;

implementation

uses
  System.SysUtils, uUpdateCli;

procedure TTestUpdateCli.ChannelNames;
begin
  Assert.IsTrue(IsUpdateChannelName('stable'));
  Assert.IsTrue(IsUpdateChannelName('Nightly'));
  Assert.IsTrue(IsUpdateChannelName('dev'), 'the older spelling of nightly');
  Assert.IsFalse(IsUpdateChannelName('beta'));
  Assert.IsFalse(IsUpdateChannelName(''));
end;

procedure TTestUpdateCli.UnknownChannelIsRefusedBeforeAnythingIsDone;
var
  Lines: string;
  Code: Integer;
begin
  Lines := '';
  Code := RunUpdateCommand('beta',
    procedure(const ALine: string)
    begin
      Lines := Lines + ALine + #10;
    end);
  Assert.AreEqual(2, Code, 'the exit code of a wrong channel');
  Assert.IsTrue(Lines.Contains('Unknown channel "beta"'), Lines);
  Assert.IsFalse(Lines.Contains('Checking'), 'no network access for a wrong channel');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUpdateCli);

end.
