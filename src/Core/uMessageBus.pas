unit uMessageBus;

{ Event Bus / Broker (IMessageBus) for decoupled Pub/Sub communication
  between Core, MDI Windows, and Plugins as specified in ARCHITECTURE.md. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs;

const
  cTopicThemeChanged   = 'theme.changed';
  cTopicPanelNavigated = 'panel.navigated';
  cTopicJobProgress    = 'job.progress';
  /// <summary>Plugin → Dual Panel: open a URI in the active panel.
  /// Payload is TPluginPayload whose Json is {"uri":"..."}.</summary>
  cTopicPanelNavigate  = 'panel.navigate';
  /// <summary>Plugin → Dual Panel: reload every visible panel already
  /// showing this URI (do not steal the active panel). Payload Json is
  /// {"uri":"..."}.</summary>
  cTopicPanelReload    = 'panel.reload';

type
  /// <summary>Callback signature for message subscribers.</summary>
  TMessageListener = reference to procedure(const ATopic: string; const APayload: TObject);

  /// <summary>Subscription token interface for unsubscribing easily.</summary>
  ISubscription = interface
    ['{F42A7691-3E8B-4C0D-9A1E-8B7C6D5E4F32}']
    procedure Unsubscribe;
  end;

  /// <summary>Core Pub/Sub Event Bus Interface.</summary>
  IMessageBus = interface
    ['{A1B2C3D4-E5F6-7890-1234-56789ABCDEF0}']
    function Subscribe(const ATopic: string; AListener: TMessageListener): ISubscription;
    procedure Publish(const ATopic: string; APayload: TObject = nil);
    procedure Clear;
  end;

/// <summary>Returns the global singleton MessageBus instance.</summary>
function MessageBus: IMessageBus;

implementation

type
  TSubscription = class(TInterfacedObject, ISubscription)
  private
    FBus: IMessageBus;
    FTopic: string;
    FListener: TMessageListener;
  public
    constructor Create(const ABus: IMessageBus; const ATopic: string; AListener: TMessageListener);
    procedure Unsubscribe;
  end;

  TMessageBusImpl = class(TInterfacedObject, IMessageBus)
  private
    FSubscribers: TObjectDictionary<string, TList<TMessageListener>>;
    FLock: TCriticalSection;
    procedure RemoveListener(const ATopic: string; AListener: TMessageListener);
  public
    constructor Create;
    destructor Destroy; override;
    function Subscribe(const ATopic: string; AListener: TMessageListener): ISubscription;
    procedure Publish(const ATopic: string; APayload: TObject = nil);
    procedure Clear;
  end;

var
  GGlobalMessageBus: IMessageBus = nil;

function MessageBus: IMessageBus;
begin
  if GGlobalMessageBus = nil then
  begin
    GGlobalMessageBus := TMessageBusImpl.Create;
  end;
  Result := GGlobalMessageBus;
end;

{ TSubscription }

constructor TSubscription.Create(const ABus: IMessageBus; const ATopic: string; AListener: TMessageListener);
begin
  inherited Create;
  FBus := ABus;
  FTopic := ATopic;
  FListener := AListener;
end;

procedure TSubscription.Unsubscribe;
begin
  if (FBus <> nil) and Assigned(FListener) then
  begin
    (FBus as TMessageBusImpl).RemoveListener(FTopic, FListener);
    FBus := nil;
    FListener := nil;
  end;
end;

{ TMessageBusImpl }

constructor TMessageBusImpl.Create;
begin
  inherited Create;
  FSubscribers := TObjectDictionary<string, TList<TMessageListener>>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
end;

destructor TMessageBusImpl.Destroy;
begin
  FLock.Free;
  FSubscribers.Free;
  inherited Destroy;
end;

function TMessageBusImpl.Subscribe(const ATopic: string; AListener: TMessageListener): ISubscription;
var
  LList: TList<TMessageListener>;
  LKey: string;
begin
  if not Assigned(AListener) then
    Exit(nil);

  LKey := ATopic.ToLower;
  FLock.Acquire;
  try
    if not FSubscribers.TryGetValue(LKey, LList) then
    begin
      LList := TList<TMessageListener>.Create;
      FSubscribers.Add(LKey, LList);
    end;
    LList.Add(AListener);
  finally
    FLock.Release;
  end;

  Result := TSubscription.Create(Self, LKey, AListener);
end;

procedure TMessageBusImpl.RemoveListener(const ATopic: string; AListener: TMessageListener);
var
  LList: TList<TMessageListener>;
  LKey: string;
begin
  LKey := ATopic.ToLower;
  FLock.Acquire;
  try
    if FSubscribers.TryGetValue(LKey, LList) then
    begin
      LList.Remove(AListener);
      if LList.Count = 0 then
        FSubscribers.Remove(LKey);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TMessageBusImpl.Publish(const ATopic: string; APayload: TObject);
var
  LList: TList<TMessageListener>;
  LListeners: TArray<TMessageListener>;
  LListener: TMessageListener;
  LKey: string;
begin
  LKey := ATopic.ToLower;
  FLock.Acquire;
  try
    if FSubscribers.TryGetValue(LKey, LList) then
      LListeners := LList.ToArray
    else
      LListeners := nil;
  finally
    FLock.Release;
  end;

  for LListener in LListeners do
  begin
    if Assigned(LListener) then
    begin
      try
        LListener(ATopic, APayload);
      except
        // Prevent single subscriber exception from breaking bus
      end;
    end;
  end;
end;

procedure TMessageBusImpl.Clear;
begin
  FLock.Acquire;
  try
    FSubscribers.Clear;
  finally
    FLock.Release;
  end;
end;

initialization

finalization
  GGlobalMessageBus := nil;

end.
