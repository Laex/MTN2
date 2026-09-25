unit uUserMenuController;

{ NDN/FAR-style User Menu (F2) popup over the active panel: the user's own
  commands (uUserMenu.pas) with hotkeys, nested submenus and separators, and
  in-place editing keys. The popup only navigates and reports what the user
  asked for; running a command and the edit/delete dialogs belong to the
  host (uDualPanelUserMenu.pas), which also owns the menu tree.

  Keys: Up/Down/Home/End/PgUp/PgDn move, Enter or Right opens a submenu or
  runs a command, a hotkey does the same for its item, Left/Esc go back up
  (Esc on the top level closes), Ins inserts before the cursor, F4 edits,
  Del deletes, Ctrl+Up/Ctrl+Down move the item, Shift+F2 asks the host for
  the other menu (folder menu <-> main menu). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.Character,
  System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes,
  uDualPanelOverlays, uUserMenu;

type
  TUserMenuAction = (
    umaExecute,  // run AParent.Items[AIndex] (the popup has already closed)
    umaInsert,   // add a new item at AIndex of AParent
    umaEdit,     // edit AParent.Items[AIndex]
    umaDelete,   // delete AParent.Items[AIndex]
    umaMoved,    // AParent's items were reordered in place: save
    umaSwitchMenu // Shift+F2: show the other menu (folder <-> main)
  );

  TUserMenuActionEvent = reference to procedure(AAction: TUserMenuAction;
    AParent: TUserMenuItem; AIndex: Integer);
  TMenuPanelBoundsEvent = reference to function(ASide: TPanelSide): TRectI;
  TActiveSideEvent = reference to function: TPanelSide;

  TUserMenuController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FOnAction: TUserMenuActionEvent;
    FGetActivePanelBounds: TMenuPanelBoundsEvent;
    FGetActiveSide: TActiveSideEvent;
    FVisible: Boolean;
    FRoot: TUserMenuItem;
    FRootTitle: string;
    // Submenus entered from the root, and the cursor each one was left at.
    FPath: TList<TUserMenuItem>;
    FPathIndex: TList<Integer>;
    FIndex: Integer;
    FTop: Integer;
    FBounds: TRectI;
    function Current: TUserMenuItem;
    function ItemCount: Integer;
    function IsSelectable(AIndex: Integer): Boolean;
    function ViewRows: Integer;
    procedure Invalidate;
    procedure Fire(AAction: TUserMenuAction; AIndex: Integer);
    procedure MoveCursor(ADelta: Integer);
    procedure EnsureCursorVisible;
    procedure Activate(AIndex: Integer);
    procedure GoUp;
    procedure MoveItem(ADelta: Integer);
    function FindHotKey(AChar: Char): Integer;
    function Title: string;
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AOnAction: TUserMenuActionEvent;
      const AGetActivePanelBounds: TMenuPanelBoundsEvent;
      const AGetActiveSide: TActiveSideEvent);
    destructor Destroy; override;
    procedure SetTheme(const ATheme: IThemeRenderer);
    /// <summary>Shows ARoot's items under ATitle ('' = "User menu"). ARoot
    /// stays owned by the caller and must outlive the popup (or be followed
    /// by Close / another Open).</summary>
    procedure Open(ARoot: TUserMenuItem; const ATitle: string = '');
    procedure Close;
    /// <summary>After the host changed the items of the submenu on screen:
    /// re-clamps and puts the cursor on ASelectIndex.</summary>
    procedure ItemsChanged(ASelectIndex: Integer);
    procedure Layout;
    procedure Draw(const AGrid: TTerminalGrid);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleClick(ALocalCol, ALocalRow: Integer): Boolean;
    property Visible: Boolean read FVisible;
    property Bounds: TRectI read FBounds;
    /// <summary>The submenu currently shown (the root at top level).</summary>
    property CurrentMenu: TUserMenuItem read Current;
    property ItemIndex: Integer read FIndex;
  end;

implementation

uses
  uInputLine, uStrings;

const
  cCursorFg = TAlphaColor($FF000000);
  cCursorBg = TAlphaColor($FF00AAAA);
  cFileFg   = TAlphaColor($FFAAAAAA);
  cPanelBg  = TAlphaColor($FF0000AA);
  cFrameActive = TAlphaColor($FF55FFFF);
  cSubmenuMark = #$25BA; // ►
  cSeparatorChar = #$2500; // ─

