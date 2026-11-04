unit TestDialogHotKeyInput;

{ A key-capture input of a dialog ("hotkey": true) stores the pressed chord as
  text instead of typing it; Backspace clears it and Tab, Enter and Esc keep their
  dialog meaning. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogHotKeyInput = class
  public
    [Test] procedure TestChordReplacesTheValue;
    [Test] procedure TestAltLetterIsCapturedNotAMnemonic;
    [Test] procedure TestKeyCodeWithFlagAboveTheLowByte;
    [Test] procedure TestMultiFieldCollectsChords;
    [Test] procedure TestBackspaceClears;
    [Test] procedure TestModifierAloneKeepsTheValue;
    [Test] procedure TestEscapeStillCancels;
    [Test] procedure TestFlagSurvivesTheJsonRoundTrip;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, uDialogHost, uDialogTypes, uDialogJson;

const
  cDecl = '{"type":"dialog","version":"2.0","title":"t","width":40,"height":8,"children":[' +
    '{"type":"input","id":"key","value":"F5","hotkey":true,"col":1,"row":1,"width":20,"height":1},' +
    '{"type":"button","id":"ok","text":"&Open","col":1,"row":4,"width":10,"height":1}]}';

procedure Press(AHost: TDialogHost; AKey: Word; AShift: TShiftState; AChar: Char = #0);
begin
  AHost.HandleInput(AKey, AShift, AChar);
end;

procedure TTestDialogHotKeyInput.TestChordReplacesTheValue;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('key');
    Press(Host, vkF8, [ssCtrl, ssShift]);
    Assert.AreEqual('Ctrl+Shift+F8', Host.GetInputValue('key'));
    Press(Host, vkF2, []);
    Assert.AreEqual('F2', Host.GetInputValue('key'), 'the next chord replaces the previous one');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogHotKeyInput.TestAltLetterIsCapturedNotAMnemonic;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('key');
    Press(Host, Ord('O'), [ssAlt], 'o');
    Assert.AreEqual('Alt+O', Host.GetInputValue('key'));
  finally
    Host.Free;
  end;
end;

procedure TTestDialogHotKeyInput.TestKeyCodeWithFlagAboveTheLowByte;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('key');
    Press(Host, $100 or Ord('T'), [ssAlt, ssShift]);
    Assert.AreEqual('Alt+Shift+T', Host.GetInputValue('key'));
  finally
    Host.Free;
  end;
end;

procedure TTestDialogHotKeyInput.TestMultiFieldCollectsChords;
const
  cMulti = '{"type":"dialog","version":"2.0","title":"t","width":40,"height":8,"children":[' +
    '{"type":"input","id":"keys","value":"Ctrl+C","hotkey":true,"multi":true,' +
    '"col":1,"row":1,"width":30,"height":1}]}';
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cMulti, nil), 'dialog opens');
    Host.FocusControlById('keys');
    Press(Host, vkF5, []);
    Assert.AreEqual('Ctrl+C; F5', Host.GetInputValue('keys'));
    Press(Host, vkF5, []);
    Assert.AreEqual('Ctrl+C; F5', Host.GetInputValue('keys'), 'a listed chord is not added twice');
    Press(Host, Ord('A'), [ssShift], 'A');
    Assert.AreEqual('Ctrl+C; F5; Shift+A', Host.GetInputValue('keys'));
    Press(Host, vkBack, []);
    Assert.AreEqual('Ctrl+C; F5', Host.GetInputValue('keys'), 'Backspace drops the last chord');
    Press(Host, vkDelete, []);
    Assert.AreEqual('', Host.GetInputValue('keys'), 'Delete clears the field');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogHotKeyInput.TestBackspaceClears;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('key');
    Press(Host, vkBack, []);
    Assert.AreEqual('', Host.GetInputValue('key'));
  finally
    Host.Free;
  end;
end;

procedure TTestDialogHotKeyInput.TestModifierAloneKeepsTheValue;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('key');
    Press(Host, vkControl, [ssCtrl]);
    Press(Host, vkShift, [ssShift]);
    Assert.AreEqual('F5', Host.GetInputValue('key'));
  finally
    Host.Free;
  end;
end;

procedure TTestDialogHotKeyInput.TestEscapeStillCancels;
var
  Host: TDialogHost;
  Key: Word;
  Ch: Char;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cDecl, nil), 'dialog opens');
    Host.FocusControlById('key');
    Key := vkEscape;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Assert.AreEqual('F5', Host.GetInputValue('key'), 'Esc is not stored as the chord');
    Assert.AreEqual(0, Integer(Key), 'Esc is consumed by the dialog');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogHotKeyInput.TestFlagSurvivesTheJsonRoundTrip;
var
  Decl: TDialogDeclaration;
  Found: Boolean;
  C: TDialogControl;
begin
  Assert.IsTrue(TryParseDialogJson(cDecl, Decl));
  Found := False;
  for C in Decl.Controls do
    if C.Id = 'key' then
    begin
      Found := True;
      Assert.IsTrue(C.HotKey);
    end;
  Assert.IsTrue(Found);
  Assert.IsTrue(Pos('"hotkey":true', DeclarationToJson(Decl)) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogHotKeyInput);

end.
