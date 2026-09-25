program TestPanelPluginRegistry;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uPanelPluginRegistry in '..\..\Core\uPanelPluginRegistry.pas';

procedure TestPluginRegistry;
var
  LRegistry: IPanelPluginRegistry;
  LResolved: string;
begin
  LRegistry := TPanelPluginRegistry.Create;
  LRegistry.RegisterPlugin('mtn.plugin.zip', 'zip');

  LResolved := LRegistry.ResolvePlugin('zip://C:/archive.zip');
  Assert(LResolved = 'mtn.plugin.zip', 'Should resolve to mtn.plugin.zip');

  LResolved := LRegistry.ResolvePlugin('file:///C:/Folder');
  Assert(LResolved = cDefaultPanelPluginId, 'Should fallback to default file plugin');

  LRegistry.RegisterPlugin('mtn.plugin.sample', 'sample');
  Assert(LRegistry.ResolvePlugin('sample://x') = 'mtn.plugin.sample', 'sample scheme');
  LRegistry.UnregisterPlugin('mtn.plugin.sample');
  Assert(LRegistry.ResolvePlugin('sample://x') = cDefaultPanelPluginId,
    'unregister restores default');

  Writeln('OK: TestPluginRegistry passed');
end;

begin
  try
    TestPluginRegistry;
    Writeln('All PanelPluginRegistry tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
