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
  RegisterCommandBinding; a chord that a built-in keymap action or an earlier
  plugin command already owns stays with its owner: the binding is refused and
  the plugin's information dialog says so.

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

  /// <summary>A plugin command as the command palette lists it.</summary>
  TPluginCommandInfo = record
    PluginId: string;
    CommandId: string;
    /// <summary>The label the plugin gave the command; '' when none.</summary>
    Caption: string;
    /// <summary>The key chord bound to the command; '' when none.</summary>
    Chord: string;
    /// <summary>The chord the plugin itself gave the command; '' when none.</summary>
    DefaultChord: string;
  end;

  ICommandRegistry = interface
    ['{5E2B7D94-3A1C-4F68-B0D5-9C4E1A7F3B26}']
    /// <summary>Every plugin command, in registration order.</summary>
    function ListCommands: TArray<TPluginCommandInfo>;
    /// <summary>Adds a hook for the built-in command ACommand (a keymap action
    /// name). An unknown name is ignored. A plugin's second hook for the same
    /// command replaces its first.</summary>
    procedure RegisterHook(const APluginId, ACommand: string; AHook: TCommandHook;
      APriority: Integer = 100);
    /// <summary>Adds the plugin command ACommandId. A built-in command name,
    /// an empty id, or an id another plugin already owns is ignored. The same
    /// plugin registering the id again replaces the handler.</summary>
    procedure RegisterCommand(const APluginId, ACommandId: string; AHandler: TProc);
    /// <summary>Gives a plugin menu item a command of the same id, running the
    /// item, so a key can be bound to it. Nothing happens when that id already
    /// names a command or a built-in command.</summary>
    procedure RegisterMenuCommand(const APluginId, ACommandId: string; AHandler: TProc);
    /// <summary>Drops the command RegisterMenuCommand made for the item.</summary>
    procedure RemoveMenuCommand(const APluginId, ACommandId: string);
    /// <summary>Binds a key combination ("Ctrl+Shift+F5") to the plugin
    /// command ACommandId. An unparsable combination is ignored.</summary>
    procedure RegisterCommandBinding(const APluginId, ACommandId, AKeyCombo: string);
    /// <summary>Reads the key chords the user gave to plugin commands from the
    /// JSON file APath (command id -> chord) and writes later changes back to
    /// it. A chord there replaces the one the plugin registers; an empty chord
    /// leaves the command without a key. A missing or malformed file changes
    /// nothing.</summary>
    procedure UseUserBindings(const APath: string);
    /// <summary>Gives the plugin command ACommandId the user's chord
    /// AKeyCombo ('' = no key) in place of the plugin's own. False with AError
    /// set when the command is unknown, the text is not one key chord, or a
    /// built-in action, a key handled in code or another plugin command
    /// already uses the chord (AError names the owner).</summary>
    function SetUserBinding(const ACommandId, AKeyCombo: string;
      out AError: string): Boolean;
    /// <summary>Drops the user's chord of ACommandId: the plugin's own chord
    /// applies again.</summary>
    procedure ResetUserBinding(const ACommandId: string);
    /// <summary>Sets the short label (a few characters) the function bar shows
    /// for the plugin command ACommandId on the F-key its chord is bound to.
    /// Only the owner can set it; an empty caption clears it.</summary>
    procedure SetCommandCaption(const APluginId, ACommandId, ACaption: string);
    /// <summary>The function bar label for a bound plain F-key chord, if the
    /// command has a caption.</summary>
    function TryGetFBarLabel(AKey: Word; AShift: TShiftState; out ALabel: string): Boolean;
    /// <summary>Marks APluginId as declarative: its commands and chords come from its
    /// manifest (DeclareCommand), ALoad loads the plugin when one of them is used,
    /// and a command or chord the plugin registers without having declared it is
    /// refused and reported in its information.</summary>
    /// AOpen: the plugin may also register commands the manifest does not list
    /// (macros, for example); the listed ones still get their stubs.
    procedure DeclarePlugin(const APluginId: string; ALoad: TFunc<Boolean>;
      AOpen: Boolean = False);
    /// <summary>Adds a command from a manifest: listed and bound right away, it
    /// loads the plugin when it runs. AKeyCombo '' = no chord.</summary>
    procedure DeclareCommand(const APluginId, ACommandId, ACaption, AKeyCombo: string);
    /// <summary>Loads a declarative plugin through the function given to
    /// DeclarePlugin. False when it is not declarative or did not load.</summary>
    function LoadDeclared(const APluginId: string): Boolean;
    /// <summary>Called after a declarative plugin loaded: a declared command the
    /// plugin did not register is dropped and reported in its information.</summary>
    procedure ReconcilePlugin(const APluginId: string);
    /// <summary>Forgets what the manifest of APluginId declared (and its stubs).</summary>
    procedure ForgetDeclared(const APluginId: string);
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
    /// <summary>The key chord most recently bound to the plugin command, '' when none.</summary>
    function CommandChordText(const ACommandId: string): string;
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
  System.IOUtils, System.JSON,
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
    /// <summary>Declared by a manifest, not registered by the plugin yet.</summary>
    Stub: Boolean;
    /// <summary>Made for a plugin menu item (RegisterMenuCommand).</summary>
    FromMenu: Boolean;
  end;

  TDeclaredCommand = record
    PluginId: string;
    CommandId: string;
    Key: string;
  end;

  TDeclaredPlugin = record
    PluginId: string;
    Load: TFunc<Boolean>;
    /// <summary>Registrations beyond the manifest are accepted.</summary>
    Open: Boolean;
  end;

  TCommandNote = record
    PluginId: string;
    Text: string;
  end;

  TBindingEntry = record
    PluginId: string;
    CommandId: string;
    Binding: TKeyBinding;
  end;

  TRejectedBinding = record
    PluginId: string;
    CommandId: string;
    Chord: string;
    Owner: string;
  end;

  TCommandRegistry = class(TInterfacedObject, ICommandRegistry)
  private
    FHooks: TList<THookEntry>;
    FCommands: TList<TCommandEntry>;
    FBindings: TList<TBindingEntry>;
    FRejected: TList<TRejectedBinding>;
    FDeclaredPlugins: TList<TDeclaredPlugin>;
    FDeclared: TList<TDeclaredCommand>;
    FNotes: TList<TCommandNote>;
    FRunning: TList<string>;
    /// <summary>Lower-cased command id -> the user's chord ('' = no key).</summary>
    FUserKeys: TDictionary<string, string>;
    /// <summary>Lower-cased command id -> the first chord the plugin registered.</summary>
    FDefaultKeys: TDictionary<string, string>;
    FUserKeysPath: string;
    procedure SaveUserKeys;
    procedure ApplyUserBinding(const ACommandId: string);
    procedure DropBindings(const ACommandId: string);
    function IsDeclarative(const APluginId: string): Boolean;
    function IsStrict(const APluginId: string): Boolean;
    function IsDeclared(const APluginId, ACommandId: string): Boolean;
    function DeclaredBinding(const APluginId, ACommandId: string;
      out ABinding: TKeyBinding): Boolean;
    procedure Note(const APluginId, AText: string);
    function IndexOfCommand(const ACommandId: string): Integer;
    function ChordOwner(const ABinding: TKeyBinding; const ACommandId: string): string;
    procedure SortHooks;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterHook(const APluginId, ACommand: string; AHook: TCommandHook;
      APriority: Integer = 100);
    procedure RegisterCommand(const APluginId, ACommandId: string; AHandler: TProc);
    procedure RegisterMenuCommand(const APluginId, ACommandId: string; AHandler: TProc);
    procedure RemoveMenuCommand(const APluginId, ACommandId: string);
    procedure RegisterCommandBinding(const APluginId, ACommandId, AKeyCombo: string);
    procedure UseUserBindings(const APath: string);
    function SetUserBinding(const ACommandId, AKeyCombo: string;
      out AError: string): Boolean;
    procedure ResetUserBinding(const ACommandId: string);
    procedure DeclarePlugin(const APluginId: string; ALoad: TFunc<Boolean>;
      AOpen: Boolean = False);
    procedure DeclareCommand(const APluginId, ACommandId, ACaption, AKeyCombo: string);
    function LoadDeclared(const APluginId: string): Boolean;
    procedure ReconcilePlugin(const APluginId: string);
    procedure ForgetDeclared(const APluginId: string);
    procedure SetCommandCaption(const APluginId, ACommandId, ACaption: string);
    function TryGetFBarLabel(AKey: Word; AShift: TShiftState; out ALabel: string): Boolean;
    function DescribePlugin(const APluginId: string): TArray<string>;
    function ListCommands: TArray<TPluginCommandInfo>;
    procedure UnregisterPlugin(const APluginId: string);
    function TryIntercept(const ACommand, AOrigin: string): Boolean;
    function TryExecute(const ACommandId: string): Boolean;
    function HasCommand(const ACommandId: string): Boolean;
    function CommandChordText(const ACommandId: string): string;
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
  FRejected := TList<TRejectedBinding>.Create;
  FDeclaredPlugins := TList<TDeclaredPlugin>.Create;
  FDeclared := TList<TDeclaredCommand>.Create;
  FNotes := TList<TCommandNote>.Create;
  FRunning := TList<string>.Create;
  FUserKeys := TDictionary<string, string>.Create;
  FDefaultKeys := TDictionary<string, string>.Create;
