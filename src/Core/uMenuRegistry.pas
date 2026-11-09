unit uMenuRegistry;

{ Open registration API for top-menu items, so plugins can add entries to
  existing categories (File, Tools, ...) without a compile-time-hardcoded
  menu.json/RCDATA list. Mirrors uKeymapRegistry.pas / uVfsRegistry.pas.

  Unlike TTopMenuAction (closed enum, dispatched via a hardcoded handler),
  plugin items carry their own TProc callback (TTopMenuController.
  TPluginMenuItemDesc.OnClick / TSubmenuItem.PluginOnClick) - so a plugin
  can wire up new behavior, not just rebind an existing command. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uTopMenuBar;

type
  IMenuRegistry = interface
    ['{3B2A9C1D-6E4F-4A8B-9D0C-1E3F5A7B9C2D}']
    /// <summary>Adds/replaces (by APluginId+AItemId) an item of the Plugins
    /// menu. The items of one plugin form a group (groups follow the order the
    /// plugins registered in, a line between them), ordered by ascending
    /// APriority inside it. AParentPath is only kept for the plugin's
    /// information dialog; the menu does not depend on it.</summary>
    procedure RegisterMenuItem(const APluginId, AParentPath, AItemId, ACaption: string;
      AOnClick: TProc; APriority: Integer = 100);
    /// <summary>Greys out (or re-enables) a registered item; False when the plugin
    /// has no such item. Registering the item again enables it.</summary>
    function SetMenuItemEnabled(const APluginId, AItemId: string; AEnabled: Boolean): Boolean;
    /// <summary>Marks APluginId as declarative: its menu items come from its manifest
    /// (DeclareMenuItem) and an item it registers without having declared it is
    /// refused and reported in its information.</summary>
    procedure DeclarePlugin(const APluginId: string; AOpen: Boolean = False);
    /// <summary>Adds an item from a manifest. Clicking it loads the plugin
    /// (CommandRegistry.LoadDeclared) and then runs the handler the plugin
    /// registered for the item. The caption and priority given here stay when the
    /// plugin registers the item.</summary>
    procedure DeclareMenuItem(const APluginId, AParentPath, AItemId, ACaption: string;
      APriority: Integer);
    /// <summary>Called after a declarative plugin loaded: a declared item the
    /// plugin did not register is dropped and reported in its information.</summary>
    procedure ReconcilePlugin(const APluginId: string);
    /// <summary>Forgets what the manifest of APluginId declared.</summary>
    procedure ForgetDeclared(const APluginId: string);
    /// <summary>Removes all items registered by APluginId.</summary>
    /// <summary>One line per thing the plugin registered, for the plugin's information
    /// dialog (already in the user's language).</summary>
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
    /// <summary>Binds the registry to the live menu controller so future
    /// Register/Unregister calls take effect immediately. Call once after
    /// the controller is constructed (e.g. from uDualPanelWindow/uMainForm).</summary>
    procedure AttachController(AController: TTopMenuController);
    /// <summary>The name shown on the line that opens a plugin's group (its
    /// manifest name); a plugin the resolver gives '' for is shown by its id.</summary>
    procedure SetTitleResolver(const AResolver: TFunc<string, string>);
    /// <summary>Position of a plugin in the plugin list (load order); the groups of
    /// the Plugins menu follow it. A plugin the resolver gives a negative number for
    /// goes after the others, in registration order.</summary>
    procedure SetOrderResolver(const AResolver: TFunc<string, Integer>);
  end;

function MenuRegistry: IMenuRegistry;

implementation

uses
  uStrings, uCommandRegistry;

type
  TRegEntry = record
    PluginId: string;
    ItemId: string;
    ParentPath: string;
    Caption: string;
    OnClick: TProc;
    Priority: Integer;
    Disabled: Boolean;
    /// <summary>Declared by a manifest, not registered by the plugin yet.</summary>
    Stub: Boolean;
  end;

  TMenuRegistry = class(TInterfacedObject, IMenuRegistry)
  private
    FEntries: TList<TRegEntry>;
    FController: TTopMenuController;
    FTitleResolver: TFunc<string, string>;
    FOrderResolver: TFunc<string, Integer>;
    FDeclarative: TList<string>;
    FOpen: TList<string>;
    FDeclared: TList<string>;
    FNotes: TList<TPair<string, string>>;
    function DeclaredKey(const APluginId, AItemId: string): string;
    procedure Note(const APluginId, AText: string);
    procedure RunStub(const APluginId, AItemId: string);
    procedure Reapply;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterMenuItem(const APluginId, AParentPath, AItemId, ACaption: string;
      AOnClick: TProc; APriority: Integer = 100);
    function SetMenuItemEnabled(const APluginId, AItemId: string; AEnabled: Boolean): Boolean;
    procedure DeclarePlugin(const APluginId: string; AOpen: Boolean = False);
    procedure DeclareMenuItem(const APluginId, AParentPath, AItemId, ACaption: string;
      APriority: Integer);
    procedure ReconcilePlugin(const APluginId: string);
    procedure ForgetDeclared(const APluginId: string);
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
    procedure AttachController(AController: TTopMenuController);
    procedure SetTitleResolver(const AResolver: TFunc<string, string>);
    procedure SetOrderResolver(const AResolver: TFunc<string, Integer>);
  end;

constructor TMenuRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TRegEntry>.Create;
  FDeclarative := TList<string>.Create;
  FOpen := TList<string>.Create;
  FDeclared := TList<string>.Create;
  FNotes := TList<TPair<string, string>>.Create;
end;

destructor TMenuRegistry.Destroy;
begin
  FNotes.Free;
  FDeclared.Free;
  FDeclarative.Free;
  FOpen.Free;
  FEntries.Free;
  inherited Destroy;
end;

procedure TMenuRegistry.AttachController(AController: TTopMenuController);
begin
  FController := AController;
  Reapply;
end;

procedure TMenuRegistry.SetTitleResolver(const AResolver: TFunc<string, string>);
begin
  FTitleResolver := AResolver;
  Reapply;
end;

procedure TMenuRegistry.SetOrderResolver(const AResolver: TFunc<string, Integer>);
begin
  FOrderResolver := AResolver;
  Reapply;
end;

procedure TMenuRegistry.RegisterMenuItem(const APluginId, AParentPath, AItemId,
  ACaption: string; AOnClick: TProc; APriority: Integer);
var
  Entry: TRegEntry;
  I: Integer;
begin
  Entry := Default(TRegEntry);
  Entry.PluginId := APluginId;
  Entry.ItemId := AItemId;
  Entry.ParentPath := AParentPath;
  Entry.Caption := ACaption;
  Entry.OnClick := AOnClick;
  Entry.Priority := APriority;

  if (FDeclarative.IndexOf(LowerCase(APluginId)) >= 0) and (FOpen.IndexOf(LowerCase(APluginId)) < 0) and
     (DeclaredKey(APluginId, AItemId) = '') then
  begin
    Note(APluginId, T('ui.plugininfo.notDeclared',
      '%s is not declared in plugin.json and was not registered', [AItemId]));
    Exit;
  end;
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].PluginId, APluginId) and SameText(FEntries[I].ItemId, AItemId) then
    begin
      // The manifest caption shows until the plugin gives its own.
      if FEntries[I].Stub and (Entry.Caption = '') then
        Entry.Caption := FEntries[I].Caption;
      FEntries[I] := Entry;
      Reapply;
      Exit;
    end;

  FEntries.Add(Entry);
  Reapply;
