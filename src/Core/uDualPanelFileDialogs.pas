unit uDualPanelFileDialogs;

{ MkDir / New file / Rename / Copy-in-place / Create-link / Select-mask
  dialogs. Extracted from TDualPanelWindow so the host keeps thin Begin*
  forwards and Confirm* callbacks. }

interface

uses
  System.SysUtils, System.Classes,
  uDialogHost, uDialogTypes, uDialogJson, uDualPanelUiTypes, uVfsTypes, uLinkUtils,
  uWinFileAttr, uStrings;

type
  TFileOpKindSetter = reference to procedure(AKind: THostDialogKind);
  TFileOpCanStart = reference to function: Boolean;
  TFileOpUnfocusCmd = reference to procedure;
  TFileOpGetActiveUri = reference to function: string;
  TFileOpInPanels = reference to function: Boolean;
  TFileOpShowStub = reference to procedure(const ATitle, ADetail: string);
  TFileOpGetMask = reference to function: string;
  TFileOpGetSelectFolders = reference to function: Boolean;
  TFileOpTryGetItem = reference to function(out AName, AUri, ATargetUri: string;
    out AIsParent: Boolean): Boolean;
  TFileOpRememberUri = reference to procedure(const AUri: string);
  TFileOpConfirmName = reference to procedure(const AName: string);
  TFileOpConfirmSelect = reference to procedure(const AMask: string; AUnselect,
    ASelectFolders: Boolean);
  TFileOpConfirmLink = reference to procedure(const AName, ATarget: string;
    AKind: TLinkKind);
  TFileOpApplySetAttr = reference to procedure(const APaths: TArray<string>;
    const APlan: TFileAttrPlan);

  TFileOpDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TFileOpKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TFileOpCanStart;
    FOnUnfocusCmd: TFileOpUnfocusCmd;
    FOnGetActiveUri: TFileOpGetActiveUri;
    FOnInPanels: TFileOpInPanels;
    FOnShowStub: TFileOpShowStub;
    FOnGetMask: TFileOpGetMask;
    FOnGetSelectFolders: TFileOpGetSelectFolders;
    FOnTryGetItem: TFileOpTryGetItem;
    FOnRememberUri: TFileOpRememberUri;
    FOnConfirmMkDir: TFileOpConfirmName;
    FOnConfirmNewFile: TFileOpConfirmName;
    FOnConfirmRename: TFileOpConfirmName;
    FOnConfirmCopyInPlace: TFileOpConfirmName;
    FOnConfirmSelect: TFileOpConfirmSelect;
    FOnConfirmLink: TFileOpConfirmLink;
    FOnApplySetAttr: TFileOpApplySetAttr;
    FAttrPaths: TArray<string>;
    // Date text the dialog opened with (date_created / _modified / _accessed):
    // an unchanged field is not written, so seconds-truncated display text
    // never rounds away a file's sub-second time.
    FAttrDateTexts: array[0..2] of string;
    function ReadAttrDateFields(var APlan: TFileAttrPlan; out ABadText: string): Boolean;
    procedure KeepSetAttributesOpen;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure UnfocusCmd;
    function DialogBlocked: Boolean;
    procedure OpenNamedInput(AKind: THostDialogKind; const ATitle, APrompt,
      AValue: string; APreferJson: Boolean);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TFileOpKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TFileOpCanStart; const AOnUnfocusCmd: TFileOpUnfocusCmd;
      const AOnGetActiveUri: TFileOpGetActiveUri; const AOnInPanels: TFileOpInPanels;
      const AOnShowStub: TFileOpShowStub; const AOnGetMask: TFileOpGetMask;
      const AOnGetSelectFolders: TFileOpGetSelectFolders;
      const AOnTryGetItem: TFileOpTryGetItem;
      const AOnRememberUri: TFileOpRememberUri;
      const AOnConfirmMkDir, AOnConfirmNewFile, AOnConfirmRename,
      AOnConfirmCopyInPlace: TFileOpConfirmName;
      const AOnConfirmSelect: TFileOpConfirmSelect;
      const AOnConfirmLink: TFileOpConfirmLink;
      const AOnApplySetAttr: TFileOpApplySetAttr);
    procedure BeginMkDir;
    procedure BeginNewFile;
    procedure BeginSelectByMask(AUnselect: Boolean);
    procedure BeginRename;
    procedure BeginCopyInPlace;
    procedure BeginCreateLink;
    procedure BeginSetAttributes(const APaths: TArray<string>);
    procedure DispatchSimpleNameCommand(const AControlId: string;
      const ACallback: TFileOpConfirmName);
    procedure DispatchSelectMaskCommand(AKind: THostDialogKind;
      const AControlId: string);
    procedure DispatchCreateLinkCommand(const AControlId: string);
    function DispatchSetAttributesCommand(const AControlId: string): Boolean;
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

