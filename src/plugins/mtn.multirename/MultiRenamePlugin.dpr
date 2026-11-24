library MultiRenamePlugin;

{ Native MTN2 plugin: Files > Multi-rename renames the selected items of a
  folder by rules (name and extension masks, search and replace, counter,
  letter case) with a live preview of every old -> new pair. The names can also
  be typed by hand in the editor. The host applies the batch as a background
  job and keeps the journal for Undo last. }

uses
  System.SysUtils, System.Classes, System.JSON, System.Math, System.StrUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uMultiRename in 'uMultiRename.pas';

const
  cPluginId = 'mtn.multirename';
  cCommandId = 'multirename.run';
  cKeyChord = 'Ctrl+Alt+N';
  cDialogWidth = 100;
  cMarkCols = 2;     // "! " in front of a row with a problem
  cSepCols = 3;      // " | " between the columns
  cNoteCols = 20;

var
  GHostApi: THostApiTable;
  GShutdown: Boolean;
  GSources: TArray<string>;
  GNames: TArray<string>;
  GIsDir: TArray<Boolean>;
  GInfos: TArray<TRenameItemInfo>;
  GExisting: TArray<string>;
  GDirUri: string;
  GRules: TMultiRenameRules;
  GManualNames: TArray<string>;
  GNameCols: Integer;
  GPendingStatus: string;
  GReply: UTF8String;
  GEditing: Boolean;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..255] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHostApi.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure Notice(const AText: string; AKind: Int64);
var
  Text: UTF8String;
begin
  if not Assigned(GHostApi.ShowMessage) then
    Exit;
  Text := UTF8String(AText);
  GHostApi.ShowMessage(PAnsiChar(Text), AKind);
end;