end;

function TMenuRegistry.SetMenuItemEnabled(const APluginId, AItemId: string;
  AEnabled: Boolean): Boolean;
var
  I: Integer;
  Entry: TRegEntry;
begin
  Result := False;
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].PluginId, APluginId) and SameText(FEntries[I].ItemId, AItemId) then
    begin
      Result := True;
      if FEntries[I].Disabled = (not AEnabled) then
        Exit;
      Entry := FEntries[I];
      Entry.Disabled := not AEnabled;
      FEntries[I] := Entry;
      Reapply;
      Exit;
    end;
end;

function TMenuRegistry.DeclaredKey(const APluginId, AItemId: string): string;
var
  Key: string;
begin
  Key := LowerCase(APluginId) + '|' + LowerCase(AItemId);
  if FDeclared.IndexOf(Key) >= 0 then
    Result := Key
  else
    Result := '';
end;

procedure TMenuRegistry.Note(const APluginId, AText: string);
var
  N: TPair<string, string>;
begin
  for N in FNotes do
    if SameText(N.Key, APluginId) and (N.Value = AText) then
      Exit;
  FNotes.Add(TPair<string, string>.Create(APluginId, AText));
end;

procedure TMenuRegistry.DeclarePlugin(const APluginId: string; AOpen: Boolean);
begin
  if Trim(APluginId) = '' then
    Exit;
  if FDeclarative.IndexOf(LowerCase(Trim(APluginId))) < 0 then
    FDeclarative.Add(LowerCase(Trim(APluginId)));
  if AOpen and (FOpen.IndexOf(LowerCase(Trim(APluginId))) < 0) then
    FOpen.Add(LowerCase(Trim(APluginId)))
  else if not AOpen then
    FOpen.Remove(LowerCase(Trim(APluginId)));
