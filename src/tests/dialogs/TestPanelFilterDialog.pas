unit TestPanelFilterDialog;

{ Panel filter dialog: a list of ready-made filters, a line for a custom mask
  and the OK / Clear / Cancel buttons. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelFilterDialog = class
  public
    [Test] procedure ListAndMaskLineAreFilled;
    [Test] procedure ButtonsAreThere;
  end;

implementation

uses
  System.SysUtils,
  uDialogTypes,
  uDialogHost;

function ControlIndex(AHost: TDialogHost; const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to AHost.ControlCount - 1 do
    if AHost.GetControl(I).Id = AId then
      Exit(I);
  Result := -1;
end;

procedure TTestPanelFilterDialog.ListAndMaskLineAreFilled;
var
  Host: TDialogHost;
  Idx: Integer;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPanelFilterDialog(['(no filter)', '*.txt', '*.pas;*.dpr'], '*.log'),
      procedure(const AId, AValues: string)
      begin
      end);
    Idx := ControlIndex(Host, 'presets');
    Assert.IsTrue(Idx >= 0, 'the list of filters');
    Assert.AreEqual(3, Integer(Length(Host.GetControl(Idx).Items)), 'every entry is listed');
    Assert.AreEqual('*.pas;*.dpr', Host.GetControl(Idx).Items[2], 'entries keep their masks');
    Assert.AreEqual('*.log', Host.GetInputValue('mask'), 'the current mask is in the custom line');
    Assert.AreEqual(0, Host.GetListSelectedIndex('presets'), 'the first entry is selected');
  finally
    Host.Free;
  end;
end;

procedure TTestPanelFilterDialog.ButtonsAreThere;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPanelFilterDialog(['(no filter)'], ''),
      procedure(const AId, AValues: string)
      begin
      end);
    Assert.IsTrue(ControlIndex(Host, 'ok') >= 0, 'OK');
    Assert.IsTrue(ControlIndex(Host, cDlgCmdClearFilter) >= 0, 'Clear');
    Assert.IsTrue(ControlIndex(Host, 'cancel') >= 0, 'Cancel');
    Assert.IsTrue(ControlIndex(Host, 'mask') >= 0, 'the custom mask line');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelFilterDialog);

end.