end;

destructor TCommandRegistry.Destroy;
begin
  FDefaultKeys.Free;
  FUserKeys.Free;
  FRunning.Free;
  FNotes.Free;
  FDeclared.Free;
  FDeclaredPlugins.Free;
  FRejected.Free;
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
  E := Default(TCommandEntry);
  E.PluginId := Trim(APluginId);
  E.CommandId := Trim(ACommandId);
  E.Handler := AHandler;
  if (E.PluginId = '') or (E.CommandId = '') or not Assigned(AHandler) or
     IsBuiltInCommandName(E.CommandId) then
    Exit;
  if IsStrict(E.PluginId) and not IsDeclared(E.PluginId, E.CommandId) then
  begin
    Note(E.PluginId, T('ui.plugininfo.notDeclared',
      '%s is not declared in plugin.json and was not registered', [E.CommandId]));
    Exit;
  end;
  I := IndexOfCommand(E.CommandId);
  if I < 0 then
  begin
    FCommands.Add(E);
    ApplyUserBinding(E.CommandId);
  end
  else if SameText(FCommands[I].PluginId, E.PluginId) then
  begin
    // The label the manifest gave stays until the plugin sets its own.
    E.Caption := FCommands[I].Caption;
    FCommands[I] := E;
  end;
end;

