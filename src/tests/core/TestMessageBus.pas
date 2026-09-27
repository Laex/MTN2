unit TestMessageBus;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMessageBus = class
  public
    [Test] procedure TestBasicPubSub;
  end;

implementation

uses
  System.SysUtils,
  uMessageBus;

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
  Assert.IsTrue(LReceived, 'Subscriber should receive published topic');
  Assert.IsTrue(LPayloadReceived, 'Subscriber should receive payload object');

  // Test unsubscribe
  LReceived := False;
  LSub.Unsubscribe;
  MessageBus.Publish('test.topic');
  Assert.IsTrue(not LReceived, 'Unsubscribed listener should not receive messages');

  Writeln('OK: TestBasicPubSub passed');
end;

{ TTestMessageBus }

procedure TTestMessageBus.TestBasicPubSub;
begin
  TestMessageBus.TestBasicPubSub;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMessageBus);

end.
