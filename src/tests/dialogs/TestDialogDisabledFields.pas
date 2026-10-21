unit TestDialogDisabledFields;

{ A disabled input or drop-down is skipped by Tab and ignores typing, a disabled
  control that had the focus hands it on, and picking another drop-down item
  reports the control id through OnValueChanged. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogDisabledFields = class
  public
    [Test] procedure TestDisabledInputIsSkippedByTab;
    [Test] procedure TestDisabledDropDownIsSkippedByTab;
    [Test] procedure TestDisablingFocusedControlMovesFocus;
    [Test] procedure TestPickingAnItemFiresValueChanged;
    [Test] procedure TestReEnabledInputTakesFocusAgain;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uDialogHost;

const
  cDecl = '{"type":"dialog","version":"2.0","title":"t","width":40,"height":12,"children":[' +
    '{"type":"dropdown","id":"kind","selected":0,"items":["zip","7z"],"col":1,"row":1,"width":20,"height":1},' +
    '{"type":"input","id":"pw","value":"bb","col":1,"row":3,"width":20,"height":1},' +
    '{"type":"dropdown","id":"level","selected":0,"items":["a","b","c"],"col":1,"row":5,"width":20,"height":1},' +
    '{"type":"checkbox","id":"names","text":"names","checked":false,"col":1,"row":7,"width":20,"height":1}]}';

procedure Press(AHost: TDialogHost; AKey: Word; AChar: Char = #0);
begin
  AHost.HandleInput(AKey, [], AChar);
end;

function OpenDialog(out AHost: TDialogHost): Boolean;
begin
  AHost := TDialogHost.Create(nil);
  Result := AHost.OpenJson(cDecl, nil);
end;

procedure TTestDialogDisabledFields.TestDisabledInputIsSkippedByTab;
var
  Host: TDialogHost;
begin
  Assert.IsTrue(OpenDialog(Host), 'dialog opens');
  try
    Host.SetControlDisabled('pw', True);
    Host.FocusControlById('kind');
    Press(Host, vkTab);
    Press(Host, Ord('X'), 'x');
    Assert.AreEqual('bb', Host.GetInputValue('pw'), 'typing does not reach the disabled input');
    Press(Host, vkDown);
    Assert.AreEqual(1, Host.GetListSelectedIndex('level'), 'Tab landed on the next control');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogDisabledFields.TestDisabledDropDownIsSkippedByTab;
var
  Host: TDialogHost;
begin
  Assert.IsTrue(OpenDialog(Host), 'dialog opens');
  try
    Host.SetControlDisabled('level', True);
    Host.FocusControlById('pw');
    Press(Host, vkTab);
    Press(Host, Ord(' '), ' ');
    Assert.IsTrue(Host.GetCheckbox('names'), 'Tab skipped the disabled drop-down');
    Assert.AreEqual(0, Host.GetListSelectedIndex('level'));
  finally
    Host.Free;
  end;
end;

procedure TTestDialogDisabledFields.TestDisablingFocusedControlMovesFocus;
var
  Host: TDialogHost;
begin
  Assert.IsTrue(OpenDialog(Host), 'dialog opens');
  try
    Host.FocusControlById('pw');
    Host.SetControlDisabled('pw', True);
    Press(Host, Ord('X'), 'x');
    Assert.AreEqual('bb', Host.GetInputValue('pw'), 'the disabled input is not edited');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogDisabledFields.TestPickingAnItemFiresValueChanged;
var
  Host: TDialogHost;
  Fired: TArray<string>;
begin
  Assert.IsTrue(OpenDialog(Host), 'dialog opens');
  try
    Host.OnValueChanged :=
      procedure(const AControlId: string)
      begin
        Fired := Fired + [AControlId];
      end;
    Host.FocusControlById('kind');
    Press(Host, vkDown);
    Assert.IsTrue(Length(Fired) = 1, 'one change reported');
    Assert.AreEqual('kind', Fired[0]);
    Press(Host, vkDown);
    Assert.IsTrue(Length(Fired) = 1, 'no report when the pick stays at the last item');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogDisabledFields.TestReEnabledInputTakesFocusAgain;
var
  Host: TDialogHost;
begin
  Assert.IsTrue(OpenDialog(Host), 'dialog opens');
  try
    Host.SetControlDisabled('pw', True);
    Host.SetControlDisabled('pw', False);
    Host.FocusControlById('kind');
    Press(Host, vkTab);
    Press(Host, vkEnd);
    Press(Host, Ord('X'), 'x');
    Assert.AreEqual('bbx', Host.GetInputValue('pw'));
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogDisabledFields);

end.