procedure TCommandRegistry.RegisterMenuCommand(const APluginId, ACommandId: string;
  AHandler: TProc);
var
  E: TCommandEntry;
begin
  E := Default(TCommandEntry);
  E.PluginId := Trim(APluginId);
  E.CommandId := Trim(ACommandId);
  E.Handler := AHandler;
  E.FromMenu := True;
  if (E.PluginId = '') or (E.CommandId = '') or not Assigned(AHandler) or
     IsBuiltInCommandName(E.CommandId) or (IndexOfCommand(E.CommandId) >= 0) then
    Exit;
  FCommands.Add(E);
  ApplyUserBinding(E.CommandId);
end;

procedure TCommandRegistry.RemoveMenuCommand(const APluginId, ACommandId: string);
var
  I: Integer;
begin
  I := IndexOfCommand(Trim(ACommandId));
  if (I < 0) or not FCommands[I].FromMenu or
     not SameText(FCommands[I].PluginId, Trim(APluginId)) then
    Exit;
  DropBindings(FCommands[I].CommandId);
  FDefaultKeys.Remove(LowerCase(FCommands[I].CommandId));
  FCommands.Delete(I);
end;

function TCommandRegistry.IsStrict(const APluginId: string): Boolean;
var
  P: TDeclaredPlugin;
begin
  for P in FDeclaredPlugins do
    if SameText(P.PluginId, APluginId) then
      Exit(not P.Open);
  Result := False;
end;

function TCommandRegistry.IsDeclarative(const APluginId: string): Boolean;
var
  P: TDeclaredPlugin;
begin
  for P in FDeclaredPlugins do
    if SameText(P.PluginId, APluginId) then
      Exit(True);
  Result := False;
end;

function TCommandRegistry.IsDeclared(const APluginId, ACommandId: string): Boolean;
var
  D: TDeclaredCommand;
begin
  for D in FDeclared do
    if SameText(D.PluginId, APluginId) and SameText(D.CommandId, ACommandId) then
      Exit(True);
  Result := False;
end;

function TCommandRegistry.DeclaredBinding(const APluginId, ACommandId: string;
  out ABinding: TKeyBinding): Boolean;
var
  D: TDeclaredCommand;
begin
  for D in FDeclared do
    if SameText(D.PluginId, APluginId) and SameText(D.CommandId, ACommandId) then
      Exit((D.Key <> '') and TryParseKeyCombo(D.Key, ABinding));
  Result := False;
end;

procedure TCommandRegistry.Note(const APluginId, AText: string);
var
  N: TCommandNote;
