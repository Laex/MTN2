unit uDualPanelThemeDialogs;

{ Theme picker and theme editor dialogs (hdkTheme, hdkThemeNew, hdkThemeName,
  hdkThemeDelete, hdkThemeEditor, hdkThemeItems, hdkThemeColors, hdkThemeText,
  hdkThemeChoice, hdkThemePicker). Extracted from TDualPanelWindow so the
  host keeps only thin forwards.

  Built-in themes are read-only: customizing one edits a working TThemeDoc
  that extends it and Save writes a new user theme file under a name the
  user types. A user theme is edited in place. Every accepted change is
  previewed at once (OnPreview); Cancel reselects the active theme. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uTerminalTypes, uThemeTypes,
  uThemeSpec, uColorCoding, uMarkdownColors;

type
  TThemeKindSetter = reference to procedure(AKind: THostDialogKind);
  TThemeCanStart = reference to function: Boolean;
  TThemePrepareUi = reference to procedure;
  TThemeGetActiveId = reference to function: string;
  TThemeSelectProc = reference to procedure(const AThemeId: string);
  TThemePreviewProc = reference to procedure(const ASpec: TThemeSpec);
  TThemeShowInfo = reference to procedure(const ATitle, ADetail: string);

  TThemeItemKind = (tikColor, tikMdFg, tikMdBg, tikMdAttrs, tikAttr, tikGlyph,
    tikFrame, tikDoubleActive, tikExtends);

  /// <summary>A change applied to the document of the theme being saved.</summary>
  TThemeMutator = reference to procedure(var ADoc: TThemeDoc);

  TThemeItem = record
    Kind: TThemeItemKind;
    Key: string;
    Role: TThemeColorRole;
    Md: TMdSpanKind;
    Attr: TThemeAttrSlot;
    Glyph: TThemeGlyph;
    Frame: TThemeFrameSlot;
  end;

  TThemeNameContext = (tncEditor, tncPending);

  /// <summary>What the colors form edits: one color per theme role, or the
  /// Markdown styles (foreground, background and text style per element).</summary>
  TThemeFormMode = (fmRoles, fmMarkdown);

  TThemeDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TThemeKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TThemeCanStart;
    FOnPrepareUi: TThemePrepareUi;
    FOnGetActiveId: TThemeGetActiveId;
    FOnSelect: TThemeSelectProc;
    FOnPreview: TThemePreviewProc;
    FOnShowInfo: TThemeShowInfo;
    /// <summary>Theme ids behind the picker's rows / the "based on" choices.</summary>
    FThemeIds: TArray<string>;
    /// <summary>The theme being edited: only what it sets.</summary>
    FDoc: TThemeDoc;
    /// <summary>Id of the user theme edited in place; '' for a new theme or a
    /// copy of a built-in one.</summary>
    FEditingId: string;
    /// <summary>The name is settled (New theme), so Save does not ask for it.</summary>
    FNameConfirmed: Boolean;
    /// <summary>Theme to reselect when the editor is cancelled.</summary>
    FRestoreId: string;
    FSections: TArray<string>;
    FSection: Integer;
    FItems: TArray<TThemeItem>;
    FItem: Integer;
    FChoiceIds: TArray<string>;
    FFormMode: TThemeFormMode;
    FFormRoles: TArray<TThemeColorRole>;
    FFormKinds: TArray<TMdSpanKind>;
    /// <summary>Text of every color field as the form opened (initial) and as
    /// it is now; Markdown rows hold foreground then background. A row the
    /// user leaves as it was is not written to the theme.</summary>
    FFormInit, FFormTexts: TArray<string>;
    FFormInitStyle, FFormStyles: TArray<Integer>;
    /// <summary>Id of the color field the picker is editing.</summary>
    FFormPick: string;
    FNameContext: TThemeNameContext;
    FPendingMutator: TThemeMutator;
    FPendingBaseId: string;
    FDeleteId: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure ShowPicker(const ASelectId, AStatus: string);
    procedure BeginCustomize(AIndex: Integer);
    procedure BeginNew(AIndex: Integer);
    procedure BeginDelete(AIndex: Integer);
    procedure ShowNewDialog(const AName: string; ABaseIndex: Integer;
      const AStatus: string);
    procedure ShowNameDialog(const AName, AStatus: string);
    procedure ShowEditor(ASelected: Integer; const AStatus: string);
    procedure OpenItems(ASection, ASelected: Integer);
    procedure BeginItemEdit(AIndex: Integer);
    procedure ShowTextEdit(const AText, AStatus: string);
    procedure ShowChoiceEdit;
    procedure OpenForm(ASection: Integer);
    procedure ShowForm(const AStatus: string; AFocus: Integer);
    procedure ReadForm;
    function FormFieldIndex(const AField: string; out AIndex: Integer): Boolean;
    function FormRowTitle(AIndex: Integer): string;
    procedure BeginFormPicker(const AField: string);
    procedure DispatchColors(const AControlId: string);
    function ValidateColorText(const AText: string; out ASlot: TThemeColorSlot;
      out AError: string): Boolean;
    function ItemTitle(const AItem: TThemeItem): string;
    function CheckName(const AName, AAllowId: string; out AError: string): Boolean;
    procedure DoSave(AAskName: Boolean);
    procedure SaveDoc(ADoc: TThemeDoc);
    procedure CancelEditor;
    procedure Preview;
    procedure ClearItem(var ADoc: TThemeDoc; const AItem: TThemeItem);
    function ItemIsSet(const AItem: TThemeItem): Boolean;
    function ItemValueText(const ASpec: TThemeSpec; const AItem: TThemeItem;
      AShowRef: Boolean): string;
    function ItemText(const ASpec: TThemeSpec; const AItem: TThemeItem): string;
    function InheritedText(const AItem: TThemeItem): string;
    procedure BuildItems(ASection: Integer);
    function SectionLabel(const ASection: string): string;
    function ApplyGlyphText(const AText: string; out AStatus: string): Boolean;
    function ApplyChoice(AIndex: Integer): Boolean;
    procedure DispatchPicker(const AControlId: string);
    procedure DispatchNew(const AControlId: string);
    procedure DispatchName(const AControlId: string);
    procedure DispatchDelete(const AControlId: string);
    procedure DispatchEditor(const AControlId: string);
    procedure DispatchItems(const AControlId: string);
    procedure DispatchText(const AControlId: string);
    procedure DispatchChoice(const AControlId: string);
    procedure DispatchColorPicker(const AControlId: string);
    procedure ResetEditState;
    procedure SaveToActiveTheme(const AMutate: TThemeMutator);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TThemeKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TThemeCanStart; const AOnPrepareUi: TThemePrepareUi;
      const AOnGetActiveId: TThemeGetActiveId; const AOnSelect: TThemeSelectProc;
      const AOnPreview: TThemePreviewProc; const AOnShowInfo: TThemeShowInfo);
    procedure OpenPicker;
    /// <summary>Stores a color coding list as part of the active theme: what
    /// differs from the theme's bases is written; a user theme is updated in
    /// place, a built-in one asks for the name of a new theme that extends it.</summary>
    procedure SaveColoring(const AGroups: TArray<TColorCodingGroup>);
    /// <summary>The Markdown styles the active theme sets itself (none for a
    /// built-in theme), as the Markdown colors dialog edits them.</summary>
    function ActiveMarkdownSet: TMdColorSet;
    /// <summary>Stores what the Markdown colors dialog changed in the active
    /// theme, the way SaveColoring stores file coloring.</summary>
    procedure SaveMarkdown(const AInitial, AEdited: TMdColorSet);
    /// <summary>F9 on a color field of the colors form opens the picker.</summary>
    function HandleColorInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

uses
  System.Generics.Collections, System.Math,
  uDialogResources, uStrings, uThemeRegistry, uThemeNames, uColorPickerControl;

