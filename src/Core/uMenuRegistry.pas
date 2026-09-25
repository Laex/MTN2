unit uMenuRegistry;

{ Open registration API for top-menu items, so plugins can add entries to
  existing categories (File, Tools, ...) without a compile-time-hardcoded
  menu.json/RCDATA list. Mirrors uKeymapRegistry.pas / uVfsRegistry.pas.

  Unlike TTopMenuAction (closed enum, dispatched via a hardcoded handler),
  plugin items carry their own TProc callback (TTopMenuController.
  TPluginMenuItemDesc.OnClick / TSubmenuItem.PluginOnClick) — so a plugin
  can wire up genuinely new behavior, not just rebind an existing command. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uTopMenuBar;

type
  IMenuRegistry = interface
    ['{3B2A9C1D-6E4F-4A8B-9D0C-1E3F5A7B9C2D}']
    /// <summary>Adds/replaces (by APluginId+AItemId) an item at the end of
    /// the category whose title matches AParentPath (e.g. "File", "Tools" —
    /// see config/menu.json category titles). Items from the same plugin
    /// within one category are ordered by ascending APriority.</summary>
    procedure RegisterMenuItem(const APluginId, AParentPath, AItemId, ACaption: string;
      AOnClick: TProc; APriority: Integer = 100);
    /// <summary>Removes all items registered by APluginId.</summary>
    procedure UnregisterPlugin(const APluginId: string);
    /// <summary>Binds the registry to the live menu controller so future
    /// Register/Unregister calls take effect immediately. Call once after
    /// the controller is constructed (e.g. from uDualPanelWindow/uMainForm).</summary>
    procedure AttachController(AController: TTopMenuController);
  end;

function MenuRegistry: IMenuRegistry;

implementation

type
  TRegEntry = record
    PluginId: string;
    ItemId: string;
    ParentPath: string;
    Caption: string;
    OnClick: TProc;
    Priority: Integer;
  end;

  TMenuRegistry = class(TInterfacedObject, IMenuRegistry)
  private
    FEntries: TList<TRegEntry>;
    FController: TTopMenuController;
    procedure Reapply;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterMenuItem(const APluginId, AParentPath, AItemId, ACaption: string;
      AOnClick: TProc; APriority: Integer = 100);
    procedure UnregisterPlugin(const APluginId: string);
    procedure AttachController(AController: TTopMenuController);
  end;

constructor TMenuRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TRegEntry>.Create;
end;

destructor TMenuRegistry.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TMenuRegistry.AttachController(AController: TTopMenuController);
begin
  FController := AController;
  Reapply;
end;

procedure TMenuRegistry.RegisterMenuItem(const APluginId, AParentPath, AItemId,
  ACaption: string; AOnClick: TProc; APriority: Integer);
var
  Entry: TRegEntry;
  I: Integer;
begin
  Entry.PluginId := APluginId;
  Entry.ItemId := AItemId;
  Entry.ParentPath := AParentPath;
  Entry.Caption := ACaption;
  Entry.OnClick := AOnClick;
  Entry.Priority := APriority;

  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].PluginId, APluginId) and SameText(FEntries[I].ItemId, AItemId) then
    begin
      FEntries[I] := Entry;
      Reapply;
      Exit;
    end;

  FEntries.Add(Entry);
  Reapply;
end;

procedure TMenuRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
  Reapply;
end;

procedure TMenuRegistry.Reapply;
var
  Items: TArray<TPluginMenuItemDesc>;
  Entry: TRegEntry;
  I: Integer;
begin
  if FController = nil then
    Exit;
  SetLength(Items, FEntries.Count);
  I := 0;
  for Entry in FEntries do
  begin
    Items[I].PluginId := Entry.PluginId;
    Items[I].ParentTitle := Entry.ParentPath;
    Items[I].Caption := Entry.Caption;
    Items[I].OnClick := Entry.OnClick;
    Items[I].Priority := Entry.Priority;
    Inc(I);
  end;
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