begin
  for N in FNotes do
    if SameText(N.PluginId, APluginId) and (N.Text = AText) then
      Exit;
  N.PluginId := APluginId;
  N.Text := AText;
  FNotes.Add(N);
end;

procedure TCommandRegistry.DeclarePlugin(const APluginId: string; ALoad: TFunc<Boolean>;
  AOpen: Boolean);
var
  P: TDeclaredPlugin;
  I: Integer;
begin
  P.PluginId := Trim(APluginId);
  P.Load := ALoad;
  P.Open := AOpen;
  if P.PluginId = '' then
    Exit;
  for I := 0 to FDeclaredPlugins.Count - 1 do
    if SameText(FDeclaredPlugins[I].PluginId, P.PluginId) then
    begin
      FDeclaredPlugins[I] := P;
      Exit;
    end;
  FDeclaredPlugins.Add(P);
end;

procedure TCommandRegistry.DeclareCommand(const APluginId, ACommandId, ACaption,
  AKeyCombo: string);
var
  D: TDeclaredCommand;
  E: TCommandEntry;
  I: Integer;
begin
  D.PluginId := Trim(APluginId);
  D.CommandId := Trim(ACommandId);
  D.Key := Trim(AKeyCombo);
  if (D.PluginId = '') or (D.CommandId = '') or not IsDeclarative(D.PluginId) or
     IsBuiltInCommandName(D.CommandId) then
    Exit;
  if not IsDeclared(D.PluginId, D.CommandId) then
    FDeclared.Add(D);
  I := IndexOfCommand(D.CommandId);
  if I >= 0 then
  begin
    // A stub follows the language the manifest text is read in; a registered command is left alone.
    if FCommands[I].Stub and SameText(FCommands[I].PluginId, D.PluginId) then
    begin
      E := FCommands[I];
      E.Caption := Trim(ACaption);
      FCommands[I] := E;
    end;
    Exit;
  end;
  E := Default(TCommandEntry);
  E.PluginId := D.PluginId;
  E.CommandId := D.CommandId;
  E.Caption := Trim(ACaption);
  E.Stub := True;
  FCommands.Add(E);
  if D.Key <> '' then
    RegisterCommandBinding(D.PluginId, D.CommandId, D.Key);
  ApplyUserBinding(D.CommandId);
end;

function TCommandRegistry.LoadDeclared(const APluginId: string): Boolean;
var
  P: TDeclaredPlugin;
begin
  Result := False;
  for P in FDeclaredPlugins do
    if SameText(P.PluginId, APluginId) then
    begin
      if not Assigned(P.Load) then
        Exit;
      try
        Result := P.Load();
      except
        Result := False;
      end;
      ReconcilePlugin(APluginId);
      Exit;
    end;
end;

procedure TCommandRegistry.ReconcilePlugin(const APluginId: string);
var
  I, J: Integer;
begin
  for I := FCommands.Count - 1 downto 0 do
    if SameText(FCommands[I].PluginId, APluginId) and FCommands[I].Stub then
    begin
      Note(APluginId, T('ui.plugininfo.notRegistered',
        '%s is declared in plugin.json but the plugin did not register it',
        [FCommands[I].CommandId]));
      for J := FBindings.Count - 1 downto 0 do
        if SameText(FBindings[J].CommandId, FCommands[I].CommandId) and
           SameText(FBindings[J].PluginId, APluginId) then
          FBindings.Delete(J);
      FCommands.Delete(I);
    end;
end;

procedure TCommandRegistry.ForgetDeclared(const APluginId: string);
var
  I: Integer;
begin
  for I := FDeclared.Count - 1 downto 0 do
    if SameText(FDeclared[I].PluginId, APluginId) then
      FDeclared.Delete(I);
  for I := FDeclaredPlugins.Count - 1 downto 0 do
    if SameText(FDeclaredPlugins[I].PluginId, APluginId) then
      FDeclaredPlugins.Delete(I);
  for I := FNotes.Count - 1 downto 0 do
    if SameText(FNotes[I].PluginId, APluginId) then
      FNotes.Delete(I);
end;

{ What already uses ABinding: a keymap action (display name), a key handled in
  code, or another command of a plugin that registered its chord first; ''
  when it is free. }
function TCommandRegistry.ChordOwner(const ABinding: TKeyBinding;
  const ACommandId: string): string;
var
  I: Integer;
