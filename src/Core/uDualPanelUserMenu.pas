unit uDualPanelUserMenu;

{ User menu (F2) host side: owns the menu tree loaded from usermenu.json,
  answers the popup's requests (uUserMenuController.pas) with the item
  editor / delete confirmation dialogs, saves every change, and runs a
  chosen command -- asking the !?Question?default! prompts first, one input
  dialog each -- through the panel console.

  Two menus: the main one (usermenu.json in the config directory) and the
  folder menu (.mtn2menu.json of the active folder or its nearest ancestor,
  uUserMenu.FindFolderUserMenu). F2 opens the folder menu when there is one;
  Shift+F2 in the popup switches between the two. Switching to a folder
  that has no menu yet shows an empty one; its first edit creates the file
  in the active folder. }

interface

uses
  System.SysUtils, System.Classes, System.Math,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uUserMenu, uUserMenuController,
  uStrings;

type
  TUserMenuKindSetter = reference to procedure(AKind: THostDialogKind);
  TUserMenuContextFn = reference to function: TUserMenuContext;
  TUserMenuRunProc = reference to procedure(const ACommand: string);
  TUserMenuShowProc = reference to procedure(ARoot: TUserMenuItem;
    const ATitle: string);
  TUserMenuFolderFn = reference to function: string;
  TUserMenuSource = (umsMain, umsFolder);
  TUserMenuChangedProc = reference to procedure(ASelectIndex: Integer);

  TUserMenuDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TUserMenuKindSetter;
    FOnNotify: TProc;
    FGetContext: TUserMenuContextFn;
    FRun: TUserMenuRunProc;
    FShowMenu: TUserMenuShowProc;
    FItemsChanged: TUserMenuChangedProc;
    FGetFolder: TUserMenuFolderFn;
    FMainFilePath: string;
    // The menu on screen and the file it is saved to.
    FSource: TUserMenuSource;
    FFilePath: string;
    FRoot: TUserMenuItem;
    // Item editor / delete confirmation target.
    FEditParent: TUserMenuItem;
    FEditIndex: Integer;
    FEditNew: Boolean;
    // Command waiting for its prompts to be answered.
    FRunTemplate: string;
    FRunTitle: string;
    FRunContext: TUserMenuContext;
    FRunPrompts: TArray<TUserMenuPrompt>;
    FRunAnswers: TArray<string>;
    function ActiveFolder: string;
    procedure ShowMenu(ASource: TUserMenuSource);
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure Save;
    procedure MenuChanged(ASelectIndex: Integer);
    procedure BeginEdit(AParent: TUserMenuItem; AIndex: Integer; ANew: Boolean);
    procedure BeginDelete(AParent: TUserMenuItem; AIndex: Integer);
    procedure BeginRun(AItem: TUserMenuItem);
    procedure AskNextPrompt;
    procedure DispatchEditCommand(const AControlId: string);
    procedure DispatchConfirmCommand(const AControlId: string);
    procedure DispatchPromptCommand(const AControlId: string);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TUserMenuKindSetter; const AOnNotify: TProc;
      const AGetContext: TUserMenuContextFn; const ARun: TUserMenuRunProc;
      const AShowMenu: TUserMenuShowProc; const AItemsChanged: TUserMenuChangedProc;
      const AGetFolder: TUserMenuFolderFn);
    destructor Destroy; override;
    /// <summary>Re-reads the menu file and shows the popup: the folder menu
    /// when the active folder (or an ancestor) has one, else the main menu.
    /// The previous tree is freed; the popup is re-pointed at the new one.</summary>
    procedure OpenMenu;
    /// <summary>The popup's TUserMenuActionEvent.</summary>
    procedure HandleMenuAction(AAction: TUserMenuAction; AParent: TUserMenuItem;
      AIndex: Integer);
    function DispatchCommand(AKind: THostDialogKind; const AControlId: string): Boolean;
    /// <summary>Test seam: where the main menu is loaded from and saved to.</summary>
    property MainFilePath: string read FMainFilePath write FMainFilePath;
    /// <summary>File of the menu on screen (may not exist yet).</summary>
    property FilePath: string read FFilePath;
    property Source: TUserMenuSource read FSource;
    property Root: TUserMenuItem read FRoot;
  end;

implementation

uses
  uDialogResources;

function KindToIndex(AKind: TUserMenuKind): Integer;
begin
  Result := Ord(AKind); // dropdown order matches TUserMenuKind
end;

function IndexToKind(AIndex: Integer): TUserMenuKind;
begin
  Result := TUserMenuKind(EnsureRange(AIndex, Ord(Low(TUserMenuKind)),
    Ord(High(TUserMenuKind))));
end;

