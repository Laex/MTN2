unit TestPanelPluginRegistry;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelPluginRegistry = class
  public
    [Test] procedure TestPluginRegistry;
    [Test] procedure TestPanelActivateHandlers;
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

procedure TestPanelActivateHandlers;
var
  Reg: IPanelPluginRegistry;
  Seen: string;
begin
  Reg := TPanelPluginRegistry.Create;
  Seen := '';
  Reg.RegisterActivateHandler('t.p', 'tmp',
    function(const APanelURI, ARowURI: string; AIsDirectory: Boolean): Boolean
    begin
      Seen := Seen + APanelURI + '|' + ARowURI + '|' + BoolToStr(AIsDirectory, True) + ';';
      Result := ARowURI.EndsWith('.take');
    end);
  Assert.IsTrue(not Reg.TryActivate('tmp:///', 'file:///C:/a.txt', False), 'handler passes');
  Assert.IsTrue(Seen = 'tmp:///|file:///C:/a.txt|False;',
    'the handler gets both URIs and the directory flag: ' + Seen);
  Assert.IsTrue(Reg.TryActivate('TMP:///', 'file:///C:/a.take', True), 'handler takes the row');
  Seen := '';
  Assert.IsTrue(not Reg.TryActivate('file:///C:/', 'file:///C:/a.take', False),
    'a handler is only asked for its own scheme');
  Assert.IsTrue(Seen = '', 'not asked for another scheme');

  Reg.RegisterActivateHandler('t.p', 'file', nil);
  Reg.RegisterActivateHandler('',
    'file',
    function(const APanelURI, ARowURI: string; AIsDirectory: Boolean): Boolean
    begin
      Result := True;
    end);
  Assert.IsTrue(not Reg.TryActivate('C:\plain\path', 'file:///C:/a', False),
    'invalid registrations are ignored, a bare path is a file panel');

  Reg.RegisterActivateHandler('t.boom', 'tmp',
    function(const APanelURI, ARowURI: string; AIsDirectory: Boolean): Boolean
    begin
      raise Exception.Create('plugin failure');
    end);
  Assert.IsTrue(not Reg.TryActivate('tmp:///', 'file:///C:/a.txt', False),
    'a handler that raises passes');
  Assert.IsTrue(Reg.TryActivate('tmp:///', 'file:///C:/a.take', False),
    'the handler before a faulty one still decides');

  Reg.UnregisterPlugin('t.p');
  Assert.IsTrue(not Reg.TryActivate('tmp:///', 'file:///C:/a.take', False),
    'unregistering drops the handlers');
end;

{ TTestPanelPluginRegistry }

procedure TTestPanelPluginRegistry.TestPanelActivateHandlers;
begin
  TestPanelPluginRegistry.TestPanelActivateHandlers;
end;

procedure TTestPanelPluginRegistry.TestPluginRegistry;
begin
  TestPanelPluginRegistry.TestPluginRegistry;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelPluginRegistry);

end.
