unit uKeymapRegistry;

{ Open registration API for keymap bindings, so plugins can rebind existing
  actions without a compile-time-hardcoded list of built-ins. Mirrors the
  IVfsRegistry pattern (uVfsRegistry.pas): plugins call RegisterBinding at
  runtime; the registry is applied as an overlay on top of the embedded
  default + user keymap.json merge (see uKeymap.GKeymapOverlayHook).

  TKeymapAction stays a closed compile-time enum (uKeymap.pas) - plugins can
  only rebind keys to *existing* actions, not introduce new ones. That is
  a deliberate scope limit: dispatch for each action is hardcoded elsewhere
  in the app. A command that a plugin defines itself, and the chord that runs
  it, live in uCommandRegistry.pas. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uKeymap;

type
  IKeymapRegistry = interface
    ['{7C6F1A2E-9B3D-4C5A-8E1F-2D4B6A8C0E12}']
    /// <summary>Registers AKeyCombo (e.g. "Ctrl+Shift+F5") as an additional
    /// hotkey for AAction (e.g. "Copy" - see KEYMAP_ACTION_NAMES in uKeymap.pas).
    /// Ignored if AAction/AKeyCombo cannot be parsed; refused (and listed in the
    /// plugin information) if the key already belongs to another action.</summary>
    procedure RegisterBinding(const APluginId, AAction, AKeyCombo: string);
    /// <summary>Removes all bindings registered by APluginId.</summary>
    /// <summary>One line per thing the plugin registered, for the plugin's information
    /// dialog (already in the user's language).</summary>
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
  end;

function KeymapRegistry: IKeymapRegistry;

/// <summary>Parses "Ctrl+Shift+F5" style combos into a TKeyBinding. Returns
/// False if the trailing key token isn't recognized by StringToVK.</summary>
function TryParseKeyCombo(const ACombo: string; out ABinding: TKeyBinding): Boolean;

/// <summary>What owns ABinding when it is handled in code instead of the keymap
/// (cursor and editing keys, word and file jumps, clipboard keys, rectangular
/// selection, drive cycling); '' when no such handler uses it. Plugin chords are
/// consulted before these handlers, so a plugin must not take them.</summary>
function ReservedChordOwner(const ABinding: TKeyBinding): string;

/// <summary>What already uses ABinding: a keymap action (display name) or a key
/// handled in code; '' when it is free. AExceptAction is skipped, so adding a
/// key to the action that already owns it is not a clash.</summary>
function KeymapChordOwner(const ABinding: TKeyBinding;
  AExceptAction: TKeymapAction = kaNone): string;

implementation

uses
  System.UITypes, uStrings;

type
  TOverlayEntry = record
    PluginId: string;
    Action: TKeymapAction;
    Binding: TKeyBinding;
  end;

  TRejectedEntry = record
    PluginId: string;
    Action: TKeymapAction;
    Chord: string;
    Owner: string;
  end;

  TKeymapRegistry = class(TInterfacedObject, IKeymapRegistry)
  private
    FEntries: TList<TOverlayEntry>;
    FRejected: TList<TRejectedEntry>;
    procedure ApplyOverlay(var AProfile: TKeymapProfile);
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterBinding(const APluginId, AAction, AKeyCombo: string);
    function DescribePlugin(const APluginId: string): TArray<string>;
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

function IsOneOf(AKey: Word; const AKeys: array of Word): Boolean;
var
  I: Integer;
begin
  for I := Low(AKeys) to High(AKeys) do
    if AKeys[I] = AKey then
      Exit(True);
  Result := False;
end;

function ReservedChordOwner(const ABinding: TKeyBinding): string;
var
  K: Word;
  Plain: Boolean;
begin
  Result := '';
  K := ABinding.Key;
  Plain := not ABinding.Alt and not ABinding.Ctrl;
  if Plain and IsOneOf(K, [vkUp, vkDown, vkLeft, vkRight, vkPrior, vkNext,
       vkHome, vkEnd, vkBack, vkDelete, vkReturn, vkNumpad5, vkClear]) and
     not ((K = vkDelete) and ABinding.Shift) then
    Exit(T('ui.reserved.edit', 'cursor and editing keys'));
  if ABinding.Ctrl and not ABinding.Alt and
     IsOneOf(K, [vkLeft, vkRight, vkHome, vkEnd]) then
    Exit(T('ui.reserved.jump', 'word and file jumps'));
  if ABinding.Alt and ABinding.Shift and not ABinding.Ctrl and
     IsOneOf(K, [vkUp, vkDown, vkLeft, vkRight, vkPrior, vkNext, vkHome, vkEnd]) then
    Exit(T('ui.reserved.block', 'rectangular selection'));
  if ABinding.Alt and ABinding.Shift and not ABinding.Ctrl and (K = vkF3) then
    Exit(T('ui.reserved.opposite', 'workspace on the opposite panel'));
  if ((K = vkInsert) and (ABinding.Shift <> ABinding.Ctrl) and not ABinding.Alt) or
     ((K = vkDelete) and (ABinding.Shift <> ABinding.Ctrl) and not ABinding.Alt) or
     (ABinding.Ctrl and not ABinding.Alt and not ABinding.Shift and
      IsOneOf(K, [Ord('A'), Ord('C'), Ord('X'), Ord('V')])) then
    Exit(T('ui.reserved.clipboard', 'clipboard keys'));
end;

function KeymapChordOwner(const ABinding: TKeyBinding;
  AExceptAction: TKeymapAction): string;
var
  Act: TKeymapAction;
  Profile: TKeymapProfile;
  I: Integer;
begin
  Profile := ActiveKeymap;
  for Act := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
    if Act <> AExceptAction then
      for I := 0 to High(Profile.Bindings[Act]) do
        if SameKeyBinding(ABinding, Profile.Bindings[Act][I]) then
          Exit(KeymapActionDisplayName(Act));
  Result := ReservedChordOwner(ABinding);
end;

constructor TKeymapRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TOverlayEntry>.Create;
  FRejected := TList<TRejectedEntry>.Create;
end;

destructor TKeymapRegistry.Destroy;
begin
  FRejected.Free;
  FEntries.Free;
  inherited Destroy;
end;

procedure TKeymapRegistry.RegisterBinding(const APluginId, AAction, AKeyCombo: string);
var
  Entry: TOverlayEntry;
  Rej: TRejectedEntry;
  Act: TKeymapAction;
  Binding: TKeyBinding;
begin
  if not TryKeymapActionByName(AAction, Act) then
    Exit;
  if not TryParseKeyCombo(AKeyCombo, Binding) then
    Exit;

  // A key owned by another action or handled in code stays with its owner;
  // adding a key to the action that already has it is harmless.
  Rej.Owner := KeymapChordOwner(Binding, Act);
  if Rej.Owner <> '' then
  begin
    Rej.PluginId := APluginId;
    Rej.Action := Act;
    Rej.Chord := KeyBindingToStr(Binding);
    FRejected.Add(Rej);
    Exit;
  end;

  Entry.PluginId := APluginId;
  Entry.Action := Act;
  Entry.Binding := Binding;
  FEntries.Add(Entry);

  // Reapply immediately so a plugin registering after startup takes effect
  // without requiring a manual keymap reload.
  ReloadKeymap('');
end;

function TKeymapRegistry.DescribePlugin(const APluginId: string): TArray<string>;
var
  E: TOverlayEntry;
  R: TRejectedEntry;
  Lines: TList<string>;
begin
  Lines := TList<string>.Create;
  try
    for E in FEntries do
      if SameText(E.PluginId, APluginId) then
        Lines.Add(T('ui.plugininfo.key', 'Extra key %s for %s',
          [KeyBindingToStr(E.Binding), KeymapActionDisplayName(E.Action)]));
    for R in FRejected do
      if SameText(R.PluginId, APluginId) then
        Lines.Add(T('ui.plugininfo.keyTaken', 'Key %s for %s is not bound: %s already uses it',
          [R.Chord, KeymapActionDisplayName(R.Action), R.Owner]));
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

procedure TKeymapRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
  for I := FRejected.Count - 1 downto 0 do
    if SameText(FRejected[I].PluginId, APluginId) then
      FRejected.Delete(I);
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