uses
  uDialogResources;

constructor TFileOpDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TFileOpKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TFileOpCanStart;
  const AOnUnfocusCmd: TFileOpUnfocusCmd; const AOnGetActiveUri: TFileOpGetActiveUri;
  const AOnInPanels: TFileOpInPanels;   const AOnShowStub: TFileOpShowStub;
  const AOnGetMask: TFileOpGetMask; const AOnGetSelectFolders: TFileOpGetSelectFolders;
  const AOnTryGetItem: TFileOpTryGetItem;
  const AOnRememberUri: TFileOpRememberUri;
  const AOnConfirmMkDir, AOnConfirmNewFile, AOnConfirmRename,
  AOnConfirmCopyInPlace: TFileOpConfirmName;
  const AOnConfirmSelect: TFileOpConfirmSelect;
  const AOnConfirmLink: TFileOpConfirmLink;
  const AOnApplySetAttr: TFileOpApplySetAttr);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnUnfocusCmd := AOnUnfocusCmd;
  FOnGetActiveUri := AOnGetActiveUri;
  FOnInPanels := AOnInPanels;
  FOnShowStub := AOnShowStub;
  FOnGetMask := AOnGetMask;
  FOnGetSelectFolders := AOnGetSelectFolders;
  FOnTryGetItem := AOnTryGetItem;
  FOnRememberUri := AOnRememberUri;
  FOnConfirmMkDir := AOnConfirmMkDir;
  FOnConfirmNewFile := AOnConfirmNewFile;
  FOnConfirmRename := AOnConfirmRename;
  FOnConfirmCopyInPlace := AOnConfirmCopyInPlace;
  FOnConfirmSelect := AOnConfirmSelect;
  FOnConfirmLink := AOnConfirmLink;
  FOnApplySetAttr := AOnApplySetAttr;
end;

procedure TFileOpDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TFileOpDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TFileOpDialogController.UnfocusCmd;
begin
  if Assigned(FOnUnfocusCmd) then
    FOnUnfocusCmd();
end;

function TFileOpDialogController.DialogBlocked: Boolean;
begin
  Result := Assigned(FDialog) and FDialog.Visible;
end;

procedure TFileOpDialogController.OpenNamedInput(AKind: THostDialogKind;
  const ATitle, APrompt, AValue: string; APreferJson: Boolean);
var
  Decl: TDialogDeclaration;
begin
  UnfocusCmd;
  SetKind(AKind);
  Decl := BuildInputDialog(ATitle, APrompt, AValue);
  // The generic input dialog is shared; the history key depends on the use.
  case AKind of
    hdkMkDir:
      DialogSetInputHistory(Decl, 'name', 'mkdir');
    hdkNewFile:
      DialogSetInputHistory(Decl, 'name', 'newfile');
  end;
  if APreferJson then
  begin
    if not FDialog.OpenJson(DeclarationToJson(Decl), FOnCommand) then
      FDialog.Open(Decl, FOnCommand);
  end
  else
    FDialog.Open(Decl, FOnCommand);
  Notify;
end;

procedure TFileOpDialogController.BeginMkDir;
var
  CurURI: string;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  CurURI := '';
  if Assigned(FOnGetActiveUri) then
    CurURI := FOnGetActiveUri();
  if HasArchiveChain(CurURI) or IsFindUri(CurURI) then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.mkdir.failedTitle', 'MkDir failed'),
        T('ui.mkdir.failedMsg', 'Cannot create folder here'));
    Exit;
  end;
  OpenNamedInput(hdkMkDir, T('ui.mkdir.title', 'Make directory'),
    T('ui.mkdir.prompt', 'Name:'), 'New folder', False);
