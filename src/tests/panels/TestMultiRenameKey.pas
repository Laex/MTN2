unit TestMultiRenameKey;

{ Ctrl+Alt+N reaches the multi-rename command: the default keymap binds it
  and the panel dispatcher calls the host. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMultiRenameKey = class
  public
    [Test] procedure TestChordIsBound;
    [Test] procedure TestActionCallsTheHost;
  end;

implementation

uses
  System.Classes, System.UITypes, uKeymap, uDualPanelInput;

type
  TCallSpy = class
  public
    Calls: Integer;
    procedure Count;
  end;

procedure TCallSpy.Count;
begin
  Inc(Calls);
end;

procedure TTestMultiRenameKey.TestChordIsBound;
begin
  Assert.IsTrue(MatchActiveAction(Ord('N'), [ssCtrl, ssAlt]) = kaMultiRename,
    'Ctrl+Alt+N is the multi-rename action');
  Assert.IsTrue(MatchActiveAction(Ord('M'), [ssCtrl]) <> kaMultiRename,
    'Ctrl+M stays with restoring the selection');
end;

procedure TTestMultiRenameKey.TestActionCallsTheHost;
var
  Host: TDualPanelKeymapHost;
  Spy: TCallSpy;
  Key: Word;
  Ch: Char;
begin
  Spy := TCallSpy.Create;
  try
    Host := Default(TDualPanelKeymapHost);
    Host.BeginMultiRename := Spy.Count;
    Key := Ord('M');
    Ch := #0;
    Assert.IsTrue(DispatchKeymapActionFunctionKeys(Host, kaMultiRename, Key, Ch),
      'the dispatcher handles it');
    Assert.AreEqual(1, Spy.Calls, 'the host command ran once');
  finally
    Spy.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMultiRenameKey);

end.