const
  cSectionMarkdown = 'markdown';
  cSectionAttrs = 'attrs';
  cSectionGlyphs = 'glyphs';
  cSectionFrames = 'frames';
  cSectionTheme = 'theme';
  cKeyColumn = 34;

constructor TThemeDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TThemeKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TThemeCanStart;
  const AOnPrepareUi: TThemePrepareUi; const AOnGetActiveId: TThemeGetActiveId;
  const AOnSelect: TThemeSelectProc; const AOnPreview: TThemePreviewProc;
  const AOnShowInfo: TThemeShowInfo);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnGetActiveId := AOnGetActiveId;
  FOnSelect := AOnSelect;
  FOnPreview := AOnPreview;
  FOnShowInfo := AOnShowInfo;
end;

procedure TThemeDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TThemeDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TThemeDialogController.ResetEditState;
begin
  FDoc := Default(TThemeDoc);
  FEditingId := '';
  FNameConfirmed := False;
  FRestoreId := '';
  SetLength(FItems, 0);
  SetLength(FChoiceIds, 0);
  FPendingMutator := nil;
  FPendingBaseId := '';
  FDeleteId := '';
  FFormPick := '';
  SetLength(FFormInit, 0);
  SetLength(FFormTexts, 0);
end;

procedure TThemeDialogController.Preview;
begin
  if Assigned(FOnPreview) then
    FOnPreview(ResolveDocSpec(FDoc));
end;

function TThemeDialogController.SectionLabel(const ASection: string): string;
begin
  Result := T('ui.themeEditor.section.' + ASection, ASection);
end;

// ------------------------------------------------------------- picker

procedure TThemeDialogController.OpenPicker;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  ResetEditState;
  if Assigned(FOnGetActiveId) then
    ShowPicker(FOnGetActiveId(), '')
  else
    ShowPicker('', '');
end;

procedure TThemeDialogController.ShowPicker(const ASelectId, AStatus: string);
var
  Infos: TArray<TThemeInfo>;
  Decl: TDialogDeclaration;
  Items: TArray<string>;
  I, Sel: Integer;
begin
  Infos := GetAvailableThemes;
  SetLength(Items, Length(Infos));
  SetLength(FThemeIds, Length(Infos));
  Sel := 0;
  for I := 0 to High(Infos) do
  begin
    Items[I] := Infos[I].DisplayName;
    if not Infos[I].BuiltIn then
      Items[I] := Items[I] + T('ui.theme.userSuffix', ' [user]');
    FThemeIds[I] := Infos[I].Id;
    if SameText(Infos[I].Id, ASelectId) then
      Sel := I;
  end;
  RequireDialogResource(cResDialogTheme, Decl);
  DialogSetListItems(Decl, 'themes', Items, Sel);
  if AStatus <> '' then
    DialogSetLabelText(Decl, 'status', AStatus);
  SetKind(hdkTheme);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

procedure TThemeDialogController.BeginCustomize(AIndex: Integer);
var
  Info: TThemeInfo;
begin
  if (AIndex < 0) or (AIndex > High(FThemeIds)) or
     not FindThemeInfo(FThemeIds[AIndex], Info) then
    Exit;
  ResetEditState;
  if Assigned(FOnGetActiveId) then
    FRestoreId := FOnGetActiveId();
  if Info.BuiltIn then
  begin
    FDoc.Extends := [Info.Id];
    FDoc.Name := Format(T('ui.theme.customName', '%s (custom)'), [Info.DisplayName]);
  end
  else
  begin
    if not TryLoadThemeDoc(Info.Id, FDoc) then
    begin
      ShowPicker(Info.Id, T('ui.theme.loadFailed', 'Could not read the theme.'));
      Exit;
    end;
    FEditingId := Info.Id;
    FNameConfirmed := True;
  end;
  SetLength(FSections, 0);
  ShowEditor(0, '');
  Preview;
end;

procedure TThemeDialogController.ShowNewDialog(const AName: string;
  ABaseIndex: Integer; const AStatus: string);
var
  Decl: TDialogDeclaration;
  Infos: TArray<TThemeInfo>;
  Items: TArray<string>;
  I: Integer;
begin
  Infos := GetAvailableThemes;
  SetLength(Items, Length(Infos) + 1);
  SetLength(FThemeIds, Length(Infos));
  Items[0] := T('ui.theme.blank', '(blank)');
  for I := 0 to High(Infos) do
  begin
    Items[I + 1] := Infos[I].DisplayName;
    FThemeIds[I] := Infos[I].Id;
  end;
  RequireDialogResource(cResDialogThemeNew, Decl);
  DialogSetInputValue(Decl, 'name', AName);
  DialogSetListItems(Decl, 'base', Items, ABaseIndex);
  if AStatus <> '' then
    DialogSetLabelText(Decl, 'status', AStatus);
  SetKind(hdkThemeNew);
  FDialog.Open(Decl, FOnCommand);
  FDialog.FocusControlById('name');
  Notify;
end;

procedure TThemeDialogController.BeginNew(AIndex: Integer);
begin
  ShowNewDialog('', AIndex + 1, '');
end;

procedure TThemeDialogController.BeginDelete(AIndex: Integer);
var
  Info: TThemeInfo;
  Decl: TDialogDeclaration;
begin
  if (AIndex < 0) or (AIndex > High(FThemeIds)) or
     not FindThemeInfo(FThemeIds[AIndex], Info) then
    Exit;
  if Info.BuiltIn then
  begin
    FDialog.SetStatus('status', T('ui.theme.builtInReadOnly',
      'Built-in themes cannot be deleted.'));
    SetKind(hdkTheme);
    Notify;
    Exit;
  end;
  FDeleteId := Info.Id;
  Decl := BuildConfirmDialog(T('ui.theme.deleteTitle', 'Delete theme'),
    Format(T('ui.theme.deleteConfirm', 'Delete theme "%s"?'), [Info.DisplayName]));
  SetKind(hdkThemeDelete);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

procedure TThemeDialogController.DispatchPicker(const AControlId: string);
var
  Idx: Integer;
  Accepted: Boolean;
begin
  Idx := FDialog.GetListSelectedIndex('themes');
  if DialogCmdIs(AControlId, 'customize') then
    BeginCustomize(Idx)
  else if DialogCmdIs(AControlId, 'new') then
    BeginNew(Idx)
  else if DialogCmdIs(AControlId, 'delete') then
    BeginDelete(Idx)
  else
  begin
    Accepted := DialogCmdIsListAccept(AControlId, 'themes');
    FDialog.Close;
    if Accepted and (Idx >= 0) and (Idx <= High(FThemeIds)) and
       (FThemeIds[Idx] <> '') and Assigned(FOnSelect) then
      FOnSelect(FThemeIds[Idx]);
    SetLength(FThemeIds, 0);
  end;
end;

procedure TThemeDialogController.DispatchDelete(const AControlId: string);
var
  Id: string;
begin
  Id := FDeleteId;
  FDeleteId := '';
  FDialog.Close;
  if DialogCmdIsAccept(AControlId) and (Id <> '') then
  begin
    if not DeleteUserTheme(Id) then
    begin
      ShowPicker(Id, T('ui.theme.deleteFailed', 'Could not delete the theme.'));
      Exit;
    end;
    if Assigned(FOnGetActiveId) and SameText(FOnGetActiveId(), Id) and
       Assigned(FOnSelect) then
      FOnSelect(DefaultThemeId);
  end;
  if Assigned(FOnGetActiveId) then
    ShowPicker(FOnGetActiveId(), '')
  else
    ShowPicker('', '');
end;

// ------------------------------------------------------ names and saving

function TThemeDialogController.CheckName(const AName, AAllowId: string;
  out AError: string): Boolean;
var
  Id: string;
  Info: TThemeInfo;
