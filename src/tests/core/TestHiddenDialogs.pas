unit TestHiddenDialogs;

{ uHiddenDialogs: "Don't show this again" choices persist and are restored in
  one step. The runner points the config folder at a temp directory. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHiddenDialogs = class
  public
    [Setup] procedure Setup;
    [Test] procedure HideAndRestore;
    [Test] procedure CheckboxValue;
  end;

implementation

uses
  uHiddenDialogs;

procedure TTestHiddenDialogs.Setup;
begin
  RestoreHiddenDialogs;
end;

procedure TTestHiddenDialogs.HideAndRestore;
begin
  Assert.IsFalse(DialogHidden('a'), 'nothing hidden at first');
  HideDialog('a');
  HideDialog('B');
  HideDialog('a');
  Assert.IsTrue(DialogHidden('a'), 'hidden id');
  Assert.IsTrue(DialogHidden('b'), 'ids compare without case');
  Assert.IsFalse(DialogHidden('c'), 'other ids stay visible');
  Assert.AreEqual(2, RestoreHiddenDialogs, 'restored count ignores duplicates');
  Assert.IsFalse(DialogHidden('a'), 'restored');
  Assert.AreEqual(0, RestoreHiddenDialogs, 'nothing left to restore');
end;

procedure TTestHiddenDialogs.CheckboxValue;
begin
  Assert.IsTrue(DialogValuesChecked('{"hide":true}', 'hide'), 'ticked');
  Assert.IsFalse(DialogValuesChecked('{"hide":false}', 'hide'), 'not ticked');
  Assert.IsFalse(DialogValuesChecked('{}', 'hide'), 'absent');
  Assert.IsFalse(DialogValuesChecked('not json', 'hide'), 'garbage');
end;

end.