end;

procedure TFileOpDialogController.BeginNewFile;
var
  CurURI: string;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  CurURI := '';
  if Assigned(FOnGetActiveUri) then
    CurURI := FOnGetActiveUri();
  if HasArchiveChain(CurURI) or IsFindUri(CurURI) then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.newFile.failedTitle', 'New file failed'),
        T('ui.newFile.failedMsg', 'Cannot create file here'));
    Exit;
  end;
  OpenNamedInput(hdkNewFile, T('ui.newFile.title', 'Create new file'),
    T('ui.mkdir.prompt', 'Name:'), 'new.txt', False);
end;

procedure TFileOpDialogController.BeginSelectByMask(AUnselect: Boolean);
var
  Title, Prompt, CurrentMask: string;
  Kind: THostDialogKind;
  Folders: Boolean;
  Decl: TDialogDeclaration;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnInPanels) and not FOnInPanels() then
    Exit;
  if AUnselect then
  begin
    Kind := hdkUnselectMask;
    Title := T('ui.selectMask.deselectTitle', 'Deselect');
    Prompt := T('ui.selectMask.prompt', 'A file mask or several file masks:');
  end
  else
  begin
    Kind := hdkSelectMask;
    Title := T('ui.selectMask.selectTitle', 'Select');
    Prompt := T('ui.selectMask.prompt', 'A file mask or several file masks:');
  end;
  CurrentMask := '*.*';
  if Assigned(FOnGetMask) then
    CurrentMask := FOnGetMask();
  Folders := False;
  if Assigned(FOnGetSelectFolders) then
    Folders := FOnGetSelectFolders();
  UnfocusCmd;
  SetKind(Kind);
  Decl := BuildSelectMaskDialog(Title, Prompt, CurrentMask, Folders);
  if not FDialog.OpenJson(DeclarationToJson(Decl), FOnCommand) then
    FDialog.Open(Decl, FOnCommand);
  Notify;
end;

procedure TFileOpDialogController.BeginRename;
var
  Name, Uri, TargetUri: string;
  IsParent: Boolean;
begin
  if DialogBlocked then
    Exit;
  if not Assigned(FOnTryGetItem) or not FOnTryGetItem(Name, Uri, TargetUri, IsParent) then
    Exit;
  if IsParent or (Uri = '') then
    Exit;
  if HasArchiveChain(Uri) or IsFindUri(Uri) then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.rename.failedTitle', 'Rename failed'),
        T('ui.rename.failedMsg', 'Cannot rename here'));
    Exit;
  end;
  if (Name <> '') and (Name[Length(Name)] = '/') then
    Delete(Name, Length(Name), 1);
  if Assigned(FOnRememberUri) then
    FOnRememberUri(Uri);
  OpenNamedInput(hdkRename, T('ui.rename.title', 'Rename'),
    T('ui.mkdir.prompt', 'Name:'), Name, True);
end;

procedure TFileOpDialogController.BeginCopyInPlace;
var
  Name, Uri, TargetUri: string;
  IsParent: Boolean;
begin
  if DialogBlocked then
    Exit;
  if not Assigned(FOnTryGetItem) or not FOnTryGetItem(Name, Uri, TargetUri, IsParent) then
    Exit;
  if IsParent or (Uri = '') then
    Exit;
  if HasArchiveChain(Uri) or IsFindUri(Uri) then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.copyInPlace.failedTitle', 'Copy failed'),
        T('ui.copyInPlace.failedMsg', 'Cannot copy here'));
    Exit;
  end;
  if (Name <> '') and (Name[Length(Name)] = '/') then
    Delete(Name, Length(Name), 1);
  if Assigned(FOnRememberUri) then
    FOnRememberUri(Uri);
  OpenNamedInput(hdkCopyInPlace, T('ui.copyInPlace.title', 'Copy'),
    T('ui.copyInPlace.prompt', 'Copy to:'), Name, True);
end;