begin
  Result := False;
  Id := ThemeIdFromName(AName);
  if Id = '' then
  begin
    AError := T('ui.theme.badName', 'Enter a name for the theme.');
    Exit;
  end;
  for Info in GetAvailableThemes do
    if (SameText(Info.Id, Id) or SameText(Info.DisplayName, Trim(AName))) and
       not SameText(Info.Id, AAllowId) then
    begin
      if Info.BuiltIn then
        AError := T('ui.theme.nameBuiltIn', 'A built-in theme has this name.')
      else
        AError := T('ui.theme.nameExists', 'A theme with this name already exists.');
      Exit;
    end;
  AError := '';
  Result := True;
end;

procedure TThemeDialogController.ShowNameDialog(const AName, AStatus: string);
var
  Decl: TDialogDeclaration;
begin
  RequireDialogResource(cResDialogThemeName, Decl);
  DialogSetInputValue(Decl, 'name', AName);
  if AStatus <> '' then
    DialogSetLabelText(Decl, 'status', AStatus);
  SetKind(hdkThemeName);
  FDialog.Open(Decl, FOnCommand);
  FDialog.FocusControlById('name');
  Notify;
end;

procedure TThemeDialogController.SaveDoc(ADoc: TThemeDoc);
var
  Err: string;
begin
  if not SaveUserTheme(ADoc, Err) then
  begin
    ShowEditor(FSection, Format(T('ui.theme.saveFailed', 'Could not save the theme: %s'), [Err]));
    Exit;
  end;
  FDialog.Close;
  if Assigned(FOnSelect) then
    FOnSelect(ADoc.Id);
  ResetEditState;
end;

procedure TThemeDialogController.DoSave(AAskName: Boolean);
var
  Doc: TThemeDoc;
begin
  if (FEditingId <> '') and not AAskName then
  begin
    Doc := FDoc;
    Doc.Id := FEditingId;
    SaveDoc(Doc);
  end
  else if FNameConfirmed and not AAskName then
  begin
    Doc := FDoc;
    Doc.Id := '';
    SaveDoc(Doc);
  end
  else
  begin
    FNameContext := tncEditor;
    ShowNameDialog(FDoc.Name, '');
  end;
end;

procedure TThemeDialogController.DispatchNew(const AControlId: string);
var
  Name, Err: string;
  BaseIdx: Integer;
  Spec: TThemeSpec;
begin
  if DialogCmdIsReject(AControlId) then
  begin
    FDialog.Close;
    if Assigned(FOnGetActiveId) then
      ShowPicker(FOnGetActiveId(), '')
    else
      ShowPicker('', '');
    Exit;
  end;
  Name := Trim(FDialog.GetInputValue('name'));
  BaseIdx := FDialog.GetListSelectedIndex('base');
  if not CheckName(Name, '', Err) then
  begin
    FDialog.SetStatus('status', Err);
    SetKind(hdkThemeNew);
    Notify;
    Exit;
  end;
  ResetEditState;
  if Assigned(FOnGetActiveId) then
    FRestoreId := FOnGetActiveId();
  if (BaseIdx <= 0) or (BaseIdx > Length(FThemeIds)) then
  begin
    // A blank theme stands alone: every slot is written out.
    if TryLoadThemeSpec(DefaultThemeId, Spec) then
      FDoc := ThemeDocFromSpec(Spec);
  end
  else
    FDoc.Extends := [FThemeIds[BaseIdx - 1]];
  FDoc.Name := Name;
  FNameConfirmed := True;
  SetLength(FSections, 0);
  ShowEditor(0, '');
  Preview;
end;

procedure TThemeDialogController.DispatchName(const AControlId: string);
var
  Name, Err, Id: string;
  Doc: TThemeDoc;
  SavedErr: string;
begin
  if DialogCmdIsReject(AControlId) then
  begin
    FDialog.Close;
    if FNameContext = tncEditor then
      ShowEditor(FSection, '')
    else
      ResetEditState;
    Exit;
  end;
  Name := Trim(FDialog.GetInputValue('name'));
  if not CheckName(Name, FEditingId, Err) then
  begin
    FDialog.SetStatus('status', Err);
    SetKind(hdkThemeName);
    Notify;
    Exit;
  end;
  if FNameContext = tncEditor then
  begin
    Doc := FDoc;
    Doc.Name := Name;
    Doc.Id := '';
    if (FEditingId <> '') and SameText(ThemeIdFromName(Name), FEditingId) then
      Doc.Id := FEditingId;
    FDoc.Name := Name;
    FNameConfirmed := True;
    SaveDoc(Doc);
  end
  else
  begin
    Doc := Default(TThemeDoc);
    Doc.Name := Name;
    Doc.Extends := [FPendingBaseId];
    if Assigned(FPendingMutator) then
      FPendingMutator(Doc);
    if not SaveUserTheme(Doc, SavedErr) then
    begin
      FDialog.SetStatus('status',
        Format(T('ui.theme.saveFailed', 'Could not save the theme: %s'), [SavedErr]));
      SetKind(hdkThemeName);
      Notify;
      Exit;
    end;
    Id := Doc.Id;
    FDialog.Close;
    ResetEditState;
    if Assigned(FOnSelect) then
      FOnSelect(Id);
  end;
end;

procedure TThemeDialogController.SaveToActiveTheme(const AMutate: TThemeMutator);
var
  ActiveId, Err: string;
  Info: TThemeInfo;
  Doc: TThemeDoc;
begin
  ActiveId := DefaultThemeId;
  if Assigned(FOnGetActiveId) and (FOnGetActiveId() <> '') then
    ActiveId := FOnGetActiveId();
  if not FindThemeInfo(ActiveId, Info) then
    FindThemeInfo(DefaultThemeId, Info);
  if not Info.BuiltIn and TryLoadThemeDoc(Info.Id, Doc) then
  begin
    AMutate(Doc);
    if not SaveUserTheme(Doc, Err) then
    begin
      if Assigned(FOnShowInfo) then
        FOnShowInfo(T('ui.theme.title', 'Theme'),
          Format(T('ui.theme.saveFailed', 'Could not save the theme: %s'), [Err]));
      Exit;
    end;
    if Assigned(FOnSelect) then
      FOnSelect(Info.Id);
    Exit;
  end;
  ResetEditState;
  FNameContext := tncPending;
  FPendingMutator := AMutate;
  FPendingBaseId := Info.Id;
  ShowNameDialog(Format(T('ui.theme.customName', '%s (custom)'), [Info.DisplayName]), '');
end;

procedure TThemeDialogController.SaveColoring(const AGroups: TArray<TColorCodingGroup>);
var
  Edited: TArray<TColorCodingGroup>;
begin
  Edited := Copy(AGroups);
  SaveToActiveTheme(
    procedure(var ADoc: TThemeDoc)
    var
      Base: TThemeSpec;
      Changes: TArray<TColorCodingGroup>;
      Order: TArray<string>;
    begin
      Base := ResolveBaseSpec(ADoc);
      ColorCodingDiff(Base.FileColoring, Edited, Changes, Order);
      ADoc.FileColoring := Changes;
      ADoc.FileColoringOrder := Order;
      ADoc.HasFileColoring := (Length(Changes) > 0) or (Length(Order) > 0);
    end);
end;

function TThemeDialogController.ActiveMarkdownSet: TMdColorSet;
var
  ActiveId: string;
  Info: TThemeInfo;
  Doc: TThemeDoc;
begin
  MdColorSetClear(Result);
  ActiveId := DefaultThemeId;
  if Assigned(FOnGetActiveId) and (FOnGetActiveId() <> '') then
    ActiveId := FOnGetActiveId();
  if FindThemeInfo(ActiveId, Info) and not Info.BuiltIn and
     TryLoadThemeDoc(Info.Id, Doc) then
    Result := ThemeDocMdSet(Doc, ResolveDocSpec(Doc));