constructor TUserMenuDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TUserMenuKindSetter;
  const AOnNotify: TProc; const AGetContext: TUserMenuContextFn;
  const ARun: TUserMenuRunProc; const AShowMenu: TUserMenuShowProc;
  const AItemsChanged: TUserMenuChangedProc; const AGetFolder: TUserMenuFolderFn);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FGetContext := AGetContext;
  FRun := ARun;
  FShowMenu := AShowMenu;
  FItemsChanged := AItemsChanged;
  FGetFolder := AGetFolder;
  FMainFilePath := DefaultUserMenuFilePath;
end;

destructor TUserMenuDialogController.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

procedure TUserMenuDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TUserMenuDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TUserMenuDialogController.Save;
begin
  SaveUserMenu(FFilePath, FRoot);
end;

procedure TUserMenuDialogController.MenuChanged(ASelectIndex: Integer);
begin
  if Assigned(FItemsChanged) then
    FItemsChanged(ASelectIndex);
  Notify;
end;

function TUserMenuDialogController.ActiveFolder: string;
begin
  if Assigned(FGetFolder) then
    Result := FGetFolder()
  else
    Result := '';
end;

procedure TUserMenuDialogController.OpenMenu;
begin
  if FindFolderUserMenu(ActiveFolder) <> '' then
    ShowMenu(umsFolder)
  else
    ShowMenu(umsMain);
end;

procedure TUserMenuDialogController.ShowMenu(ASource: TUserMenuSource);
var
  Folder, Title, MenuDir: string;
begin
  Folder := ActiveFolder;
  // Not a local folder (archive, SFTP ...): only the main menu exists.
  if (ASource = umsFolder) and (Folder = '') then
    ASource := umsMain;
  FreeAndNil(FRoot);
  FEditParent := nil;
  FSource := ASource;
  // Read on every open: a hand-edited menu file applies without a restart.
  if ASource = umsFolder then
  begin
    FFilePath := FindFolderUserMenu(Folder);
    if FFilePath = '' then
      FFilePath := FolderUserMenuPath(Folder);
    FRoot := LoadUserMenu(FFilePath, False);
    MenuDir := ExcludeTrailingPathDelimiter(ExtractFilePath(FFilePath));
    // A drive root has no folder name: show "C:" itself.
    if ExtractFileName(MenuDir) <> '' then
      MenuDir := ExtractFileName(MenuDir);
    Title := T('ui.userMenu.folderTitle', 'Folder menu: %s', [MenuDir]);
  end
  else
  begin
    FFilePath := FMainFilePath;
    FRoot := LoadUserMenu(FFilePath);
    Title := T('ui.userMenu.title', 'User menu');
  end;
  if Assigned(FShowMenu) then
    FShowMenu(FRoot, Title);
  Notify;
end;

procedure TUserMenuDialogController.HandleMenuAction(AAction: TUserMenuAction;
  AParent: TUserMenuItem; AIndex: Integer);
begin
  if not Assigned(AParent) then
    Exit;
  case AAction of
    umaExecute:
      if (AIndex >= 0) and (AIndex < AParent.Items.Count) then
        BeginRun(AParent.Items[AIndex]);
    umaInsert:
      BeginEdit(AParent, AIndex, True);
    umaEdit:
      if (AIndex >= 0) and (AIndex < AParent.Items.Count) then
        BeginEdit(AParent, AIndex, False);
    umaDelete:
      if (AIndex >= 0) and (AIndex < AParent.Items.Count) then
        BeginDelete(AParent, AIndex);
    umaMoved:
      Save;
    umaSwitchMenu:
      if FSource = umsMain then
        ShowMenu(umsFolder)
      else
        ShowMenu(umsMain);
  end;
end;

procedure TUserMenuDialogController.BeginEdit(AParent: TUserMenuItem;
  AIndex: Integer; ANew: Boolean);
var
  Item: TUserMenuItem;
begin
  FEditParent := AParent;
  FEditIndex := AIndex;
  FEditNew := ANew;
  SetKind(hdkUserMenuEdit);
  if ANew then
    FDialog.Open(BuildUserMenuEditDialog('', '', '', KindToIndex(umkCommand)), FOnCommand)
  else
  begin
    Item := AParent.Items[AIndex];
    FDialog.Open(BuildUserMenuEditDialog(Item.HotKey, Item.Caption, Item.Command,
      KindToIndex(Item.Kind)), FOnCommand);
  end;
  Notify;
end;

procedure TUserMenuDialogController.BeginDelete(AParent: TUserMenuItem;
  AIndex: Integer);
var
  Item: TUserMenuItem;
  Msg: string;
