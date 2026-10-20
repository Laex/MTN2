unit uDriveItems;

{ Entries plugins add to the Change Drive list (Alt+F1/F2) and to the drive
  bar of the panels. They follow the built-in numbered items (System folders,
  Recycle bin, Temporary, Workspace) and take the next digits, so at most
  cMaxDriveItems fit. An item shows its caption and, on Enter, opens its URI
  in the panel; the item is highlighted while the panel is on a URI of the
  same scheme.

  The plugin supplies the caption already translated. Main thread only. }

interface

uses
  System.SysUtils, System.Generics.Collections;

const
  /// <summary>Digits 5..9 follow the four built-in items.</summary>
  cMaxDriveItems = 5;
  cMaxDriveItemCaptionChars = 40;

type
  TDriveItem = record
    PluginId: string;
    ItemId: string;
    Caption: string;
    Uri: string;
    Priority: Integer;
  end;

  IDriveItemRegistry = interface
    ['{5C1D7E32-4B8A-4F09-9E6D-2A3B7C80D415}']
    /// <summary>Adds the item AItemId of APluginId, or replaces the one it
    /// already registered under that id. False when an argument is empty,
    /// AUri has no scheme, the scheme is "file", or cMaxDriveItems other
    /// items are registered already.</summary>
    function RegisterItem(const APluginId, AItemId, ACaption, AUri: string;
      APriority: Integer): Boolean;
    /// <summary>The items in ascending priority; equal priorities keep their
    /// registration order.</summary>
    function Items: TArray<TDriveItem>;
    procedure UnregisterPlugin(const APluginId: string);
  end;

function DriveItems: IDriveItemRegistry;

implementation

uses
  uPluginChrome;

type
  TDriveItemRegistry = class(TInterfacedObject, IDriveItemRegistry)
  private
    FItems: TList<TDriveItem>;
    function IndexOf(const APluginId, AItemId: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function RegisterItem(const APluginId, AItemId, ACaption, AUri: string;
      APriority: Integer): Boolean;
    function Items: TArray<TDriveItem>;
    procedure UnregisterPlugin(const APluginId: string);
  end;

var
  GRegistry: IDriveItemRegistry;

function SchemeOfUri(const AUri: string): string;
var
  P: Integer;
begin
  P := Pos('://', AUri);
  if P > 1 then
    Result := LowerCase(Copy(AUri, 1, P - 1))
  else
    Result := '';
end;

constructor TDriveItemRegistry.Create;
begin
  inherited Create;
  FItems := TList<TDriveItem>.Create;
end;

destructor TDriveItemRegistry.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TDriveItemRegistry.IndexOf(const APluginId, AItemId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if SameText(FItems[I].PluginId, APluginId) and
       SameText(FItems[I].ItemId, AItemId) then
      Exit(I);
  Result := -1;
end;

function TDriveItemRegistry.RegisterItem(const APluginId, AItemId, ACaption,
  AUri: string; APriority: Integer): Boolean;
var
  Item: TDriveItem;
  I, At: Integer;
  Scheme, Caption: string;
begin
  Result := False;
  Item.PluginId := Trim(APluginId);
  Item.ItemId := Trim(AItemId);
  Item.Uri := Trim(AUri);
  Caption := Trim(StringReplace(StringReplace(ACaption, #13, ' ', [rfReplaceAll]),
    #10, ' ', [rfReplaceAll]));
  if (Item.PluginId = '') or (Item.ItemId = '') or (Caption = '') then
    Exit;
  Scheme := SchemeOfUri(Item.Uri);
  if (Scheme = '') or (Scheme = 'file') then
    Exit;
  if Length(Caption) > cMaxDriveItemCaptionChars then
    Caption := Copy(Caption, 1, cMaxDriveItemCaptionChars);
  Item.Caption := Caption;
  Item.Priority := APriority;
  I := IndexOf(Item.PluginId, Item.ItemId);
  if I >= 0 then
    FItems.Delete(I)
  else if FItems.Count >= cMaxDriveItems then
    Exit;
  // Insert after the last item whose priority is not above the new one.
  At := FItems.Count;
  while (At > 0) and (FItems[At - 1].Priority > Item.Priority) do
    Dec(At);
  FItems.Insert(At, Item);
  NotifyPluginChromeChanged;
  Result := True;
end;

function TDriveItemRegistry.Items: TArray<TDriveItem>;
begin
  Result := FItems.ToArray;
end;

procedure TDriveItemRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
  Removed: Boolean;
begin
  Removed := False;
  for I := FItems.Count - 1 downto 0 do
    if SameText(FItems[I].PluginId, APluginId) then
    begin
      FItems.Delete(I);
      Removed := True;
    end;
  if Removed then
    NotifyPluginChromeChanged;
end;

function DriveItems: IDriveItemRegistry;
begin
  if GRegistry = nil then
    GRegistry := TDriveItemRegistry.Create;
  Result := GRegistry;
end;

initialization

finalization
  GRegistry := nil;

end.
