unit uDualPanelMenus;

{ Facade over the independent User / Sort-by / Column-mode menu popups and
  the shell-info stub overlay. Owns cross-menu mutual exclusion (opening one
  closes the others); each popup's own layout/draw/input lives in its own
  controller unit. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uTerminalTypes, uThemeTypes, uDualPanelTypes, uDualPanelUiTypes,
  uUserMenu, uUserMenuController, uSortMenuController, uColumnModeMenuController,
  uStubController;

type
  TUserMenuActionEvent = uUserMenuController.TUserMenuActionEvent;
  TSortSelectEvent = uSortMenuController.TSortSelectEvent;
  TColumnModeSelectEvent = uColumnModeMenuController.TColumnModeSelectEvent;
  TMenuPanelBoundsEvent = uUserMenuController.TMenuPanelBoundsEvent;
  TActiveSideEvent = uUserMenuController.TActiveSideEvent;

  TMenuStubController = class
  private
    FUserMenu: TUserMenuController;
    FSortMenu: TSortMenuController;
    FColumnModeMenu: TColumnModeMenuController;
    FStub: TStubController;
    function GetUserMenuVisible: Boolean;
    function GetSortMenuVisible: Boolean;
    function GetColumnModeMenuVisible: Boolean;
    function GetStubVisible: Boolean;
    function GetUserMenuBounds: TRectI;
    function GetSortMenuBounds: TRectI;
    function GetColumnModeMenuBounds: TRectI;
    function GetStubBounds: TRectI;
    function GetStubText: string;
    procedure SetStubText(const AValue: string);
    function GetStubDetail: string;
    procedure SetStubDetail(const AValue: string);
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AOnUserMenuAction: TUserMenuActionEvent;
      const AGetActivePanelBounds: TMenuPanelBoundsEvent;
      const AGetActiveSide: TActiveSideEvent);
    destructor Destroy; override;
    procedure SetTheme(const ATheme: IThemeRenderer);
    procedure SetOnSortSelect(const AHandler: TSortSelectEvent);
    procedure SetOnColumnModeSelect(const AHandler: TColumnModeSelectEvent);
    /// <summary>ARoot stays owned by the caller (see TUserMenuController.Open).</summary>
    procedure OpenUserMenu(ARoot: TUserMenuItem; const ATitle: string = '');
    procedure CloseUserMenu;
    procedure UserMenuItemsChanged(ASelectIndex: Integer);
    procedure LayoutUserMenu;
    procedure DrawUserMenu(const AGrid: TTerminalGrid);
    function HandleUserMenuInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleUserMenuClick(ALocalCol, ALocalRow: Integer): Boolean;
    procedure OpenSortMenu(ACurrent: TPanelSortColumn; ADescending: Boolean);
    procedure CloseSortMenu;
    procedure LayoutSortMenu;
    procedure DrawSortMenu(const AGrid: TTerminalGrid);
    function HandleSortMenuInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleSortMenuClick(ALocalCol, ALocalRow: Integer): Boolean;
    procedure OpenColumnModeMenu(ACurrent: TPanelColumnMode);
    procedure CloseColumnModeMenu;
    procedure LayoutColumnModeMenu;
    procedure DrawColumnModeMenu(const AGrid: TTerminalGrid);
    function HandleColumnModeMenuInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleColumnModeMenuClick(ALocalCol, ALocalRow: Integer): Boolean;
    procedure OpenStub(AKind: TStubKind; const ATitle, ADetail: string);
    procedure CloseStub;
    procedure LayoutStub(AClientWidth, AClientHeight: Integer);
    procedure DrawStub(const AGrid: TTerminalGrid;
      AClientWidth, AClientHeight: Integer);
    function HandleStubInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    property UserMenuVisible: Boolean read GetUserMenuVisible;
    property SortMenuVisible: Boolean read GetSortMenuVisible;
    property ColumnModeMenuVisible: Boolean read GetColumnModeMenuVisible;
    property StubVisible: Boolean read GetStubVisible;
    property UserMenuBounds: TRectI read GetUserMenuBounds;
    property SortMenuBounds: TRectI read GetSortMenuBounds;
    property ColumnModeMenuBounds: TRectI read GetColumnModeMenuBounds;
    property StubBounds: TRectI read GetStubBounds;
    property StubText: string read GetStubText write SetStubText;
    property StubDetail: string read GetStubDetail write SetStubDetail;
  end;

implementation

constructor TMenuStubController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AOnUserMenuAction: TUserMenuActionEvent;
  const AGetActivePanelBounds: TMenuPanelBoundsEvent;
  const AGetActiveSide: TActiveSideEvent);
begin
  inherited Create;
  FUserMenu := TUserMenuController.Create(ATheme, AOnInvalidate,
    AOnUserMenuAction, AGetActivePanelBounds, AGetActiveSide);
  FSortMenu := TSortMenuController.Create(ATheme, AOnInvalidate,
    AGetActivePanelBounds, AGetActiveSide);
  FColumnModeMenu := TColumnModeMenuController.Create(ATheme, AOnInvalidate,
    AGetActivePanelBounds, AGetActiveSide);
  FStub := TStubController.Create(ATheme, AOnInvalidate);
end;

destructor TMenuStubController.Destroy;
begin
  FUserMenu.Free;
  FSortMenu.Free;
  FColumnModeMenu.Free;
  FStub.Free;
  inherited Destroy;
end;

procedure TMenuStubController.SetTheme(const ATheme: IThemeRenderer);
begin
  FUserMenu.SetTheme(ATheme);
  FSortMenu.SetTheme(ATheme);
  FColumnModeMenu.SetTheme(ATheme);
  FStub.SetTheme(ATheme);
