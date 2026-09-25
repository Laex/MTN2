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
  IPanelPluginRegistry = interface
    ['{E8F1A2B3-C4D5-4E6F-8A9B-0C1D2E3F4A5B}']
    procedure RegisterPlugin(const APluginId, AScheme: string; APriority: Int64 = 100);
    procedure UnregisterPlugin(const APluginId: string);
    function ResolvePlugin(const AURI: string): string;
  end;

  TPanelPluginRegistry = class(TInterfacedObject, IPanelPluginRegistry)
  private
    type
      TPluginEntry = record
        PluginId: string;
        Scheme: string;
        Priority: Int64;
      end;
    var
      FEntries: TList<TPluginEntry>;
    procedure SortByPriority;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterPlugin(const APluginId, AScheme: string; APriority: Int64 = 100);
    procedure UnregisterPlugin(const APluginId: string);
    function ResolvePlugin(const AURI: string): string;
  end;

function PanelPluginRegistry: IPanelPluginRegistry;

implementation

constructor TPanelPluginRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TPluginEntry>.Create;
end;

destructor TPanelPluginRegistry.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TPanelPluginRegistry.SortByPriority;
var
  I, J: Integer;
  Tmp: TPluginEntry;
begin
  // Lower Priority number = earlier match (stable insertion sort) —
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

procedure TPanelPluginRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  if Trim(APluginId) = '' then
    Exit;
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
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
