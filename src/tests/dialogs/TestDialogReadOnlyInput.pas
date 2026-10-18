unit TestDialogReadOnlyInput;

{ A read-only input of a dialog ("readonly": true) can be focused and its text
  copied, but typing, Backspace and Delete leave the text as it is. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogReadOnlyInput = class
  public
    [Test] procedure TestEditingKeysChangeNothing;
    [Test] procedure TestOrdinaryInputStillEdits;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uDialogHost;

const
  cDecl = '{"type":"dialog","version":"2.0","title":"t","width":40,"height":8,"children":[' +
    '{"type":"input","id":"fixed","value":"abc","readonly":true,"col":1,"row":1,"width":20,"height":1},' +
    '{"type":"input","id":"free","value":"abc","col":1,"row":3,"width":20,"height":1}]}';

procedure Press(AHost: TDialogHost; AKey: Word; AChar: Char = #0);
begin
  AHost.HandleInput(AKey, [], AChar);
end;

procedure TTestDialogReadOnlyInput.TestEditingKeysChangeNothing;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('fixed');
    Press(Host, Ord('X'), 'x');
    Press(Host, vkBack);
    Press(Host, vkDelete);
    Press(Host, vkEnd);
    Press(Host, Ord('Y'), 'y');
    Assert.AreEqual('abc', Host.GetInputValue('fixed'));
  finally
    Host.Free;
  end;
end;

procedure TTestDialogReadOnlyInput.TestOrdinaryInputStillEdits;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('free');
    Press(Host, vkEnd);
    Press(Host, Ord('X'), 'x');
    Assert.AreEqual('abcx', Host.GetInputValue('free'));
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogReadOnlyInput);

end.