end;

procedure TMenuStubController.SetOnSortSelect(const AHandler: TSortSelectEvent);
begin
  FSortMenu.SetOnSortSelect(AHandler);
end;

procedure TMenuStubController.SetOnColumnModeSelect(
  const AHandler: TColumnModeSelectEvent);
begin
  FColumnModeMenu.SetOnColumnModeSelect(AHandler);
end;

function TMenuStubController.GetUserMenuVisible: Boolean;
begin
  Result := FUserMenu.Visible;
end;

function TMenuStubController.GetSortMenuVisible: Boolean;
begin
  Result := FSortMenu.Visible;
end;

function TMenuStubController.GetColumnModeMenuVisible: Boolean;
begin
  Result := FColumnModeMenu.Visible;
end;

function TMenuStubController.GetStubVisible: Boolean;
begin
  Result := FStub.Visible;
end;

function TMenuStubController.GetUserMenuBounds: TRectI;
begin
  Result := FUserMenu.Bounds;
end;

function TMenuStubController.GetSortMenuBounds: TRectI;
begin
  Result := FSortMenu.Bounds;
end;

function TMenuStubController.GetColumnModeMenuBounds: TRectI;
begin
  Result := FColumnModeMenu.Bounds;
end;

function TMenuStubController.GetStubBounds: TRectI;
begin
  Result := FStub.Bounds;
end;

function TMenuStubController.GetStubText: string;
begin
  Result := FStub.Text;
end;

procedure TMenuStubController.SetStubText(const AValue: string);
begin
  FStub.Text := AValue;
end;

function TMenuStubController.GetStubDetail: string;
begin
  Result := FStub.Detail;
end;

procedure TMenuStubController.SetStubDetail(const AValue: string);
begin
  FStub.Detail := AValue;
end;

procedure TMenuStubController.OpenUserMenu(ARoot: TUserMenuItem;
  const ATitle: string);
begin
  FSortMenu.Close;
  FColumnModeMenu.Close;
  FUserMenu.Open(ARoot, ATitle);
end;

procedure TMenuStubController.CloseUserMenu;
begin
  FUserMenu.Close;
end;

procedure TMenuStubController.UserMenuItemsChanged(ASelectIndex: Integer);
begin
  if FUserMenu.Visible then
    FUserMenu.ItemsChanged(ASelectIndex);
end;

procedure TMenuStubController.LayoutUserMenu;
begin
  FUserMenu.Layout;
end;

procedure TMenuStubController.DrawUserMenu(const AGrid: TTerminalGrid);
begin
  FUserMenu.Draw(AGrid);
end;

function TMenuStubController.HandleUserMenuInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := FUserMenu.HandleInput(AKey, AShift, AKeyChar);
end;

function TMenuStubController.HandleUserMenuClick(ALocalCol,
  ALocalRow: Integer): Boolean;
begin
  Result := FUserMenu.HandleClick(ALocalCol, ALocalRow);
end;

procedure TMenuStubController.OpenSortMenu(ACurrent: TPanelSortColumn;
  ADescending: Boolean);
begin
  FUserMenu.Close;
  FColumnModeMenu.Close;
  FSortMenu.Open(ACurrent, ADescending);
end;

procedure TMenuStubController.CloseSortMenu;
begin
  FSortMenu.Close;
end;

procedure TMenuStubController.LayoutSortMenu;
begin
  FSortMenu.Layout;
end;

procedure TMenuStubController.DrawSortMenu(const AGrid: TTerminalGrid);
begin
  FSortMenu.Draw(AGrid);
end;

function TMenuStubController.HandleSortMenuInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := FSortMenu.HandleInput(AKey, AShift, AKeyChar);
end;

function TMenuStubController.HandleSortMenuClick(ALocalCol,
  ALocalRow: Integer): Boolean;
begin
  Result := FSortMenu.HandleClick(ALocalCol, ALocalRow);
end;

procedure TMenuStubController.OpenColumnModeMenu(ACurrent: TPanelColumnMode);
begin
  FUserMenu.Close;
  FSortMenu.Close;
  FColumnModeMenu.Open(ACurrent);
end;

procedure TMenuStubController.CloseColumnModeMenu;
begin
  FColumnModeMenu.Close;
end;

procedure TMenuStubController.LayoutColumnModeMenu;
begin
  FColumnModeMenu.Layout;
end;

procedure TMenuStubController.DrawColumnModeMenu(const AGrid: TTerminalGrid);
begin
  FColumnModeMenu.Draw(AGrid);
end;

function TMenuStubController.HandleColumnModeMenuInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := FColumnModeMenu.HandleInput(AKey, AShift, AKeyChar);
end;

function TMenuStubController.HandleColumnModeMenuClick(ALocalCol,
  ALocalRow: Integer): Boolean;
begin
  Result := FColumnModeMenu.HandleClick(ALocalCol, ALocalRow);
end;

procedure TMenuStubController.OpenStub(AKind: TStubKind; const ATitle,
  ADetail: string);
begin
  FStub.Open(AKind, ATitle, ADetail);
end;

procedure TMenuStubController.CloseStub;
begin
  FStub.Close;
end;

procedure TMenuStubController.LayoutStub(AClientWidth, AClientHeight: Integer);
begin
  FStub.Layout(AClientWidth, AClientHeight);
end;

procedure TMenuStubController.DrawStub(const AGrid: TTerminalGrid;
  AClientWidth, AClientHeight: Integer);
begin
  FStub.Draw(AGrid, AClientWidth, AClientHeight);
end;

function TMenuStubController.HandleStubInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := FStub.HandleInput(AKey, AShift, AKeyChar);
end;

end.