end;

procedure TMenuRegistry.DeclareMenuItem(const APluginId, AParentPath, AItemId,
  ACaption: string; APriority: Integer);
var
  Entry: TRegEntry;
  I: Integer;
  PluginId, ItemId: string;
begin
  PluginId := Trim(APluginId);
  ItemId := Trim(AItemId);
  if (PluginId = '') or (ItemId = '') or (FDeclarative.IndexOf(LowerCase(PluginId)) < 0) then
    Exit;
  if DeclaredKey(PluginId, ItemId) = '' then
    FDeclared.Add(LowerCase(PluginId) + '|' + LowerCase(ItemId));
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].PluginId, PluginId) and SameText(FEntries[I].ItemId, ItemId) then
    begin
      // A stub follows the language the manifest text is read in; a registered item is left alone.
      if FEntries[I].Stub then
      begin
        Entry := FEntries[I];
        Entry.Caption := ACaption;
        FEntries[I] := Entry;
        Reapply;
      end;
      Exit;
    end;
  Entry := Default(TRegEntry);
  Entry.PluginId := PluginId;
  Entry.ItemId := ItemId;
  Entry.ParentPath := AParentPath;
  Entry.Caption := ACaption;
  Entry.Priority := APriority;
  Entry.Stub := True;
  Entry.OnClick :=
    procedure
    begin
      RunStub(PluginId, ItemId);
    end;
  FEntries.Add(Entry);
  Reapply;
end;

procedure TMenuRegistry.RunStub(const APluginId, AItemId: string);
var
  I: Integer;
  Handler: TProc;
begin
  if not CommandRegistry.LoadDeclared(APluginId) then
  begin
    ReconcilePlugin(APluginId);
    Exit;
  end;
  ReconcilePlugin(APluginId);
  Handler := nil;
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].PluginId, APluginId) and SameText(FEntries[I].ItemId, AItemId) and
       not FEntries[I].Stub then
      Handler := FEntries[I].OnClick;
  if Assigned(Handler) then
    Handler();
end;

procedure TMenuRegistry.ReconcilePlugin(const APluginId: string);
var
  I: Integer;
  Changed: Boolean;
begin
  Changed := False;
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) and FEntries[I].Stub then
    begin
      Note(APluginId, T('ui.plugininfo.notRegistered',
        '%s is declared in plugin.json but the plugin did not register it',
        [FEntries[I].ItemId]));
      FEntries.Delete(I);
      Changed := True;
    end;
  if Changed then
    Reapply;