end;

function MdSetsEqual(const A, B: TMdColorSet): Boolean;
var
  Kind: TMdSpanKind;
begin
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    if (A[Kind].HasFg <> B[Kind].HasFg) or (A[Kind].HasBg <> B[Kind].HasBg) or
       (A[Kind].HasStyle <> B[Kind].HasStyle) or
       (A[Kind].HasFg and (A[Kind].Fg <> B[Kind].Fg)) or
       (A[Kind].HasBg and (A[Kind].Bg <> B[Kind].Bg)) or
       (A[Kind].HasStyle and (A[Kind].Style <> B[Kind].Style)) then
      Exit(False);
  Result := True;
end;

procedure TThemeDialogController.SaveMarkdown(const AInitial, AEdited: TMdColorSet);
var
  Initial, Edited: TMdColorSet;
begin
  if MdSetsEqual(AInitial, AEdited) then
    Exit;
  Initial := AInitial;
  Edited := AEdited;
  SaveToActiveTheme(
    procedure(var ADoc: TThemeDoc)
    begin
      ThemeDocApplyMdSet(ADoc, Initial, Edited);
    end);
end;

// ------------------------------------------------------------ editor

procedure TThemeDialogController.BuildItems(ASection: Integer);
var
  Sect: string;
  Role: TThemeColorRole;
  Kind: TMdSpanKind;
  Slot: TThemeAttrSlot;
  Glyph: TThemeGlyph;
  Frame: TThemeFrameSlot;
  Item: TThemeItem;

  procedure Add(AKind: TThemeItemKind; const AKey: string);
  begin
    Item := Default(TThemeItem);
    Item.Kind := AKind;
    Item.Key := AKey;
    Item.Role := Role;
    Item.Md := Kind;
    Item.Attr := Slot;
    Item.Glyph := Glyph;
    Item.Frame := Frame;
    FItems := FItems + [Item];
  end;

begin
  SetLength(FItems, 0);
  Sect := FSections[ASection];
  Role := Low(TThemeColorRole);
  Kind := Low(TMdSpanKind);
  Slot := Low(TThemeAttrSlot);
  Glyph := Low(TThemeGlyph);
  Frame := Low(TThemeFrameSlot);
  if SameText(Sect, cSectionMarkdown) then
  begin
    for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    begin
      Add(tikMdFg, MdSpanKindKey(Kind) + '.fg');
      Add(tikMdBg, MdSpanKindKey(Kind) + '.bg');
      Add(tikMdAttrs, MdSpanKindKey(Kind) + '.attrs');
    end;
  end
  else if SameText(Sect, cSectionAttrs) then
  begin
    for Slot := Low(TThemeAttrSlot) to High(TThemeAttrSlot) do
      Add(tikAttr, ThemeAttrSlotKey(Slot));
  end
  else if SameText(Sect, cSectionGlyphs) then
  begin
    for Glyph := Low(TThemeGlyph) to High(TThemeGlyph) do
      Add(tikGlyph, ThemeGlyphKey(Glyph));
  end
  else if SameText(Sect, cSectionFrames) then
  begin
    for Frame := Low(TThemeFrameSlot) to High(TThemeFrameSlot) do
      Add(tikFrame, ThemeFrameSlotKey(Frame));
    Add(tikDoubleActive, 'doubleActivePanel');
  end
  else if SameText(Sect, cSectionTheme) then
    Add(tikExtends, 'extends')
  else
    for Role := Low(TThemeColorRole) to High(TThemeColorRole) do
      if SameText(ThemeColorRoleSection(Role), Sect) then
        Add(tikColor, ThemeColorRoleKey(Role));
end;

function DocColorSlot(const ADoc: TThemeDoc; const AItem: TThemeItem): TThemeColorSlot;
begin
  case AItem.Kind of
    tikColor: Result := ADoc.Colors[AItem.Role];
    tikMdFg: Result := ADoc.MdFg[AItem.Md];
    tikMdBg: Result := ADoc.MdBg[AItem.Md];
  else
    Result := Default(TThemeColorSlot);
  end;
end;

function TThemeDialogController.ItemIsSet(const AItem: TThemeItem): Boolean;
begin
  case AItem.Kind of
    tikColor, tikMdFg, tikMdBg: Result := DocColorSlot(FDoc, AItem).Has;
    tikMdAttrs: Result := FDoc.MdAttrs[AItem.Md].Has;
    tikAttr: Result := FDoc.Attrs[AItem.Attr].Has;
    tikGlyph: Result := FDoc.Glyphs[AItem.Glyph].Has;
    tikFrame: Result := FDoc.Frames[AItem.Frame].Has;
    tikExtends: Result := Length(FDoc.Extends) > 0;
  else
    Result := FDoc.DoubleActivePanel <> ttsUnset;
  end;
end;

function AttrText(AAttrs: TCharCellAttributes): string;
var
  Name: string;
begin
  Result := '';
  for Name in ThemeAttrsToNames(AAttrs) do
  begin
    if Result <> '' then
      Result := Result + '+';
    Result := Result + Name;
  end;
  if Result = '' then
    Result := T('ui.themeEditor.none', '(none)');
end;

// AShowRef: a color written as a reference shows the reference, then its value.
function TThemeDialogController.ItemValueText(const ASpec: TThemeSpec;
  const AItem: TThemeItem; AShowRef: Boolean): string;
var
  Text: string;
  Slot: TThemeColorSlot;
begin
  case AItem.Kind of
    tikColor: Result := ThemeColorToText(ASpec.Colors[AItem.Role]);
    tikMdFg: Result := ThemeColorToText(ASpec.MdFg[AItem.Md]);
    tikMdBg: Result := ThemeColorToText(ASpec.MdBg[AItem.Md]);
    tikMdAttrs: Result := AttrText(ASpec.MdAttrs[AItem.Md]);
    tikAttr: Result := AttrText(ASpec.Attrs[AItem.Attr]);
    tikGlyph:
      begin
        Text := ASpec.Glyphs[AItem.Glyph];
        if Length(Text) = 1 then
          Result := Format('"%s"  U+%.4X', [Text, Ord(Text[1])])
        else
          Result := '"' + Text + '"';
      end;
    tikFrame: Result := ThemeFrameSetTitle(ASpec.FrameNames[AItem.Frame]);
    tikExtends:
      if Length(FDoc.Extends) > 0 then
        Result := ThemeExtendsText(FDoc.Extends)
      else
        Result := '(' + DefaultThemeId + ')';
  else
    if ASpec.DoubleActivePanel then
      Result := T('ui.themeEditor.yes', 'yes')
    else
      Result := T('ui.themeEditor.no', 'no');
  end;
  if AShowRef and (AItem.Kind in [tikColor, tikMdFg, tikMdBg]) then
  begin
    Slot := DocColorSlot(FDoc, AItem);
    if Slot.Has and (Slot.Ref <> '') then
      Result := Slot.Ref + '  ' + Result;
  end;
end;

function TThemeDialogController.ItemTitle(const AItem: TThemeItem): string;
begin
  case AItem.Kind of
    tikColor: Result := ThemeColorRoleTitle(AItem.Role);
    tikMdFg: Result := ThemeMdKindTitle(AItem.Md) + ': ' + ThemeMdPartTitle('fg');
    tikMdBg: Result := ThemeMdKindTitle(AItem.Md) + ': ' + ThemeMdPartTitle('bg');
    tikMdAttrs: Result := ThemeMdKindTitle(AItem.Md) + ': ' + ThemeMdPartTitle('attrs');
    tikAttr: Result := ThemeAttrSlotTitle(AItem.Attr);
    tikGlyph: Result := ThemeGlyphTitle(AItem.Glyph);
    tikFrame: Result := ThemeFrameSlotTitle(AItem.Frame);
    tikExtends: Result := ThemeExtendsTitle;
  else
    Result := ThemeDoubleActiveTitle;
  end;
