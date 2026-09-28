unit uDualPanelKeymapDialog;

{ Keymap hotkey list / editor dialogs (hdkKeymap, hdkKeymapEdit). Lets the
  user rebind any TKeymapAction, warns before silently stealing a hotkey
  from another action, and writes the result to the user's keymap.json
  (uKeymap.SaveKeymapProfile) on Save. Extracted as its own controller so
  TDualPanelWindow keeps only a thin OpenKeymapDialog + dispatch forward,
  mirroring uDualPanelColorCoding.pas. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uKeymap;

type
  TKeymapKindSetter = reference to procedure(AKind: THostDialogKind);
  TKeymapCanStart = reference to function: Boolean;
  TKeymapPrepareUi = reference to procedure;

  TKeymapDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TKeymapKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TKeymapCanStart;
    FOnPrepareUi: TKeymapPrepareUi;
    /// <summary>Working copy the dialogs edit; nothing is written to disk
    /// until Save. Cloned from ActiveKeymap so in-place edits never alias
    /// the shared cache (see uKeymap.CloneKeymapProfile).</summary>
    FProfile: TKeymapProfile;
    /// <summary>Snapshot of FProfile as opened - diffed against FProfile on
    /// Save so a Cancel-only session never touches keymap.json.</summary>
    FOriginal: TKeymapProfile;
    /// <summary>Embedded defaults - source for the per-action / whole-profile
    /// Reset buttons.</summary>
    FDefaults: TKeymapProfile;
    FEditAction: TKeymapAction;
    /// <summary>The action on each list row, kaNone on a context heading
    /// (BuildRows).</summary>
    FRows: TArray<TKeymapAction>;
    /// <summary>Set once a conflict warning has been shown for the pending
    /// edit - a second Save press with the same conflicting combo confirms
    /// the reassignment instead of warning again.</summary>
    FConfirmOverwrite: Boolean;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    function ActionRowLabel(AAction: TKeymapAction): string;
    /// <summary>List rows grouped by keymap context (Global, Panels,
    /// Document, ...), each group under a heading row; fills FRows.</summary>
    function BuildRows: TArray<string>;
    /// <summary>The action on list row AIndex; kaNone on a heading or out of
    /// range.</summary>
    function ActionAt(AIndex: Integer): TKeymapAction;
    /// <summary>Splits AText on ';', parses each token via
    /// uKeymapRegistry.TryParseKeyCombo. Returns False with AError set on the
    /// first unrecognized token.</summary>
    function TryParseKeysField(const AText: string;
      out ABindings: TArray<TKeyBinding>; out AError: string): Boolean;
    /// <summary>Other actions (not AExclude) whose bindings overlap one of
    /// ABindings, in FProfile as it stands right now.</summary>
    function FindConflicts(const ABindings: TArray<TKeyBinding>;
      AExclude: TKeymapAction): TArray<TKeymapAction>;
    /// <summary>Strips every binding in ABindings away from any other action
    /// that currently holds it, then assigns ABindings to FEditAction -
    /// makes each hotkey unambiguous again after a reassignment.</summary>
    procedure ApplyEdit(const ABindings: TArray<TKeyBinding>);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TKeymapKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TKeymapCanStart; const AOnPrepareUi: TKeymapPrepareUi);
    procedure OpenList;
    procedure RefreshList(ASelectedIndex: Integer = -1);
    procedure BeginEdit(AIndex: Integer);
    procedure ResetSelected;
    procedure ResetAll;
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchListCommand(const AControlId: string);
    function DispatchEditCommand(const AControlId: string): Boolean;
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

/// <summary>Readable, translated name of AAction ("Hex <-> text").</summary>
function KeymapActionCaption(AAction: TKeymapAction): string;
/// <summary>Translated heading of a keymap context ("Viewer and editor").</summary>
function KeymapContextCaption(AContext: TKeymapContext): string;

implementation

uses
  uKeymapRegistry, uStrings;

