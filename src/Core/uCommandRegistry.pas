unit uCommandRegistry;

{ Open registration API for commands, so plugins can intercept built-in
  commands and add commands of their own. Mirrors uKeymapRegistry.pas /
  uMenuRegistry.pas / uVfsRegistry.pas.

  Built-in commands are named like the keymap actions (KEYMAP_ACTION_NAMES in
  uKeymap.pas: "Copy", "View", "Delete", ...). A hook registered for such a
  name runs before the built-in handler, from a key press on the panels, from
  the top menu, and from a global key (Help, Quit, ...). A hook that returns
  True has handled the command: the built-in handler is skipped. Hooks run in
  ascending priority order and the first one that returns True ends the chain.

  A plugin command has its own id (never a built-in name) and a handler. It
  runs from ExecuteCommand and from a key chord registered with
  RegisterCommandBinding; a chord that a built-in keymap action already owns
  stays with that action.

  Everything runs on the main thread. A hook or handler that raises is treated
  as if it had returned False / had not run, so a faulty plugin cannot break
  the command it observes. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.UITypes,
  uKeymap;

type
  /// <summary>Runs before a built-in command. AOrigin is "key" or "menu".
  /// True = handled, the built-in handler is skipped.</summary>
  TCommandHook = reference to function(const ACommand, AOrigin: string): Boolean;

  ICommandRegistry = interface
    ['{5E2B7D94-3A1C-4F68-B0D5-9C4E1A7F3B26}']
    /// <summary>Adds a hook for the built-in command ACommand (a keymap action
    /// name). An unknown name is ignored. A plugin's second hook for the same
    /// command replaces its first.</summary>
    procedure RegisterHook(const APluginId, ACommand: string; AHook: TCommandHook;
      APriority: Integer = 100);
    /// <summary>Adds the plugin command ACommandId. A built-in command name,
    /// an empty id, or an id another plugin already owns is ignored. The same
    /// plugin registering the id again replaces the handler.</summary>
    procedure RegisterCommand(const APluginId, ACommandId: string; AHandler: TProc);
    /// <summary>Binds a key combination ("Ctrl+Shift+F5") to the plugin
    /// command ACommandId. An unparsable combination is ignored.</summary>
    procedure RegisterCommandBinding(const APluginId, ACommandId, AKeyCombo: string);
    /// <summary>Sets the short label (a few characters) the function bar shows
    /// for the plugin command ACommandId on the F-key its chord is bound to.
    /// Only the owner can set it; an empty caption clears it.</summary>
    procedure SetCommandCaption(const APluginId, ACommandId, ACaption: string);
    /// <summary>The function bar label for a bound plain F-key chord, if the
    /// command has a caption.</summary>
    function TryGetFBarLabel(AKey: Word; AShift: TShiftState; out ALabel: string): Boolean;
    /// <summary>Removes the hooks, commands and bindings of APluginId.</summary>
    /// <summary>One line per thing the plugin registered, for the plugin's information
    /// dialog (already in the user's language).</summary>
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
    /// <summary>Runs the hooks of ACommand. True when one of them handled it.
    /// A hook that runs the command again (directly or not) is not asked a
    /// second time while it is still running.</summary>
    function TryIntercept(const ACommand, AOrigin: string): Boolean;
    /// <summary>Runs the plugin command ACommandId. False when no such command
    /// is registered or its handler raised.</summary>
    function TryExecute(const ACommandId: string): Boolean;
    function HasCommand(const ACommandId: string): Boolean;
    /// <summary>The plugin command bound to this key chord, if any.</summary>
    function TryMatchBinding(AKey: Word; AShift: TShiftState;
      out ACommandId: string): Boolean;
  end;

function CommandRegistry: ICommandRegistry;

/// <summary>Runs the hooks of the built-in command behind AAction. False
/// (cheaply) when no hook is registered at all.</summary>
function InterceptKeymapAction(AAction: TKeymapAction; const AOrigin: string): Boolean;

/// <summary>Runs the plugin command bound to the chord, if any. True when a
/// command ran.</summary>
function TryRunBoundCommand(AKey: Word; AShift: TShiftState): Boolean;

/// <summary>The function bar label of the plugin command bound to the F-key
/// (vkF1..vkF10) with AMods held, '' when none or it has no caption.</summary>
function PluginFBarLabel(AKey: Word; AMods: TShiftState): string;

implementation

uses
  uStrings,
  uKeymapRegistry;

type
  THookEntry = record
    PluginId: string;
    Command: string;
    Hook: TCommandHook;
    Priority: Integer;
  end;

  TCommandEntry = record
    PluginId: string;
    CommandId: string;
    Handler: TProc;
    Caption: string;
  end;

  TBindingEntry = record
    PluginId: string;
    CommandId: string;
    Binding: TKeyBinding;
  end;

  TCommandRegistry = class(TInterfacedObject, ICommandRegistry)
  private
    FHooks: TList<THookEntry>;
    FCommands: TList<TCommandEntry>;
    FBindings: TList<TBindingEntry>;
    FRunning: TList<string>;
    function IndexOfCommand(const ACommandId: string): Integer;
    procedure SortHooks;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterHook(const APluginId, ACommand: string; AHook: TCommandHook;
      APriority: Integer = 100);
    procedure RegisterCommand(const APluginId, ACommandId: string; AHandler: TProc);
    procedure RegisterCommandBinding(const APluginId, ACommandId, AKeyCombo: string);
    procedure SetCommandCaption(const APluginId, ACommandId, ACaption: string);
    function TryGetFBarLabel(AKey: Word; AShift: TShiftState; out ALabel: string): Boolean;
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
    function TryIntercept(const ACommand, AOrigin: string): Boolean;
    function TryExecute(const ACommandId: string): Boolean;
    function HasCommand(const ACommandId: string): Boolean;
    function TryMatchBinding(AKey: Word; AShift: TShiftState;
      out ACommandId: string): Boolean;
    function HookCount: Integer;
    function BindingCount: Integer;
  end;

var
  GRegistryObj: TCommandRegistry;
  GRegistry: ICommandRegistry;

function IsBuiltInCommandName(const AName: string): Boolean;
var
  Act: TKeymapAction;
begin
  Result := TryKeymapActionByName(AName, Act);
end;

constructor TCommandRegistry.Create;
begin
  inherited Create;
  FHooks := TList<THookEntry>.Create;
  FCommands := TList<TCommandEntry>.Create;
  FBindings := TList<TBindingEntry>.Create;
  FRunning := TList<string>.Create;
end;

destructor TCommandRegistry.Destroy;
begin
  FRunning.Free;
  FBindings.Free;
  FCommands.Free;
  FHooks.Free;
  inherited Destroy;
end;

function TCommandRegistry.IndexOfCommand(const ACommandId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FCommands.Count - 1 do
    if SameText(FCommands[I].CommandId, ACommandId) then
      Exit(I);
  Result := -1;
end;

procedure TCommandRegistry.SortHooks;
var
  I, J: Integer;
  Tmp: THookEntry;
begin
  // Lower Priority number = earlier (stable insertion sort).
  for I := 1 to FHooks.Count - 1 do
  begin
    Tmp := FHooks[I];
    J := I - 1;
    while (J >= 0) and (FHooks[J].Priority > Tmp.Priority) do
    begin
      FHooks[J + 1] := FHooks[J];
      Dec(J);
    end;
    FHooks[J + 1] := Tmp;
  end;
end;

procedure TCommandRegistry.RegisterHook(const APluginId, ACommand: string;
  AHook: TCommandHook; APriority: Integer);
var
  E: THookEntry;
  Act: TKeymapAction;
  I: Integer;
begin
  if (Trim(APluginId) = '') or not Assigned(AHook) or
     not TryKeymapActionByName(ACommand, Act) then
    Exit;
  E.PluginId := Trim(APluginId);
  E.Command := KeymapActionDisplayName(Act);
  E.Hook := AHook;
  E.Priority := APriority;
  for I := 0 to FHooks.Count - 1 do
    if SameText(FHooks[I].PluginId, E.PluginId) and
       SameText(FHooks[I].Command, E.Command) then
    begin
      FHooks[I] := E;
      SortHooks;
      Exit;
    end;
  FHooks.Add(E);
  SortHooks;
end;

procedure TCommandRegistry.RegisterCommand(const APluginId, ACommandId: string;
  AHandler: TProc);
var
  E: TCommandEntry;
  I: Integer;
begin
  E.PluginId := Trim(APluginId);
  E.CommandId := Trim(ACommandId);
  E.Handler := AHandler;
  if (E.PluginId = '') or (E.CommandId = '') or not Assigned(AHandler) or
     IsBuiltInCommandName(E.CommandId) then
    Exit;
  I := IndexOfCommand(E.CommandId);
  if I < 0 then
    FCommands.Add(E)
  else if SameText(FCommands[I].PluginId, E.PluginId) then
    FCommands[I] := E;
end;

procedure TCommandRegistry.RegisterCommandBinding(const APluginId, ACommandId,
  AKeyCombo: string);
var
  E: TBindingEntry;
  I: Integer;
begin
  E.PluginId := Trim(APluginId);
  E.CommandId := Trim(ACommandId);
  if (E.PluginId = '') or (E.CommandId = '') or
     not TryParseKeyCombo(AKeyCombo, E.Binding) then
    Exit;
  I := IndexOfCommand(E.CommandId);
  if (I < 0) or not SameText(FCommands[I].PluginId, E.PluginId) then
    Exit;
  FBindings.Add(E);
end;

procedure TCommandRegistry.SetCommandCaption(const APluginId, ACommandId, ACaption: string);
var
  I: Integer;
  E: TCommandEntry;
begin
  I := IndexOfCommand(Trim(ACommandId));
  if (I < 0) or not SameText(FCommands[I].PluginId, Trim(APluginId)) then
    Exit;
  E := FCommands[I];
  E.Caption := Trim(ACaption);
  FCommands[I] := E;
end;

function TCommandRegistry.TryGetFBarLabel(AKey: Word; AShift: TShiftState;
  out ALabel: string): Boolean;
var
  Id: string;
  I: Integer;
begin
  ALabel := '';
  if not TryMatchBinding(AKey, AShift, Id) then
    Exit(False);
  I := IndexOfCommand(Id);
  if (I < 0) or (FCommands[I].Caption = '') then
    Exit(False);
  ALabel := FCommands[I].Caption;
  Result := True;
end;

function TCommandRegistry.DescribePlugin(const APluginId: string): TArray<string>;
var
  E: TCommandEntry;
  B: TBindingEntry;
  H: THookEntry;
  Lines: TList<string>;
  Chords, Hooked, Line: string;
begin
  Lines := TList<string>.Create;
  try
    for E in FCommands do
      if SameText(E.PluginId, APluginId) then
      begin
        Chords := '';
        for B in FBindings do
          if SameText(B.PluginId, APluginId) and SameText(B.CommandId, E.CommandId) then
          begin
            if Chords <> '' then
              Chords := Chords + ', ';
            Chords := Chords + KeyBindingToStr(B.Binding);
          end;
        Line := T('ui.plugininfo.command', 'Command %s', [E.CommandId]);
        if Chords <> '' then
          Line := Line + T('ui.plugininfo.commandKey', ', key %s', [Chords]);
        if E.Caption <> '' then
          Line := Line + T('ui.plugininfo.commandLabel', ', bar label "%s"', [E.Caption]);
        Lines.Add(Line);
      end;
    Hooked := '';
    for H in FHooks do
      if SameText(H.PluginId, APluginId) then
      begin
        if Hooked <> '' then
          Hooked := Hooked + ', ';
        Hooked := Hooked + H.Command;
      end;
    if Hooked <> '' then
      Lines.Add(T('ui.plugininfo.hooks', 'Watches or replaces commands: %s', [Hooked]));
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

procedure TCommandRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FHooks.Count - 1 downto 0 do
    if SameText(FHooks[I].PluginId, APluginId) then
      FHooks.Delete(I);
  for I := FCommands.Count - 1 downto 0 do
    if SameText(FCommands[I].PluginId, APluginId) then
      FCommands.Delete(I);
  for I := FBindings.Count - 1 downto 0 do
    if SameText(FBindings[I].PluginId, APluginId) then
      FBindings.Delete(I);
end;

function TCommandRegistry.TryIntercept(const ACommand, AOrigin: string): Boolean;
var
  Snapshot: TArray<THookEntry>;
  E: THookEntry;
begin
  Result := False;
  if FHooks.Count = 0 then
    Exit;
  if FRunning.IndexOf(LowerCase(ACommand)) >= 0 then
    Exit;
  // A hook may unregister its plugin or register more hooks while it runs.
  Snapshot := FHooks.ToArray;
  FRunning.Add(LowerCase(ACommand));
  try
    for E in Snapshot do
      if SameText(E.Command, ACommand) then
      begin
        try
          if E.Hook(ACommand, AOrigin) then
            Exit(True);
        except
          // A faulty hook counts as "not handled".
        end;
      end;
  finally
    FRunning.Remove(LowerCase(ACommand));
  end;
end;

function TCommandRegistry.TryExecute(const ACommandId: string): Boolean;
var
  I: Integer;
  Handler: TProc;
begin
  I := IndexOfCommand(ACommandId);
  if I < 0 then
    Exit(False);
  Handler := FCommands[I].Handler;
  try
    Handler();
    Result := True;
  except
    Result := False;
  end;
end;

function TCommandRegistry.HasCommand(const ACommandId: string): Boolean;
begin
  Result := IndexOfCommand(ACommandId) >= 0;
end;

function TCommandRegistry.TryMatchBinding(AKey: Word; AShift: TShiftState;
  out ACommandId: string): Boolean;
var
  E: TBindingEntry;
begin
  ACommandId := '';
  for E in FBindings do
    if (E.Binding.Key = AKey) and (E.Binding.Shift = (ssShift in AShift)) and
       (E.Binding.Alt = (ssAlt in AShift)) and (E.Binding.Ctrl = (ssCtrl in AShift)) then
    begin
      ACommandId := E.CommandId;
      Exit(True);
    end;
  Result := False;
end;

function TCommandRegistry.HookCount: Integer;
begin
  Result := FHooks.Count;
end;

function TCommandRegistry.BindingCount: Integer;
begin
  Result := FBindings.Count;
end;

function CommandRegistry: ICommandRegistry;
begin
  if GRegistry = nil then
  begin
    GRegistryObj := TCommandRegistry.Create;
    GRegistry := GRegistryObj;
  end;
  Result := GRegistry;
end;

function InterceptKeymapAction(AAction: TKeymapAction; const AOrigin: string): Boolean;
begin
  if (AAction = kaNone) or (GRegistryObj = nil) or (GRegistryObj.HookCount = 0) then
    Exit(False);
  Result := GRegistryObj.TryIntercept(KeymapActionDisplayName(AAction), AOrigin);
end;

function TryRunBoundCommand(AKey: Word; AShift: TShiftState): Boolean;
var
  CommandId: string;
begin
  if (GRegistryObj = nil) or (GRegistryObj.BindingCount = 0) then
    Exit(False);
  Result := GRegistryObj.TryMatchBinding(AKey, AShift, CommandId) and
    GRegistryObj.TryExecute(CommandId);
end;

function PluginFBarLabel(AKey: Word; AMods: TShiftState): string;
begin
  Result := '';
  if (GRegistryObj <> nil) and (GRegistryObj.BindingCount > 0) then
    GRegistryObj.TryGetFBarLabel(AKey, AMods, Result);
end;

initialization

finalization
  GRegistry := nil;
  GRegistryObj := nil;

end.