end;

function TThemeDialogController.ItemText(const ASpec: TThemeSpec;
  const AItem: TThemeItem): string;
begin
  Result := ItemTitle(AItem);
  while Length(Result) < cKeyColumn do
    Result := Result + ' ';
  Result := Result + ItemValueText(ASpec, AItem, True);
  if ItemIsSet(AItem) then
    Result := Result + ' *';
end;

procedure TThemeDialogController.ClearItem(var ADoc: TThemeDoc; const AItem: TThemeItem);
begin
  case AItem.Kind of
    tikColor: ADoc.Colors[AItem.Role] := Default(TThemeColorSlot);
    tikMdFg: ADoc.MdFg[AItem.Md] := Default(TThemeColorSlot);
    tikMdBg: ADoc.MdBg[AItem.Md] := Default(TThemeColorSlot);
    tikMdAttrs: ADoc.MdAttrs[AItem.Md].Has := False;
    tikAttr: ADoc.Attrs[AItem.Attr].Has := False;
    tikGlyph: ADoc.Glyphs[AItem.Glyph].Has := False;
    tikFrame: ADoc.Frames[AItem.Frame].Has := False;
    tikExtends: SetLength(ADoc.Extends, 0);
  else
    ADoc.DoubleActivePanel := ttsUnset;
  end;
end;

function TThemeDialogController.InheritedText(const AItem: TThemeItem): string;
var
  Doc: TThemeDoc;
begin
  Doc := FDoc;
  ClearItem(Doc, AItem);
  Result := Format(T('ui.themeEditor.inherited', 'Inherited: %s'),
    [ItemValueText(ResolveDocSpec(Doc), AItem, False)]);
end;

procedure TThemeDialogController.ShowEditor(ASelected: Integer; const AStatus: string);
var
  Decl: TDialogDeclaration;
  Items: TArray<string>;
  Sect: string;
  I: Integer;
begin
  if Length(FSections) = 0 then
  begin
    FSections := ThemeColorSections;
    FSections := FSections + [cSectionMarkdown, cSectionAttrs, cSectionGlyphs, cSectionFrames,
      cSectionTheme];
  end;
  SetLength(Items, Length(FSections));
  I := 0;
  for Sect in FSections do
  begin
    Items[I] := SectionLabel(Sect);
    Inc(I);
  end;
  RequireDialogResource(cResDialogThemeEditor, Decl);
  DialogSetTitle(Decl, Format(T('ui.themeEditor.title', 'Theme: %s'), [FDoc.Name]));
  DialogSetListItems(Decl, 'sections', Items, ASelected);
  if AStatus <> '' then
    DialogSetLabelText(Decl, 'status', AStatus);
  FSection := ASelected;
  SetKind(hdkThemeEditor);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

procedure TThemeDialogController.OpenItems(ASection, ASelected: Integer);
var
  Decl: TDialogDeclaration;
  Spec: TThemeSpec;
  Items: TArray<string>;
  I: Integer;
begin
  if (ASection < 0) or (ASection > High(FSections)) then
    Exit;
  FSection := ASection;
  BuildItems(ASection);
  // Colors are edited in one form per section, like the Markdown styles.
  if (Length(FItems) > 0) and (FItems[0].Kind in [tikColor, tikMdFg]) then
  begin
    OpenForm(ASection);
    Exit;
  end;
  Spec := ResolveDocSpec(FDoc);
  SetLength(Items, Length(FItems));
  for I := 0 to High(FItems) do
    Items[I] := ItemText(Spec, FItems[I]);
  if ASelected > High(Items) then
    ASelected := High(Items);
  if ASelected < 0 then
    ASelected := 0;
  RequireDialogResource(cResDialogThemeItems, Decl);
  DialogSetTitle(Decl, Format(T('ui.themeEditor.title', 'Theme: %s'), [FDoc.Name]) +
    ' / ' + SectionLabel(FSections[ASection]));
  DialogSetListItems(Decl, 'items', Items, ASelected);
  SetKind(hdkThemeItems);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

procedure TThemeDialogController.CancelEditor;
begin
  FDialog.Close;
  if Assigned(FOnSelect) and (FRestoreId <> '') then
    FOnSelect(FRestoreId);
  ResetEditState;
end;

procedure TThemeDialogController.DispatchEditor(const AControlId: string);
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('sections');
  if DialogCmdIs(AControlId, 'save') then
    DoSave(False)
  else if DialogCmdIs(AControlId, 'saveas') then
    DoSave(True)
  else if DialogCmdIsReject(AControlId) then
    CancelEditor
  else
    OpenItems(Idx, 0);
end;

procedure TThemeDialogController.DispatchItems(const AControlId: string);
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('items');
  if DialogCmdIsReject(AControlId) or DialogCmdIs(AControlId, 'back') then
    ShowEditor(FSection, '')
  else if DialogCmdIs(AControlId, 'inherit') then
  begin
    if (Idx >= 0) and (Idx <= High(FItems)) then
    begin
      ClearItem(FDoc, FItems[Idx]);
      Preview;
    end;
    OpenItems(FSection, Idx);
  end
  else if (Idx >= 0) and (Idx <= High(FItems)) then
    BeginItemEdit(Idx);
end;

// ----------------------------------------------------------- value edits

procedure TThemeDialogController.BeginItemEdit(AIndex: Integer);
var
  Item: TThemeItem;
  Spec: TThemeSpec;
begin
  FItem := AIndex;
  Item := FItems[AIndex];
  Spec := ResolveDocSpec(FDoc);
  case Item.Kind of
    tikGlyph:
      ShowTextEdit(Spec.Glyphs[Item.Glyph], '');
    tikExtends:
      ShowTextEdit(ThemeExtendsText(FDoc.Extends), '');
  else
    ShowChoiceEdit;
  end;
end;

procedure TThemeDialogController.ShowTextEdit(const AText, AStatus: string);
var
  Decl: TDialogDeclaration;
  Hint, Title: string;
begin
  Title := T('ui.themeEditor.glyphTitle', 'Glyph');
  if FItems[FItem].Kind = tikExtends then
  begin
    Title := ThemeExtendsTitle;
    Hint := T('ui.themeEditor.hintExtends', 'Theme ids separated by ";"; later ones override earlier ones.');
  end
  else
    case FItems[FItem].Glyph of
      tgButtonNormal, tgButtonDefault, tgTabWorkspace, tgTabPanel:
        Hint := T('ui.themeEditor.hintTemplate', '{0} stands for the caption.');
      tgCheckOn, tgCheckOff, tgRadioOn, tgRadioOff:
        Hint := T('ui.themeEditor.hintMark', 'Drawn before the caption.');
    else
      Hint := T('ui.themeEditor.hintChar', 'One character.');
    end;
  RequireDialogResource(cResDialogThemeText, Decl);
  DialogSetTitle(Decl, Title);
  DialogSetLabelText(Decl, 'lbl_item', ItemTitle(FItems[FItem]));
  DialogSetInputValue(Decl, 'value', AText);
  DialogSetLabelText(Decl, 'lbl_inherited', InheritedText(FItems[FItem]));
  DialogSetLabelText(Decl, 'hint', Hint);
  if AStatus <> '' then
    DialogSetLabelText(Decl, 'status', AStatus);
  SetKind(hdkThemeText);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

