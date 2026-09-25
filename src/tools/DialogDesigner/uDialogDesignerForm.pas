unit uDialogDesignerForm;

{ Standalone DIALOG_PLUGIN JSON editor + live TDialogHost preview. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  System.Math, System.JSON,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Edit, FMX.Layouts, FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Menus,
  FMX.ListBox, FMX.Controls.Presentation, FMX.Objects, FMX.DialogService.Sync,
  uTerminalTypes, uThemeTypes, uDialogTypes, uDialogJson, uDialogHost,
  uDialogResources, uNDNTheme, uTerminalRenderer, uInputLine, uStrings;

type
  /// <summary>Property-panel field edit: mutates the selected control's
  /// record fields; MutateSelectedControl re-serializes and re-applies.</summary>
  TControlMutator = reference to procedure(var C: TDialogControl);

  TDialogDesignerForm = class(TForm)
  private
    FRenderer: TTerminalRenderer;
    FTheme: IThemeRenderer;
    FDialog: TDialogHost;
    /// <summary>Untranslated layout parsed from the memo. The property panel
    /// reads this; the preview may show a translated copy.</summary>
    FLayout: TDialogDeclaration;
    FFilePath: string;
    FDirty: Boolean;
    FApplying: Boolean;
    FLastScale: Single;
    FPreviewFocus: Boolean;

    /// <summary>False (default) = clicking the preview selects a control for
    /// property-panel editing. True = clicks are forwarded to TDialogHost
    /// like a real end user (test buttons/checkboxes/inputs).</summary>
    FTestMode: Boolean;
    /// <summary>Index into the currently-open FDialog's controls, -1 = none.</summary>
    FSelectedIndex: Integer;
    /// <summary>Guards property-panel field setters against firing their own
    /// OnChange while RebuildPropertyPanel is populating them.</summary>
    FPropApplying: Boolean;

    FRoot: TLayout;
    FTool: TLayout;
    FSplit: TLayout;
    FLeft: TLayout;
    FRight: TLayout;
    FBottom: TLayout;
    FMemo: TMemo;
    FPaint: TPaintBox;
    FLog: TMemo;
    FStatus: TLabel;
    FBtnNew: TButton;
    FBtnOpen: TButton;
    FBtnSave: TButton;
    FBtnSaveAs: TButton;
    FBtnApply: TButton;
    FBtnPretty: TButton;
    FChkTestMode: TCheckBox;
    FLblLocale: TLabel;
    FCmbLocale: TComboBox;
    FLocaleApplying: Boolean;
    FCmbAddKind: TComboBox;
    FBtnAddCtrl: TButton;
    FBtnDeleteCtrl: TButton;

    FPropPanel: TVertScrollBox;
    FPropHeader: TLabel;
    FPropRowText, FPropRowValue, FPropRowGroup, FPropRowChecked,
      FPropRowDefault, FPropRowCancel, FPropRowPassword, FPropRowItems,
      FPropRowSelIndex, FPropRowFgSrc, FPropRowBgSrc, FPropRowPanelState,
      FPropRowCol, FPropRowRow, FPropRowW, FPropRowH: TLayout;
    FPropEditId, FPropEditText, FPropEditValue, FPropEditGroup,
      FPropEditSelIndex, FPropEditFgSrc, FPropEditBgSrc,
      FPropEditCol, FPropEditRow, FPropEditW, FPropEditH: TEdit;
    FPropChkChecked, FPropChkDefault, FPropChkCancel, FPropChkPassword: TCheckBox;
    FPropMemoItems: TMemo;
    FPropCmbPanelState: TComboBox;
    FMenu: TMainMenu;
    FMiFile: TMenuItem;
    FMiNew: TMenuItem;
    FMiOpen: TMenuItem;
    FMiSave: TMenuItem;
    FMiSaveAs: TMenuItem;
    FMiTemplates: TMenuItem;
    FMiExit: TMenuItem;
    FMiView: TMenuItem;
    FMiApply: TMenuItem;
    FMiPretty: TMenuItem;
    FMiZoomIn: TMenuItem;
    FMiZoomOut: TMenuItem;
    FMiZoomReset: TMenuItem;

    procedure BuildUi;
    procedure WireEvents;
    procedure SetDirty(AValue: Boolean);
    procedure UpdateCaption;
    procedure SetStatus(const AText: string);
    procedure LogLine(const AText: string);
    procedure SyncPreviewSize;
    procedure Recompose;
    procedure ComposeScene(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    function PointToCell(X, Y: Single; out ACol, ARow: Integer): Boolean;
    function DefaultSampleJson(out APath: string): string;
    function PrettyJson(const AJson: string): string;
    function ProjectDialogsDir: string;
    function TryLoadProjectDialogFile(const AFileName: string;
      out AJson, APath: string): Boolean;
    procedure LoadJsonText(const AText: string; const APath: string; AMarkClean: Boolean);
    procedure ApplyPreview;
    procedure OpenTranslatedPreview;
    function DialogResourceName: string;
    procedure CmbLocaleChange(Sender: TObject);
    function ConfirmDiscard: Boolean;
    procedure DialogCommand(const AControlId, AValuesJson: string);
    procedure DialogChanged(Sender: TObject);

    function AddPropRow(const ACaption: string): TLayout;
    procedure SelectControl(AIndex: Integer);
    procedure RebuildPropertyPanel;
    procedure MutateSelectedControl(const AMutate: TControlMutator);
    procedure DrawSelectionMarks(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    procedure EditIdChange(Sender: TObject);
    procedure EditTextChange(Sender: TObject);
    procedure EditValueChange(Sender: TObject);
    procedure EditGroupChange(Sender: TObject);
    procedure EditSelIndexChange(Sender: TObject);
    procedure EditFgSourceChange(Sender: TObject);
    procedure EditBgSourceChange(Sender: TObject);
    procedure EditColChange(Sender: TObject);
    procedure EditRowChange(Sender: TObject);
    procedure EditWChange(Sender: TObject);
    procedure EditHChange(Sender: TObject);
    procedure ChkCheckedChange(Sender: TObject);
    procedure ChkDefaultChange(Sender: TObject);
    procedure ChkCancelChange(Sender: TObject);
    procedure ChkPasswordChange(Sender: TObject);
    procedure MemoItemsChange(Sender: TObject);
    procedure CmbPanelStateChange(Sender: TObject);
    procedure ChkTestModeChange(Sender: TObject);
    procedure BtnAddClick(Sender: TObject);
    procedure BtnDeleteClick(Sender: TObject);

    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
    procedure MemoChange(Sender: TObject);
    procedure MemoEnter(Sender: TObject);
    procedure PaintPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure PaintMouseEnter(Sender: TObject);
    procedure BtnNewClick(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnSaveAsClick(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnPrettyClick(Sender: TObject);
    procedure MiExitClick(Sender: TObject);
    procedure MiTemplateClick(Sender: TObject);
    procedure MiZoomInClick(Sender: TObject);
    procedure MiZoomOutClick(Sender: TObject);
    procedure MiZoomResetClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure KeyDown(var Key: Word; var KeyChar: System.WideChar;
      Shift: TShiftState); override;
  end;

var
  DialogDesignerForm: TDialogDesignerForm;

implementation

const
  cAppTitle = 'MTN2 Dialog Designer';

function MakeToolButton(AParent: TFmxObject; const AText: string;
  AOnClick: TNotifyEvent; var ALeft: Single): TButton;
begin
  Result := TButton.Create(AParent);
  Result.Parent := AParent;
  Result.Text := AText;
  Result.Position.X := ALeft;
  Result.Position.Y := 4;
  Result.Width := 78;
  Result.Height := 28;
  Result.OnClick := AOnClick;
  ALeft := ALeft + Result.Width + 6;
end;

function TDialogDesignerForm.AddPropRow(const ACaption: string): TLayout;
var
  Lbl: TLabel;
begin
  Result := TLayout.Create(FPropPanel);
  Result.Parent := FPropPanel;
  Result.Align := TAlignLayout.Top;
  Result.Height := 24;
  Result.Margins.Bottom := 4;
  Lbl := TLabel.Create(Result);
  Lbl.Parent := Result;
  Lbl.Align := TAlignLayout.Left;
  Lbl.Width := 84;
  Lbl.Text := ACaption;
  Lbl.TextSettings.Font.Size := 11;
end;

function DialogControlKindName(AKind: TDialogControlKind): string;
begin
  case AKind of
    dckLabel: Result := 'label';
    dckInput: Result := 'input';
    dckCheckbox: Result := 'checkbox';
    dckButton: Result := 'button';
    dckStatus: Result := 'status';
    dckList: Result := 'list';
    dckRadio: Result := 'radio';
    dckRadioGroup: Result := 'radio_group';
    dckDropDown: Result := 'dropdown';
    dckColorSample: Result := 'colorsample';
  else
    Result := 'unknown';
  end;
end;

constructor TDialogDesignerForm.Create(AOwner: TComponent);
var
  Path: string;
begin
  inherited CreateNew(AOwner);
  Caption := cAppTitle;
  Width := 1880;
  Height := 800;
  Position := TFormPosition.ScreenCenter;
  FLastScale := 0;
  FPreviewFocus := False;
  FTestMode := False;
  FSelectedIndex := -1;
  FTheme := TNDNTheme.Create;
  FRenderer := TTerminalRenderer.Create;
  FRenderer.OnCompose := ComposeScene;
  FDialog := TDialogHost.Create(FTheme);
  FDialog.OnChanged := DialogChanged;
  BuildUi;
  WireEvents;
  LoadJsonText(DefaultSampleJson(Path), Path, True);
  ApplyPreview;
end;

procedure TDialogDesignerForm.BuildUi;
var
  X: Single;
  Mi: TMenuItem;
  Row: TLayout;
  Loc: string;
  LocaleIndex: Integer;
begin
  FMenu := TMainMenu.Create(Self);
  FMenu.Parent := Self;
  FMiFile := TMenuItem.Create(FMenu);
  FMiFile.Text := 'File';
  FMenu.AddObject(FMiFile);
  FMiNew := TMenuItem.Create(FMiFile);
  FMiNew.Text := 'New';
  FMiNew.ShortCut := scCtrl or vkN;
  FMiNew.OnClick := BtnNewClick;
  FMiFile.AddObject(FMiNew);
  FMiOpen := TMenuItem.Create(FMiFile);
  FMiOpen.Text := 'Open...';
  FMiOpen.ShortCut := scCtrl or vkO;
  FMiOpen.OnClick := BtnOpenClick;
  FMiFile.AddObject(FMiOpen);
  FMiSave := TMenuItem.Create(FMiFile);
  FMiSave.Text := 'Save';
  FMiSave.ShortCut := scCtrl or vkS;
  FMiSave.OnClick := BtnSaveClick;
  FMiFile.AddObject(FMiSave);
  FMiSaveAs := TMenuItem.Create(FMiFile);
  FMiSaveAs.Text := 'Save As...';
  FMiSaveAs.OnClick := BtnSaveAsClick;
  FMiFile.AddObject(FMiSaveAs);
  FMiTemplates := TMenuItem.Create(FMiFile);
  FMiTemplates.Text := 'New from template';
  FMiFile.AddObject(FMiTemplates);

  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Confirm';
  Mi.Tag := 1;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Input';
  Mi.Tag := 2;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Find file';
  Mi.Tag := 3;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Copy/Move';
  Mi.Tag := 4;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Help';
  Mi.Tag := 5;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Ask save';
  Mi.Tag := 6;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Go to line';
  Mi.Tag := 7;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Code page';
  Mi.Tag := 8;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Replace';
  Mi.Tag := 9;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);
  Mi := TMenuItem.Create(FMiTemplates);
  Mi.Text := 'Delete';
  Mi.Tag := 10;
  Mi.OnClick := MiTemplateClick;
  FMiTemplates.AddObject(Mi);

  FMiExit := TMenuItem.Create(FMiFile);
  FMiExit.Text := 'Exit';
  FMiExit.OnClick := MiExitClick;
  FMiFile.AddObject(FMiExit);

  FMiView := TMenuItem.Create(FMenu);
  FMiView.Text := 'View';
  FMenu.AddObject(FMiView);
  FMiApply := TMenuItem.Create(FMiView);
  FMiApply.Text := 'Apply preview';
  FMiApply.ShortCut := vkF5;
  FMiApply.OnClick := BtnApplyClick;
  FMiView.AddObject(FMiApply);
  FMiPretty := TMenuItem.Create(FMiView);
  FMiPretty.Text := 'Pretty-print JSON';
  FMiPretty.OnClick := BtnPrettyClick;
  FMiView.AddObject(FMiPretty);
  FMiZoomIn := TMenuItem.Create(FMiView);
  FMiZoomIn.Text := 'Zoom In';
  FMiZoomIn.ShortCut := scCtrl or vkAdd;
  FMiZoomIn.OnClick := MiZoomInClick;
  FMiView.AddObject(FMiZoomIn);
  FMiZoomOut := TMenuItem.Create(FMiView);
  FMiZoomOut.Text := 'Zoom Out';
  FMiZoomOut.ShortCut := scCtrl or vkSubtract;
  FMiZoomOut.OnClick := MiZoomOutClick;
  FMiView.AddObject(FMiZoomOut);
  FMiZoomReset := TMenuItem.Create(FMiView);
  FMiZoomReset.Text := 'Reset Zoom';
  FMiZoomReset.ShortCut := scCtrl or vkNumpad0;
  FMiZoomReset.OnClick := MiZoomResetClick;
  FMiView.AddObject(FMiZoomReset);

  FRoot := TLayout.Create(Self);
  FRoot.Parent := Self;
  FRoot.Align := TAlignLayout.Client;
  FRoot.Padding.Rect := RectF(6, 6, 6, 6);

  FTool := TLayout.Create(FRoot);
  FTool.Parent := FRoot;
  FTool.Align := TAlignLayout.Top;
  FTool.Height := 36;

  X := 0;
  FBtnNew := MakeToolButton(FTool, 'New', BtnNewClick, X);
  FBtnOpen := MakeToolButton(FTool, 'Open', BtnOpenClick, X);
  FBtnSave := MakeToolButton(FTool, 'Save', BtnSaveClick, X);
  FBtnSaveAs := MakeToolButton(FTool, 'Save As', BtnSaveAsClick, X);
  FBtnApply := MakeToolButton(FTool, 'Apply', BtnApplyClick, X);
  FBtnPretty := MakeToolButton(FTool, 'Pretty', BtnPrettyClick, X);
  FBtnApply.Width := 88;
  FBtnPretty.Width := 88;

  X := X + 16;
  FChkTestMode := TCheckBox.Create(FTool);
  FChkTestMode.Parent := FTool;
  FChkTestMode.Text := 'Test mode (click = interact)';
  FChkTestMode.Position.X := X;
  FChkTestMode.Position.Y := 8;
  FChkTestMode.Width := 190;
  FChkTestMode.IsChecked := FTestMode;
  FChkTestMode.OnChange := ChkTestModeChange;
  X := X + FChkTestMode.Width + 16;

  FCmbAddKind := TComboBox.Create(FTool);
  FCmbAddKind.Parent := FTool;
  FCmbAddKind.Position.X := X;
  FCmbAddKind.Position.Y := 4;
  FCmbAddKind.Width := 110;
  FCmbAddKind.Height := 28;
  FCmbAddKind.Items.Add('Label');
  FCmbAddKind.Items.Add('Input');
  FCmbAddKind.Items.Add('Checkbox');
  FCmbAddKind.Items.Add('Button');
  FCmbAddKind.Items.Add('Status');
  FCmbAddKind.Items.Add('List');
  FCmbAddKind.Items.Add('Dropdown');
  FCmbAddKind.Items.Add('Radio group');
  FCmbAddKind.ItemIndex := 0;
  X := X + FCmbAddKind.Width + 6;

  FBtnAddCtrl := MakeToolButton(FTool, 'Add', BtnAddClick, X);
  FBtnDeleteCtrl := MakeToolButton(FTool, 'Delete', BtnDeleteClick, X);

  FCmbLocale := TComboBox.Create(FTool);
  FCmbLocale.Parent := FTool;
  FCmbLocale.Align := TAlignLayout.Right;
  FCmbLocale.Width := 72;
  FCmbLocale.Margins.Rect := RectF(0, 4, 0, 4);
  FLblLocale := TLabel.Create(FTool);
  FLblLocale.Parent := FTool;
  FLblLocale.Align := TAlignLayout.Right;
  FLblLocale.Width := 64;
  FLblLocale.Margins.Right := 6;
  FLblLocale.Text := 'Language';
  FLblLocale.TextSettings.VertAlign := TTextAlign.Center;
  FLocaleApplying := True;
  try
    for Loc in AvailableLocales do
      FCmbLocale.Items.Add(Loc);
    LocaleIndex := FCmbLocale.Items.IndexOf(CurrentLocale);
    if LocaleIndex < 0 then
      LocaleIndex := 0;
    FCmbLocale.ItemIndex := LocaleIndex;
  finally
    FLocaleApplying := False;
  end;
  FCmbLocale.OnChange := CmbLocaleChange;

  FBottom := TLayout.Create(FRoot);
  FBottom.Parent := FRoot;
  FBottom.Align := TAlignLayout.Bottom;
  FBottom.Height := 120;

  FStatus := TLabel.Create(FBottom);
  FStatus.Parent := FBottom;
  FStatus.Align := TAlignLayout.Top;
  FStatus.Height := 22;
  FStatus.Text := 'Ready';

  FLog := TMemo.Create(FBottom);
  FLog.Parent := FBottom;
  FLog.Align := TAlignLayout.Client;
  FLog.ReadOnly := True;
  FLog.StyledSettings := [];
  FLog.TextSettings.Font.Family := 'Consolas';
  FLog.TextSettings.Font.Size := 11;

  FSplit := TLayout.Create(FRoot);
  FSplit.Parent := FRoot;
  FSplit.Align := TAlignLayout.Client;
  FSplit.Margins.Top := 4;
  FSplit.Margins.Bottom := 4;

  FLeft := TLayout.Create(FSplit);
  FLeft.Parent := FSplit;
  FLeft.Align := TAlignLayout.Left;
  FLeft.Width := 520;

  FMemo := TMemo.Create(FLeft);
  FMemo.Parent := FLeft;
  FMemo.Align := TAlignLayout.Client;
  FMemo.StyledSettings := [];
  FMemo.TextSettings.Font.Family := 'Consolas';
  FMemo.TextSettings.Font.Size := 12;
  FMemo.TextSettings.FontColor := TAlphaColor($FF1A1A1A);
  FMemo.WordWrap := False;
  FMemo.OnChange := MemoChange;
  FMemo.OnEnter := MemoEnter;

  FRight := TLayout.Create(FSplit);
  FRight.Parent := FSplit;
  FRight.Align := TAlignLayout.Client;
  FRight.Margins.Left := 6;

  FPropPanel := TVertScrollBox.Create(FRight);
  FPropPanel.Parent := FRight;
  FPropPanel.Align := TAlignLayout.Right;
  FPropPanel.Width := 300;
  FPropPanel.Margins.Left := 6;

  FPropHeader := TLabel.Create(FPropPanel);
  FPropHeader.Parent := FPropPanel;
  FPropHeader.Align := TAlignLayout.Top;
  FPropHeader.Height := 24;
  FPropHeader.Margins.Bottom := 6;
  FPropHeader.TextSettings.Font.Style := [TFontStyle.fsBold];
  FPropHeader.Text := 'No control selected';

  Row := AddPropRow('Id');
  FPropEditId := TEdit.Create(Row);
  FPropEditId.Parent := Row;
  FPropEditId.Align := TAlignLayout.Client;
  FPropEditId.OnChange := EditIdChange;

  FPropRowCol := AddPropRow('Col');
  FPropEditCol := TEdit.Create(FPropRowCol);
  FPropEditCol.Parent := FPropRowCol;
  FPropEditCol.Align := TAlignLayout.Client;
  FPropEditCol.OnChange := EditColChange;

  FPropRowRow := AddPropRow('Row');
  FPropEditRow := TEdit.Create(FPropRowRow);
  FPropEditRow.Parent := FPropRowRow;
  FPropEditRow.Align := TAlignLayout.Client;
  FPropEditRow.OnChange := EditRowChange;

  FPropRowW := AddPropRow('Width');
  FPropEditW := TEdit.Create(FPropRowW);
  FPropEditW.Parent := FPropRowW;
  FPropEditW.Align := TAlignLayout.Client;
  FPropEditW.OnChange := EditWChange;

  FPropRowH := AddPropRow('Height');
  FPropEditH := TEdit.Create(FPropRowH);
  FPropEditH.Parent := FPropRowH;
  FPropEditH.Align := TAlignLayout.Client;
  FPropEditH.OnChange := EditHChange;

  FPropRowText := AddPropRow('Text');
  FPropEditText := TEdit.Create(FPropRowText);
  FPropEditText.Parent := FPropRowText;
  FPropEditText.Align := TAlignLayout.Client;
  FPropEditText.OnChange := EditTextChange;

  FPropRowValue := AddPropRow('Value');
  FPropEditValue := TEdit.Create(FPropRowValue);
  FPropEditValue.Parent := FPropRowValue;
  FPropEditValue.Align := TAlignLayout.Client;
  FPropEditValue.OnChange := EditValueChange;

  FPropRowGroup := AddPropRow('Group');
  FPropEditGroup := TEdit.Create(FPropRowGroup);
  FPropEditGroup.Parent := FPropRowGroup;
  FPropEditGroup.Align := TAlignLayout.Client;
  FPropEditGroup.OnChange := EditGroupChange;

  FPropRowChecked := TLayout.Create(FPropPanel);
  FPropRowChecked.Parent := FPropPanel;
  FPropRowChecked.Align := TAlignLayout.Top;
  FPropRowChecked.Height := 24;
  FPropChkChecked := TCheckBox.Create(FPropRowChecked);
  FPropChkChecked.Parent := FPropRowChecked;
  FPropChkChecked.Align := TAlignLayout.Client;
  FPropChkChecked.Text := 'Checked';
  FPropChkChecked.OnChange := ChkCheckedChange;

  FPropRowDefault := TLayout.Create(FPropPanel);
  FPropRowDefault.Parent := FPropPanel;
  FPropRowDefault.Align := TAlignLayout.Top;
  FPropRowDefault.Height := 24;
  FPropChkDefault := TCheckBox.Create(FPropRowDefault);
  FPropChkDefault.Parent := FPropRowDefault;
  FPropChkDefault.Align := TAlignLayout.Client;
  FPropChkDefault.Text := 'Default button';
  FPropChkDefault.OnChange := ChkDefaultChange;

  FPropRowCancel := TLayout.Create(FPropPanel);
  FPropRowCancel.Parent := FPropPanel;
  FPropRowCancel.Align := TAlignLayout.Top;
  FPropRowCancel.Height := 24;
  FPropChkCancel := TCheckBox.Create(FPropRowCancel);
  FPropChkCancel.Parent := FPropRowCancel;
  FPropChkCancel.Align := TAlignLayout.Client;
  FPropChkCancel.Text := 'Cancel button';
  FPropChkCancel.OnChange := ChkCancelChange;

  FPropRowPassword := TLayout.Create(FPropPanel);
  FPropRowPassword.Parent := FPropPanel;
  FPropRowPassword.Align := TAlignLayout.Top;
  FPropRowPassword.Height := 24;
  FPropChkPassword := TCheckBox.Create(FPropRowPassword);
  FPropChkPassword.Parent := FPropRowPassword;
  FPropChkPassword.Align := TAlignLayout.Client;
  FPropChkPassword.Text := 'Password';
  FPropChkPassword.OnChange := ChkPasswordChange;

  FPropRowSelIndex := AddPropRow('Selected #');
  FPropEditSelIndex := TEdit.Create(FPropRowSelIndex);
  FPropEditSelIndex.Parent := FPropRowSelIndex;
  FPropEditSelIndex.Align := TAlignLayout.Client;
  FPropEditSelIndex.OnChange := EditSelIndexChange;

  FPropRowItems := TLayout.Create(FPropPanel);
  FPropRowItems.Parent := FPropPanel;
  FPropRowItems.Align := TAlignLayout.Top;
  FPropRowItems.Height := 140;
  FPropRowItems.Margins.Bottom := 4;
  FPropMemoItems := TMemo.Create(FPropRowItems);
  FPropMemoItems.Parent := FPropRowItems;
  FPropMemoItems.Align := TAlignLayout.Client;
  FPropMemoItems.StyledSettings := [];
  FPropMemoItems.TextSettings.Font.Size := 11;
  FPropMemoItems.OnChange := MemoItemsChange;

  FPropRowFgSrc := AddPropRow('Fg source id');
  FPropEditFgSrc := TEdit.Create(FPropRowFgSrc);
  FPropEditFgSrc.Parent := FPropRowFgSrc;
  FPropEditFgSrc.Align := TAlignLayout.Client;
  FPropEditFgSrc.OnChange := EditFgSourceChange;

  FPropRowBgSrc := AddPropRow('Bg source id');
  FPropEditBgSrc := TEdit.Create(FPropRowBgSrc);
  FPropEditBgSrc.Parent := FPropRowBgSrc;
  FPropEditBgSrc.Align := TAlignLayout.Client;
  FPropEditBgSrc.OnChange := EditBgSourceChange;

  FPropRowPanelState := AddPropRow('Panel state');
  FPropCmbPanelState := TComboBox.Create(FPropRowPanelState);
  FPropCmbPanelState.Parent := FPropRowPanelState;
  FPropCmbPanelState.Align := TAlignLayout.Client;
  FPropCmbPanelState.Items.Add('none');
  FPropCmbPanelState.Items.Add('normal');
  FPropCmbPanelState.Items.Add('selected');
  FPropCmbPanelState.Items.Add('current');
  FPropCmbPanelState.OnChange := CmbPanelStateChange;

  FPaint := TPaintBox.Create(FRight);
  FPaint.Parent := FRight;
  FPaint.Align := TAlignLayout.Client;
  FPaint.OnPaint := PaintPaint;
  FPaint.OnMouseDown := PaintMouseDown;
  FPaint.OnMouseEnter := PaintMouseEnter;
  FPaint.CanFocus := True;
  FPaint.TabStop := True;
end;

procedure TDialogDesignerForm.WireEvents;
begin
  OnDestroy := FormDestroy;
  OnResize := FormResize;
  OnPaint := FormPaint;
  OnKeyDown := FormKeyDown;
end;

procedure TDialogDesignerForm.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FDialog);
  FreeAndNil(FRenderer);
  FTheme := nil;
end;

procedure TDialogDesignerForm.SetDirty(AValue: Boolean);
begin
  if FDirty = AValue then
    Exit;
  FDirty := AValue;
  UpdateCaption;
end;

procedure TDialogDesignerForm.UpdateCaption;
var
  Name, Mark: string;
begin
  if FFilePath <> '' then
    Name := ExtractFileName(FFilePath)
  else
    Name := '(untitled)';
  if FDirty then
    Mark := ' *'
  else
    Mark := '';
  if Assigned(FRenderer) then
    Caption := Format('%s — %s%s  [%dx%d zoom %.0f%%]',
      [cAppTitle, Name, Mark, FRenderer.Cols, FRenderer.Rows, FRenderer.Zoom * 100])
  else
    Caption := Format('%s — %s%s', [cAppTitle, Name, Mark]);
end;

procedure TDialogDesignerForm.SetStatus(const AText: string);
begin
  if Assigned(FStatus) then
    FStatus.Text := AText;
end;

procedure TDialogDesignerForm.LogLine(const AText: string);
begin
  if Assigned(FLog) then
    FLog.Lines.Add(AText);
end;

procedure TDialogDesignerForm.SyncPreviewSize;
begin
  if not Assigned(FRenderer) or not Assigned(FPaint) then
    Exit;
  if (FPaint.Width < 8) or (FPaint.Height < 8) then
    Exit;
  FRenderer.Resize(FPaint.Width, FPaint.Height, Canvas);
  UpdateCaption;
  FPaint.Repaint;
end;

procedure TDialogDesignerForm.Recompose;
begin
  if Assigned(FRenderer) then
  begin
    FRenderer.Recompose;
    UpdateCaption;
  end;
  if Assigned(FPaint) then
    FPaint.Repaint;
end;

procedure TDialogDesignerForm.ComposeScene(const AGrid: TTerminalGrid;
  ACols, ARows: Integer);
begin
  if Assigned(FTheme) then
    FTheme.DrawDesktop(AGrid, TRectI.Make(0, 0, ACols - 1, ARows - 1))
  else
    FillGridRect(AGrid, 0, 0, ACols - 1, ARows - 1, ' ',
      TAlphaColor($FFAAAAAA), TAlphaColor($FF000000));
  if Assigned(FDialog) and FDialog.Visible then
    FDialog.Draw(AGrid, ACols, ARows);
  if not FTestMode then
    DrawSelectionMarks(AGrid, ACols, ARows);
end;

function TDialogDesignerForm.PointToCell(X, Y: Single; out ACol, ARow: Integer): Boolean;
begin
  ACol := 0;
  ARow := 0;
  Result := Assigned(FRenderer) and (FRenderer.CellWidth > 0) and
    (FRenderer.CellHeight > 0);
  if not Result then
    Exit;
  ACol := Trunc(X / FRenderer.CellWidth);
  ARow := Trunc(Y / FRenderer.CellHeight);
end;

function TDialogDesignerForm.ProjectDialogsDir: string;
var
  Dir, Src: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  while Dir <> '' do
  begin
    if TDirectory.Exists(System.IOUtils.TPath.Combine(Dir, 'dialogs')) and
       TFile.Exists(System.IOUtils.TPath.Combine(Dir, 'MTN2.dpr')) then
      Exit(System.IOUtils.TPath.Combine(Dir, 'dialogs'));
    // bin\DialogDesigner.exe sits next to src\, not inside it.
    Src := System.IOUtils.TPath.Combine(Dir, 'src');
    if TDirectory.Exists(System.IOUtils.TPath.Combine(Src, 'dialogs')) and
       TFile.Exists(System.IOUtils.TPath.Combine(Src, 'MTN2.dpr')) then
      Exit(System.IOUtils.TPath.Combine(Src, 'dialogs'));
    if SameText(ExpandFileName(System.IOUtils.TPath.Combine(Dir, '..')),
      ExpandFileName(Dir)) then
      Break;
    Dir := ExpandFileName(System.IOUtils.TPath.Combine(Dir, '..'));
  end;
  Result := '';
end;

function TDialogDesignerForm.TryLoadProjectDialogFile(const AFileName: string;
  out AJson, APath: string): Boolean;
var
  Dir: string;
begin
  Result := False;
  AJson := '';
  APath := '';
  Dir := ProjectDialogsDir;
  if Dir = '' then
    Exit;
  APath := System.IOUtils.TPath.Combine(Dir, AFileName);
  if not TFile.Exists(APath) then
    Exit;
  AJson := TFile.ReadAllText(APath, TEncoding.UTF8);
  Result := Trim(AJson) <> '';
end;

function TDialogDesignerForm.DefaultSampleJson(out APath: string): string;
var
  Json: string;
begin
  APath := '';
  if TryLoadProjectDialogFile('search.json', Json, APath) then
    Exit(PrettyJson(Json));
  Result := PrettyJson(DeclarationToJson(
    BuildSearchDialog('*.*', '', False, False, False, True, True)));
end;

function TDialogDesignerForm.DialogResourceName: string;
var
  Name: string;
begin
  Result := '';
  if FFilePath = '' then
    Exit;
  Name := UpperCase(System.IOUtils.TPath.GetFileNameWithoutExtension(FFilePath));
  if Name = '' then
    Exit;
  if Name.StartsWith('DIALOG_') then
    Result := Name
  else
    Result := 'DIALOG_' + Name;
end;

procedure TDialogDesignerForm.OpenTranslatedPreview;
var
  Shown: TDialogDeclaration;
  ResourceName: string;
begin
  Shown := FLayout;
  ResourceName := DialogResourceName;
  if (ResourceName <> '') and not SameText(CurrentLocale, 'en') then
    TranslateDialogDeclaration(ResourceName, Shown);
  FDialog.Open(Shown, DialogCommand);
end;

procedure TDialogDesignerForm.CmbLocaleChange(Sender: TObject);
var
  Loc: string;
begin
  if FLocaleApplying or (FCmbLocale.ItemIndex < 0) then
    Exit;
  Loc := FCmbLocale.Items[FCmbLocale.ItemIndex];
  if SameText(Loc, CurrentLocale) then
    Exit;
  SetLocale(Loc);
  if not TryParseDialogJson(FMemo.Text, FLayout) then
  begin
    SetStatus('JSON parse error — language not applied');
    Exit;
  end;
  OpenTranslatedPreview;
  Recompose;
  SetStatus('Language: ' + CurrentLocale);
end;

function TDialogDesignerForm.PrettyJson(const AJson: string): string;
var
  V: TJSONValue;
begin
  Result := AJson;
  V := TJSONObject.ParseJSONValue(AJson);
  if V = nil then
    Exit;
  try
    Result := V.Format(2);
  finally
    V.Free;
  end;
end;

procedure TDialogDesignerForm.LoadJsonText(const AText, APath: string;
  AMarkClean: Boolean);
begin
  FApplying := True;
  try
    FMemo.Text := AText;
    FFilePath := APath;
    if AMarkClean then
      SetDirty(False)
    else
      SetDirty(True);
  finally
    FApplying := False;
  end;
  UpdateCaption;
end;

procedure TDialogDesignerForm.ApplyPreview;
var
  Decl: TDialogDeclaration;
  Json: string;
begin
  Json := FMemo.Text;
  if not TryParseDialogJson(Json, Decl) then
  begin
    SetStatus('JSON parse error — preview not updated');
    Exit;
  end;
  FLayout := Decl;
  OpenTranslatedPreview;
  SetStatus(Format('Preview OK — version %s, %d×%d, %d controls',
    [Decl.Version, Decl.Width, Decl.Height, Length(Decl.Controls)]));
  if FSelectedIndex > High(Decl.Controls) then
    FSelectedIndex := -1;
  RebuildPropertyPanel;
  Recompose;
  FPreviewFocus := True;
  if Assigned(FPaint) then
    FPaint.SetFocus;
end;

function TDialogDesignerForm.ConfirmDiscard: Boolean;
var
  R: Integer;
begin
  Result := True;
  if not FDirty then
    Exit;
  R := TDialogServiceSync.MessageDialog('Discard unsaved changes?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbCancel, 0);
  if R = mrYes then
    Exit(True);
  if R = mrNo then
  begin
    BtnSaveClick(nil);
    Exit(not FDirty);
  end;
  Result := False;
end;

procedure TDialogDesignerForm.DialogCommand(const AControlId, AValuesJson: string);
begin
  LogLine(Format('command id="%s" values=%s', [AControlId, AValuesJson]));
  SetStatus(Format('Command: %s', [AControlId]));
  // Keep dialog open so the designer can keep interacting.
  Recompose;
end;

procedure TDialogDesignerForm.DialogChanged(Sender: TObject);
begin
  Recompose;
end;

procedure TDialogDesignerForm.DrawSelectionMarks(const AGrid: TTerminalGrid;
  ACols, ARows: Integer);
const
  // Reverse-video overlay: recolors whatever glyph Draw already put in each
  // cell instead of overwriting it with box-drawing characters, so a 1-row
  // control (button/checkbox/input — most controls) keeps its text readable
  // while selected.
  cSelFg = TAlphaColor($FF1A1A1A);
  cSelBg = TAlphaColor($FFFFA500);
var
  R: TRectI;
  X, Y: Integer;
  Ch: Char;
begin
  if (FSelectedIndex < 0) or not Assigned(FDialog) or not FDialog.Visible then
    Exit;
  if FSelectedIndex >= FDialog.ControlCount then
    Exit;
  R := FDialog.ControlBoundsAt(FSelectedIndex);
  if (R.Right < R.Left) or (R.Bottom < R.Top) then
    Exit;
  for Y := Max(R.Top, 0) to Min(R.Bottom, ARows - 1) do
    for X := Max(R.Left, 0) to Min(R.Right, ACols - 1) do
    begin
      Ch := AGrid[Y][X].CharValue;
      if Ch = #0 then
        Ch := ' ';
      DrawGridChar(AGrid, X, Y, Ch, cSelFg, cSelBg);
    end;
end;

procedure TDialogDesignerForm.SelectControl(AIndex: Integer);
begin
  FSelectedIndex := AIndex;
  RebuildPropertyPanel;
  Recompose;
end;

procedure TDialogDesignerForm.RebuildPropertyPanel;
var
  C: TDialogControl;
  HasCtrl: Boolean;
  I: Integer;
  ItemsText: string;
begin
  HasCtrl := (FSelectedIndex >= 0) and (FSelectedIndex <= High(FLayout.Controls));
  FPropApplying := True;
  try
    if not HasCtrl then
    begin
      FPropHeader.Text := 'No control selected — click one in the preview';
      FPropEditId.Text := '';
      FPropRowCol.Visible := False;
      FPropRowRow.Visible := False;
      FPropRowW.Visible := False;
      FPropRowH.Visible := False;
      FPropRowText.Visible := False;
      FPropRowValue.Visible := False;
      FPropRowGroup.Visible := False;
      FPropRowChecked.Visible := False;
      FPropRowDefault.Visible := False;
      FPropRowCancel.Visible := False;
      FPropRowPassword.Visible := False;
      FPropRowItems.Visible := False;
      FPropRowSelIndex.Visible := False;
      FPropRowFgSrc.Visible := False;
      FPropRowBgSrc.Visible := False;
      FPropRowPanelState.Visible := False;
      Exit;
    end;
    C := FLayout.Controls[FSelectedIndex];
    FPropHeader.Text := Format('#%d — %s', [FSelectedIndex, DialogControlKindName(C.Kind)]);
    FPropEditId.Text := C.Id;

    FPropRowCol.Visible := True;
    FPropRowRow.Visible := True;
    FPropRowW.Visible := True;
    FPropRowH.Visible := True;
    FPropEditCol.Text := IntToStr(C.Col);
    FPropEditRow.Text := IntToStr(C.Row);
    FPropEditW.Text := IntToStr(C.BoxW);
    FPropEditH.Text := IntToStr(C.BoxH);

    FPropRowText.Visible := C.Kind in [dckLabel, dckButton, dckCheckbox, dckRadio,
      dckStatus, dckColorSample, dckRadioGroup];
    if FPropRowText.Visible then
      FPropEditText.Text := C.Text;

    FPropRowValue.Visible := C.Kind = dckInput;
    if FPropRowValue.Visible then
      FPropEditValue.Text := C.Edit.Text;

    FPropRowGroup.Visible := C.Kind = dckRadio;
    if FPropRowGroup.Visible then
      FPropEditGroup.Text := C.Group;

    FPropRowChecked.Visible := C.Kind in [dckCheckbox, dckRadio];
    if FPropRowChecked.Visible then
      FPropChkChecked.IsChecked := C.Checked;

    FPropRowDefault.Visible := C.Kind = dckButton;
    if FPropRowDefault.Visible then
      FPropChkDefault.IsChecked := C.IsDefault;

    FPropRowCancel.Visible := C.Kind = dckButton;
    if FPropRowCancel.Visible then
      FPropChkCancel.IsChecked := C.IsCancel;

    FPropRowPassword.Visible := C.Kind = dckInput;
    if FPropRowPassword.Visible then
      FPropChkPassword.IsChecked := C.Password;

    FPropRowItems.Visible := C.Kind in [dckList, dckDropDown, dckRadioGroup];
    if FPropRowItems.Visible then
    begin
      ItemsText := '';
      for I := 0 to High(C.Items) do
      begin
        if I > 0 then
          ItemsText := ItemsText + sLineBreak;
        ItemsText := ItemsText + C.Items[I];
      end;
      FPropMemoItems.Text := ItemsText;
    end;

    FPropRowSelIndex.Visible := C.Kind in [dckList, dckDropDown, dckRadioGroup];
    if FPropRowSelIndex.Visible then
      FPropEditSelIndex.Text := IntToStr(C.SelectedIndex);

    FPropRowFgSrc.Visible := C.Kind = dckColorSample;
    if FPropRowFgSrc.Visible then
      FPropEditFgSrc.Text := C.FgSourceId;

    FPropRowBgSrc.Visible := C.Kind = dckColorSample;
    if FPropRowBgSrc.Visible then
      FPropEditBgSrc.Text := C.BgSourceId;

    FPropRowPanelState.Visible := C.Kind = dckColorSample;
    if FPropRowPanelState.Visible then
      case C.PanelState of
        cspsNormal: FPropCmbPanelState.ItemIndex := 1;
        cspsSelected: FPropCmbPanelState.ItemIndex := 2;
        cspsCurrent: FPropCmbPanelState.ItemIndex := 3;
      else
        FPropCmbPanelState.ItemIndex := 0;
      end;
  finally
    FPropApplying := False;
  end;
end;

procedure TDialogDesignerForm.MutateSelectedControl(const AMutate: TControlMutator);
var
  Decl: TDialogDeclaration;
begin
  if FSelectedIndex < 0 then
    Exit;
  if not TryParseDialogJson(FMemo.Text, Decl) then
  begin
    SetStatus('JSON parse error — cannot edit');
    Exit;
  end;
  if FSelectedIndex > High(Decl.Controls) then
  begin
    FSelectedIndex := -1;
    Exit;
  end;
  AMutate(Decl.Controls[FSelectedIndex]);
  FApplying := True;
  try
    FMemo.Text := PrettyJson(DeclarationToJson(Decl));
  finally
    FApplying := False;
  end;
  SetDirty(True);
  FLayout := Decl;
  // Reopen directly (not the full ApplyPreview) so the edit field the user
  // is typing in keeps focus instead of losing it to the preview pane.
  OpenTranslatedPreview;
  Recompose;
end;

procedure TDialogDesignerForm.EditIdChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.Id := FPropEditId.Text; end);
end;

procedure TDialogDesignerForm.EditTextChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.Text := FPropEditText.Text; end);
end;

procedure TDialogDesignerForm.EditValueChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl)
    begin
      InputLineSetText(C.Edit, FPropEditValue.Text);
    end);
