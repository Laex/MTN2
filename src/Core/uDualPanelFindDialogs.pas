unit uDualPanelFindDialogs;

{ Alt+F7 search dialog and directory-sync preview. Extracted from
  TDualPanelWindow; Find/VFS execution stays on TSearchController / FJobs. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uDialogHost, uDialogTypes, uDialogBuilders, uDialogJson, uDualPanelUiTypes, uDualPanelSearch,
  uDualPanelSync, uDualPanelJobs, uDualPanelJobList, uVfsTypes, uFindSession, uDialogHistory,
  uSearchEngines, uDialogPresets, uSyncIgnore;

type
  TFindKindSetter = reference to procedure(AKind: THostDialogKind);
  TFindBlockedFn = reference to function: Boolean;
  TFindPrepareProc = reference to procedure;
  TFindGetUriFn = reference to function: string;
  TFindStubProc = reference to procedure(const ATitle, ADetail: string);
  TFindAliveFn = reference to function: Boolean;

  TSearchDialogController = class
  private
    FDialog: TDialogHost;
    FSearch: TSearchController;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TFindKindSetter;
    FOnBlocked: TFindBlockedFn;
    FOnPrepare: TFindPrepareProc;
    FOnGetUri: TFindGetUriFn;
    FOnNotify: TProc;
    FPickField: string;
    FSyncing: Boolean;
    FHexMode: Boolean;
    FLastText: string;
    FLastHex: string;
    FPresets: TDialogPresets;
    FPresetName: string;
    function ReadDialogFields: TDialogCommandFields;
    procedure ShowPresets;
    procedure RunPresetCommand(const AControlId: string;
      const AFields: TDialogCommandFields);
    procedure ApplyFields(const AFields: TDialogCommandFields);
    procedure BeginDatePick(const AFieldId: string);
    procedure OpenPipeline;
    function PipelineCaption: string;
  public
    constructor Create(ADialog: TDialogHost; ASearch: TSearchController;
      const AOnCommand: TDialogCommandEvent; const AOnSetKind: TFindKindSetter;
      const AOnBlocked: TFindBlockedFn; const AOnPrepare: TFindPrepareProc;
      const AOnGetUri: TFindGetUriFn; const AOnNotify: TProc);
    destructor Destroy; override;
    procedure Open;
    /// <summary>Keeps the text and hex fields in step while either is edited:
    /// text shows its UTF-8 bytes; bytes that spell text show it; bytes typed
    /// by hand are searched instead of the text.</summary>
    procedure SyncHexField;
    function DispatchCommand(const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
    /// <summary>F9 on a date field opens the calendar.</summary>
    function HandleEditInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchDatePickerCommand(const AControlId: string): Boolean;
    /// <summary>Result of the pipeline dialog: OK keeps the two choices; the Find dialog
    /// opens again either way.</summary>
    function DispatchPipelineCommand(const AControlId: string): Boolean;
  end;

  TDirSyncDialogController = class
  private
    FDialog: TDialogHost;
    FJobs: TPanelJobList;
    FItems: TArray<TSyncItem>;
    FBusy: Boolean;
    FSrcRoot: string;
    FDstRoot: string;
    FSnapshotPending: Boolean;
    FPendingConflictRels: TArray<string>;
    FByContent: Boolean;
    FComparedByContent: Boolean;
    FCompareGen: Integer;
    // List row -> index in FItems (the list can show a filtered view).
    FViewIdx: TArray<Integer>;
    FTwoWay: Boolean;
    FMirror: Boolean;
    FOnlySkipped: Boolean;
    // Target-only files to remove once the copy job succeeds.
    FPendingDeletes: TArray<string>;
    FPendingDeleteToBin: Boolean;
    FPresets: TDialogPresets;
    FPresetIdx: Integer;
    FApplyingPreset: Boolean;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TFindKindSetter;
    FOnPrepare: TFindPrepareProc;
    FOnOpenStub: TFindStubProc;
    FOnCloseStub: TProc;
    FOnNotify: TProc;
    FOnAlive: TFindAliveFn;
    FOnShowExtras: TProc<TArray<string>>;
    // The running comparison: its counters and stop flag, and the entry in the
    // job list that lets it go on out of sight.
    FProgress: ISyncProgress;
    FJobKey: string;
    FJobSeq: Integer;
    FForeground: Boolean;
    // A comparison that finished while its progress was hidden waits in the
    // job list until the user opens it.
    FResultReady: Boolean;
    FReadyByContent: Boolean;
    FReadyAt: TDateTime;
    // What the comparison leaves out; asked in the dialog that precedes it.
    FFilterOpts: TSyncFilterOptions;
    FOptionsOpen: Boolean;
    procedure ShowOptions;
    procedure DispatchOptionsCommand(const AControlId: string);
    procedure BeginCompareJob;
    procedure EndCompareJob;
    procedure ShowProgress(AGen: Integer; AByContent: Boolean);
    procedure CancelCompare;
    procedure OpenCompareJob;
    procedure ShowCompareResult(AByContent, AFromBackground: Boolean);
    procedure StartCompare;
    procedure ApplyCompareResult(const AItems: TArray<TSyncItem>;
      const AError: string; AByContent: Boolean; AGen: Integer);
    procedure ReadViewMode;
    procedure RefreshPlan(ASelect: Integer);
    procedure ApplyRowAction(AAction: TSyncAction);
    procedure StartPendingDeletes;
    procedure RefreshPresetList(const ASelectName: string);
    procedure ApplyPreset(const AName: string);
    procedure SavePreset;
    procedure DeletePreset;
    procedure ShowExtras(ATwoWay: Boolean);
  public
    constructor Create(ADialog: TDialogHost; AJobs: TPanelJobList;
      const AOnCommand: TDialogCommandEvent; const AOnSetKind: TFindKindSetter;
      const AOnPrepare: TFindPrepareProc; const AOnOpenStub: TFindStubProc;
      const AOnCloseStub, AOnNotify: TProc; const AOnAlive: TFindAliveFn);
    destructor Destroy; override;
    procedure Open(const ASrcURI, ADstURI: string);
    function DispatchCommand(const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
    procedure NotifyJobFinished(ASuccess: Boolean);
    procedure NotifyDialogChanged;
    /// <summary>Receives the target-only files of the mirror plan when the
    /// user asks to review them in a panel instead of deleting them.</summary>
    property OnShowExtras: TProc<TArray<string>> read FOnShowExtras
      write FOnShowExtras;
    /// <summary>Right / Left / Space / Del on the difference list set the
    /// action of the current row.</summary>
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    property Busy: Boolean read FBusy;
  end;

function ResolveSearchRootPath(const ACurrentUri: string): string;

implementation

uses
  System.DateUtils, uFileFind, uStrings, uConfigLocation, uPluginServices, uNotice;

const
  // Cells of the path labels in dirsync.json.
  cDirSyncPathCells = 96;
  cDirSyncCmdRight = 'act_right';
  cDirSyncCmdLeft = 'act_left';
  cDirSyncCmdSkip = 'act_skip';
  cDirSyncCmdAuto = 'act_auto';
  cDirSyncPresetFile = 'syncpresets.json';
  cSyncJobOwner = 'sync';
  cSearchPresetFile = 'searchpresets.json';

function BoolText(AValue: Boolean): string;
begin
  if AValue then
    Result := '1'
  else
    Result := '0';
end;

function ResolveSearchRootPath(const ACurrentUri: string): string;
var
  FindData: TFindSessionData;
begin
  if HasArchiveChain(ACurrentUri) then
    Result := SafeDirectoryName(ArchiveBasePath(ACurrentUri))
  else if IsFindUri(ACurrentUri) then
  begin
    if TryGetFindSessionFromUri(ACurrentUri, FindData) then
      Result := FindData.RootPath
    else
      Result := '';
  end
  else
    Result := FileUriToPath(ACurrentUri);
  if (Result <> '') and (Length(Result) = 2) and (Result[2] = ':') then
    Result := Result + PathDelim;
end;

constructor TSearchDialogController.Create(ADialog: TDialogHost;
  ASearch: TSearchController; const AOnCommand: TDialogCommandEvent;
  const AOnSetKind: TFindKindSetter; const AOnBlocked: TFindBlockedFn;
  const AOnPrepare: TFindPrepareProc; const AOnGetUri: TFindGetUriFn;
  const AOnNotify: TProc);
begin
  inherited Create;
  FDialog := ADialog;
  FSearch := ASearch;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnBlocked := AOnBlocked;
  FOnPrepare := AOnPrepare;
  FOnGetUri := AOnGetUri;
  FOnNotify := AOnNotify;
end;

destructor TSearchDialogController.Destroy;
begin
  FPresets.Free;
  inherited;
end;

function SearchPresetValues(ASearch: TSearchController): TPresetValues;
var
  F: TFindFilterText;
begin
  F := ASearch.Filters;
  SetLength(Result, 0);
  PresetAdd(Result, 'mask', ASearch.Mask);
  PresetAdd(Result, 'text', ASearch.ContainingText);
  PresetAdd(Result, 'case', BoolText(ASearch.CaseSensitive));
  PresetAdd(Result, 'words', BoolText(ASearch.WholeWords));
  PresetAdd(Result, 'folders', BoolText(ASearch.SearchFolders));
  PresetAdd(Result, 'regex', BoolText(ASearch.UseRegex));
  PresetAdd(Result, 'subdirs', BoolText(ASearch.Subdirs));
  PresetAdd(Result, 'archives', BoolText(ASearch.SearchArchives));
  PresetAdd(Result, 'encoding', IntToStr(ASearch.EncodingIdx));
  PresetAdd(Result, 'size_min', F.SizeMin);
  PresetAdd(Result, 'size_max', F.SizeMax);
  PresetAdd(Result, 'date_from', F.DateFrom);
  PresetAdd(Result, 'date_to', F.DateTo);
  PresetAdd(Result, 'attr_ro', IntToStr(Ord(F.AttrReadOnly)));
  PresetAdd(Result, 'attr_hidden', IntToStr(Ord(F.AttrHidden)));
  PresetAdd(Result, 'attr_system', IntToStr(Ord(F.AttrSystem)));
  PresetAdd(Result, 'attr_archive', IntToStr(Ord(F.AttrArchive)));
end;

function PresetAttr(const AValues: TPresetValues; const AKey: string): TFindAttrState;
var
  N: Integer;
begin
  N := StrToIntDef(PresetGet(AValues, AKey, '0'), 0);
  if (N < Ord(Low(TFindAttrState))) or (N > Ord(High(TFindAttrState))) then
    N := 0;
  Result := TFindAttrState(N);
end;

procedure ApplySearchPreset(ASearch: TSearchController; const AValues: TPresetValues);
var
  F: TFindFilterText;
begin
  ASearch.Mask := PresetGet(AValues, 'mask', '*.*');
  ASearch.ContainingText := PresetGet(AValues, 'text', '');
  ASearch.CaseSensitive := PresetGet(AValues, 'case', '0') = '1';
  ASearch.WholeWords := PresetGet(AValues, 'words', '0') = '1';
  ASearch.SearchFolders := PresetGet(AValues, 'folders', '0') = '1';
  ASearch.UseRegex := PresetGet(AValues, 'regex', '0') = '1';
  ASearch.Subdirs := PresetGet(AValues, 'subdirs', '1') = '1';
  ASearch.SearchArchives := PresetGet(AValues, 'archives', '0') = '1';
  ASearch.EncodingIdx := StrToIntDef(PresetGet(AValues, 'encoding', '0'), 0);
  ASearch.HexMode := False;
  F.SizeMin := PresetGet(AValues, 'size_min', '');
  F.SizeMax := PresetGet(AValues, 'size_max', '');
  F.DateFrom := PresetGet(AValues, 'date_from', '');
  F.DateTo := PresetGet(AValues, 'date_to', '');
  F.AttrReadOnly := PresetAttr(AValues, 'attr_ro');
  F.AttrHidden := PresetAttr(AValues, 'attr_hidden');
  F.AttrSystem := PresetAttr(AValues, 'attr_system');
  F.AttrArchive := PresetAttr(AValues, 'attr_archive');
  ASearch.Filters := F;
end;

// The preset list and the name box under the options. The dialog is rebuilt
// from the search state by every preset command, so the list is refilled here.
procedure TSearchDialogController.ShowPresets;
var
  Names, Items: TArray<string>;
  I, Sel: Integer;
begin
  if FPresets = nil then
    FPresets := TDialogPresets.Create(GetConfigFilePath(cSearchPresetFile));
  Names := FPresets.Names;
  SetLength(Items, Length(Names) + 1);
  Items[0] := T('ui.search.noPreset', '(no preset)');
  Sel := 0;
  for I := 0 to High(Names) do
  begin
    Items[I + 1] := Names[I];
    if SameText(Names[I], FPresetName) then
      Sel := I + 1;
  end;
  FDialog.SetDropDownItems('preset', Items, Sel);
  FDialog.SetInputValue('preset_name', FPresetName);
end;

procedure TSearchDialogController.RunPresetCommand(const AControlId: string;
  const AFields: TDialogCommandFields);
var
  Names: TArray<string>;
  Idx: Integer;
  Typed, Chosen: string;
  Values: TPresetValues;
begin
  if FPresets = nil then
    FPresets := TDialogPresets.Create(GetConfigFilePath(cSearchPresetFile));
  Names := FPresets.Names;
  Typed := Trim(FDialog.GetInputValue('preset_name'));
  Idx := FDialog.GetListSelectedIndex('preset');
  if (Idx > 0) and (Idx <= Length(Names)) then
    Chosen := Names[Idx - 1]
  else
    Chosen := '';
  ApplyFields(AFields);
  if DialogCmdIs(AControlId, 'preset_save') then
  begin
    if Typed = '' then
      Typed := Chosen;
    if (Typed <> '') and FPresets.Put(Typed, SearchPresetValues(FSearch)) then
      FPresetName := Typed;
  end
  else if DialogCmdIs(AControlId, 'preset_load') then
  begin
    if (Chosen <> '') and FPresets.Find(Chosen, Values) then
    begin
      ApplySearchPreset(FSearch, Values);
      FPresetName := Chosen;
    end;
  end
  else if DialogCmdIs(AControlId, 'preset_del') then
  begin
    if Chosen = '' then
      Chosen := Typed;
    if (Chosen <> '') and FPresets.Delete(Chosen) then
      FPresetName := '';
  end;
  FDialog.Close;
  Open;
end;

procedure TSearchDialogController.Open;
var
  Mask, Uri: string;
begin
  if not Assigned(FSearch) or not Assigned(FDialog) then
    Exit;
  if FSearch.Phase = spResults then
    FSearch.CloseSearchUi;
  if FSearch.Phase <> spNone then
    Exit;
  if Assigned(FOnBlocked) and FOnBlocked() then
    Exit;
  if Assigned(FOnPrepare) then
    FOnPrepare();

  Uri := '';
  if Assigned(FOnGetUri) then
    Uri := FOnGetUri();
  FSearch.RootPath := ResolveSearchRootPath(Uri);
  Mask := FSearch.Mask;
  if Mask = '' then
    Mask := '*.*';
  FSearch.FocusField := 0;
  FSearch.Phase := spNone;
  if not FSearch.HexMode then
    FSearch.HexText := TextToHexString(FSearch.ContainingText);
  FHexMode := FSearch.HexMode;
  FLastText := FSearch.ContainingText;
  FLastHex := FSearch.HexText;
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkSearch);
  if not FDialog.OpenJson(
    DeclarationToJson(BuildSearchDialog(Mask, FSearch.ContainingText,
      FSearch.CaseSensitive, FSearch.WholeWords, FSearch.SearchFolders,
      FSearch.UseRegex, FSearch.HexText, FSearch.Subdirs, FSearch.SearchArchives,
      PipelineCaption, FSearch.EncodingIdx, FSearch.Filters)),
    FOnCommand) then
    FDialog.Open(BuildSearchDialog(Mask, FSearch.ContainingText,
      FSearch.CaseSensitive, FSearch.WholeWords, FSearch.SearchFolders,
      FSearch.UseRegex, FSearch.HexText, FSearch.Subdirs, FSearch.SearchArchives,
      PipelineCaption, FSearch.EncodingIdx, FSearch.Filters), FOnCommand);
  ShowPresets;
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TSearchDialogController.ReadDialogFields: TDialogCommandFields;
begin
  Result := ReadDialogCommandFields(FDialog);
end;

procedure TSearchDialogController.SyncHexField;
var
  Text, Hex, NewHex, NewText: string;
  Cursor, NewCursor: Integer;
begin
  if FSyncing or not Assigned(FDialog) then
    Exit;
  FSyncing := True;
  try
    Text := FDialog.GetInputValue('search_text');
    Hex := FDialog.GetInputValue('search_hex');
    if Text <> FLastText then
    begin
      FHexMode := False;
      NewHex := TextToHexString(Text);
      if NewHex <> Hex then
        FDialog.SetInputValue('search_hex', NewHex);
      FLastText := Text;
      FLastHex := NewHex;
    end
    else if Hex <> FLastHex then
    begin
      Cursor := FDialog.GetInputCursor('search_hex');
      EditHexField(FLastHex, Hex, Cursor, NewHex, NewCursor);
      if (NewHex <> Hex) or (NewCursor <> Cursor) then
        FDialog.SetInputValueAt('search_hex', NewHex, NewCursor);
      if NewHex <> FLastHex then
      begin
        FHexMode := True;
        FLastHex := NewHex;
        if TryHexToText(NewHex, NewText) and (NewText <> Text) then
        begin
          FDialog.SetInputValue('search_text', NewText);
          FLastText := NewText;
        end;
      end;
    end;
  finally
    FSyncing := False;
  end;
end;

function TSearchDialogController.PipelineCaption: string;
var
  NameEngines, TextEngines: TArray<TSearchEngine>;
  AutoText, BuiltInText: string;
  NameIdx, TextIdx: Integer;
begin
  AutoText := T('ui.search.engineAuto', 'Auto');
  BuiltInText := T('ui.search.engineBuiltIn', 'Built-in');
  NameEngines := SearchStageEngines(SearchEngines, ssNames);
  TextEngines := SearchStageEngines(SearchEngines, ssText);
  NameIdx := SearchEngineIndex(FSearch.UsePlugins, FSearch.Engine, NameEngines);
  TextIdx := SearchEngineIndex(FSearch.ContentUsePlugins, FSearch.ContentEngine, TextEngines);
  Result := SearchPipelineCaption(T('ui.search.pipeline', 'Pipeline'), AutoText,
    SearchEngineItems(NameEngines, AutoText, BuiltInText),
    SearchEngineItems(TextEngines, AutoText, BuiltInText), NameIdx, TextIdx);
end;

procedure TSearchDialogController.OpenPipeline;
var
  NameEngines, TextEngines: TArray<TSearchEngine>;
  AutoText, BuiltInText: string;
begin
  AutoText := T('ui.search.engineAuto', 'Auto');
  BuiltInText := T('ui.search.engineBuiltIn', 'Built-in');
  NameEngines := SearchStageEngines(SearchEngines, ssNames);
  TextEngines := SearchStageEngines(SearchEngines, ssText);
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkFindPipeline);
  FDialog.Open(BuildPipelineDialog(SearchEngineItems(NameEngines, AutoText, BuiltInText),
    SearchEngineItems(TextEngines, AutoText, BuiltInText),
    SearchEngineIndex(FSearch.UsePlugins, FSearch.Engine, NameEngines),
    SearchEngineIndex(FSearch.ContentUsePlugins, FSearch.ContentEngine, TextEngines)),
    FOnCommand);
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TSearchDialogController.DispatchPipelineCommand(const AControlId: string): Boolean;
var
  UsePlugins: Boolean;
  Engine: string;
  NameIdx, TextIdx: Integer;
begin
  Result := True;
  if DialogCmdIsAccept(AControlId) and Assigned(FSearch) then
  begin
    NameIdx := FDialog.GetListSelectedIndex('pipe_names');
    TextIdx := FDialog.GetListSelectedIndex('pipe_text');
    SearchEngineFromIndex(NameIdx, SearchStageEngines(SearchEngines, ssNames),
      UsePlugins, Engine);
    FSearch.UsePlugins := UsePlugins;
    FSearch.Engine := Engine;
    SearchEngineFromIndex(TextIdx, SearchStageEngines(SearchEngines, ssText),
      UsePlugins, Engine);
    FSearch.ContentUsePlugins := UsePlugins;
    FSearch.ContentEngine := Engine;
  end;
  FDialog.Close;
  Open;
end;

procedure TSearchDialogController.ApplyFields(const AFields: TDialogCommandFields);
begin
  FSearch.Mask := AFields.Mask;
  if FSearch.Mask = '' then
    FSearch.Mask := '*.*';
  FSearch.ContainingText := AFields.Containing;
  FSearch.CaseSensitive := AFields.CaseSens;
  FSearch.WholeWords := AFields.WholeWords;
  FSearch.SearchFolders := AFields.SearchFolders;
  FSearch.UseRegex := AFields.UseRegex;
  FSearch.SearchArchives := AFields.SearchArchives;
  FSearch.EncodingIdx := AFields.SearchEncodingIdx;
  FSearch.HexText := AFields.HexText;
  FSearch.HexMode := FHexMode;
  FSearch.Subdirs := AFields.Subdirs;
  FSearch.Filters := AFields.Filters;
end;

procedure TSearchDialogController.BeginDatePick(const AFieldId: string);
var
  Fields: TDialogCommandFields;
  Filters: TFindFilterText;
  Text, TimeText: string;
  Stamp: TDateTime;
begin
  Fields := ReadDialogFields;
  ApplyFields(Fields);
  FPickField := AFieldId;
  Filters := FSearch.Filters;
  if SameText(AFieldId, 'filter_date_to') then
    Text := Filters.DateTo
  else
    Text := Filters.DateFrom;
  Stamp := 0;
  TimeText := '';
  // The same reading as the search itself, so a weekday in the short date
  // opens the calendar on that day instead of today.
  if not TryParseFindDate(Text, False, Stamp) then
    Stamp := 0;
  if (Stamp <> 0) and (Frac(Stamp) <> 0) then
    TimeText := FormatDateTime('hh:nn', Stamp);
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkDatePicker);
  FDialog.Open(BuildDatePickerDialog(T('ui.datePicker.title', 'Pick date'),
    Stamp, TimeText), FOnCommand);
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TSearchDialogController.HandleEditInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Id: string;
begin
  Result := False;
  if AKey <> vkF9 then
    Exit;
  Id := FDialog.FocusedControlId;
  if not (SameText(Id, 'filter_date_from') or SameText(Id, 'filter_date_to')) then
    Exit;
  BeginDatePick(Id);
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

