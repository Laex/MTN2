unit uTopMenuBar;

{***************************************************************************}
{ TUI Top Menu Bar and Dropdown Popup Controller for MTN2 (NDN / FAR style).}
{ Handles F9 / Alt menu bar activation, top-level item selection,           }
{ dropdown overlay rendering, keyboard navigation, and mouse interaction.   }
{***************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.JSON, System.IOUtils,
  System.Generics.Collections, System.TypInfo, System.Character, Winapi.Windows,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes, uDualPanelOverlays, uStrings;

type
  TTopMenuAction = (
    tmaNone,
    tmaLeftDrive,
    tmaLeftSort,
    tmaLeftColumnModes,
    tmaLeftInfo,
    tmaLeftShowHidden,
    tmaLeftNewTab,
    tmaLeftCloseTab,
    tmaLeftToggle,
    tmaRightDrive,
    tmaRightSort,
    tmaRightColumnModes,
    tmaRightInfo,
    tmaRightShowHidden,
    tmaRightNewTab,
    tmaRightCloseTab,
    tmaRightToggle,
    tmaFileView,
    tmaFileEdit,
    tmaFileExternalView,
    tmaFileExternalEdit,
    tmaFileCopy,
    tmaFileMove,
    tmaFileRename,
    tmaFileMkDir,
    tmaFileCreateLink,
    tmaFileSetAttributes,
    tmaFileProperties,
    tmaFileCompare,
    tmaFileChecksums,
    tmaFileRestore,
    tmaFileDelete,
    tmaFileWipe,
    tmaFilePack,
    tmaFileUnpack,
    tmaFileJobList,
    tmaFileSelectMask,
    tmaFileUnselectMask,
    tmaFileSelectByExt,
    tmaFileUnselectByExt,
    tmaFileSelectAll,
    tmaFileInvertSelect,
    tmaFileCalcSize,
    tmaFileCopyPath,
    tmaFileRunDetached,
    tmaFileNew,
    tmaCmdQuickView,
    tmaCmdFind,
    tmaCmdHistoryBack,
    tmaCmdHistoryForward,
    tmaCmdDriveRoot,
    tmaCmdRefresh,
    tmaCmdSwapPanels,
    tmaCmdEqualizeOther,
    tmaCmdEqualizeActive,
    tmaCmdUserMenu,
    tmaCmdInsertName,
    tmaCmdInsertPath,
    tmaCmdFocusCmdLine,
    tmaCmdConsoleToggle,
    tmaCmdDirSync,
    tmaCmdCompareFolders,
    tmaCmdJobList,
    tmaCmdNewTerminal,
    tmaCmdSyncConsoleDir,
    tmaCmdConsoleProfile,
    tmaCmdFolderHistory,
    tmaCmdFileHistory,
    tmaCmdCmdHistory,
    tmaCmdFolderHotlist,
    tmaCmdFolderHotlistAdd,
    tmaCmdWorkspaceLibrary,
    tmaCmdWorkspaceSave,
    tmaCmdSshConnections,
    tmaCmdAssociations,
    tmaCmdBranchView,
    tmaCmdLiveFilter,
    tmaCmdRecycleBin,
    tmaCmdNextTab,
    tmaEditCopy,
    tmaEditCut,
    tmaEditPaste,
    tmaEditGotoLine,
    tmaEditFind,
    tmaEditFindReplace,
    tmaEditEncoding,
    tmaEditUndo,
    tmaEditRedo,
    tmaEditHexToggle,
    tmaOptReloadKeymap,
    tmaOptShowPlugins,
    tmaOptColorCoding,
    tmaOptKeymap,
    tmaOptTheme,
    tmaOptColumnsConfig,
    tmaOptDisplay,
    tmaOptExternalTools,
    tmaOptZoomIn,
    tmaOptZoomOut,
    tmaOptResetZoom,
    tmaHelpContents,
    tmaHelpAbout,
    tmaQuit
  );

  TSubmenuItem = record
    Caption: string;
    HotChar: Char;
    HotPos: Integer; // 1-indexed position in Caption; 0 = not highlighted
    Shortcut: string;
    Action: TTopMenuAction;
    IsSeparator: Boolean;
    /// <summary>Plugin-supplied items dispatch through PluginOnClick instead
    /// of the closed TTopMenuAction enum (see uMenuRegistry.pas). Empty
    /// PluginId = not a plugin item (built-in, from menu.json/RCDATA).</summary>
    IsPluginItem: Boolean;
    PluginId: string;
    PluginOnClick: TProc;
  end;

  TPluginMenuItemDesc = record
    PluginId: string;
    ParentTitle: string;
    Caption: string;
    OnClick: TProc;
    Priority: Integer;
  end;

  TTopMenuCategory = record
    Title: string;
    HotChar: Char;
    HotPos: Integer; // 1-indexed position in Title
    Items: TArray<TSubmenuItem>;
  end;

  TTopMenuExecuteEvent = reference to procedure(AAction: TTopMenuAction);
  TTopMenuEnabledFn = reference to function(AAction: TTopMenuAction): Boolean;

  TTopMenuController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FOnExecuteAction: TTopMenuExecuteEvent;
    FOnIsActionEnabled: TTopMenuEnabledFn;
    FActive: Boolean;
    FSubmenuOpen: Boolean;
    FCategoryIndex: Integer;
    FSubmenuIndex: Integer;
    FCategories: TArray<TTopMenuCategory>;
    FSubmenuBounds: TRectI;
    FPluginItems: TArray<TPluginMenuItemDesc>;
    procedure LayoutSubmenu(AClientWidth: Integer);
    function FindHotCategory(AChar: Char): Integer;
    function FindHotSubItem(AChar: Char): Integer;
    procedure ApplyPluginItemsToCategories;
    function IsItemEnabled(const AItem: TSubmenuItem): Boolean;
    procedure ExecuteItem(const AItem: TSubmenuItem);
    procedure MoveSubmenuCursor(ADelta: Integer);
    procedure SnapSubmenuToSelectable;
    function HandleTopBarClick(ACol: Integer): Boolean;
    function HandleSubmenuClick(ACol, ARow: Integer): Boolean;
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AOnExecuteAction: TTopMenuExecuteEvent);
    procedure SetTheme(const ATheme: IThemeRenderer);

    function LoadMenuFromJson(const AJsonText: string): Boolean;
    function LoadMenuFromFile(const AFilePath: string): Boolean;
    function LoadMenuFromResource(const AResName: string): Boolean;
    /// <summary>Re-resolves the menu from scratch (RCDATA MENU_MAIN, then a
    /// config\menu.json fallback next to the exe, then a hardcoded default)
    /// and reapplies any registered plugin items. Called once from Create;
    /// call again after SetLocale to pick up a locale switch's translated
    /// captions -- the caller is responsible for redrawing afterwards, same
    /// as every other live setting change in this app.</summary>
    procedure BuildMenuStructure;
    /// <summary>'' when AIndex is out of range. For inspecting the parsed
    /// (and, once translated, localized) menu structure -- e.g. tests.</summary>
    function CategoryTitle(AIndex: Integer): string;
    /// <summary>'' when either index is out of range.</summary>
    function CategoryItemCaption(ACategoryIndex, AItemIndex: Integer): string;

    /// <summary>Replaces all plugin-registered menu items with AItems (each
    /// inserted into the category matching ParentTitle, sorted by Priority)
    /// and reapplies them to the current menu structure. Called by
    /// uMenuRegistry whenever a plugin registers/unregisters an item.</summary>
    procedure SetPluginMenuItems(const AItems: TArray<TPluginMenuItemDesc>);

    procedure ActivateMenu(ACategoryIndex: Integer = 1; AOpenSubmenu: Boolean = True);
    procedure DeactivateMenu;
    procedure ToggleMenu;

    procedure DrawTopBar(const AGrid: TTerminalGrid; AWidth: Integer);
    procedure DrawSubmenu(const AGrid: TTerminalGrid; AClientWidth: Integer);

    function HandleInput(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function HandleClick(ACol, ARow: Integer): Boolean;

    property Active: Boolean read FActive;
    property SubmenuOpen: Boolean read FSubmenuOpen;
    property CategoryIndex: Integer read FCategoryIndex;
    property SubmenuIndex: Integer read FSubmenuIndex;
    property OnIsActionEnabled: TTopMenuEnabledFn read FOnIsActionEnabled
      write FOnIsActionEnabled;
  end;

/// <summary>Parses a JSON menu action name (LoadMenuFromJson) back to its
/// TTopMenuAction, or tmaNone if AName is empty, unrecognized, or does not
/// match a member's exact case.</summary>
function StringToTopMenuAction(const AName: string): TTopMenuAction;

implementation

uses
  uInputLine;

const
  // Submenu (F9 dropdown) idle-row hotkey — dark red on the theme's own
  // dialog body, fixed rather than theme-driven at the user's request (this
  // is how FAR/NDN's dropdown always looked). The selected row still uses
  // the theme's own accent (see DrawSubmenu) since that already matched the
  // historical yellow-on-blue look before themes existed.
  cSubmenuHotFg = cMenuHotKeyFg;
  cSubmenuDisabledFg = TAlphaColor($FF808080);

// System.UpCase only folds a..z; a translated mnemonic can be any letter.
function HotUpper(AChar: Char): Char;
begin
  Result := AChar.ToUpper;
end;

// Mnemonic lookup order for a typed char: the exact letter first, then the
// same key on the other layout (#0 if none — callers skip it).
function HotCandidates(AChar: Char): TArray<Char>;
begin
  Result := [HotUpper(AChar), TextKeyLayoutAlternate(AChar)];
end;

constructor TTopMenuController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AOnExecuteAction: TTopMenuExecuteEvent);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FOnExecuteAction := AOnExecuteAction;
  FActive := False;
  FSubmenuOpen := False;
  FCategoryIndex := 1;
  FSubmenuIndex := 0;
  BuildMenuStructure;
