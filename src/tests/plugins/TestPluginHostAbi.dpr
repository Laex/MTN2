program TestPluginHostAbi;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes,
  uMessageBus in '..\..\Core\uMessageBus.pas',
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas';

procedure TestHostAbiCall;
var
  LRes: Int64;
  LSub: ISubscription;
  LReceived: Boolean;
  LReceivedPayload: string;
begin
  LReceived := False;
  LReceivedPayload := '';
  LSub := MessageBus.Subscribe('abi.topic',
    procedure(const ATopic: string; const APayload: TObject)
    begin
      LReceived := True;
      if APayload is TPluginPayload then
        LReceivedPayload := TPluginPayload(APayload).Json;
    end);

  LRes := mtn_host_publish(PAnsiChar(UTF8String('test.plugin')),
    PAnsiChar(UTF8String('abi.topic')), PAnsiChar(UTF8String('{"x":1}')));
  Assert(LRes = 0, 'mtn_host_publish should return 0');
  Assert(LReceived, 'Subscriber should receive published topic via C-ABI');
  Assert(LReceivedPayload = '{"x":1}', 'Subscriber should receive the payload JSON');
  LSub.Unsubscribe;

  Writeln('OK: TestHostAbiCall passed');
end;

procedure TestHostInvalidate;
var
  LWindowId, LRes: Int64;
  LInvalidated: Boolean;
begin
  LInvalidated := False;
  LWindowId := RegisterInvalidatableWindow(
    procedure
    begin
      LInvalidated := True;
    end);

  LRes := mtn_host_invalidate(LWindowId);
  Assert(LRes = 0, 'mtn_host_invalidate should return 0 for a registered window');
  // Invalidate is delivered via TThread.Queue — pump the message queue.
  CheckSynchronize(200);
  Assert(LInvalidated, 'Registered invalidate proc should have run');

  UnregisterInvalidatableWindow(LWindowId);
  LRes := mtn_host_invalidate(LWindowId);
  Assert(LRes <> 0, 'mtn_host_invalidate should fail for an unregistered window');

  Writeln('OK: TestHostInvalidate passed');
end;

begin
  try
    TestHostAbiCall;
    TestHostInvalidate;
    Writeln('All PluginHostAbi tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
