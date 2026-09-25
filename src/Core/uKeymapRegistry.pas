unit uKeymapRegistry;

{ Open registration API for keymap bindings, so plugins can rebind existing
  actions without a compile-time-hardcoded list of built-ins. Mirrors the
  IVfsRegistry pattern (uVfsRegistry.pas): plugins call RegisterBinding at
  runtime; the registry is applied as an overlay on top of the embedded
  default + user keymap.json merge (see uKeymap.GKeymapOverlayHook).

  TKeymapAction stays a closed compile-time enum (uKeymap.pas) — plugins can
  only rebind keys to *existing* actions, not introduce new ones. That is
  a deliberate scope limit: dispatch for each action is still hardcoded
  elsewhere in the app, so a "new action" would need a matching dispatch
  handler to do anything. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uKeymap;

type
  IKeymapRegistry = interface
    ['{7C6F1A2E-9B3D-4C5A-8E1F-2D4B6A8C0E12}']
    /// <summary>Registers AKeyCombo (e.g. "Ctrl+Shift+F5") as an additional
    /// hotkey for AAction (e.g. "Copy" — see KEYMAP_ACTION_NAMES in uKeymap.pas).
    /// Silently ignored if AAction/AKeyCombo cannot be parsed.</summary>
    procedure RegisterBinding(const APluginId, AAction, AKeyCombo: string);
    /// <summary>Removes all bindings registered by APluginId.</summary>
    procedure UnregisterPlugin(const APluginId: string);
  end;

function KeymapRegistry: IKeymapRegistry;

/// <summary>Parses "Ctrl+Shift+F5" style combos into a TKeyBinding. Returns
/// False if the trailing key token isn't recognized by StringToVK.</summary>
function TryParseKeyCombo(const ACombo: string; out ABinding: TKeyBinding): Boolean;

implementation

type
  TOverlayEntry = record
    PluginId: string;
    Action: TKeymapAction;
    Binding: TKeyBinding;
  end;

  TKeymapRegistry = class(TInterfacedObject, IKeymapRegistry)
  private
    FEntries: TList<TOverlayEntry>;
    procedure ApplyOverlay(var AProfile: TKeymapProfile);
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterBinding(const APluginId, AAction, AKeyCombo: string);
    procedure UnregisterPlugin(const APluginId: string);
  end;

function TryParseKeyCombo(const ACombo: string; out ABinding: TKeyBinding): Boolean;
var
  Parts: TArray<string>;
  I: Integer;
  Token: string;
  VK: Word;
  ShiftB, AltB, CtrlB: Boolean;
begin
  ABinding := KeyBinding(0);
  Result := False;
  Parts := ACombo.Split(['+']);
  if Length(Parts) = 0 then
    Exit;

  ShiftB := False;
  AltB := False;
  CtrlB := False;
  for I := 0 to High(Parts) - 1 do
  begin
    Token := UpperCase(Trim(Parts[I]));
    if Token = 'CTRL' then CtrlB := True
    else if Token = 'ALT' then AltB := True
    else if Token = 'SHIFT' then ShiftB := True;
  end;

  VK := StringToVK(Trim(Parts[High(Parts)]));
  if VK = 0 then
    Exit;

  ABinding := KeyBinding(VK, ShiftB, AltB, CtrlB);
  Result := True;
end;

constructor TKeymapRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TOverlayEntry>.Create;
end;

destructor TKeymapRegistry.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TKeymapRegistry.RegisterBinding(const APluginId, AAction, AKeyCombo: string);
var
  Entry: TOverlayEntry;
  Act: TKeymapAction;
  Binding: TKeyBinding;
begin
  if not TryKeymapActionByName(AAction, Act) then
    Exit;
  if not TryParseKeyCombo(AKeyCombo, Binding) then
    Exit;

  Entry.PluginId := APluginId;
  Entry.Action := Act;
  Entry.Binding := Binding;
  FEntries.Add(Entry);

  // Reapply immediately so a plugin registering after startup takes effect
  // without requiring a manual keymap reload.
  ReloadKeymap('');
end;

procedure TKeymapRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
  if KeymapCacheLoaded then
    ReloadKeymap('');
end;

procedure TKeymapRegistry.ApplyOverlay(var AProfile: TKeymapProfile);
var
  Entry: TOverlayEntry;
begin
  for Entry in FEntries do
    AddBinding(AProfile, Entry.Action, Entry.Binding);
end;

var
  GRegistryObj: TKeymapRegistry;
  GRegistry: IKeymapRegistry;

function KeymapRegistry: IKeymapRegistry;
begin
  if GRegistry = nil then
  begin
    GRegistryObj := TKeymapRegistry.Create;
    GRegistry := GRegistryObj;
  end;
  Result := GRegistry;
end;

initialization
  GKeymapOverlayHook :=
    procedure(var AProfile: TKeymapProfile)
    begin
      KeymapRegistry; // ensure GRegistryObj is created
      GRegistryObj.ApplyOverlay(AProfile);
    end;

finalization
  GKeymapOverlayHook := nil;
  GRegistry := nil;
  GRegistryObj := nil;

end.