end;

procedure TTopMenuController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

function TTopMenuController.CategoryTitle(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FCategories)) then
    Result := FCategories[AIndex].Title;
end;

function TTopMenuController.CategoryItemCaption(ACategoryIndex, AItemIndex: Integer): string;
begin
  Result := '';
  if (ACategoryIndex < 0) or (ACategoryIndex > High(FCategories)) then
    Exit;
  if (AItemIndex < 0) or (AItemIndex > High(FCategories[ACategoryIndex].Items)) then
    Exit;
  Result := FCategories[ACategoryIndex].Items[AItemIndex].Caption;
end;

// Every TTopMenuAction member's Delphi identifier is also its JSON menu
// action string (see the enum declaration above), so this is RTTI name
// lookup rather than 90-odd hand-maintained comparisons that could drift
// out of sync with the enum. GetEnumValue itself is case-insensitive; the
// GetEnumName round-trip re-enforces the exact-case match the old chain of
// "=" comparisons made, so an unrecognized or wrongly-cased name still
// falls back to tmaNone exactly as before.
function StringToTopMenuAction(const AName: string): TTopMenuAction;
var
  V: Integer;
begin
  V := GetEnumValue(TypeInfo(TTopMenuAction), AName);
  if (V < 0) or (GetEnumName(TypeInfo(TTopMenuAction), V) <> AName) then
    Exit(tmaNone);
  Result := TTopMenuAction(V);
end;

function TTopMenuController.LoadMenuFromJson(const AJsonText: string): Boolean;
var
  Val, CatsVal, ItemsVal: TJSONValue;
  Obj, CatObj, ItemObj: TJSONObject;
  CatsArr, ItemsArr: TJSONArray;
  I, J, PosIdx: Integer;
  CatTitle, HotStr, CapStr, ShortStr, ActStr: string;
  IsSep: Boolean;
  HotC: Char;
  NewCategories: TArray<TTopMenuCategory>;
