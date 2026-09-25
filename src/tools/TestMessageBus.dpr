program TestMessageBus;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMessageBus in '..\Core\uMessageBus.pas';

procedure TestBasicPubSub;
var
  LReceived: Boolean;
  LSub: ISubscription;
  LPayloadReceived: Boolean;
begin
  LReceived := False;
  LPayloadReceived := False;

  LSub := MessageBus.Subscribe('test.topic',
    procedure(const ATopic: string; const APayload: TObject)
    begin
      if ATopic = 'test.topic' then
        LReceived := True;
      if APayload <> nil then
        LPayloadReceived := True;
    end);

  MessageBus.Publish('test.topic', TObject.Create);
  Assert(LReceived, 'Subscriber should receive published topic');
  Assert(LPayloadReceived, 'Subscriber should receive payload object');

  // Test unsubscribe
  LReceived := False;
  LSub.Unsubscribe;
  MessageBus.Publish('test.topic');
  Assert(not LReceived, 'Unsubscribed listener should not receive messages');

  Writeln('OK: TestBasicPubSub passed');
end;

begin
  try
    TestBasicPubSub;
    Writeln('All MessageBus tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