procedure TFileOpDialogController.BeginCreateLink;
var
  Name, Uri, TargetUri, TargetPath, Suggested: string;
  IsParent: Boolean;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if not Assigned(FOnTryGetItem) or not FOnTryGetItem(Name, Uri, TargetUri, IsParent) then
    Exit;
  if IsParent then
    Exit;
  TargetPath := FileUriToPath(Uri);
  if TargetPath = '' then
    TargetPath := FileUriToPath(TargetUri);
  if TargetPath = '' then
    Exit;
  Suggested := 'link_' + Name;
  UnfocusCmd;
  SetKind(hdkCreateLink);
  FDialog.Open(BuildCreateLinkDialog(Suggested, TargetPath, 0), FOnCommand);
  Notify;
end;

procedure TFileOpDialogController.BeginSetAttributes(const APaths: TArray<string>);
var
  State: TFileAttrDialogState;
  OwnerEdit: string;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Length(APaths) = 0 then
    Exit;
  FAttrPaths := Copy(APaths);
  State := BuildFileAttrDialogState(APaths);
  FAttrDateTexts[0] := FormatFileAttrTime(State.Times.Created);
  FAttrDateTexts[1] := FormatFileAttrTime(State.Times.Modified);
  FAttrDateTexts[2] := FormatFileAttrTime(State.Times.Accessed);
  OwnerEdit := State.Owner;
  if State.OwnerMixed then
    OwnerEdit := '';
  UnfocusCmd;
  SetKind(hdkSetAttributes);
  FDialog.Open(BuildSetAttributesDialog(State.Summary, State.Owner, OwnerEdit,
    FileAttrChoiceToIndex(State.ReadOnly), FileAttrChoiceToIndex(State.Hidden),
    FileAttrChoiceToIndex(State.Archive), FileAttrChoiceToIndex(State.System),
    FAttrDateTexts[0], FAttrDateTexts[1], FAttrDateTexts[2]),
    FOnCommand);
  Notify;
end;

procedure TFileOpDialogController.DispatchSimpleNameCommand(
  const AControlId: string; const ACallback: TFileOpConfirmName);
var
  Accepted: Boolean;
  NameVal: string;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  FDialog.Close;
  if Accepted and Assigned(ACallback) then
    ACallback(NameVal);
end;

procedure TFileOpDialogController.DispatchSelectMaskCommand(
  AKind: THostDialogKind; const AControlId: string);
var
  Accepted: Boolean;
  NameVal: string;
  Folders: Boolean;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  Folders := FDialog.GetCheckbox('select_folders');
  FDialog.Close;
  if Accepted and Assigned(FOnConfirmSelect) then
    FOnConfirmSelect(NameVal, AKind = hdkUnselectMask, Folders);
end;

procedure TFileOpDialogController.DispatchCreateLinkCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  NameVal, TargetVal: string;
  LinkTypeIdx: Integer;
  LinkKind: TLinkKind;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  LinkTypeIdx := 0;
  NameVal := '';
  TargetVal := '';
  if Accepted then
  begin
    NameVal := FDialog.GetInputValue('link_name');
    TargetVal := FDialog.GetInputValue('target');
    LinkTypeIdx := FDialog.GetListSelectedIndex('link_type');
  end;
  FDialog.Close;
  if Accepted and Assigned(FOnConfirmLink) then
  begin
    case LinkTypeIdx of
      1: LinkKind := lkSymlinkDir;
      2: LinkKind := lkHardlink;
      3: LinkKind := lkJunction;
    else
      LinkKind := lkSymlinkFile;
    end;
    FOnConfirmLink(NameVal, TargetVal, LinkKind);
  end;
end;

const
  cAttrDateIds: array[0..2] of string = ('date_created', 'date_modified', 'date_accessed');

// The host clears the dialog kind before dispatching a command; a button that
// keeps the dialog up (date buttons, a date typo) has to claim it back.
procedure TFileOpDialogController.KeepSetAttributesOpen;
begin
  SetKind(hdkSetAttributes);
  Notify;
end;

// Empty or untouched field: keep that time. Anything else must parse.
function TFileOpDialogController.ReadAttrDateFields(var APlan: TFileAttrPlan;
  out ABadText: string): Boolean;