end;

procedure TDialogDesignerForm.EditGroupChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.Group := FPropEditGroup.Text; end);
end;

procedure TDialogDesignerForm.EditSelIndexChange(Sender: TObject);
var
  V: Integer;
begin
  if FPropApplying then Exit;
  if not TryStrToInt(FPropEditSelIndex.Text, V) then
    Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.SelectedIndex := V; end);
end;

procedure TDialogDesignerForm.EditFgSourceChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.FgSourceId := FPropEditFgSrc.Text; end);
end;

procedure TDialogDesignerForm.EditBgSourceChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.BgSourceId := FPropEditBgSrc.Text; end);
end;

procedure TDialogDesignerForm.EditColChange(Sender: TObject);
var
  V: Integer;
begin
  if FPropApplying then Exit;
  if not TryStrToInt(FPropEditCol.Text, V) then
    Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.Col := V; end);
end;

procedure TDialogDesignerForm.EditRowChange(Sender: TObject);
var
  V: Integer;
begin
  if FPropApplying then Exit;
  if not TryStrToInt(FPropEditRow.Text, V) then
    Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.Row := V; end);
end;

procedure TDialogDesignerForm.EditWChange(Sender: TObject);
var
  V: Integer;
begin
  if FPropApplying then Exit;
  if not TryStrToInt(FPropEditW.Text, V) then
    Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.BoxW := V; end);