constructor TUserMenuController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AOnAction: TUserMenuActionEvent;
  const AGetActivePanelBounds: TMenuPanelBoundsEvent;
  const AGetActiveSide: TActiveSideEvent);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FOnAction := AOnAction;
  FGetActivePanelBounds := AGetActivePanelBounds;
  FGetActiveSide := AGetActiveSide;
  FPath := TList<TUserMenuItem>.Create;
  FPathIndex := TList<Integer>.Create;
end;

destructor TUserMenuController.Destroy;
begin
  FPathIndex.Free;
  FPath.Free;
  inherited Destroy;
end;

procedure TUserMenuController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

function TUserMenuController.Current: TUserMenuItem;
begin
  if FPath.Count > 0 then
    Result := FPath.Last
  else
    Result := FRoot;
end;

function TUserMenuController.ItemCount: Integer;
begin
  if Current <> nil then
    Result := Current.Items.Count
  else
    Result := 0;
end;

function TUserMenuController.IsSelectable(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < ItemCount) and
    (Current.Items[AIndex].Kind <> umkSeparator);
end;

procedure TUserMenuController.Invalidate;
begin
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TUserMenuController.Fire(AAction: TUserMenuAction; AIndex: Integer);
begin
  if Assigned(FOnAction) then
    FOnAction(AAction, Current, AIndex);
end;

procedure TUserMenuController.Open(ARoot: TUserMenuItem; const ATitle: string);
begin
  FRoot := ARoot;
  FRootTitle := ATitle;
  FPath.Clear;
  FPathIndex.Clear;
  FIndex := 0;
  FTop := 0;
  FVisible := True;
  ItemsChanged(0);
end;

procedure TUserMenuController.Close;
begin
  FVisible := False;
  FRoot := nil;
  FPath.Clear;
  FPathIndex.Clear;
  Invalidate;
end;

procedure TUserMenuController.ItemsChanged(ASelectIndex: Integer);
begin
  FIndex := EnsureRange(ASelectIndex, 0, Max(ItemCount - 1, 0));
  // Land on a real item: first one below, else above.
  if not IsSelectable(FIndex) then
  begin
    MoveCursor(1);
    if not IsSelectable(FIndex) then
      MoveCursor(-1);
  end;
  Layout;
  EnsureCursorVisible;
  Invalidate;
end;

function TUserMenuController.Title: string;
begin
  if FPath.Count > 0 then
    Result := FPath.Last.Caption
  else if FRootTitle <> '' then
    Result := FRootTitle
  else
    Result := T('ui.userMenu.title', 'User menu');
end;

function ItemLabel(AItem: TUserMenuItem): string;
begin
  // " H  Caption"; the hotkey column is always there so captions line up.
  if AItem.HotKey <> '' then
    Result := ' ' + AItem.HotKey + '  ' + AItem.Caption
  else
    Result := '    ' + AItem.Caption;
end;

procedure TUserMenuController.Layout;
var
  PanelBounds: TRectI;
  W, H, MaxW, I: Integer;
begin
  if not Assigned(FGetActivePanelBounds) or not Assigned(FGetActiveSide) then
    Exit;
  PanelBounds := FGetActivePanelBounds(FGetActiveSide);
  MaxW := Length(Title) + 6;
  if ItemCount = 0 then
    MaxW := Max(MaxW, Length(T('ui.userMenu.empty', '(empty: Ins adds an item)')) + 2);
  for I := 0 to ItemCount - 1 do
    // +3: submenu mark column and the right padding.
    MaxW := Max(MaxW, Length(ItemLabel(Current.Items[I])) + 3);
  W := MaxW + 2;
  if W > PanelBounds.Width - 1 then
    W := Max(PanelBounds.Width - 1, 16);
  H := Max(ItemCount, 1) + 2;
  if H > PanelBounds.Height - 1 then
    H := Max(PanelBounds.Height - 1, 3);
  FBounds := TRectI.Make(
    PanelBounds.Left + 2,
    PanelBounds.Top + 2,
    PanelBounds.Left + 2 + W - 1,
    PanelBounds.Top + 2 + H - 1);
end;

function TUserMenuController.ViewRows: Integer;
begin
  Result := Max(FBounds.Height - 2, 1);
end;

procedure TUserMenuController.EnsureCursorVisible;
begin
  if FIndex < FTop then
    FTop := FIndex;
  if FIndex >= FTop + ViewRows then
    FTop := FIndex - ViewRows + 1;
  FTop := EnsureRange(FTop, 0, Max(ItemCount - ViewRows, 0));
end;