function TSearchDialogController.DispatchDatePickerCommand(
  const AControlId: string): Boolean;
var
  Value, TimeText: string;
  Stamp: TDateTime;
  Filters: TFindFilterText;
begin
  Result := True;
  Value := '';
  if DialogCmdIsAccept(AControlId) then
  begin
    TimeText := Trim(FDialog.GetInputValue('time'));
    Value := DateToStr(FDialog.GetDatePickerDate('date'));
    // A time that is not a time of day is left out rather than guessed.
    if (TimeText <> '') and TryStrToTime(TimeText, Stamp) then
      Value := Value + ' ' + FormatDateTime('hh:nn', Stamp);
  end
  else if not DialogCmdIs(AControlId, 'clear') then
    Value := #0;
  FDialog.Close;
  if Assigned(FSearch) then
  begin
    Filters := FSearch.Filters;
    if Value <> #0 then
      if SameText(FPickField, 'filter_date_to') then
        Filters.DateTo := Value
      else
        Filters.DateFrom := Value;
    FSearch.Filters := Filters;
  end;
  Open;
end;

function TSearchDialogController.DispatchCommand(const AControlId: string;
  const AFields: TDialogCommandFields): Boolean;
var
  PickField: string;
begin
  Result := True;
  if DialogCmdIsPick(AControlId, PickField) then
  begin
    BeginDatePick(PickField);
    Exit;
  end;
  if SameText(Trim(AControlId), 'pipeline') then
  begin
    ApplyFields(AFields);
    OpenPipeline;
    Exit;
  end;
  if DialogCmdIs(AControlId, 'preset_save') or
     DialogCmdIs(AControlId, 'preset_load') or
     DialogCmdIs(AControlId, 'preset_del') then
  begin
    if Assigned(FSearch) then
      RunPresetCommand(AControlId, AFields);
    Exit;
  end;
  FDialog.Close;
  if not Assigned(FSearch) then
    Exit;
  if DialogCmdIsOk(AControlId) then
  begin
    ApplyFields(AFields);
    // The editor's F7 starts from this text (a regex is not a plain needle).
    if not (AFields.UseRegex or FHexMode) then
      DialogHistoryAdd('editfind', Trim(AFields.Containing));
    FSearch.StartSearch;
  end
  else if SameText(Trim(AControlId), 'background') then
  begin
    ApplyFields(AFields);
    if not (AFields.UseRegex or FHexMode) then
      DialogHistoryAdd('editfind', Trim(AFields.Containing));
    FSearch.StartSearchInBackground;
  end
  else
    FSearch.CloseSearchUi;