end;

procedure TDialogDesignerForm.EditHChange(Sender: TObject);
var
  V: Integer;
begin
  if FPropApplying then Exit;
  if not TryStrToInt(FPropEditH.Text, V) then
    Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.BoxH := V; end);
end;

procedure TDialogDesignerForm.ChkCheckedChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.Checked := FPropChkChecked.IsChecked; end);
end;

procedure TDialogDesignerForm.ChkDefaultChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.IsDefault := FPropChkDefault.IsChecked; end);
end;

procedure TDialogDesignerForm.ChkCancelChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.IsCancel := FPropChkCancel.IsChecked; end);
end;

procedure TDialogDesignerForm.ChkPasswordChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.Password := FPropChkPassword.IsChecked; end);
end;

procedure TDialogDesignerForm.MemoItemsChange(Sender: TObject);
begin
  if FPropApplying then Exit;
  MutateSelectedControl(
    procedure(var C: TDialogControl)
    var
      Lines: TArray<string>;
    begin
      Lines := FPropMemoItems.Text.Replace(#13#10, #10).Split([#10]);
      C.Items := Lines;
      if C.SelectedIndex > High(C.Items) then
        C.SelectedIndex := High(C.Items);
      if C.SelectedIndex < 0 then
        C.SelectedIndex := 0;
    end);
end;

procedure TDialogDesignerForm.CmbPanelStateChange(Sender: TObject);
var
  St: TColorSamplePanelState;
begin
  if FPropApplying then Exit;
  case FPropCmbPanelState.ItemIndex of
    1: St := cspsNormal;
    2: St := cspsSelected;
    3: St := cspsCurrent;
  else
    St := cspsNone;
  end;
  MutateSelectedControl(
    procedure(var C: TDialogControl) begin C.PanelState := St; end);
end;

procedure TDialogDesignerForm.ChkTestModeChange(Sender: TObject);
begin
  FTestMode := FChkTestMode.IsChecked;
  if FTestMode then
    FSelectedIndex := -1;
  RebuildPropertyPanel;
  Recompose;
end;

procedure TDialogDesignerForm.BtnAddClick(Sender: TObject);
var
  Decl: TDialogDeclaration;
  NewCtrl: TDialogControl;
  Id: string;
  N: Integer;
begin
  if not TryParseDialogJson(FMemo.Text, Decl) then
  begin
    SetStatus('JSON parse error — cannot add control');
    Exit;
  end;
  N := Length(Decl.Controls);
  Id := Format('ctrl%d', [N + 1]);
  case FCmbAddKind.ItemIndex of
    0: NewCtrl := MakeLabel('Label', Id);
    1: NewCtrl := MakeInput(Id, '');
    2: NewCtrl := MakeCheckbox(Id, 'Checkbox', False);
    3: NewCtrl := MakeButton(Id, 'Button');
    4: NewCtrl := MakeStatus(Id, 'Status');
    5: NewCtrl := MakeList(Id, TArray<string>.Create('Item 1', 'Item 2'));
    6: NewCtrl := MakeDropDown(Id, TArray<string>.Create('Item 1', 'Item 2'));
    7: NewCtrl := MakeRadioGroup(Id, 'Options', TArray<string>.Create('Option 1', 'Option 2'));
  else
    Exit;
  end;
  if IsDialogProtocolV2(Decl.Version) then
    NewCtrl := WithControlBox(NewCtrl, 0, N, 0, 0);
  SetLength(Decl.Controls, N + 1);
  Decl.Controls[N] := NewCtrl;
  FApplying := True;
  try
    FMemo.Text := PrettyJson(DeclarationToJson(Decl));
  finally
    FApplying := False;
  end;
  SetDirty(True);
  FSelectedIndex := N;
  ApplyPreview;
  LogLine('Added control: ' + Id);
end;

procedure TDialogDesignerForm.BtnDeleteClick(Sender: TObject);
var
  Decl: TDialogDeclaration;
  I: Integer;
begin
  if FSelectedIndex < 0 then
  begin
    SetStatus('No control selected to delete');
    Exit;
  end;
  if not TryParseDialogJson(FMemo.Text, Decl) then
  begin
    SetStatus('JSON parse error — cannot delete control');
    Exit;
  end;
  if FSelectedIndex > High(Decl.Controls) then
  begin
    FSelectedIndex := -1;
    Exit;
  end;
  for I := FSelectedIndex to High(Decl.Controls) - 1 do
    Decl.Controls[I] := Decl.Controls[I + 1];
  SetLength(Decl.Controls, Length(Decl.Controls) - 1);
  FApplying := True;
  try
    FMemo.Text := PrettyJson(DeclarationToJson(Decl));
  finally
    FApplying := False;
  end;
  SetDirty(True);
  FSelectedIndex := -1;
  ApplyPreview;
  LogLine('Deleted control');
end;

procedure TDialogDesignerForm.FormResize(Sender: TObject);
begin
  if Assigned(FLeft) and (ClientWidth > 200) then
    FLeft.Width := Min(560, Max(320, ClientWidth * 0.42));
  SyncPreviewSize;
end;

procedure TDialogDesignerForm.FormPaint(Sender: TObject; Canvas: TCanvas;
  const ARect: TRectF);
begin
  // Preview paints on FPaint; keep form paint for DPI scale tracking.
  if Assigned(FRenderer) and (Canvas.Scale > 0) and (Canvas.Scale <> FLastScale) then
  begin
    FLastScale := Canvas.Scale;
    FRenderer.SetSceneScale(Canvas.Scale, FPaint.Width, FPaint.Height, Canvas);
    SyncPreviewSize;
  end;
end;

procedure TDialogDesignerForm.PaintPaint(Sender: TObject; Canvas: TCanvas);
begin
  if not Assigned(FRenderer) then
    Exit;
  if (Canvas.Scale > 0) and (Canvas.Scale <> FLastScale) then
  begin
    FLastScale := Canvas.Scale;
    FRenderer.SetSceneScale(Canvas.Scale, FPaint.Width, FPaint.Height, Canvas);
  end;
  FRenderer.Resize(FPaint.Width, FPaint.Height, Canvas);
  FRenderer.Draw(Canvas, RectF(0, 0, FPaint.Width, FPaint.Height));
end;

procedure TDialogDesignerForm.PaintMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Col, Row: Integer;
begin
  FPreviewFocus := True;
  FPaint.SetFocus;
  if (Button = TMouseButton.mbLeft) and PointToCell(X, Y, Col, Row) then
  begin
    if not Assigned(FDialog) or not FDialog.Visible then
      Exit;
    if FTestMode then
    begin
      FDialog.HandleClick(Col, Row);
      Recompose;
    end
    else
      SelectControl(FDialog.ControlIndexAt(Col, Row));
  end;
end;

procedure TDialogDesignerForm.PaintMouseEnter(Sender: TObject);
begin
  // Keep memo as text editor; click preview to focus interaction.
end;

procedure TDialogDesignerForm.MemoEnter(Sender: TObject);
begin
  FPreviewFocus := False;
end;

procedure TDialogDesignerForm.MemoChange(Sender: TObject);
begin
  if FApplying then
    Exit;
  SetDirty(True);
end;

procedure TDialogDesignerForm.FormKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: Char; Shift: TShiftState);
begin
  // Handled in KeyDown override for Tab interception.