procedure TUserMenuController.Draw(const AGrid: TTerminalGrid);
var
  R: TRectI;
  I, Row, Y, InnerW: Integer;
  Item: TUserMenuItem;
  Line: string;
  Fg, Bg: TAlphaColor;
begin
  if not FVisible then
    Exit;
  Layout;
  EnsureCursorVisible;
  R := FBounds;
  if (R.Width < 8) or (R.Height < 3) then
    Exit;
  DrawHostOverlayFrame(AGrid, FTheme, R, Title,
    cFileFg, cPanelBg, cFrameActive, cCursorFg);
  InnerW := R.Width - 2;
  ResolveOverlayTextColors(FTheme, False, False, False, cFileFg, cPanelBg, Fg, Bg);
  if ItemCount = 0 then
  begin
    Line := Copy(' ' + T('ui.userMenu.empty', '(empty: Ins adds an item)'), 1, InnerW);
    PutGridText(AGrid, R.Left + 1, R.Top + 1, Line.PadRight(InnerW), Fg, Bg);
    Exit;
  end;
  for Row := 0 to ViewRows - 1 do
  begin
    I := FTop + Row;
    if I >= ItemCount then
      Break;
    Y := R.Top + 1 + Row;
    Item := Current.Items[I];
    if Item.Kind = umkSeparator then
    begin
      ResolveOverlayTextColors(FTheme, False, False, False, cFileFg, cPanelBg, Fg, Bg);
      PutGridText(AGrid, R.Left + 1, Y, StringOfChar(cSeparatorChar, InnerW), Fg, Bg);
      Continue;
    end;
    Line := ItemLabel(Item);
    if Item.Kind = umkSubmenu then
      Line := Copy(Line, 1, InnerW - 2).PadRight(InnerW - 2) + cSubmenuMark + ' '
    else
      Line := Copy(Line, 1, InnerW).PadRight(InnerW);
    if I = FIndex then
      ResolveOverlayTextColors(FTheme, False, False, True, cCursorFg, cCursorBg, Fg, Bg)
    else
      ResolveOverlayTextColors(FTheme, Item.Kind = umkSubmenu, False, False,
        cFileFg, cPanelBg, Fg, Bg);
    PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);
    // Same accent as the F9 menus' hotkeys, on the cursor row too.
    if Item.HotKey <> '' then
      PutGridText(AGrid, R.Left + 2, Y, Item.HotKey, cMenuHotKeyFg, Bg, [ccaBold]);
  end;
end;

// Moves over |ADelta| selectable items (separators do not count), stopping
// at the last selectable one when the list ends first.
procedure TUserMenuController.MoveCursor(ADelta: Integer);
var
  I, Best, Remaining: Integer;
begin
  if ItemCount = 0 then
  begin
    FIndex := 0;
    Exit;
  end;
  I := FIndex;
  Best := FIndex;
  Remaining := Abs(ADelta);
  while Remaining > 0 do
  begin
    Inc(I, Sign(ADelta));
    if (I < 0) or (I >= ItemCount) then
      Break;
    if IsSelectable(I) then
    begin
      Best := I;
      Dec(Remaining);
    end;
  end;
  FIndex := Best;
end;

procedure TUserMenuController.Activate(AIndex: Integer);
var
  Item: TUserMenuItem;
begin
  if not IsSelectable(AIndex) then
    Exit;
  FIndex := AIndex;
  Item := Current.Items[AIndex];
  if Item.Kind = umkSubmenu then
  begin
    FPath.Add(Item);
    FPathIndex.Add(AIndex);
    FTop := 0;
    ItemsChanged(0);
  end
  else
  begin
    // Close first: the host may open a prompt dialog or run the command in
    // the console, and neither should sit under a stale popup.
    FVisible := False;
    Fire(umaExecute, AIndex);
    Close;
  end;
end;

procedure TUserMenuController.GoUp;
var
  Back: Integer;
begin
  if FPath.Count = 0 then
  begin
    Close;
    Exit;
  end;
  Back := FPathIndex.Last;
  FPath.Delete(FPath.Count - 1);
  FPathIndex.Delete(FPathIndex.Count - 1);
  FTop := 0;
  ItemsChanged(Back);
end;

procedure TUserMenuController.MoveItem(ADelta: Integer);
var
  Target: Integer;
begin
  Target := FIndex + ADelta;
  if (FIndex < 0) or (FIndex >= ItemCount) or (Target < 0) or (Target >= ItemCount) then
    Exit;
  Current.Items.Exchange(FIndex, Target);
  FIndex := Target;
  EnsureCursorVisible;
  Fire(umaMoved, FIndex);
  Invalidate;