procedure TThemeDialogController.ShowChoiceEdit;
var
  Decl: TDialogDeclaration;
  Item: TThemeItem;
  Choices: TArray<string>;
  Sel, I: Integer;
  Names: TArray<string>;
  Name: string;
  Spec: TThemeSpec;
  Pair: TMdColorPair;
  Attr: TThemeAttrValue;

  procedure AddCustomFrameSets;
  var
    J, K: Integer;
    Known: Boolean;
  begin
    Spec := ResolveDocSpec(FDoc);
    for J := 0 to High(Spec.FrameSets) do
    begin
      Known := False;
      for K := 0 to High(FChoiceIds) do
        if SameText(FChoiceIds[K], Spec.FrameSets[J].Name) then
          Known := True;
      if not Known then
      begin
        FChoiceIds := FChoiceIds + [Spec.FrameSets[J].Name];
        Choices := Choices + [ThemeFrameSetTitle(Spec.FrameSets[J].Name)];
      end;
    end;
  end;

begin
  Item := FItems[FItem];
  SetLength(FChoiceIds, 0);
  SetLength(Choices, 0);
  Sel := 0;
  case Item.Kind of
    tikDoubleActive:
      begin
        Choices := [T('ui.themeEditor.auto', 'Automatic'),
          T('ui.themeEditor.yes', 'yes'), T('ui.themeEditor.no', 'no')];
        case FDoc.DoubleActivePanel of
          ttsTrue: Sel := 1;
          ttsFalse: Sel := 2;
        end;
      end;
    tikAttr, tikMdAttrs:
      begin
        SetLength(Choices, MdStyleChoiceCount);
        for I := 0 to High(Choices) do
          if I = 0 then
            Choices[I] := T('ui.themeEditor.inherit', 'Inherit')
          else
            Choices[I] := T('ui.markdownColors.style.' + MdStyleChoiceKey(I), MdStyleChoiceKey(I));
        if Item.Kind = tikAttr then
          Attr := FDoc.Attrs[Item.Attr]
        else
          Attr := FDoc.MdAttrs[Item.Md];
        if Attr.Has then
        begin
          Pair := Default(TMdColorPair);
          Pair.HasStyle := True;
          Pair.Style := Attr.Value;
          Sel := MdStyleChoiceOf(Pair);
          // A style the list does not offer (blink, reverse) shows as plain.
          if Sel = 0 then
            Sel := 1;
        end;
      end;
    tikFrame:
      begin
        Choices := [T('ui.themeEditor.inherit', 'Inherit')];
        FChoiceIds := [''];
        Names := BuiltInFrameSetNames;
        for Name in Names do
        begin
          Choices := Choices + [ThemeFrameSetTitle(Name)];
          FChoiceIds := FChoiceIds + [Name];
        end;
        AddCustomFrameSets;
        if FDoc.Frames[Item.Frame].Has then
          for I := 0 to High(FChoiceIds) do
            if SameText(FChoiceIds[I], FDoc.Frames[Item.Frame].Value) then
              Sel := I;
      end;
  end;
  RequireDialogResource(cResDialogThemeChoice, Decl);
  DialogSetLabelText(Decl, 'lbl_item', ItemTitle(Item));
  DialogSetListItems(Decl, 'choice', Choices, Sel);
  DialogSetLabelText(Decl, 'lbl_inherited', InheritedText(Item));
  SetKind(hdkThemeChoice);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

function TThemeDialogController.ValidateColorText(const AText: string;
  out ASlot: TThemeColorSlot; out AError: string): Boolean;
var
  Spec: TThemeSpec;
  Known: Boolean;
  I: Integer;
begin
  Result := False;
  AError := '';
  if not ThemeSlotFromText(AText, ASlot) then
  begin
    AError := T('ui.themeEditor.badColor',
      'Colors must be #RRGGBB, #AARRGGBB, @role.key or a palette name.');
    Exit;
  end;
  if (ASlot.Ref <> '') and (ASlot.Ref[1] <> '@') then
  begin
    Spec := ResolveDocSpec(FDoc);
    Known := False;
    for I := 0 to High(Spec.Palette) do
      if SameText(Spec.Palette[I].Name, ASlot.Ref) then
        Known := True;
    if not Known then
    begin
      AError := T('ui.themeEditor.unknownPalette', 'No such palette color.');
      Exit;
    end;
  end;
  Result := True;
end;

function TThemeDialogController.ApplyGlyphText(const AText: string;
  out AStatus: string): Boolean;
var
  Glyph: TThemeGlyph;
  Ids: TArray<string>;
  Id: string;
begin
  Result := False;
  AStatus := '';
  if FItems[FItem].Kind = tikExtends then
  begin
    Ids := ThemeParseExtends(AText);
    for Id in Ids do
    begin
      if SameText(Id, FDoc.Id) and (FDoc.Id <> '') then
      begin
        AStatus := T('ui.themeEditor.selfExtend', 'A theme cannot build on itself.');
        Exit;
      end;
      if not ThemeExists(Id) then
      begin
        AStatus := Format(T('ui.themeEditor.baseNotFound', 'No theme "%s".'), [Id]);
        Exit;
      end;
    end;
    FDoc.Extends := Ids;
    Exit(True);
  end;
  Glyph := FItems[FItem].Glyph;
  case Glyph of
    tgButtonNormal, tgButtonDefault, tgTabWorkspace, tgTabPanel:
      if not ThemeTemplateValid(AText) then
      begin
        AStatus := T('ui.themeEditor.needTemplate', 'The text must contain {0}.');
        Exit;
      end;
    tgCheckOn, tgCheckOff, tgRadioOn, tgRadioOff:
      if AText = '' then
      begin
        AStatus := T('ui.themeEditor.emptyText', 'The text must not be empty.');
        Exit;
      end;
  else
    if Length(AText) <> 1 then
    begin
      AStatus := T('ui.themeEditor.oneChar', 'Enter exactly one character.');
      Exit;
    end;
  end;
  FDoc.Glyphs[Glyph].Has := True;
  FDoc.Glyphs[Glyph].Value := AText;
  Result := True;
end;

function TThemeDialogController.ApplyChoice(AIndex: Integer): Boolean;
var
  Item: TThemeItem;
  Pair: TMdColorPair;
  Attr: TThemeAttrValue;
begin
  Result := True;
  Item := FItems[FItem];
  case Item.Kind of
    tikDoubleActive:
      case AIndex of
        1: FDoc.DoubleActivePanel := ttsTrue;
        2: FDoc.DoubleActivePanel := ttsFalse;
      else
        FDoc.DoubleActivePanel := ttsUnset;
      end;
    tikAttr, tikMdAttrs:
      begin
        Attr := Default(TThemeAttrValue);
        if AIndex > 0 then
        begin
          Pair := Default(TMdColorPair);
          MdStyleChoiceApply(Pair, AIndex);
          Attr.Has := True;
          Attr.Value := Pair.Style;
        end;
        if Item.Kind = tikAttr then
          FDoc.Attrs[Item.Attr] := Attr
        else
          FDoc.MdAttrs[Item.Md] := Attr;
      end;
    tikFrame:
      if (AIndex <= 0) or (AIndex > High(FChoiceIds)) then
        FDoc.Frames[Item.Frame].Has := False
      else
      begin
        FDoc.Frames[Item.Frame].Has := True;
        FDoc.Frames[Item.Frame].Value := FChoiceIds[AIndex];
      end;
  else
    Result := False;
  end;
end;

procedure TThemeDialogController.DispatchText(const AControlId: string);
var
  Status: string;
begin
  if DialogCmdIs(AControlId, 'inherit') then
  begin
    ClearItem(FDoc, FItems[FItem]);
    Preview;
    OpenItems(FSection, FItem);
    Exit;
  end;
  if DialogCmdIsReject(AControlId) then
  begin
    OpenItems(FSection, FItem);
    Exit;
  end;
  if not ApplyGlyphText(FDialog.GetInputValue('value'), Status) then
  begin
    FDialog.SetStatus('status', Status);
    SetKind(hdkThemeText);
    Notify;
    Exit;
  end;
  Preview;
  OpenItems(FSection, FItem);
end;