begin
  Result := KeymapChordOwner(ABinding);
  if Result <> '' then
    Exit;
  for I := 0 to FBindings.Count - 1 do
    if SameKeyBinding(ABinding, FBindings[I].Binding) and
       not SameText(FBindings[I].CommandId, ACommandId) then
      Exit(FBindings[I].CommandId);
  Result := '';
end;

procedure TCommandRegistry.RegisterCommandBinding(const APluginId, ACommandId,
  AKeyCombo: string);
var
  E: TBindingEntry;
  R: TRejectedBinding;
  Declared: TKeyBinding;
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
  for I := 0 to FBindings.Count - 1 do
    if SameText(FBindings[I].CommandId, E.CommandId) and
       SameKeyBinding(FBindings[I].Binding, E.Binding) then
      Exit;
  if IsStrict(E.PluginId) and
     not (DeclaredBinding(E.PluginId, E.CommandId, Declared) and
          SameKeyBinding(Declared, E.Binding)) then
  begin
    Note(E.PluginId, T('ui.plugininfo.notDeclared',
      '%s is not declared in plugin.json and was not registered',
      [KeyBindingToStr(E.Binding)]));
    Exit;
  end;
  if not FDefaultKeys.ContainsKey(LowerCase(E.CommandId)) then
    FDefaultKeys.Add(LowerCase(E.CommandId), KeyBindingToStr(E.Binding));
  // The user's own chord stands in for the plugin's.
  if FUserKeys.ContainsKey(LowerCase(E.CommandId)) then
    Exit;
  R.Owner := ChordOwner(E.Binding, E.CommandId);
  if R.Owner <> '' then
  begin
    R.PluginId := E.PluginId;
    R.CommandId := E.CommandId;
    R.Chord := KeyBindingToStr(E.Binding);
    FRejected.Add(R);
    Exit;
  end;
  FBindings.Add(E);
end;

procedure TCommandRegistry.DropBindings(const ACommandId: string);
var
  I: Integer;
begin
  for I := FBindings.Count - 1 downto 0 do
    if SameText(FBindings[I].CommandId, ACommandId) then
      FBindings.Delete(I);
end;

procedure TCommandRegistry.SaveUserKeys;
var
  Root: TJSONObject;
  Pair: TPair<string, string>;
begin
  if FUserKeysPath = '' then
    Exit;
  Root := TJSONObject.Create;
  try
    for Pair in FUserKeys do
      Root.AddPair(Pair.Key, Pair.Value);
    try
      TFile.WriteAllText(FUserKeysPath, Root.Format(2), TEncoding.UTF8);
    except
      // The chord stays in effect for this run; only its persistence is lost.
    end;
  finally
    Root.Free;
  end;
end;

{ Puts the user's chord of a command in place of the plugin's. A chord that
  has become taken since it was saved leaves the command without a key. }
procedure TCommandRegistry.ApplyUserBinding(const ACommandId: string);
var
  Chord: string;
  E: TBindingEntry;
  I: Integer;
begin
  if not FUserKeys.TryGetValue(LowerCase(ACommandId), Chord) then
    Exit;
  I := IndexOfCommand(ACommandId);
  if I < 0 then
    Exit;
  DropBindings(ACommandId);
  if (Chord = '') or not TryParseKeyCombo(Chord, E.Binding) or
     (ChordOwner(E.Binding, ACommandId) <> '') then
    Exit;
  E.PluginId := FCommands[I].PluginId;
  E.CommandId := FCommands[I].CommandId;
  FBindings.Add(E);
end;

procedure TCommandRegistry.UseUserBindings(const APath: string);
var
  Root: TJSONValue;
  Pair: TJSONPair;
  I: Integer;
begin
  if SameText(APath, FUserKeysPath) then
    Exit;
  FUserKeysPath := APath;
  FUserKeys.Clear;
  if (APath <> '') and FileExists(APath) then
  begin
    try
      Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
    except
      Root := nil;
    end;
    try
      if Root is TJSONObject then
        for Pair in TJSONObject(Root) do
          if (Pair.JsonValue is TJSONString) and not Pair.JsonString.Value.StartsWith('//') then
            FUserKeys.AddOrSetValue(LowerCase(Pair.JsonString.Value),
              Trim(Pair.JsonValue.Value));
    finally
      Root.Free;
    end;
  end;
  for I := 0 to FCommands.Count - 1 do
    ApplyUserBinding(FCommands[I].CommandId);
end;

function TCommandRegistry.SetUserBinding(const ACommandId, AKeyCombo: string;
  out AError: string): Boolean;
