unit TestPluginServiceSettings;

{ The option that stops a plugin from registering its JSON-RPC services. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginServiceSettings = class
  public
    [Setup] procedure Setup;
    [Test] procedure TestMissingValueMeansEnabled;
    [Test] procedure TestClearedOptionDisablesTheProvider;
    [Test] procedure TestProviderRegistersOnlyWhenEnabled;
    [Test] procedure TestDialogCarriesTheCheckboxState;
    [Test] procedure TestAnswerOfOkGivesTheCheckbox;
    [Test] procedure TestOtherButtonsChangeNothing;
  end;

implementation

uses
  System.SysUtils, System.JSON, uPluginHostAbi, uPluginServiceProvider,
  uPluginServiceSettings;

var
  GValue: string;
  GRegistered: Integer;

function FakeGetSetting(APluginId, AKey: PAnsiChar; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
var
  U: UTF8String;
begin
  if GValue = '' then
    Exit(-1);
  U := UTF8String(GValue);
  Move(PAnsiChar(U)^, ABuf^, Length(U) + 1);
  Result := Length(U);
end;

function FakeRegister(APluginId, AName: PAnsiChar; AVersion: Int64; ADescribeJson: PAnsiChar;
  AHandler: TServiceHandlerFn; AUserData: Pointer; APriority: Int64): Int64; cdecl;
begin
  Inc(GRegistered);
  Result := 0;
end;

function FakeReply(ACall: Int64; AJson: PAnsiChar): Int64; cdecl;
begin
  Result := 0;
end;

procedure TTestPluginServiceSettings.Setup;
begin
  GValue := '';
  GRegistered := 0;
end;

function Host: THostApiTable;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.AbiVersion := cPluginAbiVersion;
  Result.GetSetting := FakeGetSetting;
  Result.RegisterService := FakeRegister;
  Result.ServiceReply := FakeReply;
  Result.ServiceNotify := FakeReply;
end;

procedure TTestPluginServiceSettings.TestMissingValueMeansEnabled;
var
  H: THostApiTable;
begin
  H := Host;
  Assert.IsTrue(ServiceProviderEnabled(@H, 'test.plugin'));
  GValue := '1';
  Assert.IsTrue(ServiceProviderEnabled(@H, 'test.plugin'));
end;

procedure TTestPluginServiceSettings.TestClearedOptionDisablesTheProvider;
var
  H: THostApiTable;
begin
  H := Host;
  GValue := '0';
  Assert.IsFalse(ServiceProviderEnabled(@H, 'test.plugin'));
end;

procedure TTestPluginServiceSettings.TestProviderRegistersOnlyWhenEnabled;
var
  H: THostApiTable;
  P: TServiceProvider;
begin
  H := Host;
  P := TServiceProvider.Create(@H, procedure(AJob: TServiceJob; const ARequestJson: string)
    begin
    end);
  try
    Assert.IsTrue(P.Register('test.plugin', 'test.service', '{}', 50));
    Assert.AreEqual<Integer>(1, GRegistered);
    GValue := '0';
    Assert.IsFalse(P.Register('test.plugin', 'test.service', '{}', 50));
    Assert.AreEqual<Integer>(1, GRegistered, 'nothing is offered to the host');
  finally
    P.Free;
  end;
end;

procedure TTestPluginServiceSettings.TestDialogCarriesTheCheckboxState;
var
  Root: TJSONValue;
  Kids: TJSONArray;
  I: Integer;
  Found: Boolean;
begin
  Found := False;
  Root := TJSONObject.ParseJSONValue(ServiceSettingsDialogJson('T', 'Enabled', 'OK', 'Cancel', False));
  try
    Kids := TJSONObject(Root).GetValue('children') as TJSONArray;
    for I := 0 to Kids.Count - 1 do
      if TJSONObject(Kids.Items[I]).GetValue<string>('id', '') = cSettingProvider then
      begin
        Found := True;
        Assert.IsFalse(TJSONObject(Kids.Items[I]).GetValue<Boolean>('checked'));
      end;
    Assert.IsTrue(Found, 'the checkbox is in the dialog');
  finally
    Root.Free;
  end;
end;

procedure TTestPluginServiceSettings.TestAnswerOfOkGivesTheCheckbox;
var
  Enabled: Boolean;
begin
  Assert.IsTrue(ServiceSettingsAnswerEnabled('ok', '{"jsonrpc_provider":false}', Enabled));
  Assert.IsFalse(Enabled);
  Assert.IsTrue(ServiceSettingsAnswerEnabled('ok', '{"jsonrpc_provider":true}', Enabled));
  Assert.IsTrue(Enabled);
end;

procedure TTestPluginServiceSettings.TestOtherButtonsChangeNothing;
var
  Enabled: Boolean;
begin
  Assert.IsFalse(ServiceSettingsAnswerEnabled('cancel', '{"jsonrpc_provider":false}', Enabled));
  Assert.IsFalse(ServiceSettingsAnswerEnabled('ok', 'not json', Enabled));
end;

end.