begin
  Result := False;
  if Trim(AJsonText) = '' then Exit;

  Val := TJSONObject.ParseJSONValue(AJsonText);
  if not Assigned(Val) then Exit;
  try
    if not (Val is TJSONObject) then Exit;
    Obj := TJSONObject(Val);
    CatsVal := Obj.GetValue('categories');
    if not (CatsVal is TJSONArray) then Exit;

    CatsArr := TJSONArray(CatsVal);
    SetLength(NewCategories, CatsArr.Count);

    for I := 0 to CatsArr.Count - 1 do
    begin
      if not (CatsArr.Items[I] is TJSONObject) then Exit;
      CatObj := TJSONObject(CatsArr.Items[I]);

      CatTitle := CatObj.GetValue<string>('title', '');
      HotStr := CatObj.GetValue<string>('hotChar', '');
      // Categories have no stable id in menu.json (unlike items, which key
      // off their Action's own enum name) -- the untranslated title is the
      // best available key. Renaming a category's English text in menu.json
      // orphans any translation keyed to the old text; give categories a
      // real id there first if that turns out to matter in practice.
      CatTitle := T('menu.category.' + CatTitle, CatTitle);

      HotC := #0;
      if HotStr <> '' then
        HotC := HotUpper(HotStr[1]);
      MenuResolveMnemonic(CatTitle, HotC, PosIdx);

      NewCategories[I].Title := CatTitle;
      NewCategories[I].HotChar := HotC;
      NewCategories[I].HotPos := PosIdx;

      ItemsVal := CatObj.GetValue('items');
      if ItemsVal is TJSONArray then
      begin
        ItemsArr := TJSONArray(ItemsVal);
        SetLength(NewCategories[I].Items, ItemsArr.Count);
        for J := 0 to ItemsArr.Count - 1 do
        begin
          if ItemsArr.Items[J] is TJSONObject then
          begin
            ItemObj := TJSONObject(ItemsArr.Items[J]);
            IsSep := ItemObj.GetValue<Boolean>('isSeparator', False);
            if IsSep then
            begin
              NewCategories[I].Items[J].Caption := '-';
              NewCategories[I].Items[J].HotChar := #0;
              NewCategories[I].Items[J].HotPos := 0;
              NewCategories[I].Items[J].Shortcut := '';
              NewCategories[I].Items[J].Action := tmaNone;
              NewCategories[I].Items[J].IsSeparator := True;
            end
            else
            begin
              CapStr := ItemObj.GetValue<string>('caption', '');
              HotStr := ItemObj.GetValue<string>('hotChar', '');
              ShortStr := ItemObj.GetValue<string>('shortcut', '');
              ActStr := ItemObj.GetValue<string>('action', '');

              HotC := #0;
              if HotStr <> '' then
                HotC := HotUpper(HotStr[1]);

              // Keyed by the action's own RTTI name (StringToTopMenuAction's
              // enum-name lookup below already needs this pairing to exist),
              // not by the English caption -- so renaming CapStr in
              // menu.json never orphans a translation the way the untranslatable
              // category title above can.
              if ActStr <> '' then
                CapStr := T('menu.' + ActStr, CapStr);
              MenuResolveMnemonic(CapStr, HotC, PosIdx);

              NewCategories[I].Items[J].Caption := CapStr;
              NewCategories[I].Items[J].HotChar := HotC;
              NewCategories[I].Items[J].HotPos := PosIdx;
              NewCategories[I].Items[J].Shortcut := ShortStr;
              NewCategories[I].Items[J].Action := StringToTopMenuAction(ActStr);
              NewCategories[I].Items[J].IsSeparator := False;
            end;
          end;
        end;
      end;
    end;

    FCategories := NewCategories;
    Result := True;
  finally
    Val.Free;
  end;
end;

function TTopMenuController.LoadMenuFromFile(const AFilePath: string): Boolean;
var
  Content: string;
begin
  Result := False;
  if not FileExists(AFilePath) then Exit;
  try
    Content := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    Result := LoadMenuFromJson(Content);
  except
    Result := False;
  end;
end;

function TTopMenuController.LoadMenuFromResource(const AResName: string): Boolean;
var
  RS: TResourceStream;
  Bytes: TBytes;
  Json: string;
  UResName: string;
begin
  Result := False;
  UResName := UpperCase(Trim(AResName));
  if FindResource(HInstance, PChar(UResName), RT_RCDATA) = 0 then
    Exit;
  try
    RS := TResourceStream.Create(HInstance, UResName, RT_RCDATA);
    try
      SetLength(Bytes, RS.Size);
      if RS.Size > 0 then
        RS.ReadBuffer(Bytes[0], RS.Size);
      Json := TEncoding.UTF8.GetString(Bytes);
      if (Length(Json) > 0) and (Ord(Json[1]) = $FEFF) then
        Delete(Json, 1, 1);
      Result := (Trim(Json) <> '') and LoadMenuFromJson(Json);
    finally
      RS.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TTopMenuController.BuildMenuStructure;
const
  cResMenuMain = 'MENU_MAIN';
var
  ConfigPath: string;

  function SubItem(const ACaption: string; AHot: Char; const AShortcut: string;
    AAct: TTopMenuAction): TSubmenuItem;
  begin
    Result.Caption := ACaption;
    Result.HotChar := AHot;
    Result.HotPos := MenuFindHotPos(ACaption, AHot);
    Result.Shortcut := AShortcut;
    Result.Action := AAct;
    Result.IsSeparator := False;
  end;

  function Separator: TSubmenuItem;
  begin
    Result.Caption := '-';
    Result.HotChar := #0;
    Result.HotPos := 0;
    Result.Shortcut := '';
    Result.Action := tmaNone;
    Result.IsSeparator := True;
  end;

