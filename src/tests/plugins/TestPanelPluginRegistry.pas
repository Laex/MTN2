unit TestPanelPluginRegistry;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelPluginRegistry = class
  public
    [Test] procedure TestPluginRegistry;
  end;

implementation

uses
  System.SysUtils,
  uPanelPluginRegistry;

procedure TestPluginRegistry;
var
  LRegistry: IPanelPluginRegistry;
  LResolved: string;
begin
  LRegistry := TPanelPluginRegistry.Create;
  LRegistry.RegisterPlugin('mtn.plugin.zip', 'zip');

  LResolved := LRegistry.ResolvePlugin('zip://C:/archive.zip');
  Assert.IsTrue(LResolved = 'mtn.plugin.zip', 'Should resolve to mtn.plugin.zip');

  LResolved := LRegistry.ResolvePlugin('file:///C:/Folder');
  Assert.IsTrue(LResolved = cDefaultPanelPluginId, 'Should fallback to default file plugin');

  LRegistry.RegisterPlugin('mtn.plugin.sample', 'sample');
  Assert.IsTrue(LRegistry.ResolvePlugin('sample://x') = 'mtn.plugin.sample', 'sample scheme');
  LRegistry.UnregisterPlugin('mtn.plugin.sample');
  Assert.IsTrue(LRegistry.ResolvePlugin('sample://x') = cDefaultPanelPluginId,
    'unregister restores default');

end;

{ TTestPanelPluginRegistry }

procedure TTestPanelPluginRegistry.TestPluginRegistry;
begin
  TestPanelPluginRegistry.TestPluginRegistry;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelPluginRegistry);

end.
