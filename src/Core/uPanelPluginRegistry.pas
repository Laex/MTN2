unit uPanelPluginRegistry;

{ File Panel Plugin Registry: Resolves URI scheme / predicate to bound Panel Plugin
  and IPanelModel instances for cross-platform x64 architecture. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uVfsTypes;

const
  cDefaultPanelPluginId = 'mtn.plugin.default_file';

type
  /// <summary>Runs when the user activates a row (Enter, double click) of a
  /// panel whose URI has the scheme the handler was registered for. True =
  /// the plugin dealt with the row (the host does nothing more). A directory
  /// row and a file row both come here; the ".." row does not.</summary>
  TPanelActivateHandler = reference to function(const APanelURI, ARowURI: string;
    AIsDirectory: Boolean): Boolean;

  IPanelPluginRegistry = interface
    ['{E8F1A2B3-C4D5-4E6F-8A9B-0C1D2E3F4A5B}']
    procedure RegisterPlugin(const APluginId, AScheme: string; APriority: Int64 = 100);
    /// <summary>One line per thing the plugin registered, for the plugin's information
    /// dialog (already in the user's language).</summary>
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
    function ResolvePlugin(const AURI: string): string;
    /// <summary>Adds the activation handler of APluginId for panels showing
    /// AScheme ("file" for local folders). A plugin's second handler for the
    /// same scheme replaces its first. Handlers run in registration order.</summary>
    procedure RegisterActivateHandler(const APluginId, AScheme: string;
      AHandler: TPanelActivateHandler);
    /// <summary>Asks the handlers of the panel's scheme; True when one handled
    /// the row. A handler that raises counts as not handled.</summary>
    function TryActivate(const APanelURI, ARowURI: string; AIsDirectory: Boolean): Boolean;
  end;

  TPanelPluginRegistry = class(TInterfacedObject, IPanelPluginRegistry)
  private
    type
      TPluginEntry = record
        PluginId: string;
        Scheme: string;
        Priority: Int64;
      end;
      TActivateEntry = record
        PluginId: string;
        Scheme: string;
        Handler: TPanelActivateHandler;
      end;
    var
      FEntries: TList<TPluginEntry>;
      FActivate: TList<TActivateEntry>;
    procedure SortByPriority;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterPlugin(const APluginId, AScheme: string; APriority: Int64 = 100);
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
    function ResolvePlugin(const AURI: string): string;
    procedure RegisterActivateHandler(const APluginId, AScheme: string;
      AHandler: TPanelActivateHandler);
    function TryActivate(const APanelURI, ARowURI: string; AIsDirectory: Boolean): Boolean;
  end;

function PanelPluginRegistry: IPanelPluginRegistry;

implementation

uses
  uStrings;

constructor TPanelPluginRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TPluginEntry>.Create;
  FActivate := TList<TActivateEntry>.Create;
end;

destructor TPanelPluginRegistry.Destroy;
begin
  FActivate.Free;
  FEntries.Free;
  inherited Destroy;
end;

function SchemeOfUri(const AURI: string): string;
var
  P: Integer;
begin
  P := Pos('://', AURI);
  if P > 0 then
    Result := Copy(AURI, 1, P - 1).ToLower
  else
    Result := 'file';
end;

procedure TPanelPluginRegistry.RegisterActivateHandler(const APluginId, AScheme: string;
  AHandler: TPanelActivateHandler);
var
  E: TActivateEntry;
  I: Integer;
begin
  E.PluginId := Trim(APluginId);
  E.Scheme := LowerCase(Trim(AScheme));
  E.Handler := AHandler;
  if (E.PluginId = '') or (E.Scheme = '') or not Assigned(AHandler) then
    Exit;
  for I := 0 to FActivate.Count - 1 do
    if SameText(FActivate[I].PluginId, E.PluginId) and (FActivate[I].Scheme = E.Scheme) then
    begin
      FActivate[I] := E;
      Exit;
    end;
  FActivate.Add(E);
end;

function TPanelPluginRegistry.TryActivate(const APanelURI, ARowURI: string;
  AIsDirectory: Boolean): Boolean;
var
  Snapshot: TArray<TActivateEntry>;
  E: TActivateEntry;
  Scheme: string;
begin
  Result := False;
  if FActivate.Count = 0 then
    Exit;
  Scheme := SchemeOfUri(APanelURI);
  // A handler may unregister its plugin while it runs.
  Snapshot := FActivate.ToArray;
  for E in Snapshot do
    if E.Scheme = Scheme then
    begin
      try
        if E.Handler(APanelURI, ARowURI, AIsDirectory) then
          Exit(True);
      except
        // A faulty handler counts as "not handled".
      end;
    end;
end;

procedure TPanelPluginRegistry.SortByPriority;
var
  I, J: Integer;
  Tmp: TPluginEntry;
begin
  // Lower Priority number = earlier match (stable insertion sort) -
  // mirrors TVfsRegistry.SortByPriority in uVfsRegistry.pas.
  for I := 1 to FEntries.Count - 1 do
  begin
    Tmp := FEntries[I];
    J := I - 1;
    while (J >= 0) and (FEntries[J].Priority > Tmp.Priority) do
    begin
      FEntries[J + 1] := FEntries[J];
      Dec(J);
    end;
    FEntries[J + 1] := Tmp;
  end;
end;

procedure TPanelPluginRegistry.RegisterPlugin(const APluginId, AScheme: string; APriority: Int64);
var
  LEntry: TPluginEntry;
begin
  LEntry.PluginId := APluginId;
  LEntry.Scheme := AScheme.ToLower;
  LEntry.Priority := APriority;
  FEntries.Add(LEntry);
  SortByPriority;
end;

function TPanelPluginRegistry.ResolvePlugin(const AURI: string): string;
var
  LScheme: string;
  LEntry: TPluginEntry;
  LPos: Integer;
begin
  LPos := Pos('://', AURI);
  if LPos > 0 then
    LScheme := Copy(AURI, 1, LPos - 1).ToLower
  else
    LScheme := 'file';

  for LEntry in FEntries do
  begin
    if LEntry.Scheme = LScheme then
      Exit(LEntry.PluginId);
  end;

  Result := cDefaultPanelPluginId;
end;

function TPanelPluginRegistry.DescribePlugin(const APluginId: string): TArray<string>;
var
  E: TActivateEntry;
  Lines: TList<string>;
begin
  Lines := TList<string>.Create;
  try
    for E in FActivate do
      if SameText(E.PluginId, APluginId) then
        Lines.Add(T('ui.plugininfo.activate', 'Handles Enter on panels showing %s://', [E.Scheme]));
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

procedure TPanelPluginRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  if Trim(APluginId) = '' then
    Exit;
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
  for I := FActivate.Count - 1 downto 0 do
    if SameText(FActivate[I].PluginId, APluginId) then
      FActivate.Delete(I);
end;

var
  GPanelPluginRegistry: IPanelPluginRegistry;

function PanelPluginRegistry: IPanelPluginRegistry;
begin
  if GPanelPluginRegistry = nil then
    GPanelPluginRegistry := TPanelPluginRegistry.Create;
  Result := GPanelPluginRegistry;
end;

initialization

finalization
  GPanelPluginRegistry := nil;

end.