function HostText(AFn: THostTextOutFn): string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if not Assigned(AFn) then
    Exit;
  Len := AFn(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := AFn(PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

function HostPanelListText: string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if not Assigned(GHostApi.PanelList) then
    Exit;
  Len := GHostApi.PanelList(-1, nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelList(-1, PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

{ ---- dialog ------------------------------------------------------------- }

function CaseCaptions: TArray<string>;
begin
  Result := [
    Tr('dlg.caseKeep', 'Unchanged'),
    Tr('dlg.caseLower', 'lower case'),
    Tr('dlg.caseUpper', 'UPPER CASE'),
    Tr('dlg.caseFirst', 'First letter upper'),
    Tr('dlg.caseWords', 'Each Word Upper')];
end;

function Cell(const AText: string; AWidth: Integer): string;
begin
  if Length(AText) > AWidth then
    Result := Copy(AText, 1, Max(AWidth - 1, 0)) + '~'
  else
    Result := AText + StringOfChar(' ', AWidth - Length(AText));
end;

function ColumnsText: string;
begin
  Result := Cell('', cMarkCols) + Cell(Tr('dlg.colOld', 'Old name'), GNameCols) + ' | ' +
    Cell(Tr('dlg.colNew', 'New name'), GNameCols) + ' | ' + Tr('dlg.colNote', 'Note');
end;

procedure AddItem(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth, AHeight: Integer; ADefault: Boolean = False; ACancel: Boolean = False);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(AHeight));
  AChildren.AddElement(O);
end;

procedure AddField(AChildren: TJSONArray; const AId, AValue: string;
  ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'input');
  O.AddPair('id', AId);
  O.AddPair('value', AValue);
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

procedure AddCheck(AChildren: TJSONArray; const AId, AText: string; AChecked: Boolean;
  ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'checkbox');
  O.AddPair('id', AId);
  O.AddPair('text', AText);
  O.AddPair('checked', TJSONBool.Create(AChecked));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

function BuildDeclaration: TJSONObject;
const
  cHalf = (cDialogWidth - 4) div 2;
  cRightLabel = cHalf + 3;
  cRightInput = cHalf + 15;
var
  Kids, Items: TJSONArray;
  Drop, List: TJSONObject;
  Cap: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'dialog');
  Result.AddPair('version', '2.0');
  Result.AddPair('title', Tr('dlg.title', 'Multi-rename'));
  Result.AddPair('width', TJSONNumber.Create(cDialogWidth));
  Result.AddPair('height', TJSONNumber.Create(29));
  Kids := TJSONArray.Create;
  Result.AddPair('children', Kids);
  AddItem(Kids, 'label', 'lbl_name_mask', Tr('dlg.nameMask', 'Name mask:'), 1, 1, 14, 1);
  AddField(Kids, 'name_mask', GRules.NameMask, 16, 1, cHalf - 17);
  AddItem(Kids, 'label', 'lbl_ext_mask', Tr('dlg.extMask', 'Extension:'), cRightLabel, 1, 11, 1);
  AddField(Kids, 'ext_mask', GRules.ExtMask, cRightInput, 1, cDialogWidth - 2 - cRightInput);
  AddItem(Kids, 'label', 'lbl_search', Tr('dlg.search', 'Search:'), 1, 3, 14, 1);
  AddField(Kids, 'search', GRules.Search, 16, 3, cHalf - 17);
  AddItem(Kids, 'label', 'lbl_replace', Tr('dlg.replace', 'Replace:'), cRightLabel, 3, 11, 1);
  AddField(Kids, 'replace', GRules.Replace, cRightInput, 3, cDialogWidth - 2 - cRightInput);
  AddItem(Kids, 'label', 'lbl_counter', Tr('dlg.counter', 'Counter from:'), 1, 5, 14, 1);
  AddField(Kids, 'c_start', IntToStr(GRules.CounterStart), 16, 5, 6);
  AddItem(Kids, 'label', 'lbl_step', Tr('dlg.step', 'step:'), 24, 5, 6, 1);
  AddField(Kids, 'c_step', IntToStr(GRules.CounterStep), 31, 5, 5);
  AddItem(Kids, 'label', 'lbl_digits', Tr('dlg.digits', 'digits:'), 38, 5, 7, 1);
  AddField(Kids, 'c_digits', IntToStr(GRules.CounterDigits), 46, 5, 4);
  AddCheck(Kids, 'match_case', Tr('dlg.matchCase', 'Match &case'), GRules.MatchCase,
    cRightLabel, 5, cDialogWidth - 2 - cRightLabel);
  AddItem(Kids, 'label', 'lbl_case', Tr('dlg.letterCase', 'Letter case:'), 1, 7, 14, 1);
  Drop := TJSONObject.Create;
  Drop.AddPair('type', 'dropdown');
  Drop.AddPair('id', 'case_mode');
  Drop.AddPair('selected', TJSONNumber.Create(Ord(GRules.CaseMode)));
  Items := TJSONArray.Create;
  for Cap in CaseCaptions do
    Items.Add(Cap);
  Drop.AddPair('items', Items);
  Drop.AddPair('col', TJSONNumber.Create(16));
  Drop.AddPair('row', TJSONNumber.Create(7));
  Drop.AddPair('width', TJSONNumber.Create(cHalf - 17));
  Drop.AddPair('height', TJSONNumber.Create(1));
  Kids.AddElement(Drop);
  AddCheck(Kids, 'use_regex', Tr('dlg.regex', 'Regular e&xpression'), GRules.UseRegex,
    cRightLabel, 7, cDialogWidth - 2 - cRightLabel);
  AddItem(Kids, 'label', 'lbl_tokens', Tr('dlg.tokens',
    'Tokens: [N] [E] [C] [Date] [Time] [Year] [Month] [Day] [Parent] [Size] [Dim] [Camera] [Artist] [Title]'),
    1, 8, cDialogWidth - 4, 1);
  AddItem(Kids, 'label', 'status', GPendingStatus, 1, 9, cDialogWidth - 4, 1);
  AddItem(Kids, 'label', 'columns', ColumnsText, 1, 10, cDialogWidth - 4, 1);
  List := TJSONObject.Create;
  List.AddPair('type', 'list');
  List.AddPair('id', 'preview');
  List.AddPair('selected', TJSONNumber.Create(0));
  Items := TJSONArray.Create;
  Items.Add('');
  List.AddPair('items', Items);
  List.AddPair('col', TJSONNumber.Create(1));
  List.AddPair('row', TJSONNumber.Create(11));
  List.AddPair('width', TJSONNumber.Create(cDialogWidth - 4));
  List.AddPair('height', TJSONNumber.Create(11));
  Kids.AddElement(List);
  AddItem(Kids, 'separator', '', '', 0, 23, cDialogWidth - 2, 1);
  AddItem(Kids, 'button', 'undo', Tr('dlg.undo', '&Undo last'), 1, 25, 17, 1);
  AddItem(Kids, 'button', 'editor', Tr('dlg.editor', 'In &editor'), 20, 25, 17, 1);
  AddItem(Kids, 'button', 'ok', Tr('dlg.ok', 'Rename'), cDialogWidth div 2 - 12, 25, 12, 1, True);
  AddItem(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), cDialogWidth div 2 + 2, 25, 12, 1,
    False, True);
end;

{ ---- plan --------------------------------------------------------------- }

function RulesFromValues(ARoot: TJSONObject): TMultiRenameRules;
var
  S: string;
  B: Boolean;
  I, Mode: Integer;
  Caps: TArray<string>;
begin
  Result := GRules;
  if ARoot.TryGetValue<string>('name_mask', S) then
    Result.NameMask := S;
  if ARoot.TryGetValue<string>('ext_mask', S) then
    Result.ExtMask := S;
  if ARoot.TryGetValue<string>('search', S) then
    Result.Search := S;
  if ARoot.TryGetValue<string>('replace', S) then
    Result.Replace := S;
  if ARoot.TryGetValue<Boolean>('match_case', B) then
    Result.MatchCase := B;
  if ARoot.TryGetValue<Boolean>('use_regex', B) then
    Result.UseRegex := B;
  if ARoot.TryGetValue<string>('c_start', S) then
    Result.CounterStart := StrToIntDef(Trim(S), 1);
  if ARoot.TryGetValue<string>('c_step', S) then
    Result.CounterStep := StrToIntDef(Trim(S), 1);
  if ARoot.TryGetValue<string>('c_digits', S) then
    Result.CounterDigits := EnsureRange(StrToIntDef(Trim(S), 1), 1, 12);
  if ARoot.TryGetValue<string>('case_mode', S) then
  begin
    Caps := CaseCaptions;
    Mode := 0;
    for I := 0 to High(Caps) do
      if Caps[I] = S then
        Mode := I;
    Result.CaseMode := TRenameCase(EnsureRange(Mode, Ord(Low(TRenameCase)), Ord(High(TRenameCase))));
  end;
end;

function ParseRules(const AValuesJson: string): TMultiRenameRules;
var
  Root: TJSONValue;
begin
  Result := GRules;
  Root := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if Root is TJSONObject then
      Result := RulesFromValues(TJSONObject(Root));
  finally
    Root.Free;
  end;
end;

function CurrentPlan(const ARules: TMultiRenameRules): TRenamePlan;
begin
  if Length(GManualNames) = Length(GNames) then
    Result := PlanRenameTo(GNames, GManualNames, GExisting)
  else
    Result := PlanMultiRename(GNames, GIsDir, GExisting, ARules, GInfos);
end;

function ProblemText(AProblem: TRenameProblem): string;
begin
  case AProblem of
    rpEmpty: Result := Tr('msg.problemEmpty', 'empty name');
    rpInvalid: Result := Tr('msg.problemInvalid', 'invalid name');
    rpDuplicate: Result := Tr('msg.problemDuplicate', 'same name twice');
    rpExists: Result := Tr('msg.problemExists', 'name is taken');
  else
    Result := '';
  end;
end;

{ What the dialog shows for ARules: the status line and the preview list, as
  the JSON the host applies. }
function PreviewJson(const ARules: TMultiRenameRules; const AStatusOverride: string): string;
var
  Plan: TRenamePlan;
  Root, LabelsObj, ListsObj, ListObj: TJSONObject;
  Items, Accents, Mark: TJSONArray;
  I, Unchanged, Blocked, Prefix, Suffix, ChangedLen, NewCol, NoteCol, NoteWidth: Integer;
  OldName, NewName, Note, Status: string;

  procedure AddAccent(AItem, ACol, ALen: Integer);
  begin
    if ALen <= 0 then
      Exit;
    Mark := TJSONArray.Create;
    Mark.Add(AItem);
    Mark.Add(ACol);
    Mark.Add(ALen);
    Accents.AddElement(Mark);
  end;

begin
  Plan := CurrentPlan(ARules);
  NoteWidth := cNoteCols;
  Items := TJSONArray.Create;
  Accents := TJSONArray.Create;
  Unchanged := 0;
  Blocked := 0;
  NewCol := cMarkCols + GNameCols + cSepCols;
  NoteCol := NewCol + GNameCols + cSepCols;
  for I := 0 to High(Plan) do
  begin
    OldName := Plan[I].OldName;
    NewName := Plan[I].NewName;
    Note := '';
    case Plan[I].Problem of
      rpNone: ;
      rpUnchanged:
        begin
          Inc(Unchanged);
          NewName := '';
        end;
    else
      Note := ProblemText(Plan[I].Problem);
      Inc(Blocked);
    end;
    Items.Add(Cell(IfThen(Plan[I].Problem in [rpNone, rpUnchanged], '', '!'), cMarkCols) +
      Cell(OldName, GNameCols) + ' | ' + Cell(NewName, GNameCols) + ' | ' + Cell(Note, NoteWidth));
    // The stretch of the new name that differs from the original name: what
    // lies between their common beginning and common end.
    if NewName <> '' then
    begin
      Prefix := 0;
      while (Prefix < Length(OldName)) and (Prefix < Length(NewName)) and
            (OldName[Prefix + 1] = NewName[Prefix + 1]) do
        Inc(Prefix);
      Suffix := 0;
      while (Suffix < Length(OldName) - Prefix) and (Suffix < Length(NewName) - Prefix) and
            (OldName[Length(OldName) - Suffix] = NewName[Length(NewName) - Suffix]) do
        Inc(Suffix);
      ChangedLen := Length(NewName) - Prefix - Suffix;
      AddAccent(I, NewCol + Prefix, Min(ChangedLen, GNameCols - Prefix));
    end;
    if Note <> '' then
      AddAccent(I, NoteCol, Min(Length(Note), NoteWidth));
  end;
  if AStatusOverride <> '' then
    Status := AStatusOverride
  else
    Status := Format(Tr('msg.status', '%d to rename, %d unchanged, %d with a problem'),
      [RenamePlanChangeCount(Plan), Unchanged, Blocked]);
  Root := TJSONObject.Create;
  try
    LabelsObj := TJSONObject.Create;
    LabelsObj.AddPair('status', Status);
    Root.AddPair('labels', LabelsObj);
    ListObj := TJSONObject.Create;
    ListObj.AddPair('items', Items);
    ListObj.AddPair('selected', TJSONNumber.Create(0));
    ListObj.AddPair('accents', Accents);
    ListsObj := TJSONObject.Create;
    ListsObj.AddPair('preview', ListObj);
    Root.AddPair('lists', ListsObj);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function OnDialogChange(AUserData: Pointer; AValuesJson: PAnsiChar): PAnsiChar; cdecl;
var
  Rules: TMultiRenameRules;
  Status: string;
begin
  GReply := '';
  try
    if AValuesJson <> nil then
    begin
      Rules := ParseRules(UTF8ToString(AValuesJson));
      GRules := Rules;
      Status := GPendingStatus;
      GPendingStatus := '';
      GReply := UTF8String(PreviewJson(Rules, Status));
    end;
  except
    GReply := '';
  end;
  if GReply = '' then
    Result := nil
  else
    Result := PAnsiChar(GReply);
end;

{ ---- commands ----------------------------------------------------------- }

procedure ShowDialogNow; forward;

procedure OnNamesEdited(AUserData: Pointer; AText: PAnsiChar); cdecl;
var
  Names: TArray<string>;
begin
  try
    GEditing := False;
    if GShutdown then
      Exit;
    if (AText <> nil) and ParseRenameLines(UTF8ToString(AText), Length(GNames), Names) then
      GManualNames := Names
    else
      GPendingStatus := Format(Tr('msg.linesChanged',
        'The number of lines must stay %d: one new name per item'), [Length(GNames)]);
    ShowDialogNow;
  except
    // Never let an exception cross into the host.
  end;
end;

procedure BeginEditInEditor;
var
  Plan: TRenamePlan;
  Names: TArray<string>;
  I: Integer;
  Text: UTF8String;
begin
  Plan := CurrentPlan(GRules);
  SetLength(Names, Length(Plan));
  for I := 0 to High(Plan) do
    Names[I] := Plan[I].NewName;
  Text := UTF8String(RenameLinesText(Names));
  GEditing := True;
  if not Assigned(GHostApi.EditText) or
     (GHostApi.EditText(PAnsiChar(UTF8String(cPluginId)), PAnsiChar(Text), @OnNamesEdited, nil) <> 0) then
  begin
    GEditing := False;
    ShowDialogNow;
  end;
end;

function BatchJson: string;
var
  Plan: TRenamePlan;
  Root, Pair: TJSONObject;
  Pairs: TJSONArray;
  I: Integer;
begin
  Plan := CurrentPlan(GRules);
  Root := TJSONObject.Create;
  try
    Pairs := TJSONArray.Create;
    Root.AddPair('pairs', Pairs);
    for I := 0 to High(Plan) do
      if Plan[I].Problem = rpNone then
      begin
        Pair := TJSONObject.Create;
        Pair.AddPair('from', GSources[I]);
        Pair.AddPair('to', JoinFileUri(GDirUri, Plan[I].NewName));
        Pairs.AddElement(Pair);
      end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure OnDialogCommand(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Id: string;
  Plan: TRenamePlan;
  Json, Plugin: UTF8String;
begin
  try
    if GShutdown then
      Exit;
    Id := string(AControlId);
    if AValuesJson <> nil then
      GRules := ParseRules(UTF8ToString(AValuesJson));
    if SameText(Id, 'editor') then
    begin
      BeginEditInEditor;
      Exit;
    end;
    Plugin := UTF8String(cPluginId);
    if SameText(Id, 'undo') then
    begin
      if not Assigned(GHostApi.RenameUndo) or (GHostApi.RenameUndo(PAnsiChar(Plugin)) <> 0) then
        Notice(Tr('msg.busy', 'Another job is already running'), 1);
      Exit;
    end;
    if not SameText(Id, 'ok') then
      Exit;
    Plan := CurrentPlan(GRules);
    if RenamePlanBlocked(Plan) then
    begin
      GPendingStatus := Tr('msg.blocked', 'Fix the names marked with ! first');
      ShowDialogNow;
      Exit;
    end;
    if RenamePlanChangeCount(Plan) = 0 then
      Exit;
    Json := UTF8String(BatchJson);
    if not Assigned(GHostApi.RenameBatch) or
       (GHostApi.RenameBatch(PAnsiChar(Plugin), PAnsiChar(Json)) <> 0) then
      Notice(Tr('msg.busy', 'Another job is already running'), 1);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure ShowDialogNow;
var
  Decl: TJSONObject;
  Json, Plugin: UTF8String;
begin
  GNameCols := (cDialogWidth - 4 - 1 - cMarkCols - 2 * cSepCols - cNoteCols) div 2;
  Decl := BuildDeclaration;
  try
    Json := UTF8String(Decl.ToJSON);
  finally
    Decl.Free;
  end;
  Plugin := UTF8String(cPluginId);
  if not Assigned(GHostApi.ShowDialogLive) or
     (GHostApi.ShowDialogLive(PAnsiChar(Plugin), PAnsiChar(Json), @OnDialogCommand,
       @OnDialogChange, nil) <> 0) then
    Notice(Tr('msg.noDialog', 'The dialog cannot be shown now'), 1);
end;

function FolderName(const AFolderUri: string): string;
var
  Path: string;
  P: Integer;
begin
  Path := ExcludeTrailingPathDelimiter(AFolderUri);
  P := LastDelimiter('/\', Path);
  Result := Copy(Path, P + 1, MaxInt);
end;

function StripSlash(const AName: string): string;
begin
  Result := AName;
  if (Result <> '') and (Result[Length(Result)] = '/') then
    Delete(Result, Length(Result), 1);
end;

{ Reads the panel: the selected rows of the active panel (or the row under the
  cursor) become the batch, every name of the folder is what a new name may
  not collide with. False, with a message shown, when there is nothing to do. }
function CollectBatch: Boolean;
var
  List, Info, Side: TJSONValue;
  Rows, Selected: TJSONArray;
  Row: TJSONValue;
  Sel: TArray<string>;
  Uri, Name, ActiveSide: string;
  Cursor, I, J, N: Integer;
  IsDir: Boolean;
  Info1: TRenameItemInfo;
  Cols: TJSONValue;
  M: Double;
  Size: Int64;
  S: string;
begin
  Result := False;
  GSources := nil;
  GNames := nil;
  GIsDir := nil;
  GInfos := nil;
  GExisting := nil;
  GManualNames := nil;
  List := TJSONObject.ParseJSONValue(HostPanelListText);
  Info := TJSONObject.ParseJSONValue(HostText(GHostApi.PanelInfo));
  try
    if not (List is TJSONObject) or not (Info is TJSONObject) or
       not TJSONObject(List).TryGetValue<string>('uri', GDirUri) or
       not TJSONObject(List).TryGetValue<TJSONArray>('rows', Rows) then
    begin
      Notice(Tr('msg.nothingSelected', 'Select files or folders first'), 1);
      Exit;
    end;
    if TJSONObject(Info).TryGetValue<string>('active', ActiveSide) then
    begin
      Side := TJSONObject(Info).GetValue(ActiveSide);
      if (Side is TJSONObject) and TJSONObject(Side).TryGetValue<TJSONArray>('selected', Selected) then
        for I := 0 to Selected.Count - 1 do
          Sel := Sel + [Selected.Items[I].Value];
    end;
    if (Length(Sel) = 0) and TJSONObject(List).TryGetValue<Integer>('cursor', Cursor) and
       (Cursor >= 0) and (Cursor < Rows.Count) and (Rows.Items[Cursor] is TJSONObject) and
       TJSONObject(Rows.Items[Cursor]).TryGetValue<string>('uri', Uri) then
      Sel := [Uri];
    if Length(Sel) = 0 then
    begin
      Notice(Tr('msg.nothingSelected', 'Select files or folders first'), 1);
      Exit;
    end;
    for Uri in Sel do
      if ParentFileUri(Uri) <> ParentFileUri(Sel[0]) then
      begin
        Notice(Tr('msg.oneFolder', 'Select items of one folder'), 1);
        Exit;
      end;
    for Row in Rows do
      if (Row is TJSONObject) and TJSONObject(Row).TryGetValue<string>('name', Name) then
        GExisting := GExisting + [StripSlash(Name)];
    for J := 0 to High(Sel) do
    begin
      N := -1;
      for I := 0 to Rows.Count - 1 do
        if (Rows.Items[I] is TJSONObject) and
           TJSONObject(Rows.Items[I]).TryGetValue<string>('uri', Uri) and (Uri = Sel[J]) then
        begin
          N := I;
          Break;
        end;
      if N < 0 then
      begin
        Notice(Tr('msg.nothingSelected', 'Select files or folders first'), 1);
        Exit;
      end;
      Row := Rows.Items[N];
      Name := '';
      TJSONObject(Row).TryGetValue<string>('name', Name);
      IsDir := False;
      TJSONObject(Row).TryGetValue<Boolean>('dir', IsDir);
      Name := StripSlash(Name);
      Info1 := EmptyRenameItemInfo;
      if TJSONObject(Row).TryGetValue<Double>('mtime', M) then
        Info1.Modified := M;
      if (not IsDir) and TJSONObject(Row).TryGetValue<Int64>('size', Size) then
        Info1.Size := Size;
      Info1.Parent := FolderName(GDirUri);
      Cols := TJSONObject(Row).GetValue('cols');
      if Cols is TJSONObject then
      begin
        if TJSONObject(Cols).TryGetValue<string>('dim', S) then
          Info1.Dim := S;
        if TJSONObject(Cols).TryGetValue<string>('camera', S) then
          Info1.Camera := S;
        if TJSONObject(Cols).TryGetValue<string>('artist', S) then
          Info1.Artist := S;
        if TJSONObject(Cols).TryGetValue<string>('title', S) then
          Info1.Title := S;
      end;
      GSources := GSources + [Sel[J]];
      GNames := GNames + [Name];
      GIsDir := GIsDir + [IsDir];
      GInfos := GInfos + [Info1];
    end;
    Result := True;
  finally
    List.Free;
    Info.Free;
  end;
end;

procedure CmdRun(AUserData: Pointer); cdecl;
begin
  try
    if GEditing then
      Exit;
    if not CollectBatch then
      Exit;
    GRules := DefaultMultiRenameRules;
    GPendingStatus := '';
    ShowDialogNow;
  except
    // Never let an exception cross into the host.
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  PluginId, CommandId, Chord: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 13) or not Assigned(AHostApi.PanelInfo) or
     not Assigned(AHostApi.PanelList) or not Assigned(AHostApi.ShowDialogLive) or
     not Assigned(AHostApi.RegisterCommand) then
    Exit(-1);
  GHostApi := AHostApi^;
  GShutdown := False;
  GEditing := False;
  PluginId := UTF8String(cPluginId);
  CommandId := UTF8String(cCommandId);
  Chord := UTF8String(cKeyChord);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(CommandId), @CmdRun, nil);
  if Assigned(GHostApi.RegisterKeyBinding) then
    GHostApi.RegisterKeyBinding(PAnsiChar(PluginId), PAnsiChar(CommandId), PAnsiChar(Chord));
  if Assigned(GHostApi.RegisterMenuItem) then
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Files', PAnsiChar(CommandId),
      PAnsiChar(UTF8String(Tr('menu.run', 'Multi-rename...'))), @CmdRun, nil, 45);
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GShutdown := True;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