end;

constructor TDirSyncDialogController.Create(ADialog: TDialogHost;
  AJobs: TPanelJobList; const AOnCommand: TDialogCommandEvent;
  const AOnSetKind: TFindKindSetter; const AOnPrepare: TFindPrepareProc;
  const AOnOpenStub: TFindStubProc; const AOnCloseStub, AOnNotify: TProc;
  const AOnAlive: TFindAliveFn);
begin
  inherited Create;
  FDialog := ADialog;
  FJobs := AJobs;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnPrepare := AOnPrepare;
  FOnOpenStub := AOnOpenStub;
  FOnCloseStub := AOnCloseStub;
  FOnNotify := AOnNotify;
  FOnAlive := AOnAlive;
  FBusy := False;
  FSnapshotPending := False;
  FSrcRoot := '';
  FDstRoot := '';
  FByContent := False;
  FComparedByContent := False;
  FCompareGen := 0;
  FTwoWay := False;
  FMirror := False;
  FOnlySkipped := False;
  FFilterOpts := DefaultSyncFilterOptions;
  FPendingDeleteToBin := True;
  SetLength(FPendingDeletes, 0);
  SetLength(FItems, 0);
  SetLength(FViewIdx, 0);
  SetLength(FPendingConflictRels, 0);
end;