var
  Binding: TKeyBinding;
  Chord, Owner: string;
begin
  Result := False;
  AError := '';
  if IndexOfCommand(ACommandId) < 0 then
  begin
    AError := T('ui.pluginkey.unknown', 'Unknown plugin command');
    Exit;
  end;
  Chord := Trim(AKeyCombo);
  if Chord <> '' then
  begin
    if (Pos(';', Chord) > 0) or not TryParseKeyCombo(Chord, Binding) then
    begin
      AError := T('ui.pluginkey.invalid', 'Enter one key, for example Ctrl+Shift+F5');
      Exit;
    end;
    Chord := KeyBindingToStr(Binding);
    // The plugin's own chord needs no override of the user's.
    if FDefaultKeys.TryGetValue(LowerCase(ACommandId), Owner) and SameText(Owner, Chord) then
    begin
      ResetUserBinding(ACommandId);
      Exit(True);
    end;
    Owner := ChordOwner(Binding, ACommandId);
    if Owner <> '' then
    begin
      AError := T('ui.pluginkey.taken', 'Already used by: %s', [Owner]);
      Exit;
    end;
  end;
  FUserKeys.AddOrSetValue(LowerCase(ACommandId), Chord);
  ApplyUserBinding(ACommandId);
  SaveUserKeys;
  Result := True;
end;

procedure TCommandRegistry.ResetUserBinding(const ACommandId: string);
var
  Chord: string;
  E: TBindingEntry;
  I: Integer;
begin
  if not FUserKeys.ContainsKey(LowerCase(ACommandId)) then
    Exit;
  FUserKeys.Remove(LowerCase(ACommandId));
  I := IndexOfCommand(ACommandId);
  if I >= 0 then
  begin
    DropBindings(ACommandId);
    if FDefaultKeys.TryGetValue(LowerCase(ACommandId), Chord) and
       TryParseKeyCombo(Chord, E.Binding) and
       (ChordOwner(E.Binding, ACommandId) = '') then
    begin
      E.PluginId := FCommands[I].PluginId;
      E.CommandId := FCommands[I].CommandId;
      FBindings.Add(E);
    end;
  end;
  SaveUserKeys;
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
  R: TRejectedBinding;
  N: TCommandNote;
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
    for R in FRejected do
      if SameText(R.PluginId, APluginId) then
        Lines.Add(T('ui.plugininfo.keyTaken', 'Key %s for %s is not bound: %s already uses it',
          [R.Chord, R.CommandId, R.Owner]));
    for N in FNotes do
      if SameText(N.PluginId, APluginId) then
        Lines.Add(N.Text);
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

function TCommandRegistry.ListCommands: TArray<TPluginCommandInfo>;
var
  I: Integer;
begin
  SetLength(Result, FCommands.Count);
  for I := 0 to FCommands.Count - 1 do
  begin
    Result[I].PluginId := FCommands[I].PluginId;
    Result[I].CommandId := FCommands[I].CommandId;
    Result[I].Caption := FCommands[I].Caption;
    Result[I].Chord := CommandChordText(FCommands[I].CommandId);
    if not FDefaultKeys.TryGetValue(LowerCase(FCommands[I].CommandId),
         Result[I].DefaultChord) then
      Result[I].DefaultChord := '';
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
    begin
      FDefaultKeys.Remove(LowerCase(FCommands[I].CommandId));
      FCommands.Delete(I);
    end;
  for I := FBindings.Count - 1 downto 0 do
    if SameText(FBindings[I].PluginId, APluginId) then
      FBindings.Delete(I);
  for I := FRejected.Count - 1 downto 0 do
    if SameText(FRejected[I].PluginId, APluginId) then
      FRejected.Delete(I);
  for I := FNotes.Count - 1 downto 0 do
    if SameText(FNotes[I].PluginId, APluginId) then
      FNotes.Delete(I);
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
  if FCommands[I].Stub then
  begin
    // A declared command: loading the plugin makes it register the real handler.
    if not LoadDeclared(FCommands[I].PluginId) then
      Exit(False);
    I := IndexOfCommand(ACommandId);
    if (I < 0) or FCommands[I].Stub then
      Exit(False);
  end;
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

function TCommandRegistry.CommandChordText(const ACommandId: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := FBindings.Count - 1 downto 0 do
    if SameText(FBindings[I].CommandId, ACommandId) then
      Exit(KeyBindingToStr(FBindings[I].Binding));
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