procedure TThemeDialogController.DispatchChoice(const AControlId: string);
begin
  if DialogCmdIsAccept(AControlId) then
  begin
    ApplyChoice(FDialog.GetListSelectedIndex('choice'));
    Preview;
  end;
  OpenItems(FSection, FItem);
end;

// ------------------------------------------------------------ color picker

function SlotOrEffective(const ASlot: TThemeColorSlot; AEffective: TAlphaColor): string;
begin
  if ASlot.Has then
    Result := ThemeSlotText(ASlot)
  else
    Result := ThemeColorToText(AEffective);
end;

function StyleChoiceOfAttr(const AAttr: TThemeAttrValue): Integer;
var
  Pair: TMdColorPair;
begin
  if not AAttr.Has then
    Exit(0);
  Pair := Default(TMdColorPair);
  Pair.HasStyle := True;
  Pair.Style := AAttr.Value;
  Result := MdStyleChoiceOf(Pair);
  // A style the list does not offer (blink, reverse) shows as plain.
  if Result = 0 then
    Result := 1;
end;

procedure TThemeDialogController.OpenForm(ASection: Integer);
var
  Spec: TThemeSpec;
  I: Integer;
begin
  FSection := ASection;
  Spec := ResolveDocSpec(FDoc);
  SetLength(FFormRoles, 0);
  SetLength(FFormKinds, 0);
  SetLength(FFormTexts, 0);
  SetLength(FFormStyles, 0);
  if SameText(FSections[ASection], cSectionMarkdown) then
  begin
    FFormMode := fmMarkdown;
    for I := Ord(Low(TMdSpanKind)) to Ord(High(TMdSpanKind)) do
    begin
      FFormKinds := FFormKinds + [TMdSpanKind(I)];
      FFormTexts := FFormTexts + [
        SlotOrEffective(FDoc.MdFg[TMdSpanKind(I)], Spec.MdFg[TMdSpanKind(I)]),
        SlotOrEffective(FDoc.MdBg[TMdSpanKind(I)], Spec.MdBg[TMdSpanKind(I)])];
      FFormStyles := FFormStyles + [StyleChoiceOfAttr(FDoc.MdAttrs[TMdSpanKind(I)])];
    end;
  end
  else
  begin
    FFormMode := fmRoles;
    for I := 0 to High(FItems) do
    begin
      FFormRoles := FFormRoles + [FItems[I].Role];
      FFormTexts := FFormTexts + [SlotOrEffective(FDoc.Colors[FItems[I].Role],
        Spec.Colors[FItems[I].Role])];
    end;
  end;
  FFormInit := Copy(FFormTexts);
  FFormInitStyle := Copy(FFormStyles);
  FFormPick := '';
  ShowForm('', 0);
end;

procedure TThemeDialogController.ShowForm(const AStatus: string; AFocus: Integer);
var
  Decl: TDialogDeclaration;
  Head, Rows, Tail: TDialogControls;
  Ctrl: TDialogControl;
  I, N, Row, RuleCount: Integer;
  Md: Boolean;
  Styles, StyleAttrs: TArray<string>;
  Spec: TThemeSpec;
  Base, Id: string;
  Names: TArray<string>;

  function Box(const C: TDialogControl; ACol, ARow, AW: Integer): TDialogControl;
  begin
    Result := WithControlBox(C, ACol, ARow, AW, 1);
  end;

  function ColorInput(const AId, AText: string): TDialogControl;
  begin
    Result := MakeInput(AId, AText);
    Result.ColorPick := True;
  end;

begin
  Md := FFormMode = fmMarkdown;
  if Md then
    N := Length(FFormKinds)
  else
    N := Length(FFormRoles);
  Spec := ResolveDocSpec(FDoc);
  RequireDialogResource(cResDialogThemeColors, Decl);
  SetLength(Head, 0);
  SetLength(Tail, 0);
  for Ctrl in Decl.Controls do
  begin
    Id := Ctrl.Id;
    if SameText(Id, 'lbl_element') then
      Head := Head + [Box(Ctrl, 1, 0, IfThen(Md, 19, 34))]
    else if SameText(Id, 'lbl_color') then
    begin
      if not Md then
        Head := Head + [Box(Ctrl, 36, 0, 12)];
    end
    else if SameText(Id, 'lbl_sample') then
      Head := Head + [Box(Ctrl, IfThen(Md, 45, 50), 0, 14)]
    else
      Tail := Tail + [Ctrl];
  end;

  if Md then
  begin
    Head := Head + [Box(MakeLabel(T('ui.themeEditor.colFg', 'Foreground'), 'lbl_fg'), 21, 0, 11)];
    Head := Head + [Box(MakeLabel(T('ui.themeEditor.colBg', 'Background'), 'lbl_bg'), 33, 0, 11)];
    Head := Head + [Box(MakeLabel(T('ui.themeEditor.colStyle', 'Style'), 'lbl_style'), 60, 0, 20)];
  end;
  SetLength(Rows, 0);
  if Md then
  begin
    SetLength(Styles, MdStyleChoiceCount);
    SetLength(StyleAttrs, MdStyleChoiceCount);
    for I := 0 to High(Styles) do
    begin
      if I = 0 then
        Styles[I] := T('ui.themeEditor.inherit', 'Inherit')
      else
        Styles[I] := T('ui.markdownColors.style.' + MdStyleChoiceKey(I), MdStyleChoiceKey(I));
      StyleAttrs[I] := MdStyleChoiceAttrs(I);
    end;
  end;
  for I := 0 to N - 1 do
  begin
    Row := 1 + I;
    if Md then
    begin
      Rows := Rows + [Box(MakeLabel(ThemeMdKindTitle(FFormKinds[I]), 'lbl_r' + IntToStr(I)), 1, Row, 19)];
      Rows := Rows + [Box(ColorInput('f_' + IntToStr(I), FFormTexts[2 * I]), 21, Row, 11)];
      Rows := Rows + [Box(ColorInput('g_' + IntToStr(I), FFormTexts[2 * I + 1]), 33, Row, 11)];
      Ctrl := MakeColorSample('s_' + IntToStr(I), 'Abc  Abc',
        'f_' + IntToStr(I), 'g_' + IntToStr(I));
      Ctrl.StyleSourceId := 'y_' + IntToStr(I);
      Names := ThemeAttrsToNames(Spec.MdAttrs[FFormKinds[I]]);
      Base := '';
      for Id in Names do
      begin
        if Base <> '' then
          Base := Base + '+';
        Base := Base + Id;
      end;
      Ctrl.BaseStyle := Base;
      Rows := Rows + [Box(Ctrl, 45, Row, 14)];
      Ctrl := MakeDropDown('y_' + IntToStr(I), Styles, FFormStyles[I]);
      Ctrl.ItemIds := Copy(StyleAttrs);
      Rows := Rows + [Box(Ctrl, 60, Row, 20)];
    end
    else
    begin
      Rows := Rows + [Box(MakeLabel(ThemeColorRoleTitle(FFormRoles[I]), 'lbl_r' + IntToStr(I)), 1, Row, 34)];
      Rows := Rows + [Box(ColorInput('c_' + IntToStr(I), FFormTexts[I]), 36, Row, 12)];
      Rows := Rows + [Box(MakeColorSample('s_' + IntToStr(I), '  Aa  ', '', 'c_' + IntToStr(I)),
        50, Row, 14)];
    end;
  end;
  // Rule, hint, rule, status and the buttons below the rows.
  RuleCount := 0;
  for I := 0 to High(Tail) do
  begin
    Id := Tail[I].Id;
    if SameText(Id, 'hint') then
      Tail[I] := WithControlBox(Tail[I], 1, N + 2, IfThen(Md, 80, 64), 1)
    else if SameText(Id, 'status') then
      Tail[I] := WithControlBox(Tail[I], 1, N + 4, IfThen(Md, 80, 64), 1)
    else if IsHRuleText(Tail[I].Text) then
    begin
      Tail[I] := WithControlBox(Tail[I], 0, IfThen(RuleCount = 0, N + 1, N + 3),
        IfThen(Md, 84, 68) - 2, 1);
      Inc(RuleCount);
    end
    else if SameText(Id, 'ok') then
      Tail[I] := WithControlBox(Tail[I], 1, N + 5, 10, 1)
    else if SameText(Id, 'cancel') then
      Tail[I] := WithControlBox(Tail[I], 13, N + 5, 12, 1);
  end;
  Decl.Controls := Head + Rows + Tail;
  Decl.Width := IfThen(Md, 84, 68);
  Decl.Height := N + 9;
  DialogSetTitle(Decl, Format(T('ui.themeEditor.title', 'Theme: %s'), [FDoc.Name]) +
    ' / ' + SectionLabel(FSections[FSection]));
  if AStatus <> '' then
    DialogSetLabelText(Decl, 'status', AStatus);
  SetKind(hdkThemeColors);
  FDialog.Open(Decl, FOnCommand);
  if (AFocus >= 0) and (AFocus < N) then
    if Md then
      FDialog.FocusControlById('f_' + IntToStr(AFocus))
    else
      FDialog.FocusControlById('c_' + IntToStr(AFocus));
  Notify;