destructor TDirSyncDialogController.Destroy;
begin
  if FProgress <> nil then
  begin
    FProgress.Cancel;
    FProgress.SetOnChanged(nil);
  end;
  EndCompareJob;
  FPresets.Free;
  inherited;
end;

procedure TDirSyncDialogController.RefreshPresetList(const ASelectName: string);
var
  Names, Items: TArray<string>;
  I, Sel: Integer;
begin
  Names := FPresets.Names;
  SetLength(Items, Length(Names) + 1);
  Items[0] := T('ui.dirSync.noPreset', '(no preset)');
  Sel := 0;
  for I := 0 to High(Names) do
  begin
    Items[I + 1] := Names[I];
    if SameText(Names[I], ASelectName) then
      Sel := I + 1;
  end;
  FApplyingPreset := True;
  try
    FDialog.SetDropDownItems('preset', Items, Sel);
    FPresetIdx := Sel;
  finally
    FApplyingPreset := False;
  end;
end;

// Mode, comparison, mirror and delete options come from the preset; the
// report-only run is never part of one, and the mirror mode turns it on.
procedure TDirSyncDialogController.ApplyPreset(const AName: string);
var
  Values: TPresetValues;
begin
  if not FPresets.Find(AName, Values) then
    Exit;
  FApplyingPreset := True;
  FDialog.BeginUpdate;
  try
    FDialog.SetRadio('sync_mode', PresetGet(Values, 'mode', 'oneway'));
    FDialog.SetRadio('compare_by', PresetGet(Values, 'compare', 'bydate'));
    FDialog.SetCheckbox('mirror', PresetGet(Values, 'mirror', '0') = '1');
    FDialog.SetCheckbox('del_perm', PresetGet(Values, 'del_perm', '0') = '1');
    FDialog.SetCheckbox('only_skipped', PresetGet(Values, 'only_skipped', '0') = '1');
    FDialog.SetInputValue('preset_name', AName);
  finally
    FDialog.EndUpdate;
    FApplyingPreset := False;
  end;