var
  I: Integer;
  Text: string;
  Time: TDateTime;
begin
  Result := True;
  ABadText := '';
  for I := 0 to High(cAttrDateIds) do
  begin
    Text := Trim(FDialog.GetInputValue(cAttrDateIds[I]));
    if (Text = '') or (Text = FAttrDateTexts[I]) then
      Continue;
    if not TryParseFileAttrTime(Text, Time) then
    begin
      ABadText := Text;
      Exit(False);
    end;
    case I of
      0:
        begin
          APlan.SetCreated := True;
          APlan.Times.Created := Time;
        end;
      1:
        begin
          APlan.SetModified := True;
          APlan.Times.Modified := Time;
        end;
    else
      begin
        APlan.SetAccessed := True;
        APlan.Times.Accessed := Time;
      end;
    end;
  end;
end;

function TFileOpDialogController.DispatchSetAttributesCommand(
  const AControlId: string): Boolean;
var
  Accepted: Boolean;
  Plan: TFileAttrPlan;
  I: Integer;
  NowText, BadText: string;
begin
  Result := True;
  if DialogCmdIs(AControlId, 'dates_now') then
  begin
    NowText := FormatFileAttrTime(Now);
    for I := 0 to High(cAttrDateIds) do
      FDialog.SetInputValue(cAttrDateIds[I], NowText);
    FDialog.SetLabelText('date_error', '');
    KeepSetAttributesOpen;
    Exit;
  end;
  if DialogCmdIs(AControlId, 'dates_orig') then
  begin
    for I := 0 to High(cAttrDateIds) do
      FDialog.SetInputValue(cAttrDateIds[I], FAttrDateTexts[I]);
    FDialog.SetLabelText('date_error', '');
    KeepSetAttributesOpen;
    Exit;
  end;
  Accepted := not DialogCmdIsReject(AControlId);
  Plan := Default(TFileAttrPlan);
  if Accepted then
  begin
    Plan.ReadOnly := FileAttrIndexToChoice(FDialog.GetListSelectedIndex('attr_ro'));
    Plan.Hidden := FileAttrIndexToChoice(FDialog.GetListSelectedIndex('attr_h'));
    Plan.Archive := FileAttrIndexToChoice(FDialog.GetListSelectedIndex('attr_a'));
    Plan.System := FileAttrIndexToChoice(FDialog.GetListSelectedIndex('attr_s'));
    Plan.ChangeOwner := FDialog.GetCheckbox('change_owner');
    Plan.Owner := FDialog.GetInputValue('owner');
    Plan.Recurse := FDialog.GetCheckbox('recurse');
    if not ReadAttrDateFields(Plan, BadText) then
    begin
      FDialog.SetLabelText('date_error',
        T('ui.setAttr.badDate', 'Invalid date: %s', [BadText]));
      KeepSetAttributesOpen;
      Exit;
    end;
  end;
  FDialog.Close;
  if not Accepted then
    Exit;
  if Plan.ChangeOwner and (Trim(Plan.Owner) = '') then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.setAttr.failedTitle', 'Set attributes failed'),
        T('ui.setAttr.ownerEmptyMsg', 'Owner name is empty'));
    Exit;
  end;
  if FileAttrPlanIsNoOp(Plan) then
    Exit;
  if Assigned(FOnApplySetAttr) then
    FOnApplySetAttr(FAttrPaths, Plan);
end;

function TFileOpDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkMkDir: DispatchSimpleNameCommand(AControlId, FOnConfirmMkDir);
    hdkNewFile: DispatchSimpleNameCommand(AControlId, FOnConfirmNewFile);
    hdkRename: DispatchSimpleNameCommand(AControlId, FOnConfirmRename);
    hdkCopyInPlace: DispatchSimpleNameCommand(AControlId, FOnConfirmCopyInPlace);
    hdkSelectMask, hdkUnselectMask: DispatchSelectMaskCommand(AKind, AControlId);
    hdkCreateLink: DispatchCreateLinkCommand(AControlId);
    hdkSetAttributes: Result := DispatchSetAttributesCommand(AControlId);
  else
    { not a file-op dialog }
  end;
end;

end.