const
  /// <summary>English captions of the actions, in TKeymapAction order;
  /// translated as ui.keymap.action.<keymap.json name>.</summary>
  KEYMAP_ACTION_CAPTIONS: array[TKeymapAction] of string = (
    '',
    'Help',
    'Pack into an archive',
    'User menu',
    'Unpack an archive',
    'View file / folder size',
    'Edit file',
    'Copy',
    'Move',
    'Rename',
    'Copy here under a new name',
    'Create folder',
    'Create link',
    'Compare files',
    'Recycle Bin',
    'Restore from Recycle Bin',
    'Delete to Recycle Bin',
    'Delete permanently',
    'Quit (panels)',
    'Find files',
    'Swap panels',
    'Other panel to this folder',
    'This panel to the other folder',
    'Info panel',
    'Column mode menu',
    'Sort menu',
    'Panels <-> console (panels)',
    'Drive root',
    'Left panel drive',
    'Right panel drive',
    'Refresh panel',
    'Select all',
    'Invert selection',
    'Folder history back',
    'Folder history forward',
    'Folder history',
    'File history',
    'Command history',
    'Folder hotlist',
    'Add folder to hotlist',
    'Branch view',
    'Filter by mask',
    'Show / hide left panel',
    'Show / hide right panel',
    'Sort by name',
    'Sort by extension',
    'Sort by modified time',
    'Sort by size',
    'Unsorted',
    'Sort by creation time',
    'Sort by access time',
    'Copy full path',
    'Name to command line',
    'Path to command line',
    'Run in a separate window',
    'Go to command line',
    'New panel tab',
    'Close panel tab',
    'Next workspace tab',
    'Select by mask',
    'Deselect by mask',
    'Synchronize folders',
    'Background jobs',
    'New terminal',
    'New file',
    'Quick view',
    'Sync folder with console',
    'Console shell profile',
    'Show / hide hidden files',
    'Columns: Brief',
    'Columns: Size',
    'Columns: Date',
    'Columns: Full',
    'Columns: Created',
    'Columns: Types',
    'Columns: Custom',
    'Copy to clipboard',
    'Cut to clipboard',
    'Paste from clipboard',
    'Saved workspaces',
    'Save workspace',
    'File attributes',
    'Windows properties',
    'SSH connections',
    'File associations',
    'Compare folders',
    'External viewer',
    'External editor',
    'Checksums',
    'Copy name',
    'Viewer <-> editor',
    'Hex <-> text',
    'Markdown <-> text',
    'Next encoding',
    'Choose encoding',
    'Go to line',
    'Find',
    'Find next',
    'Find previous',
    'Copy selection or line',
    'Select all',
    'Clear selection',
    'Close',
    'Word wrap',
    'Rendered <-> source',
    'Save',
    'Replace',
    'Paste',
    'Cut selection or line',
    'Undo',
    'Redo',
    'Delete line',
    'Delete to end of line',
    'Insert line below',
    'Previous workspace tab',
    'Top menu',
    'Quit',
    'Panels <-> console',
    'Zoom 100%',
    'Reload keymap.json',
    'Command history',
    'Select all',
    'Copy, or interrupt the command',
    'Copy selection',
    'Paste',
    'Panel to the console folder'
  );

  /// <summary>Order of the groups in the list.</summary>
  KEYMAP_CONTEXT_ORDER: array[0..8] of TKeymapContext = (
    kcGlobal, kcPanels, kcDocument, kcViewer, kcMarkdown, kcEditor, kcShell, kcConsole, kcTerminal);

function KeymapActionCaption(AAction: TKeymapAction): string;
begin
  Result := T('ui.keymap.action.' + KeymapActionDisplayName(AAction),
    KEYMAP_ACTION_CAPTIONS[AAction]);
end;

function KeymapContextCaption(AContext: TKeymapContext): string;
begin
  case AContext of
    kcGlobal: Result := T('ui.keymap.context.global', 'Global (any window)');
    kcPanels: Result := T('ui.keymap.context.panels', 'File panels');
    kcDocument: Result := T('ui.keymap.context.document', 'Viewer and editor');
    kcViewer: Result := T('ui.keymap.context.viewer', 'Viewer');
    kcMarkdown: Result := T('ui.keymap.context.markdown', 'Markdown view');
    kcEditor: Result := T('ui.keymap.context.editor', 'Editor');
    kcShell: Result := T('ui.keymap.context.shell', 'Console and terminal');
    kcConsole: Result := T('ui.keymap.context.console', 'Console');
    kcTerminal: Result := T('ui.keymap.context.terminal', 'Terminal');
  end;
end;

constructor TKeymapDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TKeymapKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TKeymapCanStart;
  const AOnPrepareUi: TKeymapPrepareUi);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FEditAction := kaNone;
end;

procedure TKeymapDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TKeymapDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TKeymapDialogController.ActionRowLabel(AAction: TKeymapAction): string;
var
  Keys: string;
begin
  Keys := BindingsToStr(FProfile.Bindings[AAction]);
  if Keys = '' then
    Keys := T('ui.keymap.noKeys', '(none)');
  // Two spaces in, keys at column 40: lines up with the "header" label.
  Result := Format('  %-38s%s', [KeymapActionCaption(AAction), Keys]);