end;

function TUserMenuController.FindHotKey(AChar: Char): Integer;
var
  Alt: Char;
  Pass, I: Integer;
  Hot: Char;
begin
  Result := -1;
  if AChar < ' ' then
    Exit;
  Alt := TextKeyLayoutAlternate(AChar);
  // Exact char first, then the same key on the other keyboard layout.
  for Pass := 0 to 1 do
    for I := 0 to ItemCount - 1 do
    begin
      if not IsSelectable(I) or (Current.Items[I].HotKey = '') then
        Continue;
      Hot := Current.Items[I].HotKey[1].ToUpper;
      if ((Pass = 0) and (Hot = AChar.ToUpper)) or
         ((Pass = 1) and (Alt <> #0) and (Hot = Alt)) then
        Exit(I);
    end;
end;

function TUserMenuController.HandleInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Hot: Integer;
  Ctrl: Boolean;
begin
  Result := True;
  Ctrl := ssCtrl in AShift;
  case AKey of
    vkEscape:
      begin
        GoUp;
        AKey := 0;
        Exit;
      end;
    vkLeft:
      begin
        if FPath.Count > 0 then
          GoUp;
        AKey := 0;
        Exit;
      end;
    vkUp, vkDown:
      begin
        if Ctrl then
        begin
          if AKey = vkUp then
            MoveItem(-1)
          else
            MoveItem(1);
        end
        else
        begin
          if AKey = vkUp then
            MoveCursor(-1)
          else
            MoveCursor(1);
          EnsureCursorVisible;
          Invalidate;
        end;
        AKey := 0;
        Exit;
      end;
    vkHome, vkEnd, vkPrior, vkNext:
      begin
        case AKey of
          vkHome: begin FIndex := 0; if not IsSelectable(0) then MoveCursor(1); end;
          vkEnd: begin FIndex := Max(ItemCount - 1, 0); if not IsSelectable(FIndex) then MoveCursor(-1); end;
          vkPrior: MoveCursor(-Max(ViewRows - 1, 1));
          vkNext: MoveCursor(Max(ViewRows - 1, 1));
        end;
        EnsureCursorVisible;
        Invalidate;
        AKey := 0;
        Exit;
      end;
    vkReturn, vkRight:
      begin
        // Right only enters submenus; Enter also runs commands.
        if (AKey = vkReturn) or (IsSelectable(FIndex) and
           (Current.Items[FIndex].Kind = umkSubmenu)) then
          Activate(FIndex);
        AKey := 0;
        Exit;
      end;
    vkInsert:
      begin
        if ItemCount = 0 then
          Fire(umaInsert, 0)
        else
          Fire(umaInsert, FIndex);
        AKey := 0;
        Exit;
      end;
    vkF4:
      begin
        if (FIndex >= 0) and (FIndex < ItemCount) then
          Fire(umaEdit, FIndex);
        AKey := 0;
        Exit;
      end;
    vkF2:
      begin
        // The host answers with Open on the other menu's tree; nothing of
        // the current one may be touched after this.
        if ssShift in AShift then
        begin
          AKey := 0;
          Fire(umaSwitchMenu, FIndex);
          Exit;
        end;
      end;
    vkDelete:
      begin
        if (FIndex >= 0) and (FIndex < ItemCount) then
          Fire(umaDelete, FIndex);
        AKey := 0;
        Exit;
      end;
  end;
  if (AKeyChar <> #0) and not Ctrl and not (ssAlt in AShift) then
  begin
    Hot := FindHotKey(AKeyChar);
    if Hot >= 0 then
      Activate(Hot);
  end;
  // Modal while open: nothing reaches the panel underneath.
  AKey := 0;
  AKeyChar := #0;
end;

function TUserMenuController.HandleClick(ALocalCol,
  ALocalRow: Integer): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if not FVisible then
    Exit;
  Layout;
  Result := True;
  if WindowFrameCloseHit(FBounds, ALocalCol, ALocalRow) then
  begin
    Close;
    Exit;
  end;
  if not FBounds.Contains(ALocalCol, ALocalRow) then
  begin
    Close;
    Exit;
  end;
  if (ALocalCol <= FBounds.Left) or (ALocalCol >= FBounds.Right) then
    Exit;
  Idx := FTop + ALocalRow - (FBounds.Top + 1);
  if (ALocalRow > FBounds.Top) and (ALocalRow < FBounds.Bottom) and IsSelectable(Idx) then
    Activate(Idx);
end;

end.