end;

procedure TDirSyncDialogController.SavePreset;
var
  Name: string;
  Values: TPresetValues;
begin
  Name := Trim(FDialog.GetInputValue('preset_name'));
  if Name = '' then
  begin
    FDialog.SetLabelText('status',
      T('ui.dirSync.presetNeedName', 'Type a name for the preset first'));
    Exit;
  end;
  SetLength(Values, 0);
  PresetAdd(Values, 'mode', FDialog.GetRadio('sync_mode'));
  PresetAdd(Values, 'compare', FDialog.GetRadio('compare_by'));
  PresetAdd(Values, 'mirror', BoolText(FDialog.GetCheckbox('mirror')));
  PresetAdd(Values, 'del_perm', BoolText(FDialog.GetCheckbox('del_perm')));
  PresetAdd(Values, 'only_skipped', BoolText(FDialog.GetCheckbox('only_skipped')));
  if FPresets.Put(Name, Values) then
  begin
    RefreshPresetList(Name);
    FDialog.SetLabelText('status',
      T('ui.dirSync.presetSaved', 'Preset "%s" saved', [Name]));
  end
  else
    FDialog.SetLabelText('status',
      T('ui.dirSync.presetFailed', 'The preset could not be saved'));
end;

procedure TDirSyncDialogController.DeletePreset;
var
  Names: TArray<string>;
  Idx: Integer;
  Name: string;
begin
  Names := FPresets.Names;
  Idx := FDialog.GetListSelectedIndex('preset');
  if (Idx > 0) and (Idx <= Length(Names)) then
    Name := Names[Idx - 1]
  else
    Name := Trim(FDialog.GetInputValue('preset_name'));
  if (Name <> '') and FPresets.Delete(Name) then
  begin
    RefreshPresetList('');
    FDialog.SetInputValue('preset_name', '');
    FDialog.SetLabelText('status',
      T('ui.dirSync.presetDeleted', 'Preset "%s" deleted', [Name]));
  end;
end;

// Hands the target-only files to a panel so the user can review and delete
// them selectively; the dialog closes only when there is something to show.
procedure TDirSyncDialogController.ShowExtras(ATwoWay: Boolean);
var
  Extras: TArray<string>;
  I: Integer;
begin
  Extras := CollectDirSyncDeletePaths(FItems, ATwoWay, True);
  for I := 0 to High(Extras) do
    Extras[I] := FileUriToPath(Extras[I]);
  if (Length(Extras) = 0) or not Assigned(FOnShowExtras) then
  begin
    FDialog.SetLabelText('status',
      T('ui.dirSync.noExtras', 'No extra files on the target'));
    Exit;
  end;
  FDialog.Close;
  SetLength(FItems, 0);
  SetLength(FViewIdx, 0);
  FOnShowExtras(Extras);
end;

procedure TDirSyncDialogController.Open(const ASrcURI, ADstURI: string);
var
  SrcPath, DstPath: string;