end;

function TKeymapDialogController.BuildRows: TArray<string>;
var
  Ctx: TKeymapContext;
  Act: TKeymapAction;
  First: Boolean;
begin
  Result := nil;
  FRows := nil;
  for Ctx in KEYMAP_CONTEXT_ORDER do
  begin
    First := True;
    for Act := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
    begin
      if KeymapActionContext(Act) <> Ctx then
        Continue;
      if First then
      begin
        // #$2500 = box-drawing line; this unit has no BOM, so a literal
        // would be read as ANSI.
        Result := Result + [#$2500#$2500' ' + KeymapContextCaption(Ctx) + ' '#$2500#$2500];
        FRows := FRows + [kaNone];
        First := False;
      end;
      Result := Result + [ActionRowLabel(Act)];
      FRows := FRows + [Act];
    end;
  end;
end;

function TKeymapDialogController.ActionAt(AIndex: Integer): TKeymapAction;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
    Exit(kaNone);
  Result := FRows[AIndex];
end;

procedure TKeymapDialogController.OpenList;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  FProfile := CloneKeymapProfile(ActiveKeymap);
  FOriginal := CloneKeymapProfile(FProfile);
  FDefaults := LoadDefaultKeymapProfile;

  SetKind(hdkKeymap);
  // Row 0 is the first group's heading.
  FDialog.Open(BuildKeymapDialog(BuildRows, 1), FOnCommand);
  Notify;
end;

procedure TKeymapDialogController.RefreshList(ASelectedIndex: Integer);
var
  Sel: Integer;
begin
  if not Assigned(FDialog) then
    Exit;
  if ASelectedIndex >= 0 then
    Sel := ASelectedIndex
  else
    Sel := FDialog.GetListSelectedIndex('actions');
  if Sel < 1 then
    Sel := 1;
  SetKind(hdkKeymap);
  FDialog.Open(BuildKeymapDialog(BuildRows, Sel), FOnCommand);
  Notify;
end;

procedure TKeymapDialogController.BeginEdit(AIndex: Integer);
begin
  if ActionAt(AIndex) = kaNone then
    Exit;
  FEditAction := ActionAt(AIndex);
  FConfirmOverwrite := False;
  SetKind(hdkKeymapEdit);
  FDialog.Open(BuildKeymapEditDialog(Format('%s [%s]',
    [KeymapActionCaption(FEditAction), KeymapActionDisplayName(FEditAction)]),
    BindingsToStr(FProfile.Bindings[FEditAction]), ''), FOnCommand);
  Notify;
end;

procedure TKeymapDialogController.ResetSelected;
var
  Idx: Integer;
  Act: TKeymapAction;
begin
  Idx := FDialog.GetListSelectedIndex('actions');
  Act := ActionAt(Idx);
  if Act = kaNone then
    Exit;
  FProfile.Bindings[Act] := Copy(FDefaults.Bindings[Act]);
  RefreshList(Idx);
end;

procedure TKeymapDialogController.ResetAll;
begin
  FProfile := CloneKeymapProfile(FDefaults);
  RefreshList(1);
end;

function TKeymapDialogController.TryParseKeysField(const AText: string;
  out ABindings: TArray<TKeyBinding>; out AError: string): Boolean;
var
  Tokens: TArray<string>;
  I: Integer;
  Token: string;
  Binding: TKeyBinding;
begin
  SetLength(ABindings, 0);
  AError := '';
  Tokens := AText.Split([';']);
  for I := 0 to High(Tokens) do
  begin
    Token := Trim(Tokens[I]);
    if Token = '' then
      Continue;
    if not TryParseKeyCombo(Token, Binding) then
    begin
      AError := 'Unrecognized key: "' + Token + '".';
      Exit(False);
    end;
    ABindings := ABindings + [Binding];
  end;
  Result := True;
end;

function TKeymapDialogController.FindConflicts(const ABindings: TArray<TKeyBinding>;
  AExclude: TKeymapAction): TArray<TKeymapAction>;
var
  Act: TKeymapAction;
  I, J: Integer;
  Found: Boolean;
begin
  SetLength(Result, 0);
  for Act := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
  begin
    // Only the same context clashes: Ctrl+C copies files on panels and text
    // in a document, and a specific context overriding a general one
    // (Markdown F4 over Document F4) is by design.
    if (Act = AExclude) or
       (KeymapActionContext(Act) <> KeymapActionContext(AExclude)) then
      Continue;
    Found := False;
    for I := 0 to High(ABindings) do
      for J := 0 to High(FProfile.Bindings[Act]) do
        if SameKeyBinding(ABindings[I], FProfile.Bindings[Act][J]) then
        begin
          Found := True;
          Break;
        end;
    if Found then
      Result := Result + [Act];
  end;
end;

procedure TKeymapDialogController.ApplyEdit(const ABindings: TArray<TKeyBinding>);
var
  Act: TKeymapAction;
  Kept: TArray<TKeyBinding>;
  I, J: Integer;
  Clash: Boolean;
begin
  for Act := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
  begin
    if (Act = FEditAction) or
       (KeymapActionContext(Act) <> KeymapActionContext(FEditAction)) then
      Continue; // see FindConflicts
    SetLength(Kept, 0);
    for I := 0 to High(FProfile.Bindings[Act]) do
    begin
      Clash := False;
      for J := 0 to High(ABindings) do
        if SameKeyBinding(FProfile.Bindings[Act][I], ABindings[J]) then
        begin
          Clash := True;
          Break;
        end;
      if not Clash then
        Kept := Kept + [FProfile.Bindings[Act][I]];
    end;
    if Length(Kept) <> Length(FProfile.Bindings[Act]) then
      FProfile.Bindings[Act] := Kept;
  end;
  FProfile.Bindings[FEditAction] := ABindings;
end;

function TKeymapDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := False;
  if AKey = vkF4 then
  begin
    BeginEdit(FDialog.GetListSelectedIndex('actions'));
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

procedure TKeymapDialogController.DispatchListCommand(const AControlId: string);
begin
  if DialogCmdIs(AControlId, 'edit') then
    BeginEdit(FDialog.GetListSelectedIndex('actions'))
  else if DialogCmdIs(AControlId, 'reset') then
    ResetSelected
  else if DialogCmdIs(AControlId, 'resetall') then
    ResetAll
  else if DialogCmdIsAccept(AControlId) then
  begin
    FDialog.Close;
    // Only touch keymap.json if the effective bindings actually
    // changed - comparing serialized JSON is simpler and just as
    // correct as a field-by-field diff.
    if KeymapProfileToJson(FProfile) <> KeymapProfileToJson(FOriginal) then
    begin
      SaveKeymapProfile(FProfile);
      ReloadKeymap('');
    end;
  end
  else
    // Cancel or dismiss: discard the working copy, nothing is written.
    FDialog.Close;
end;

function TKeymapDialogController.DispatchEditCommand(
  const AControlId: string): Boolean;
var
  SelectAfter: Integer;
  NewBindings: TArray<TKeyBinding>;
  Conflicts: TArray<TKeymapAction>;
  ParseError, Names, Status: string;
  I: Integer;
begin
  SelectAfter := Ord(FEditAction) - 1;
  if DialogCmdIs(AControlId, 'reset') then
  begin
    FDialog.SetInputValue('km_keys', BindingsToStr(FDefaults.Bindings[FEditAction]));
    FDialog.SetStatus('km_status', '');
    FConfirmOverwrite := False;
    Notify;
    Exit(False);
  end;
  if DialogCmdIsAccept(AControlId) then
  begin
    if not TryParseKeysField(FDialog.GetInputValue('km_keys'), NewBindings, ParseError) then
    begin
      FDialog.SetStatus('km_status', ParseError);
      SetKind(hdkKeymapEdit);
      Notify;
      Exit(False);
    end;
    Conflicts := FindConflicts(NewBindings, FEditAction);
    if (Length(Conflicts) > 0) and not FConfirmOverwrite then
    begin
      Names := '';
      for I := 0 to High(Conflicts) do
      begin
        if I > 0 then
          Names := Names + ', ';
        Names := Names + KeymapActionDisplayName(Conflicts[I]);
      end;
      Status := 'Already used by: ' + Names + '. Press OK again to reassign.';
      FDialog.SetStatus('km_status', Status);
      FConfirmOverwrite := True;
      SetKind(hdkKeymapEdit);
      Notify;
      Exit(False);
    end;
    ApplyEdit(NewBindings);
  end;
  FDialog.Close;
  RefreshList(SelectAfter);
  Result := True;
end;

function TKeymapDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkKeymap: DispatchListCommand(AControlId);
    hdkKeymapEdit: Result := DispatchEditCommand(AControlId);
  else
    { not a keymap dialog }
  end;
end;

end.