end;

procedure TThemeDialogController.ReadForm;
var
  I: Integer;
begin
  if FFormMode = fmMarkdown then
  begin
    for I := 0 to High(FFormKinds) do
    begin
      FFormTexts[2 * I] := Trim(FDialog.GetInputValue('f_' + IntToStr(I)));
      FFormTexts[2 * I + 1] := Trim(FDialog.GetInputValue('g_' + IntToStr(I)));
      FFormStyles[I] := FDialog.GetListSelectedIndex('y_' + IntToStr(I));
    end;
  end
  else
    for I := 0 to High(FFormRoles) do
      FFormTexts[I] := Trim(FDialog.GetInputValue('c_' + IntToStr(I)));
end;

// AIndex is the position in FFormTexts.
function TThemeDialogController.FormFieldIndex(const AField: string;
  out AIndex: Integer): Boolean;
var
  N: Integer;
begin
  Result := False;
  AIndex := -1;
  if (Length(AField) < 3) or (AField[2] <> '_') then
    Exit;
  N := StrToIntDef(Copy(AField, 3, MaxInt), -1);
  if N < 0 then
    Exit;
  case AField[1] of
    'c': if (FFormMode = fmRoles) and (N <= High(FFormRoles)) then AIndex := N;
    'f': if (FFormMode = fmMarkdown) and (N <= High(FFormKinds)) then AIndex := 2 * N;
    'g': if (FFormMode = fmMarkdown) and (N <= High(FFormKinds)) then AIndex := 2 * N + 1;
  end;
  Result := AIndex >= 0;
end;

function TThemeDialogController.FormRowTitle(AIndex: Integer): string;
begin
  if FFormMode = fmMarkdown then
  begin
    Result := ThemeMdKindTitle(FFormKinds[AIndex div 2]) + ': ';
    if AIndex mod 2 = 0 then
      Result := Result + ThemeMdPartTitle('fg')
    else
      Result := Result + ThemeMdPartTitle('bg');
  end
  else
    Result := ThemeColorRoleTitle(FFormRoles[AIndex]);
end;

procedure TThemeDialogController.BeginFormPicker(const AField: string);
var
  Idx: Integer;
  Start: TAlphaColor;
begin
  if not FormFieldIndex(AField, Idx) then
    Exit;
  ReadForm;
  FFormPick := AField;
  if not TryParseThemeColor(FFormTexts[Idx], Start) then
    Start := cPickerNoColor;
  SetKind(hdkThemePicker);
  FDialog.Open(BuildColorPickerDialog(T('ui.themeEditor.pickColor', 'Pick color'), Start),
    FOnCommand);
  Notify;
end;

procedure TThemeDialogController.DispatchColors(const AControlId: string);
var
  Field, Err: string;
  Idx, I: Integer;
  Slots: TArray<TThemeColorSlot>;
  Changed: TArray<Boolean>;
  Attr: TThemeAttrValue;
  Pair: TMdColorPair;
begin
  if DialogCmdIsPick(AControlId, Field) then
  begin
    BeginFormPicker(Field);
    Exit;
  end;
  if DialogCmdIsReject(AControlId) then
  begin
    ShowEditor(FSection, '');
    Exit;
  end;
  ReadForm;
  SetLength(Slots, Length(FFormTexts));
  SetLength(Changed, Length(FFormTexts));
  for I := 0 to High(FFormTexts) do
  begin
    Changed[I] := FFormTexts[I] <> FFormInit[I];
    if Changed[I] and (FFormTexts[I] <> '') and
       not ValidateColorText(FFormTexts[I], Slots[I], Err) then
    begin
      FDialog.SetStatus('status', FormRowTitle(I) + ': ' + Err);
      SetKind(hdkThemeColors);
      Notify;
      Exit;
    end;
  end;
  for I := 0 to High(FFormTexts) do
  begin
    if not Changed[I] then
      Continue;
    if FFormMode = fmRoles then
      FDoc.Colors[FFormRoles[I]] := Slots[I]
    else if I mod 2 = 0 then
      FDoc.MdFg[FFormKinds[I div 2]] := Slots[I]
    else
      FDoc.MdBg[FFormKinds[I div 2]] := Slots[I];
  end;
  if FFormMode = fmMarkdown then
    for Idx := 0 to High(FFormKinds) do
      if FFormStyles[Idx] <> FFormInitStyle[Idx] then
      begin
        Attr := Default(TThemeAttrValue);
        if FFormStyles[Idx] > 0 then
        begin
          Pair := Default(TMdColorPair);
          MdStyleChoiceApply(Pair, FFormStyles[Idx]);
          Attr.Has := True;
          Attr.Value := Pair.Style;
        end;
        FDoc.MdAttrs[FFormKinds[Idx]] := Attr;
      end;
  Preview;
  ShowEditor(FSection, '');
end;

procedure TThemeDialogController.DispatchColorPicker(const AControlId: string);
var
  Idx: Integer;
  Field: string;
begin
  Field := FFormPick;
  FFormPick := '';
  if FormFieldIndex(Field, Idx) then
  begin
    if DialogCmdIsAccept(AControlId) then
      FFormTexts[Idx] := FDialog.GetColorPickerHex('picker')
    else if DialogCmdIs(AControlId, 'clear') then
      FFormTexts[Idx] := '';
    if FFormMode = fmMarkdown then
      ShowForm('', Idx div 2)
    else
      ShowForm('', Idx);
    Exit;
  end;
  ShowForm('', 0);
end;

function TThemeDialogController.HandleColorInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Idx: Integer;
begin
  Result := (AKey = vkF9) and FormFieldIndex(FDialog.FocusedControlId, Idx);
  if Result then
  begin
    BeginFormPicker(FDialog.FocusedControlId);
    AKey := 0;
    AKeyChar := #0;
  end;
end;

function TThemeDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkTheme: DispatchPicker(AControlId);
    hdkThemeNew: DispatchNew(AControlId);
    hdkThemeName: DispatchName(AControlId);
    hdkThemeDelete: DispatchDelete(AControlId);
    hdkThemeEditor: DispatchEditor(AControlId);
    hdkThemeItems: DispatchItems(AControlId);
    hdkThemeColors: DispatchColors(AControlId);
    hdkThemeText: DispatchText(AControlId);
    hdkThemeChoice: DispatchChoice(AControlId);
    hdkThemePicker: DispatchColorPicker(AControlId);
  else
    { not a theme dialog }
  end;
end;

end.