end;

procedure TDialogDesignerForm.KeyDown(var Key: Word; var KeyChar: System.WideChar;
  Shift: TShiftState);
var
  K: Word;
  C: Char;
begin
  if (Key = vkF5) and not (ssCtrl in Shift) and not (ssAlt in Shift) then
  begin
    ApplyPreview;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  if FTestMode and FPreviewFocus and Assigned(FDialog) and FDialog.Visible and
     not (ssCtrl in Shift) then
  begin
    K := Key;
    C := Char(KeyChar);
    if FDialog.HandleInput(K, Shift, C) then
    begin
      Key := 0;
      KeyChar := #0;
      Recompose;
      Exit;
    end;
  end;

  inherited;
end;

procedure TDialogDesignerForm.BtnNewClick(Sender: TObject);
var
  Path: string;
begin
  if not ConfirmDiscard then
    Exit;
  LoadJsonText(DefaultSampleJson(Path), Path, True);
  ApplyPreview;
  LogLine('New sample dialog');
end;

procedure TDialogDesignerForm.BtnOpenClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  Text, Dir: string;
begin
  if not ConfirmDiscard then
    Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Dialog JSON (*.json)|*.json|All files (*.*)|*.*';
    Dlg.DefaultExt := 'json';
    Dir := ProjectDialogsDir;
    if Dir <> '' then
      Dlg.InitialDir := Dir;
    if not Dlg.Execute then
      Exit;
    Text := TFile.ReadAllText(Dlg.FileName, TEncoding.UTF8);
    LoadJsonText(PrettyJson(Text), Dlg.FileName, True);
    ApplyPreview;
    LogLine('Opened ' + Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TDialogDesignerForm.BtnSaveClick(Sender: TObject);
begin
  if FFilePath = '' then
  begin
    BtnSaveAsClick(Sender);
    Exit;
  end;
  TFile.WriteAllText(FFilePath, FMemo.Text, TEncoding.UTF8);
  SetDirty(False);
  SetStatus('Saved ' + FFilePath);
  LogLine('Saved ' + FFilePath);
end;

procedure TDialogDesignerForm.BtnSaveAsClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Dir: string;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Dialog JSON (*.json)|*.json|All files (*.*)|*.*';
    Dlg.DefaultExt := 'json';
    if FFilePath <> '' then
      Dlg.FileName := FFilePath
    else
    begin
      Dir := ProjectDialogsDir;
      if Dir <> '' then
        Dlg.InitialDir := Dir;
    end;
    if not Dlg.Execute then
      Exit;
    FFilePath := Dlg.FileName;
    TFile.WriteAllText(FFilePath, FMemo.Text, TEncoding.UTF8);
    SetDirty(False);
    SetStatus('Saved ' + FFilePath);
    LogLine('Saved ' + FFilePath);
    UpdateCaption;
  finally
    Dlg.Free;
  end;
end;

procedure TDialogDesignerForm.BtnApplyClick(Sender: TObject);
begin
  ApplyPreview;
end;

procedure TDialogDesignerForm.BtnPrettyClick(Sender: TObject);
var
  Decl: TDialogDeclaration;
  Pretty: string;
begin
  if not TryParseDialogJson(FMemo.Text, Decl) then
  begin
    SetStatus('Cannot pretty-print — JSON parse error');
    Exit;
  end;
  Pretty := PrettyJson(DeclarationToJson(Decl));
  FApplying := True;
  try
    FMemo.Text := Pretty;
  finally
    FApplying := False;
  end;
  SetDirty(True);
  SetStatus('Pretty-printed via parse → DeclarationToJson');
end;

procedure TDialogDesignerForm.MiExitClick(Sender: TObject);
begin
  Close;
end;

procedure TDialogDesignerForm.MiTemplateClick(Sender: TObject);
var
  Decl: TDialogDeclaration;
  Tag: Integer;
  FileName, Json, Path: string;
begin
  if not (Sender is TMenuItem) then
    Exit;
  if not ConfirmDiscard then
    Exit;
  Tag := TMenuItem(Sender).Tag;
  case Tag of
    1: FileName := 'confirm.json';
    2: FileName := 'input.json';
    3: FileName := 'search.json';
    4: FileName := 'copymove.json';
    5: FileName := 'help.json';
    6: FileName := 'asksave.json';
    7: FileName := 'gotoline.json';
    8: FileName := 'encoding.json';
    9: FileName := 'replace.json';
    10: FileName := 'delete.json';
  else
    Exit;
  end;
  if TryLoadProjectDialogFile(FileName, Json, Path) then
  begin
    LoadJsonText(PrettyJson(Json), Path, True);
    ApplyPreview;
    LogLine('Loaded project dialog ' + Path);
    Exit;
  end;
  case Tag of
    1: Decl := BuildConfirmDialog('Confirm', 'Proceed with the operation?');
    2: Decl := BuildInputDialog('Input', 'Value:', '');
    3: Decl := BuildSearchDialog('*.*', '', False, False, False, True, True);
    4: Decl := BuildCopyMoveDialog('Copy', 'Copy to:', 'D:\Dest', 0, True);
    5: Decl := BuildHelpDialog;
    6: Decl := BuildAskSaveDialog('readme.md');
    7: Decl := BuildGotoLineDialog(1);
    8: Decl := BuildEncodingDialog('UTF-8');
    9: Decl := BuildReplaceDialog('foo', 'bar');
    10: Decl := BuildDeleteDialog('Delete', 'Delete selected item(s)?', 'Delete', False);
  else
    Exit;
  end;
  LoadJsonText(PrettyJson(DeclarationToJson(Decl)), '', True);
  ApplyPreview;
  LogLine('Template (fallback Build*): ' + TMenuItem(Sender).Text);
end;

procedure TDialogDesignerForm.MiZoomInClick(Sender: TObject);
begin
  if not Assigned(FRenderer) then
    Exit;
  FRenderer.AdjustZoom(0.1, FPaint.Width, FPaint.Height, Canvas);
  SyncPreviewSize;
end;

procedure TDialogDesignerForm.MiZoomOutClick(Sender: TObject);
begin
  if not Assigned(FRenderer) then
    Exit;
  FRenderer.AdjustZoom(-0.1, FPaint.Width, FPaint.Height, Canvas);
  SyncPreviewSize;
end;

procedure TDialogDesignerForm.MiZoomResetClick(Sender: TObject);
begin
  if not Assigned(FRenderer) then
    Exit;
  FRenderer.SetZoom(1.0, FPaint.Width, FPaint.Height, Canvas);
  SyncPreviewSize;
end;

end.