begin
  // Primary source: MENU_MAIN RCDATA (MTN2.rc), embedded from config/menu.json.
  if LoadMenuFromResource(cResMenuMain) then
  begin
    ApplyPluginItemsToCategories;
    Exit;
  end;

  // Fallback for tools/dev runs without the compiled resource (e.g. running
  // straight from source before a full rebuild).
  ConfigPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'config', 'menu.json');
  if not FileExists(ConfigPath) then
    ConfigPath := TPath.Combine('src', 'config', 'menu.json');

  if FileExists(ConfigPath) and LoadMenuFromFile(ConfigPath) then
  begin
    ApplyPluginItemsToCategories;
    Exit;
  end;
  SetLength(FCategories, 7);

  // 0: System ≡
  FCategories[0].Title := #$2261;
  FCategories[0].HotChar := #0;
  FCategories[0].HotPos := 0;
  SetLength(FCategories[0].Items, 4);
  FCategories[0].Items[0] := SubItem('About MTN2...', 'A', '', tmaHelpAbout);
  FCategories[0].Items[1] := SubItem('Help contents', 'H', 'F1', tmaHelpContents);
  FCategories[0].Items[2] := Separator;
  FCategories[0].Items[3] := SubItem('Quit', 'Q', 'F10', tmaQuit);

  // 1: Left
  FCategories[1].Title := 'Left';
  FCategories[1].HotChar := 'L';
  FCategories[1].HotPos := 1;
  SetLength(FCategories[1].Items, 9);
  FCategories[1].Items[0] := SubItem('Drive selection...', 'D', 'Alt+F1', tmaLeftDrive);
  FCategories[1].Items[1] := SubItem('Sort menu...', 'S', 'Ctrl+F12', tmaLeftSort);
  FCategories[1].Items[2] := SubItem('Column modes...', 'C', 'Ctrl+`', tmaLeftColumnModes);
  FCategories[1].Items[3] := SubItem('Info panel toggle', 'I', 'Ctrl+L', tmaLeftInfo);
  FCategories[1].Items[4] := SubItem('Show hidden/system files', 'H', 'Ctrl+H', tmaLeftShowHidden);
  FCategories[1].Items[5] := Separator;
  FCategories[1].Items[6] := SubItem('New panel tab', 'N', 'Ctrl+T', tmaLeftNewTab);
  FCategories[1].Items[7] := SubItem('Close panel tab', 'W', 'Ctrl+W', tmaLeftCloseTab);
  FCategories[1].Items[8] := SubItem('Toggle Left panel', 'T', 'Ctrl+F1', tmaLeftToggle);

  // 2: Files
  FCategories[2].Title := 'Files';
  FCategories[2].HotChar := 'F';
  FCategories[2].HotPos := 1;
  SetLength(FCategories[2].Items, 23);
  FCategories[2].Items[0] := SubItem('View', 'V', 'F3', tmaFileView);
  FCategories[2].Items[1] := SubItem('Edit', 'E', 'F4', tmaFileEdit);
  FCategories[2].Items[2] := SubItem('Copy', 'C', 'F5', tmaFileCopy);
  FCategories[2].Items[3] := SubItem('Move / Rename', 'M', 'F6', tmaFileMove);
  FCategories[2].Items[4] := SubItem('Make directory', 'K', 'F7', tmaFileMkDir);
  FCategories[2].Items[5] := SubItem('Set attributes...', 'B', 'Ctrl+Shift+A', tmaFileSetAttributes);
  FCategories[2].Items[6] := SubItem('Delete', 'D', 'F8', tmaFileDelete);
  FCategories[2].Items[7] := SubItem('Wipe file', 'W', 'Shift+F8', tmaFileWipe);
  FCategories[2].Items[8] := Separator;
  FCategories[2].Items[9] := SubItem('Pack archive', 'P', 'Shift+F1', tmaFilePack);
  FCategories[2].Items[10] := SubItem('Unpack archive', 'U', 'Shift+F2', tmaFileUnpack);
  FCategories[2].Items[11] := SubItem('Background jobs...', 'J', 'Ctrl+Shift+J', tmaFileJobList);
  FCategories[2].Items[12] := Separator;
  FCategories[2].Items[13] := SubItem('Select by mask...', 'S', 'Num+', tmaFileSelectMask);
  FCategories[2].Items[14] := SubItem('Unselect by mask...', 'N', 'Num-', tmaFileUnselectMask);
  FCategories[2].Items[15] := SubItem('Select by extension', #0, 'Ctrl++', tmaFileSelectByExt);
  FCategories[2].Items[16] := SubItem('Unselect by extension', #0, 'Ctrl+-', tmaFileUnselectByExt);
  FCategories[2].Items[17] := SubItem('Select all', 'A', 'Ctrl+A', tmaFileSelectAll);
  FCategories[2].Items[18] := SubItem('Invert selection', 'I', 'Ctrl+I', tmaFileInvertSelect);
  FCategories[2].Items[19] := Separator;
  FCategories[2].Items[20] := SubItem('Calculate folder size', 'Z', 'F3', tmaFileCalcSize);
  FCategories[2].Items[21] := SubItem('Copy full path', 'Y', 'Ctrl+Alt+Ins', tmaFileCopyPath);
  FCategories[2].Items[22] := SubItem('Run detached (OS)', 'R', 'Shift+Enter', tmaFileRunDetached);

  // 3: Edit (clipboard + document ops — not Files → Edit / F4)
  FCategories[3].Title := 'Edit';
  FCategories[3].HotChar := 'E';
  FCategories[3].HotPos := 1;
  SetLength(FCategories[3].Items, 11);
  FCategories[3].Items[0] := SubItem('Copy', 'C', 'Ctrl+C / Ctrl+Ins', tmaEditCopy);
  FCategories[3].Items[1] := SubItem('Cut', 'T', 'Ctrl+X / Ctrl+Del', tmaEditCut);
  FCategories[3].Items[2] := SubItem('Paste', 'P', 'Ctrl+V / Shift+Ins', tmaEditPaste);
  FCategories[3].Items[3] := Separator;
  FCategories[3].Items[4] := SubItem('Goto line...', 'G', 'Alt+F8', tmaEditGotoLine);
  FCategories[3].Items[5] := SubItem('Find...', 'F', 'F7', tmaEditFind);
  FCategories[3].Items[6] := SubItem('Find and replace...', 'R', 'Ctrl+F7', tmaEditFindReplace);
  FCategories[3].Items[7] := SubItem('Encoding...', 'N', 'Shift+F8', tmaEditEncoding);
  FCategories[3].Items[8] := SubItem('Undo', 'U', 'Ctrl+Z', tmaEditUndo);
  FCategories[3].Items[9] := SubItem('Redo', 'D', 'Ctrl+Shift+Z', tmaEditRedo);
  FCategories[3].Items[10] := SubItem('Hex↔Text', 'H', 'Ctrl+H', tmaEditHexToggle);

  // 4: Commands
  FCategories[4].Title := 'Commands';
  FCategories[4].HotChar := 'C';
  FCategories[4].HotPos := 1;
  SetLength(FCategories[4].Items, 19);
  FCategories[4].Items[0] := SubItem('Find file...', 'F', 'Alt+F7', tmaCmdFind);
  FCategories[4].Items[1] := SubItem('Synchronize dirs...', 'Y', 'Ctrl+Alt+S', tmaCmdDirSync);
  FCategories[4].Items[2] := SubItem('Background jobs...', 'J', 'Ctrl+Shift+J', tmaCmdJobList);
  FCategories[4].Items[3] := SubItem('User menu', 'U', 'F2', tmaCmdUserMenu);
  FCategories[4].Items[4] := SubItem('History back', 'B', 'Alt+Left', tmaCmdHistoryBack);
  FCategories[4].Items[5] := SubItem('History forward', 'G', 'Alt+Right', tmaCmdHistoryForward);
  FCategories[4].Items[6] := SubItem('Drive root', 'R', 'Ctrl+\', tmaCmdDriveRoot);
  FCategories[4].Items[7] := SubItem('Refresh panel', 'E', 'Ctrl+R', tmaCmdRefresh);
  FCategories[4].Items[8] := Separator;
  FCategories[4].Items[9] := SubItem('Swap panels', 'S', 'Ctrl+U', tmaCmdSwapPanels);
  FCategories[4].Items[10] := SubItem('Target := Active', 'T', 'Ctrl+]', tmaCmdEqualizeOther);
  FCategories[4].Items[11] := SubItem('Active := Target', 'A', 'Ctrl+[', tmaCmdEqualizeActive);
  FCategories[4].Items[12] := Separator;
  FCategories[4].Items[13] := SubItem('Insert item name', 'N', 'Ctrl+Enter', tmaCmdInsertName);
  FCategories[4].Items[14] := SubItem('Insert item path', 'P', 'Ctrl+Shift+Enter', tmaCmdInsertPath);
  FCategories[4].Items[15] := SubItem('Console toggle', 'O', 'Ctrl+O', tmaCmdConsoleToggle);
  FCategories[4].Items[16] := SubItem('Background console...', 'Q', 'Ctrl+Alt+O', tmaCmdConsoleProfile);
  FCategories[4].Items[17] := SubItem('Sync console dir', 'I', 'Ctrl+Shift+O', tmaCmdSyncConsoleDir);
  FCategories[4].Items[18] := SubItem('New terminal...', 'M', 'Ctrl+Shift+N', tmaCmdNewTerminal);

  // 5: Options
  FCategories[5].Title := 'Options';
  FCategories[5].HotChar := 'O';
  FCategories[5].HotPos := 1;
  SetLength(FCategories[5].Items, 11);
  FCategories[5].Items[0] := SubItem('Reload keymap', 'K', 'Ctrl+Alt+K', tmaOptReloadKeymap);
  FCategories[5].Items[1] := SubItem('Plugins...', 'P', '', tmaOptShowPlugins);
  FCategories[5].Items[2] := SubItem('Color coding...', 'C', '', tmaOptColorCoding);
  FCategories[5].Items[3] := SubItem('Keymap...', 'M', '', tmaOptKeymap);
  FCategories[5].Items[4] := SubItem('Theme...', 'T', '', tmaOptTheme);
  FCategories[5].Items[5] := SubItem('Font / Display...', 'F', '', tmaOptDisplay);
  FCategories[5].Items[6] := SubItem('Columns...', 'L', 'Ctrl+Shift+F7', tmaOptColumnsConfig);
  FCategories[5].Items[7] := Separator;
  FCategories[5].Items[8] := SubItem('Zoom In', 'I', 'Ctrl+Wheel', tmaOptZoomIn);
  FCategories[5].Items[9] := SubItem('Zoom Out', 'O', 'Ctrl+Wheel', tmaOptZoomOut);
  FCategories[5].Items[10] := SubItem('Reset Zoom', 'R', 'Ctrl+0', tmaOptResetZoom);

  // 6: Right
  FCategories[6].Title := 'Right';
  FCategories[6].HotChar := 'R';
  FCategories[6].HotPos := 1;
  SetLength(FCategories[6].Items, 9);
  FCategories[6].Items[0] := SubItem('Drive selection...', 'D', 'Alt+F2', tmaRightDrive);
  FCategories[6].Items[1] := SubItem('Sort menu...', 'S', 'Ctrl+F12', tmaRightSort);
  FCategories[6].Items[2] := SubItem('Column modes...', 'C', 'Ctrl+`', tmaRightColumnModes);
  FCategories[6].Items[3] := SubItem('Info panel toggle', 'I', 'Ctrl+L', tmaRightInfo);
  FCategories[6].Items[4] := SubItem('Show hidden/system files', 'H', 'Ctrl+H', tmaRightShowHidden);
  FCategories[6].Items[5] := Separator;
  FCategories[6].Items[6] := SubItem('New panel tab', 'N', 'Ctrl+T', tmaRightNewTab);
  FCategories[6].Items[7] := SubItem('Close panel tab', 'W', 'Ctrl+W', tmaRightCloseTab);
  FCategories[6].Items[8] := SubItem('Toggle Right panel', 'T', 'Ctrl+F2', tmaRightToggle);
  ApplyPluginItemsToCategories;
end;

procedure TTopMenuController.ApplyPluginItemsToCategories;
var
  I, J: Integer;
  Desc: TPluginMenuItemDesc;
  NewItem: TSubmenuItem;
  Kept: TArray<TSubmenuItem>;
begin
  // Strip previously-inserted plugin items first, so this is safe to call
  // repeatedly (e.g. after every SetPluginMenuItems / menu reload).
  for I := 0 to High(FCategories) do
  begin
    SetLength(Kept, 0);
    for J := 0 to High(FCategories[I].Items) do
      if not FCategories[I].Items[J].IsPluginItem then
      begin
        SetLength(Kept, Length(Kept) + 1);
        Kept[High(Kept)] := FCategories[I].Items[J];
      end;
    FCategories[I].Items := Kept;
  end;

  // FPluginItems is pre-sorted by (ParentTitle, Priority) in
  // SetPluginMenuItems, so appending in order keeps priority ascending
  // within each category.
  for Desc in FPluginItems do
    for I := 0 to High(FCategories) do
      if SameText(FCategories[I].Title, Desc.ParentTitle) then
      begin
        NewItem.Caption := Desc.Caption;
        NewItem.HotChar := #0;
        NewItem.HotPos := 0;
        NewItem.Shortcut := '';
        NewItem.Action := tmaNone;
        NewItem.IsSeparator := False;
        NewItem.IsPluginItem := True;
        NewItem.PluginId := Desc.PluginId;
        NewItem.PluginOnClick := Desc.OnClick;

        SetLength(FCategories[I].Items, Length(FCategories[I].Items) + 1);
        FCategories[I].Items[High(FCategories[I].Items)] := NewItem;
        Break;
      end;
end;

procedure TTopMenuController.SetPluginMenuItems(const AItems: TArray<TPluginMenuItemDesc>);
var
  Sorted: TArray<TPluginMenuItemDesc>;
  I, J: Integer;
  Tmp: TPluginMenuItemDesc;
begin
  Sorted := Copy(AItems);
  // Stable insertion sort by (ParentTitle, Priority) — plugin item counts
  // are expected to be small, so O(n^2) is fine here.
  for I := 1 to High(Sorted) do
  begin
    Tmp := Sorted[I];
    J := I - 1;
    while (J >= 0) and
          ((Sorted[J].ParentTitle > Tmp.ParentTitle) or
           ((Sorted[J].ParentTitle = Tmp.ParentTitle) and (Sorted[J].Priority > Tmp.Priority))) do
    begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := Tmp;
  end;

  FPluginItems := Sorted;
  ApplyPluginItemsToCategories;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

function TTopMenuController.IsItemEnabled(const AItem: TSubmenuItem): Boolean;
begin
  if AItem.IsSeparator then
    Exit(False);
  if AItem.IsPluginItem then
    Exit(True);
  if not Assigned(FOnIsActionEnabled) then
    Exit(True);
  Result := FOnIsActionEnabled(AItem.Action);
end;

procedure TTopMenuController.ExecuteItem(const AItem: TSubmenuItem);
begin
  if not IsItemEnabled(AItem) then
    Exit;
  DeactivateMenu;
  if (AItem.Action <> tmaNone) and Assigned(FOnExecuteAction) then
    FOnExecuteAction(AItem.Action)
  else if Assigned(AItem.PluginOnClick) then
    AItem.PluginOnClick();
end;

procedure TTopMenuController.SnapSubmenuToSelectable;
var
  Items: TArray<TSubmenuItem>;
  I: Integer;
begin
  if (FCategoryIndex < 0) or (FCategoryIndex > High(FCategories)) then
    Exit;
  Items := FCategories[FCategoryIndex].Items;
  if Length(Items) = 0 then
    Exit;
  if (FSubmenuIndex >= 0) and (FSubmenuIndex <= High(Items)) and
     IsItemEnabled(Items[FSubmenuIndex]) then
    Exit;
  for I := 0 to High(Items) do
    if IsItemEnabled(Items[I]) then
    begin
      FSubmenuIndex := I;
      Exit;
    end;
end;

procedure TTopMenuController.MoveSubmenuCursor(ADelta: Integer);
var
  Items: TArray<TSubmenuItem>;
  Start, N: Integer;
begin
  if (FCategoryIndex < 0) or (FCategoryIndex > High(FCategories)) then
    Exit;
  Items := FCategories[FCategoryIndex].Items;
  N := Length(Items);
  if N = 0 then
    Exit;
  Start := FSubmenuIndex;
  repeat
    FSubmenuIndex := (FSubmenuIndex + ADelta + N) mod N;
    if IsItemEnabled(Items[FSubmenuIndex]) then
      Exit;
  until FSubmenuIndex = Start;
end;

procedure TTopMenuController.ActivateMenu(ACategoryIndex: Integer; AOpenSubmenu: Boolean);
begin
  FActive := True;
  FCategoryIndex := EnsureRange(ACategoryIndex, 0, High(FCategories));
  FSubmenuOpen := AOpenSubmenu;
  FSubmenuIndex := 0;
  SnapSubmenuToSelectable;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TTopMenuController.DeactivateMenu;
begin
  if not FActive then
    Exit;
  FActive := False;
  FSubmenuOpen := False;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TTopMenuController.ToggleMenu;
begin
  if FActive then
    DeactivateMenu
  else
    ActivateMenu(1, True);
end;

procedure TTopMenuController.LayoutSubmenu(AClientWidth: Integer);
var
  I, X, W, H, MaxCapW, MaxShortW, ItemW: Integer;
  Cat: TTopMenuCategory;
begin
  if (FCategoryIndex < 0) or (FCategoryIndex > High(FCategories)) then
    Exit;
  Cat := FCategories[FCategoryIndex];
  
  // Calculate X position of top bar title
  X := 1;
  for I := 0 to FCategoryIndex - 1 do
    Inc(X, Length(FCategories[I].Title) + 2);

  MaxCapW := 10;
  MaxShortW := 0;
  for I := 0 to High(Cat.Items) do
  begin
    if Cat.Items[I].IsSeparator then
      Continue;
    MaxCapW := Max(MaxCapW, Length(Cat.Items[I].Caption));
    MaxShortW := Max(MaxShortW, Length(Cat.Items[I].Shortcut));
  end;

  ItemW := MaxCapW + 2;
  if MaxShortW > 0 then
    Inc(ItemW, MaxShortW + 2);
  W := ItemW + 2;
  if X + W > AClientWidth - 1 then
    X := Max(1, AClientWidth - W - 1);
  H := Length(Cat.Items) + 2;

  FSubmenuBounds := TRectI.Make(X, 1, X + W - 1, 1 + H - 1);
end;

procedure TTopMenuController.DrawTopBar(const AGrid: TTerminalGrid; AWidth: Integer);
var
  I, X: Integer;
  Title, Clock: string;
  IsSel: Boolean;
  Fg, Bg: TAlphaColor;
  NormalFg, NormalBg, SelFg, SelBg: TAlphaColor;
  ClockX: Integer;
begin
  Clock := '[ ' + FormatDateTime('hh:nn:ss', Now) + ' ]';

  // Themed bar colours. First pass reused pcpWorkspaceTabIdle for the
  // resting bar, but that role is deliberately muted in most themes (an
  // idle tab shouldn't shout) — for a theme whose idle tone happens to be
  // close to another theme's (e.g. NDN and High Contrast both rest on
  // plain black), the always-visible top bar ended up looking unchanged
  // even though the colour value genuinely did change a few shades.
  // pcpPanelTabActive is every theme's vivid, unambiguous identity accent
  // (FAR/NDN's cyan bar, Dracula's purple, Nord's frost cyan, ...) and is
  // what this bar historically looked like before themes existed at all, so
  // the resting strip uses that instead. The open category then inverts
  // that same accent for a pressed/engaged look — there's no separate
  // "pressed" role on IThemeRenderer, and colour inversion is the classic
  // textmode convention for exactly this.
  FTheme.ResolvePanelChromeColors(pcpPanelTabActive, True, NormalFg, NormalBg);
  SelFg := NormalBg;
  SelBg := NormalFg;

  FillGridRect(AGrid, 0, 0, AWidth - 1, 0, ' ', NormalFg, NormalBg);

  X := 1;
  for I := 0 to High(FCategories) do
  begin
    Title := ' ' + FCategories[I].Title + ' ';
    IsSel := FActive and (I = FCategoryIndex);

    if IsSel then
    begin
      Fg := SelFg;
      Bg := SelBg;
    end
    else
    begin
      Fg := NormalFg;
      Bg := NormalBg;
    end;

    PutGridText(AGrid, X, 0, Title, Fg, Bg);

    // Highlight mnemonic char: same fixed red as the submenu's idle-row
    // hotkey (cSubmenuHotFg), background left untouched — at the user's
    // explicit request, for one consistent "this is a shortcut" colour
    // across the whole menu instead of a per-bar accent.
    if (FCategories[I].HotPos > 0) and (FCategories[I].HotPos <= Length(FCategories[I].Title)) then
      PutGridText(AGrid, X + FCategories[I].HotPos, 0,
        FCategories[I].Title[FCategories[I].HotPos], cSubmenuHotFg, Bg, [ccaBold]);

    Inc(X, Length(Title));
  end;

  // Render live clock at right side
  ClockX := AWidth - Length(Clock) - 1;
  if ClockX < X + 2 then
    ClockX := X + 2;
  if ClockX + Length(Clock) <= AWidth then
    PutGridText(AGrid, ClockX, 0, Clock, NormalFg, NormalBg);
end;

procedure TTopMenuController.DrawSubmenu(const AGrid: TTerminalGrid; AClientWidth: Integer);
var
  Cat: TTopMenuCategory;
  R: TRectI;
  I, Y, InnerW, CapW: Integer;
  Item: TSubmenuItem;
  Cap, Line, ShortText: string;
  Fg, Bg: TAlphaColor;
  SubFg, SubBg, SubSelFg, SubSelBg: TAlphaColor;
  IsSel: Boolean;
begin
  if not FActive or not FSubmenuOpen then
    Exit;
  if (FCategoryIndex < 0) or (FCategoryIndex > High(FCategories)) then
    Exit;

  Cat := FCategories[FCategoryIndex];
  LayoutSubmenu(AClientWidth);
  R := FSubmenuBounds;
  if (R.Width < 8) or (R.Height < 3) then
    Exit;

  // Themed dropdown chrome: the submenu is just a small themed popup, so
  // reuse the same dialog frame/body every other Host dialog draws with
  // (keeps it visually consistent with the rest of the theme) instead of a
  // hand-rolled double-line box in fixed NDN colours.
  FTheme.ResolveDialogRowColors(False, SubFg, SubBg);
  FTheme.ResolveDialogRowColors(True, SubSelFg, SubSelBg);
  FTheme.DrawDialogFrame(AGrid, R, Cat.Title, []);

  // Drop shadow
  DrawDialogShadow(AGrid, R);

  InnerW := R.Width - 2;
  for I := 0 to High(Cat.Items) do
  begin
    Y := R.Top + 1 + I;
    if Y >= R.Bottom then
      Break;
    Item := Cat.Items[I];
    if Item.IsSeparator then
    begin
      Line := StringOfChar(#$2500, InnerW); // ─
      PutGridText(AGrid, R.Left + 1, Y, Line, SubFg, SubBg);
      Continue;
    end;

    Cap := Item.Caption;
    ShortText := Item.Shortcut;
    CapW := InnerW - 2;
    if ShortText <> '' then
      CapW := Max(CapW - Length(ShortText) - 1, 4);

    if Length(Cap) > CapW then
      Cap := Copy(Cap, 1, CapW)
    else
      while Length(Cap) < CapW do
        Cap := Cap + ' ';

    Line := ' ' + Cap;
    if ShortText <> '' then
      Line := Line + ' ' + ShortText;

    while Length(Line) < InnerW do
      Line := Line + ' ';

    IsSel := I = FSubmenuIndex;
    if not IsItemEnabled(Item) then
    begin
      Fg := cSubmenuDisabledFg;
      Bg := SubBg;
    end
    else if IsSel then
    begin
      Fg := SubSelFg;
      Bg := SubSelBg;
    end
    else
    begin
      Fg := SubFg;
      Bg := SubBg;
    end;

    PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);

    // Mnemonic char in submenu: fixed dark red on whichever background the
    // row already has (idle or selected) — no background inversion, at the
    // user's explicit request. Restores the original FAR/NDN submenu look;
    // never clashes since none of the eight themes' dialog/cursor colours
    // are reddish. Disabled rows skip the accent so they stay uniformly dim.
    // HotPos is resolved once at load time (an '&' marker in a translated
    // caption can point past an earlier occurrence of the same letter).
    if (Item.HotChar <> #0) and (Item.HotPos > 0) and (Item.HotPos <= Length(Cap))
      and IsItemEnabled(Item) then
      PutGridText(AGrid, R.Left + 2 + Item.HotPos - 1, Y,
        Item.Caption[Item.HotPos], cSubmenuHotFg, Bg, [ccaBold]);
  end;
end;

function TTopMenuController.FindHotCategory(AChar: Char): Integer;
var
  I: Integer;
  C: Char;
begin
  Result := -1;
  if AChar = #0 then
    Exit;
  // Exact char first, then the same key on the other keyboard layout.
  for C in HotCandidates(AChar) do
    if C <> #0 then
      for I := 0 to High(FCategories) do
        if (FCategories[I].HotChar <> #0) and (HotUpper(FCategories[I].HotChar) = C) then
          Exit(I);
end;

function TTopMenuController.FindHotSubItem(AChar: Char): Integer;
var
  I: Integer;
  C: Char;
  Cat: TTopMenuCategory;
begin
  Result := -1;
  if (AChar = #0) or (FCategoryIndex < 0) or (FCategoryIndex > High(FCategories)) then
    Exit;
  Cat := FCategories[FCategoryIndex];
  for C in HotCandidates(AChar) do
  begin
    if C = #0 then
      Continue;
    for I := 0 to High(Cat.Items) do
    begin
      if Cat.Items[I].IsSeparator then
        Continue;
      if not IsItemEnabled(Cat.Items[I]) then
        Continue;
      if (Cat.Items[I].HotChar <> #0) and (HotUpper(Cat.Items[I].HotChar) = C) then
        Exit(I);
    end;
  end;
end;

function TTopMenuController.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  HotCat, HotSub: Integer;
begin
  Result := False;
  if not FActive then
  begin
    // F9 or single Alt release (without character) activates the menu
    if (AKey = vkF9) or ((ssAlt in AShift) and (AKey = 0) and (AKeyChar = #0)) then
    begin
      ActivateMenu(1, True);
      AKey := 0;
      Result := True;
      Exit;
    end;
    // Pass all Alt+Character combinations to Panel Quick Search
    Exit;
  end;

  Result := True;

  // Esc or second F9 / Alt press toggles menu off
  if (AKey = vkEscape) or (AKey = vkF9) or ((ssAlt in AShift) and (AKey = 0) and (AKeyChar = #0)) then
  begin
    DeactivateMenu;
    AKey := 0;
    Exit;
  end;

  // Left / Right navigation between top categories
  if AKey = vkLeft then
  begin
    if FCategoryIndex > 0 then
      Dec(FCategoryIndex)
    else
      FCategoryIndex := High(FCategories);
    FSubmenuIndex := 0;
    SnapSubmenuToSelectable;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;

  if AKey = vkRight then
  begin
    if FCategoryIndex < High(FCategories) then
      Inc(FCategoryIndex)
    else
      FCategoryIndex := 0;
    FSubmenuIndex := 0;
    SnapSubmenuToSelectable;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;

  // Down arrow opens/moves inside submenu
  if AKey = vkDown then
  begin
    if not FSubmenuOpen then
    begin
      FSubmenuOpen := True;
      SnapSubmenuToSelectable;
    end
    else
      MoveSubmenuCursor(1);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;

  // Up arrow moves up inside submenu
  if AKey = vkUp then
  begin
    if FSubmenuOpen then
      MoveSubmenuCursor(-1);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;

  // Enter executes selected submenu item
  if AKey = vkReturn then
  begin
    if FSubmenuOpen and (FCategoryIndex <= High(FCategories)) then
    begin
      if (FSubmenuIndex >= 0) and (FSubmenuIndex <= High(FCategories[FCategoryIndex].Items)) then
        ExecuteItem(FCategories[FCategoryIndex].Items[FSubmenuIndex]);
    end
    else
    begin
      FSubmenuOpen := True;
      SnapSubmenuToSelectable;
    end;
    AKey := 0;
    Exit;
  end;

  // Mnemonic hotkey inside active menu (Category or Submenu item)
  // With a dropdown open its own items win: the category letters overlap
  // item letters heavily (e.g. Files > Copy vs Commands), and a letter that
  // is lit up in the open dropdown must do what it shows.
  if AKeyChar <> #0 then
  begin
    HotSub := -1;
    if FSubmenuOpen then
      HotSub := FindHotSubItem(AKeyChar);

    HotCat := -1;
    if HotSub < 0 then
      HotCat := FindHotCategory(AKeyChar);
    if HotCat >= 0 then
    begin
      ActivateMenu(HotCat, True);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;

    if (HotSub < 0) and not FSubmenuOpen then
      HotSub := FindHotSubItem(AKeyChar);
    if HotSub >= 0 then
    begin
      FSubmenuIndex := HotSub;
      ExecuteItem(FCategories[FCategoryIndex].Items[HotSub]);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
  end;

  AKey := 0;
  AKeyChar := #0;
end;

function TTopMenuController.HandleTopBarClick(ACol: Integer): Boolean;
var
  I, X, ItemW: Integer;
  Title: string;
begin
  Result := True;
  X := 1;
  for I := 0 to High(FCategories) do
  begin
    Title := ' ' + FCategories[I].Title + ' ';
    ItemW := Length(Title);
    if (ACol >= X) and (ACol < X + ItemW) then
    begin
      if FActive and (FCategoryIndex = I) and FSubmenuOpen then
        DeactivateMenu
      else
        ActivateMenu(I, True);
      Exit;
    end;
    Inc(X, ItemW);
  end;
  DeactivateMenu;
end;

function TTopMenuController.HandleSubmenuClick(ACol, ARow: Integer): Boolean;
var
  Idx: Integer;
begin
  Result := True;
  if not FSubmenuBounds.Contains(ACol, ARow) then
  begin
    // Click outside submenu closes it.
    DeactivateMenu;
    Exit;
  end;
  Idx := ARow - (FSubmenuBounds.Top + 1);
  if (Idx >= 0) and (Idx <= High(FCategories[FCategoryIndex].Items)) and
     not FCategories[FCategoryIndex].Items[Idx].IsSeparator then
  begin
    FSubmenuIndex := Idx;
    ExecuteItem(FCategories[FCategoryIndex].Items[Idx]);
  end;
end;

function TTopMenuController.HandleClick(ACol, ARow: Integer): Boolean;
begin
  if ARow = 0 then
    Exit(HandleTopBarClick(ACol));
  if FActive and FSubmenuOpen then
    Exit(HandleSubmenuClick(ACol, ARow));
  Result := False;
end;

end.