end;

procedure TMenuRegistry.ForgetDeclared(const APluginId: string);
var
  I: Integer;
  Prefix: string;
begin
  Prefix := LowerCase(APluginId) + '|';
  for I := FDeclared.Count - 1 downto 0 do
    if FDeclared[I].StartsWith(Prefix) then
      FDeclared.Delete(I);
  FOpen.Remove(LowerCase(APluginId));
  I := FDeclarative.IndexOf(LowerCase(APluginId));
  if I >= 0 then
    FDeclarative.Delete(I);
  for I := FNotes.Count - 1 downto 0 do
    if SameText(FNotes[I].Key, APluginId) then
      FNotes.Delete(I);
end;

function TMenuRegistry.DescribePlugin(const APluginId: string): TArray<string>;
var
  E: TRegEntry;
  N: TPair<string, string>;
  Lines: TList<string>;
begin
  Lines := TList<string>.Create;
  try
    for E in FEntries do
      if SameText(E.PluginId, APluginId) then
        Lines.Add(T('ui.plugininfo.menu', 'Menu item: %s > %s',
          [StringReplace(T('menu.category.Plugins', 'Plugins'), '&', '', []), E.Caption]));
    for N in FNotes do
      if SameText(N.Key, APluginId) then
        Lines.Add(N.Value);
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

procedure TMenuRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
  for I := FNotes.Count - 1 downto 0 do
    if SameText(FNotes[I].Key, APluginId) then
      FNotes.Delete(I);
  Reapply;
end;

procedure TMenuRegistry.Reapply;
var
  Items: TArray<TPluginMenuItemDesc>;
  Entry: TRegEntry;
  Sorted: TArray<TRegEntry>;
  Pos: TArray<Integer>;
  I, J, K, PosTmp: Integer;
begin
  if FController = nil then
    Exit;
  SetLength(Items, FEntries.Count);
  I := 0;
  // The controller puts a plugin's group where its first item appears, so
  // feeding the entries in plugin-list order orders the groups the same way.
  Sorted := FEntries.ToArray;
  if Assigned(FOrderResolver) then
  begin
    SetLength(Pos, Length(Sorted));
    for J := 0 to High(Sorted) do
    begin
      Pos[J] := FOrderResolver(Sorted[J].PluginId);
      if Pos[J] < 0 then
        Pos[J] := MaxInt;
    end;
    for J := 1 to High(Sorted) do
    begin
      Entry := Sorted[J];
      PosTmp := Pos[J];
      K := J - 1;
      while (K >= 0) and (Pos[K] > PosTmp) do
      begin
        Sorted[K + 1] := Sorted[K];
        Pos[K + 1] := Pos[K];
        Dec(K);
      end;
      Sorted[K + 1] := Entry;
      Pos[K + 1] := PosTmp;
    end;
  end;
  for Entry in Sorted do
  begin
    // An item registered again with an empty caption is hidden.
    if Entry.Caption = '' then
      Continue;
    Items[I].PluginId := Entry.PluginId;
    Items[I].ItemId := Entry.ItemId;
    if Assigned(FTitleResolver) then
      Items[I].PluginTitle := FTitleResolver(Entry.PluginId);
    Items[I].ParentTitle := Entry.ParentPath;
    Items[I].Caption := Entry.Caption;
    Items[I].OnClick := Entry.OnClick;
    Items[I].Priority := Entry.Priority;
    Items[I].Disabled := Entry.Disabled;
    Items[I].Shortcut := CommandRegistry.CommandChordText(Entry.ItemId);
    Inc(I);
  end;
  SetLength(Items, I);
  FController.SetPluginMenuItems(Items);
end;

var
  GRegistry: IMenuRegistry;

function MenuRegistry: IMenuRegistry;
begin
  if GRegistry = nil then
    GRegistry := TMenuRegistry.Create;
  Result := GRegistry;
end;

initialization

finalization
  GRegistry := nil;

end.