begin
  if Assigned(FOnPrepare) then
    FOnPrepare();

  if not DirSyncUrisAreLocalFolders(ASrcURI, ADstURI) then
  begin
    if Assigned(FOnOpenStub) then
      FOnOpenStub(T('ui.dirSync.title', 'Synchronize'),
        T('ui.dirSync.localOnly', 'Only local folders (file://) are supported'));
    Exit;
  end;
  SrcPath := FileUriToPath(ASrcURI);
  DstPath := FileUriToPath(ADstURI);
  if (SrcPath = '') or (DstPath = '') or not TDirectory.Exists(SrcPath) then
  begin
    if Assigned(FOnOpenStub) then
      FOnOpenStub(T('ui.dirSync.title', 'Synchronize'),
        T('ui.dirSync.activeLocal', 'Active panel must be a local folder'));
    Exit;
  end;

  if FBusy or FResultReady then
  begin
    if SameText(SrcPath, FSrcRoot) and SameText(DstPath, FDstRoot) then
      OpenCompareJob
    else if Assigned(FOnOpenStub) then
      FOnOpenStub(T('ui.dirSync.title', 'Synchronize'),
        T('ui.dirSync.compareRunning',
          'Another folder comparison is running or waiting in the job list'));
    Exit;
  end;

  FSrcRoot := SrcPath;
  FDstRoot := DstPath;
  FPresets.Free;
  FPresets := TDialogPresets.Create(GetConfigFilePath(cDirSyncPresetFile));
  FPresetIdx := 0;
  FSnapshotPending := False;
  FByContent := False;
  FComparedByContent := False;
  FTwoWay := False;
  FMirror := False;
  FOnlySkipped := False;
  SetLength(FPendingConflictRels, 0);
  SetLength(FPendingDeletes, 0);
  ShowOptions;
end;

// The folders and the exclusion sources are confirmed before anything is
// scanned; OK starts the comparison.
procedure TDirSyncDialogController.ShowOptions;
begin
  FOptionsOpen := True;
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkDirSync);
  FDialog.Open(BuildDirSyncOptionsDialog(FitSyncPath(FSrcRoot, 56),
    FitSyncPath(FDstRoot, 56), FTwoWay, FByContent, FFilterOpts.SkipJunctions,
    FFilterOpts.UseIgnoreFiles, FFilterOpts.UseRobocopyFile,
    FFilterOpts.UseObsidian, FFilterOpts.Extra), FOnCommand);
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TDirSyncDialogController.DispatchOptionsCommand(
  const AControlId: string);
var
  Accepted: Boolean;
begin
  Accepted := DialogCmdIsAccept(AControlId);
  if Accepted then
  begin
    FTwoWay := SameText(FDialog.GetRadio('sync_mode'), 'twoway');
    FByContent := SameText(FDialog.GetRadio('compare_by'), 'bycontent');
    FFilterOpts.SkipJunctions := FDialog.GetCheckbox('skip_junctions');
    FFilterOpts.UseIgnoreFiles := FDialog.GetCheckbox('use_ignore');
    FFilterOpts.UseRobocopyFile := FDialog.GetCheckbox('use_rcj');
    FFilterOpts.UseObsidian := FDialog.GetCheckbox('use_obsidian');
    FFilterOpts.Extra := Trim(FDialog.GetInputValue('extra'));
  end;
  FOptionsOpen := False;
  FDialog.Close;
  if Accepted then
    StartCompare;
end;

function SyncRootLabel(const APath: string): string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if Result = '' then
    Result := APath;
end;

procedure TDirSyncDialogController.BeginCompareJob;
begin
  Inc(FJobSeq);
  FJobKey := 'sync:' + IntToStr(FJobSeq);
  PluginJobBegin(cSyncJobOwner, FJobKey,
    T('ui.dirSync.jobTitle', 'Compare: %s - %s',
      [SyncRootLabel(FSrcRoot), SyncRootLabel(FDstRoot)]),
    procedure
    begin
      CancelCompare;
    end,
    procedure
    begin
      OpenCompareJob;
    end,
    procedure(AForeground: Boolean)
    begin
      FForeground := AForeground;
    end,
    False);
  // The progress dialog of the job is the window shown while the comparison
  // runs in front; its Background button hides it and leaves the chip.
  PluginJobSetForeground(PluginJobIdByKey(cSyncJobOwner, FJobKey), True);
end;

procedure TDirSyncDialogController.EndCompareJob;
begin
  if FJobKey <> '' then
    PluginJobEnd(cSyncJobOwner, FJobKey);
  FJobKey := '';
  FForeground := False;
  FResultReady := False;
end;

procedure TDirSyncDialogController.ShowProgress(AGen: Integer;
  AByContent: Boolean);
var
  Info: TSyncProgressInfo;
  Text: string;
