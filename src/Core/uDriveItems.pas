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
  /// <summary>Glyphs 5..9, ! @ # $ % follow the four built-in items.</summary>
  cMaxDriveItems = 10;
  cMaxDriveItemCaptionChars = 40;

type
  TDriveItem = record
    PluginId: string;
    ItemId: string;
    Caption: string;
    Uri: string;
    Priority: Integer;
    /// <summary>Declared by a manifest, not registered by the plugin yet.</summary>
    Stub: Boolean;
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
    /// <summary>Marks APluginId as declarative: its items come from its manifest
    /// (DeclareItem) and an item it registers without having declared it is
    /// refused and reported in its information.</summary>
    procedure DeclarePlugin(const APluginId: string);
    /// <summary>Adds an item from a manifest (shown before the plugin loads); the
    /// plugin's own registration of the same id replaces it.</summary>
    procedure DeclareItem(const APluginId, AItemId, ACaption, AUri: string;
      APriority: Integer);
    /// <summary>Called after a declarative plugin loaded: a declared item the plugin
    /// did not register is dropped and reported in its information.</summary>
    procedure ReconcilePlugin(const APluginId: string);
    /// <summary>Forgets what the manifest of APluginId declared.</summary>
    procedure ForgetDeclared(const APluginId: string);
    function DescribePlugin(const APluginId: string): TArray<string>;
  end;

function DriveItems: IDriveItemRegistry;

implementation

uses
  uStrings, uPluginChrome;

type
  TDriveItemRegistry = class(TInterfacedObject, IDriveItemRegistry)
  private
    FItems: TList<TDriveItem>;
    FDeclarative: TList<string>;
    FDeclared: TList<string>;
    FNotes: TList<string>;
    function IndexOf(const APluginId, AItemId: string): Integer;
    procedure Note(const AText, APluginId: string);
  public
    constructor Create;
    destructor Destroy; override;
    function RegisterItem(const APluginId, AItemId, ACaption, AUri: string;
      APriority: Integer): Boolean;
    function Items: TArray<TDriveItem>;
    procedure UnregisterPlugin(const APluginId: string);
    procedure DeclarePlugin(const APluginId: string);
    procedure DeclareItem(const APluginId, AItemId, ACaption, AUri: string;
      APriority: Integer);
    procedure ReconcilePlugin(const APluginId: string);
    procedure ForgetDeclared(const APluginId: string);
    function DescribePlugin(const APluginId: string): TArray<string>;
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
  FDeclarative := TList<string>.Create;
  FDeclared := TList<string>.Create;
  FNotes := TList<string>.Create;
end;

destructor TDriveItemRegistry.Destroy;
begin
  FNotes.Free;
  FDeclared.Free;
  FDeclarative.Free;
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
  Item.Stub := False;
  if (FDeclarative.IndexOf(LowerCase(Item.PluginId)) >= 0) and
     (FDeclared.IndexOf(LowerCase(Item.PluginId) + '|' + LowerCase(Item.ItemId)) < 0) then
  begin
    Note(T('ui.plugininfo.notDeclared',
      '%s is not declared in plugin.json and was not registered', [Item.ItemId]), Item.PluginId);
    Exit;
  end;
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

procedure TDriveItemRegistry.Note(const AText, APluginId: string);
var
  Line: string;
begin
  Line := LowerCase(APluginId) + '|' + AText;
  if FNotes.IndexOf(Line) < 0 then
    FNotes.Add(Line);
end;

procedure TDriveItemRegistry.DeclarePlugin(const APluginId: string);
begin
  if (Trim(APluginId) <> '') and (FDeclarative.IndexOf(LowerCase(Trim(APluginId))) < 0) then
    FDeclarative.Add(LowerCase(Trim(APluginId)));
end;

procedure TDriveItemRegistry.DeclareItem(const APluginId, AItemId, ACaption, AUri: string;
  APriority: Integer);
var
  Key: string;
  I: Integer;
  Item: TDriveItem;
begin
  Key := LowerCase(Trim(APluginId)) + '|' + LowerCase(Trim(AItemId));
  if FDeclarative.IndexOf(LowerCase(Trim(APluginId))) < 0 then
    Exit;
  if FDeclared.IndexOf(Key) < 0 then
    FDeclared.Add(Key);
  I := IndexOf(Trim(APluginId), Trim(AItemId));
  if I >= 0 then
  begin
    // A stub follows the language the manifest text is read in; a registered item is left alone.
    if FItems[I].Stub then
    begin
      Item := FItems[I];
      Item.Caption := Trim(ACaption);
      FItems[I] := Item;
      NotifyPluginChromeChanged;
    end;
    Exit;
  end;
  if RegisterItem(APluginId, AItemId, ACaption, AUri, APriority) then
  begin
    I := IndexOf(Trim(APluginId), Trim(AItemId));
    Item := FItems[I];
    Item.Stub := True;
    FItems[I] := Item;
  end;
end;

procedure TDriveItemRegistry.ReconcilePlugin(const APluginId: string);
var
  I: Integer;
  Changed: Boolean;
begin
  Changed := False;
  for I := FItems.Count - 1 downto 0 do
    if SameText(FItems[I].PluginId, APluginId) and FItems[I].Stub then
    begin
      Note(T('ui.plugininfo.notRegistered',
        '%s is declared in plugin.json but the plugin did not register it',
        [FItems[I].ItemId]), APluginId);
      FItems.Delete(I);
      Changed := True;
    end;
  if Changed then
    NotifyPluginChromeChanged;
end;

procedure TDriveItemRegistry.ForgetDeclared(const APluginId: string);
var
  I: Integer;
  Prefix: string;
begin
  Prefix := LowerCase(APluginId) + '|';
  for I := FDeclared.Count - 1 downto 0 do
    if FDeclared[I].StartsWith(Prefix) then
      FDeclared.Delete(I);
  for I := FNotes.Count - 1 downto 0 do
    if FNotes[I].StartsWith(Prefix) then
      FNotes.Delete(I);
  I := FDeclarative.IndexOf(LowerCase(APluginId));
  if I >= 0 then
    FDeclarative.Delete(I);
end;

function TDriveItemRegistry.DescribePlugin(const APluginId: string): TArray<string>;
var
  Line, Prefix: string;
  Lines: TList<string>;
begin
  Prefix := LowerCase(APluginId) + '|';
  Lines := TList<string>.Create;
  try
    for Line in FNotes do
      if Line.StartsWith(Prefix) then
        Lines.Add(Line.Substring(Prefix.Length));
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
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