begin
  FEditParent := AParent;
  FEditIndex := AIndex;
  Item := AParent.Items[AIndex];
  case Item.Kind of
    umkSeparator:
      Msg := T('ui.userMenu.confirmDeleteSeparator', 'Delete the separator?');
    umkSubmenu:
      Msg := T('ui.userMenu.confirmDeleteSubmenu',
        'Delete submenu "%s" with all its items?', [Item.Caption]);
  else
    Msg := T('ui.userMenu.confirmDelete', 'Delete "%s"?', [Item.Caption]);
  end;
  SetKind(hdkUserMenuConfirm);
  FDialog.Open(BuildConfirmDialog(T('ui.userMenu.title', 'User menu'), Msg), FOnCommand);
  Notify;
end;

procedure TUserMenuDialogController.BeginRun(AItem: TUserMenuItem);
begin
  if (AItem.Kind <> umkCommand) or (Trim(AItem.Command) = '') then
    Exit;
  // The panels as they are now, before any prompt dialog: that is what the
  // user picked the command for.
  if Assigned(FGetContext) then
    FRunContext := FGetContext()
  else
    FRunContext := Default(TUserMenuContext);
  FRunTemplate := AItem.Command;
  FRunTitle := AItem.Caption;
  FRunPrompts := ParseUserMenuPrompts(FRunTemplate);
  FRunAnswers := nil;
  AskNextPrompt;
end;

procedure TUserMenuDialogController.AskNextPrompt;
var
  Prompt: TUserMenuPrompt;
  Cmd: string;
  Decl: TDialogDeclaration;
begin
  if Length(FRunAnswers) < Length(FRunPrompts) then
  begin
    Prompt := FRunPrompts[Length(FRunAnswers)];
    SetKind(hdkUserMenuPrompt);
    Decl := BuildInputDialog(FRunTitle, Prompt.Title, Prompt.Default);
    DialogSetInputHistory(Decl, 'name', 'usermenuprompt');
    FDialog.Open(Decl, FOnCommand);
    Notify;
    Exit;
  end;
  Cmd := Trim(ExpandUserMenuCommand(FRunTemplate, FRunContext, FRunAnswers));
  FRunTemplate := '';
  if (Cmd <> '') and Assigned(FRun) then
    FRun(Cmd);
  Notify;
end;

procedure TUserMenuDialogController.DispatchEditCommand(const AControlId: string);
var
  Accepted: Boolean;
  HotKey, Caption, Command: string;
  Kind: TUserMenuKind;
  Item: TUserMenuItem;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  HotKey := Copy(Trim(FDialog.GetInputValue('hotkey')), 1, 1);
  Caption := Trim(FDialog.GetInputValue('caption'));
  Command := Trim(FDialog.GetInputValue('command'));
  Kind := IndexToKind(FDialog.GetListSelectedIndex('kind'));
  FDialog.Close;
  if not Accepted or not Assigned(FEditParent) then
  begin
    MenuChanged(FEditIndex);
    Exit;
  end;
  // A command without a caption shows the command itself.
  if (Kind = umkCommand) and (Caption = '') then
    Caption := Command;
  if (Kind <> umkSeparator) and (Caption = '') then
  begin
    MenuChanged(FEditIndex); // nothing to show: treat as cancel
    Exit;
  end;
  if FEditNew then
  begin
    Item := TUserMenuItem.Create(Kind);
    FEditIndex := EnsureRange(FEditIndex, 0, FEditParent.Items.Count);
    FEditParent.Items.Insert(FEditIndex, Item);
  end
  else
    Item := FEditParent.Items[FEditIndex];
  Item.Kind := Kind;
  if Kind = umkSeparator then
  begin
    Item.HotKey := '';
    Item.Caption := '';
    Item.Command := '';
  end
  else
  begin
    Item.HotKey := HotKey;
    Item.Caption := Caption;
    Item.Command := Command;
  end;
  Save;
  MenuChanged(FEditIndex);
end;

procedure TUserMenuDialogController.DispatchConfirmCommand(const AControlId: string);
var
  Accepted: Boolean;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  FDialog.Close;
  if Accepted and Assigned(FEditParent) and (FEditIndex >= 0) and
     (FEditIndex < FEditParent.Items.Count) then
  begin
    FEditParent.Items.Delete(FEditIndex); // owned: frees the item
    Save;
  end;
  MenuChanged(FEditIndex);
end;

procedure TUserMenuDialogController.DispatchPromptCommand(const AControlId: string);
var
  Accepted: Boolean;
  Answer: string;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  Answer := FDialog.GetInputValue('name');
  FDialog.Close;
  if not Accepted then
  begin
    // Cancelling any prompt cancels the command.
    FRunTemplate := '';
    Notify;
    Exit;
  end;
  FRunAnswers := FRunAnswers + [Answer];
  AskNextPrompt;
end;

function TUserMenuDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkUserMenuEdit: DispatchEditCommand(AControlId);
    hdkUserMenuConfirm: DispatchConfirmCommand(AControlId);
    hdkUserMenuPrompt: DispatchPromptCommand(AControlId);
  else
    Result := False;
  end;
end;

end.
