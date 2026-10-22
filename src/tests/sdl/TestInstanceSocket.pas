unit TestInstanceSocket;

{ The Unix socket behind "one window per user" in mtn2-sdl: a later start hands
  its path to the first instance, which receives it on the main thread. Linux
  only (the Windows build uses uSingleInstance): on Windows the unit is empty. }

interface

{$IFDEF LINUX}
uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInstanceSocket = class
  public
    [Test] procedure NobodyListeningMeansNoHandOver;
    [Test] procedure PathReachesTheListenerOnTheMainThread;
    [Test] procedure StoppedListenerLeavesNoSocketBehind;
    [Test] procedure StaleSocketFileIsReplaced;
  end;
{$ENDIF}

implementation

{$IFDEF LINUX}
uses
  System.SysUtils, System.Classes, System.IOUtils, uInstanceSocket;

function UniqueName(const ATag: string): string;
begin
  Result := 'test-' + ATag + '-' + IntToStr(TThread.CurrentThread.ThreadID);
end;

// Runs the queued callbacks until AReceived is set or the time is up.
function WaitFor(var AReceived: Boolean; ATimeoutMs: Integer): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while not AReceived and (Waited < ATimeoutMs) do
  begin
    CheckSynchronize(20);
    Inc(Waited, 20);
  end;
  Result := AReceived;
end;

procedure TTestInstanceSocket.NobodyListeningMeansNoHandOver;
begin
  Assert.IsFalse(InstanceTryHandOver(UniqueName('nobody'), '/tmp'), 'no listener, no hand-over');
end;

procedure TTestInstanceSocket.PathReachesTheListenerOnTheMainThread;
var
  Name, Got: string;
  Received, OnMain: Boolean;
begin
  Name := UniqueName('deliver');
  Received := False;
  OnMain := False;
  Got := '';
  Assert.IsTrue(InstanceStartListening(Name,
    procedure(APath: string)
    begin
      Got := APath;
      OnMain := TThread.CurrentThread.ThreadID = MainThreadID;
      Received := True;
    end), 'listening');
  try
    Assert.IsTrue(InstanceTryHandOver(Name, '/home/user/Проекты'), 'hand-over is acknowledged');
    Assert.IsTrue(WaitFor(Received, 3000), 'the callback ran');
    Assert.AreEqual('/home/user/Проекты', Got, 'the path arrives whole');
    Assert.IsTrue(OnMain, 'on the main thread');

    Received := False;
    Assert.IsTrue(InstanceTryHandOver(Name, ''), 'an empty path only raises the window');
    Assert.IsTrue(WaitFor(Received, 3000), 'the empty request arrives too');
    Assert.AreEqual('', Got, 'empty path');
  finally
    InstanceStopListening;
  end;
end;

procedure TTestInstanceSocket.StoppedListenerLeavesNoSocketBehind;
var
  Name: string;
begin
  Name := UniqueName('stop');
  Assert.IsTrue(InstanceStartListening(Name, procedure(APath: string) begin end), 'listening');
  Assert.IsTrue(TFile.Exists(InstanceSocketPath(Name)), 'the socket file exists while listening');
  InstanceStopListening;
  Assert.IsFalse(TFile.Exists(InstanceSocketPath(Name)), 'the socket file is removed');
  Assert.IsFalse(InstanceTryHandOver(Name, '/tmp'), 'nobody answers after stopping');
end;

procedure TTestInstanceSocket.StaleSocketFileIsReplaced;
var
  Name, Path: string;
  Received: Boolean;
begin
  Name := UniqueName('stale');
  Path := InstanceSocketPath(Name);
  // What a crashed instance leaves: a file at the socket path that nobody serves.
  TFile.WriteAllText(Path, 'stale');
  Received := False;
  Assert.IsTrue(InstanceStartListening(Name,
    procedure(APath: string)
    begin
      Received := True;
    end), 'the stale file does not block listening');
  try
    Assert.IsTrue(InstanceTryHandOver(Name, '/tmp'), 'the new listener answers');
    Assert.IsTrue(WaitFor(Received, 3000), 'and gets the path');
  finally
    InstanceStopListening;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInstanceSocket);
{$ENDIF}

end.