begin
  if (AGen <> FCompareGen) or (FProgress = nil) then
    Exit;
  if Assigned(FOnAlive) and not FOnAlive() then
    Exit;
  Info := FProgress.Snapshot;
  Text := FormatSyncProgress(Info, AByContent);
  if FJobKey <> '' then
  begin
    PluginJobUpdate(cSyncJobOwner, FJobKey,
      Text + #10 + FitSyncPath(Info.Current, 70), SyncProgressPercent(Info));
    PluginJobSetBadge(cSyncJobOwner, FJobKey, SyncProgressBadge(Info));
  end
  else if Assigned(FDialog) and FDialog.Visible then
    FDialog.SetLabelText('status', Text);
end;

procedure TDirSyncDialogController.CancelCompare;
begin
  if FBusy and (FProgress <> nil) then
    FProgress.Cancel
  else if FResultReady then
  begin
    SetLength(FItems, 0);
    SetLength(FViewIdx, 0);
    EndCompareJob;
  end;
end;

procedure TDirSyncDialogController.OpenCompareJob;
begin
  if FResultReady then
  begin
    EndCompareJob;
    ShowCompareResult(FReadyByContent, True);
  end
  else if FBusy and (FJobKey <> '') then
  begin
    if Assigned(FOnPrepare) then
      FOnPrepare();
    PluginJobSetForeground(PluginJobIdByKey(cSyncJobOwner, FJobKey), True);
  end;
end;

procedure TDirSyncDialogController.StartCompare;
var
  Snap: TArray<TSyncSnapshotEntry>;
  Gen: Integer;
  ByContent: Boolean;
  Progress: ISyncProgress;
  Filter: ISyncFilter;
begin
  if FBusy then
    Exit;
  FBusy := True;
  Inc(FCompareGen);
  Gen := FCompareGen;
  ByContent := FByContent;
  Progress := NewSyncProgress;
  FProgress := Progress;
  Progress.SetOnChanged(
    procedure
    begin
      ShowProgress(Gen, ByContent);
    end);
  if Assigned(FDialog) and FDialog.Visible then
    FDialog.SetLabelText('status', T('ui.dirSync.comparing', 'Comparing...'))
  else
  begin
    BeginCompareJob;
    ShowProgress(Gen, ByContent);
  end;
  Snap := LoadDirSyncSnapshot(FSrcRoot, FDstRoot);
  if SyncFilterOptionsActive(FFilterOpts) then
    Filter := NewSyncFilter(FFilterOpts, [FSrcRoot, FDstRoot])
  else
    Filter := nil;
  CompareDirsTwoWayAsync(FSrcRoot, FDstRoot, Snap,
    procedure(const AItems: TArray<TSyncItem>; const AError: string)
    begin
      ApplyCompareResult(AItems, AError, ByContent, Gen);
    end, ByContent, Progress, Filter);
end;

procedure TDirSyncDialogController.ApplyCompareResult(
  const AItems: TArray<TSyncItem>; const AError: string;
  AByContent: Boolean; AGen: Integer);
var
  Stopped: Boolean;
begin
  if AGen <> FCompareGen then
    Exit;
  FBusy := False;
  Stopped := (FProgress <> nil) and FProgress.Cancelled;
  if FProgress <> nil then
    FProgress.SetOnChanged(nil);
  FProgress := nil;
  if Assigned(FOnAlive) and not FOnAlive() then
  begin
    EndCompareJob;
    Exit;
  end;
  if Stopped then
  begin
    EndCompareJob;
    Exit;
  end;
  if AError <> '' then
  begin
    EndCompareJob;
    if Assigned(FOnCloseStub) then
      FOnCloseStub();
    if Assigned(FOnOpenStub) then
      FOnOpenStub(T('ui.dirSync.titleFailed', 'Synchronize failed'), AError);
    Exit;
  end;
  FItems := AItems;
  FComparedByContent := AByContent;
  if (FJobKey <> '') and not FForeground then
  begin
    FResultReady := True;
    FReadyByContent := AByContent;
    FReadyAt := Now;
    PluginJobUpdate(cSyncJobOwner, FJobKey,
      T('ui.dirSync.readyJob', 'Done: %d differences', [Length(AItems)]), 100);
    PluginJobSetBadge(cSyncJobOwner, FJobKey, T('ui.dirSync.readyBadge', 'OK'));
    NoticeRequest(TNoticeRequest.Make('%s',
      T('ui.dirSync.readyNotice',
        'Folder comparison finished: %d differences', [Length(AItems)])));
    Exit;
  end;
  EndCompareJob;
  ShowCompareResult(AByContent, False);
end;

procedure TDirSyncDialogController.ShowCompareResult(AByContent,
  AFromBackground: Boolean);
var
  Preview: TArray<string>;
  Status: string;
begin
  if AFromBackground and Assigned(FOnPrepare) then
    FOnPrepare();
  FComparedByContent := AByContent;
  if Assigned(FDialog) and FDialog.Visible then
    ReadViewMode;
  Preview := FormatSyncPlanLines(FItems, FTwoWay, FOnlySkipped, FViewIdx,
    FMirror);
  if Assigned(FDialog) and FDialog.Visible then
  begin
    FDialog.SetLabelText('status',
      FormatDirSyncPlanStatus(FItems, FTwoWay, FMirror));
    FDialog.SetListItems('preview', Preview, 0);
  end
  else
  begin
    if Assigned(FOnCloseStub) then
      FOnCloseStub();
    if Assigned(FOnSetKind) then
      FOnSetKind(hdkDirSync);
    Status := FormatDirSyncPlanStatus(FItems, FTwoWay, FMirror);
    if AFromBackground then
      Status := Status + T('ui.dirSync.comparedAt', '  (compared at %s)',
        [FormatDateTime('hh:nn', FReadyAt)]);
    FDialog.Open(BuildDirSyncDialog(FitSyncPath(FSrcRoot, cDirSyncPathCells),
      FitSyncPath(FDstRoot, cDirSyncPathCells), Status, Preview, False, FTwoWay,
      AByContent), FOnCommand);
    RefreshPresetList('');
  end;
  if Assigned(FOnNotify) then
    FOnNotify();
  if Assigned(FDialog) and FDialog.Visible then
  begin
    FByContent := SameText(FDialog.GetRadio('compare_by'), 'bycontent');
    if FByContent <> FComparedByContent then
      StartCompare;
  end;
end;

procedure TDirSyncDialogController.ReadViewMode;
begin
  FTwoWay := SameText(FDialog.GetRadio('sync_mode'), 'twoway');
  FMirror := FDialog.GetCheckbox('mirror') and not FTwoWay;
  FOnlySkipped := FDialog.GetCheckbox('only_skipped');
end;

procedure TDirSyncDialogController.RefreshPlan(ASelect: Integer);
var
  Lines: TArray<string>;
  ScrollTop: Integer;
begin
  Lines := FormatSyncPlanLines(FItems, FTwoWay, FOnlySkipped, FViewIdx, FMirror);
  ScrollTop := FDialog.GetListScrollTop;
  FDialog.SetLabelText('status',
    FormatDirSyncPlanStatus(FItems, FTwoWay, FMirror));
  FDialog.SetListItems('preview', Lines, ASelect);
  FDialog.SetListScrollTop(ScrollTop);
end;

procedure TDirSyncDialogController.ApplyRowAction(AAction: TSyncAction);
var
  Sel, Idx: Integer;
begin
  if FBusy or not Assigned(FDialog) or not FDialog.Visible then
    Exit;
  Sel := FDialog.GetListSelectedIndex('preview');
  if (Sel < 0) or (Sel > High(FViewIdx)) then
    Exit;
  Idx := FViewIdx[Sel];
  if AAction = saAuto then
    FItems[Idx].Action := saAuto
  else if not ApplySyncAction(FItems[Idx], AAction) then
    Exit;
  ReadViewMode;
  // Move on to the next row so a run of decisions needs no navigation; in the
  // filtered view the decided row leaves the list and the next one slides in.
  if FOnlySkipped then
    RefreshPlan(Sel)
  else
    RefreshPlan(Sel + 1);
end;

function TDirSyncDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Action: TSyncAction;
begin
  Result := False;
  if (AShift * [ssShift, ssCtrl, ssAlt] <> []) or
     not SameText(FDialog.FocusedControlId, 'preview') then
    Exit;
  case AKey of
    vkRight: Action := saCopyRight;
    vkLeft: Action := saCopyLeft;
    vkDelete: Action := saAuto;
  else
    if AKeyChar = ' ' then
      Action := saSkip
    else if (AKeyChar = 'x') or (AKeyChar = 'X') then
      Action := saDelete
    else
      Exit;
  end;
  ApplyRowAction(Action);
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

procedure TDirSyncDialogController.NotifyDialogChanged;
var
  WantContent, OldTwoWay, OldOnlySkipped, OldMirror: Boolean;
  Idx: Integer;
begin
  if FBusy or FApplyingPreset or FOptionsOpen then
    Exit;
  if not Assigned(FDialog) or not FDialog.Visible then
    Exit;
  Idx := FDialog.GetListSelectedIndex('preset');
  if Idx <> FPresetIdx then
  begin
    FPresetIdx := Idx;
    if (Idx > 0) and (Idx <= Length(FPresets.Names)) then
      ApplyPreset(FPresets.Names[Idx - 1]);
  end;
  OldTwoWay := FTwoWay;
  OldMirror := FMirror;
  OldOnlySkipped := FOnlySkipped;
  ReadViewMode;
  // Deleting is never the first step: choosing the mirror mode turns on the
  // report-only run, which the user has to clear on purpose.
  if FMirror and not OldMirror then
    FDialog.SetCheckbox('dry_run', True);
  if (FTwoWay <> OldTwoWay) or (FMirror <> OldMirror) or
     (FOnlySkipped <> OldOnlySkipped) then
    RefreshPlan(0);
  WantContent := SameText(FDialog.GetRadio('compare_by'), 'bycontent');
  if WantContent = FComparedByContent then
    Exit;
  FByContent := WantContent;
  StartCompare;
end;

function TDirSyncDialogController.DispatchCommand(const AControlId: string;
  const AFields: TDialogCommandFields): Boolean;
var
  Accepted: Boolean;
  Sources, DestURIs: TArray<string>;
  Unresolved: Integer;
  CopyCount: Integer;
  Msg: string;
  Mirror, ToBin: Boolean;
  Deletes: TArray<string>;
begin
  Result := True;
  if FOptionsOpen then
  begin
    DispatchOptionsCommand(AControlId);
    Exit;
  end;
  if DialogCmdIs(AControlId, cDirSyncCmdRight) then
  begin
    ApplyRowAction(saCopyRight);
    Exit;
  end;
  if DialogCmdIs(AControlId, cDirSyncCmdLeft) then
  begin
    ApplyRowAction(saCopyLeft);
    Exit;
  end;
  if DialogCmdIs(AControlId, cDirSyncCmdSkip) then
  begin
    ApplyRowAction(saSkip);
    Exit;
  end;
  if DialogCmdIs(AControlId, cDirSyncCmdAuto) then
  begin
    ApplyRowAction(saAuto);
    Exit;
  end;
  if DialogCmdIs(AControlId, 'show_extras') then
  begin
    ShowExtras(AFields.SyncTwoWay);
    Exit;
  end;
  if DialogCmdIs(AControlId, 'preset_save') then
  begin
    SavePreset;
    Exit;
  end;
  if DialogCmdIs(AControlId, 'preset_del') then
  begin
    DeletePreset;
    Exit;
  end;
  Accepted := DialogCmdIsAccept(AControlId);
  Mirror := FDialog.GetCheckbox('mirror') and not AFields.SyncTwoWay;
  ToBin := not FDialog.GetCheckbox('del_perm');
  FDialog.Close;
  if Accepted then
  begin
    CollectDirSyncJobPairs(FItems, Sources, DestURIs, AFields.SyncTwoWay,
      Mirror);
    Deletes := CollectDirSyncDeletePaths(FItems, AFields.SyncTwoWay, Mirror);
    CopyCount := Length(Sources);
    Unresolved := Length(CollectDirSyncUnresolvedRels(FItems,
      AFields.SyncTwoWay, Mirror));
    if AFields.DryRun then
    begin
      if Unresolved > 0 then
        Msg := T('ui.dirSync.wouldCopyOpen',
          'Would copy %d file(s); %d item(s) left unresolved',
          [CopyCount, Unresolved])
      else
        Msg := T('ui.dirSync.wouldCopy', 'Would copy %d file(s)', [CopyCount]);
      if Length(Deletes) > 0 then
        Msg := Msg + T('ui.dirSync.wouldDelete', '; would delete %d file(s)',
          [Length(Deletes)]);
      if Assigned(FOnOpenStub) then
        FOnOpenStub(T('ui.dirSync.title', 'Synchronize'), Msg);
    end
    else if (CopyCount = 0) and (Length(Deletes) > 0) then
    begin
      FPendingDeletes := Deletes;
      FPendingDeleteToBin := ToBin;
      StartPendingDeletes;
    end
    else if CopyCount = 0 then
    begin
      if Unresolved > 0 then
        Msg := T('ui.dirSync.nothingOpen',
          'Nothing to copy; %d item(s) need a manual choice', [Unresolved])
      else
        Msg := T('ui.dirSync.nothing', 'Nothing to copy');
      if Assigned(FOnOpenStub) then
        FOnOpenStub(T('ui.dirSync.title', 'Synchronize'), Msg);
      try
        CommitDirSyncSnapshot(FSrcRoot, FDstRoot,
          CollectDirSyncUnresolvedRels(FItems, AFields.SyncTwoWay));
      except
      end;
    end
    else if Assigned(FJobs) and FJobs.CanStartAnother then
    begin
      FPendingConflictRels := CollectDirSyncUnresolvedRels(FItems,
        AFields.SyncTwoWay, Mirror);
      FSnapshotPending := True;
      // The removals wait for the copy: a failed copy leaves the target
      // untouched.
      FPendingDeletes := Deletes;
      FPendingDeleteToBin := ToBin;
      FJobs.BeginJobPairs(Sources, DestURIs, pjkCopy);
    end;
  end;
  SetLength(FItems, 0);
  SetLength(FViewIdx, 0);
end;

// The delete job asks its own confirmation (with the count and whether the
// files go to the Recycle Bin) before anything is removed.
procedure TDirSyncDialogController.StartPendingDeletes;
var
  Paths: TArray<string>;
begin
  Paths := FPendingDeletes;
  SetLength(FPendingDeletes, 0);
  if (Length(Paths) > 0) and Assigned(FJobs) and FJobs.CanStartAnother then
    FJobs.BeginJob(Paths, '', pjkDelete, FPendingDeleteToBin);
end;

procedure TDirSyncDialogController.NotifyJobFinished(ASuccess: Boolean);
begin
  if not FSnapshotPending then
    Exit;
  FSnapshotPending := False;
  if not ASuccess then
  begin
    SetLength(FPendingConflictRels, 0);
    SetLength(FPendingDeletes, 0);
    Exit;
  end;
  try
    CommitDirSyncSnapshot(FSrcRoot, FDstRoot, FPendingConflictRels);
  except
  end;
  SetLength(FPendingConflictRels, 0);
  StartPendingDeletes;
end;

end.
