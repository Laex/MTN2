unit uEditorDialogs;

{ Ask-save / encoding / goto / replace dialogs. Extracted from TEditorWindow
  so the host keeps thin Open* forwards and Confirm* callbacks. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDialogJson, uTextEncoding;

type
  TEditorAskSaveAction = (esaCancel, esaYes, esaNo);
  TEditorReplaceAction = (eraNone, eraOne, eraAll);

  TEditorNotifyProc = reference to procedure;
  TEditorGotoLineProc = reference to procedure(ALine1Based: Integer);
  TEditorRequestEncodingProc = reference to procedure(AEncoding: TTextFileEncoding);
  TEditorReplaceProc = reference to procedure(const AFind, AReplace: string;
    AAll: Boolean);

  TEditorDialogController = class
  private
    FDialog: TDialogHost;
    FOnNotify: TEditorNotifyProc;
    FOnSetConfirmNone: TEditorNotifyProc;
    FOnSaveAndMaybeClose: TEditorNotifyProc;
    FOnForceClose: TEditorNotifyProc;
    FOnGotoLine: TEditorGotoLineProc;
    FOnApplyPendingEncoding: TEditorNotifyProc;
    FOnRequestEncoding: TEditorRequestEncodingProc;
    FOnReplace: TEditorReplaceProc;
    procedure Notify;
    procedure ClearConfirm;
    procedure CloseDialog;
  public
    constructor Create(ADialog: TDialogHost;
      const AOnNotify, AOnSetConfirmNone, AOnSaveAndMaybeClose,
      AOnForceClose: TEditorNotifyProc;
      const AOnGotoLine: TEditorGotoLineProc;
      const AOnApplyPendingEncoding: TEditorNotifyProc;
      const AOnRequestEncoding: TEditorRequestEncodingProc;
      const AOnReplace: TEditorReplaceProc);
    procedure OpenAskSave(const AFileName: string);
    procedure OpenDiscardEncoding;
    procedure OpenGoto(ALine1Based: Integer);
    procedure OpenEncoding(const ACurrentName: string);
    procedure OpenReplace(const AFindText: string);
    procedure AskSaveCommand(const AControlId, AValuesJson: string);
    procedure DiscardEncodingCommand(const AControlId, AValuesJson: string);
    procedure GotoLineCommand(const AControlId, AValuesJson: string);
    procedure EncodingDialogCommand(const AControlId, AValuesJson: string);
    procedure ReplaceDialogCommand(const AControlId, AValuesJson: string);
    function HandleAskSaveInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
  end;

function EditorAskSaveHotkey(AKey: Word; AKeyChar: Char): string;
function EditorAskSaveAction(const AControlId: string): TEditorAskSaveAction;
function EditorReplaceAction(const AControlId: string): TEditorReplaceAction;
function EditorReplaceShouldRun(const AControlId, AFindText: string): Boolean;
function EditorEncodingAccepted(const AControlId: string): Boolean;
procedure EditorMergeEncodingJson(const AValuesJson: string; var AName: string;
  var AIdx: Integer);

implementation

uses
  System.JSON, uStrings;

function EditorAskSaveHotkey(AKey: Word; AKeyChar: Char): string;
var
  Ch: Char;
begin
  // Physical Latin keys — layout-independent (Y/S=Yes, N/D=No).
  case AKey of
    Ord('Y'), Ord('y'), Ord('S'), Ord('s'):
      Exit(cDlgCmdYes);
    Ord('N'), Ord('n'), Ord('D'), Ord('d'):
      Exit(cDlgCmdNo);
  end;
  // Typed glyph: Latin fallback + Cyrillic Да/Нет.
  Ch := AKeyChar;
  if (Ch >= 'a') and (Ch <= 'z') then
    Ch := UpCase(Ch);
  if (Ch = 'Y') or (Ch = 'S') or (Ch = #$0414) or (Ch = #$0434) then // Д/д
    Exit(cDlgCmdYes);
  if (Ch = 'N') or (Ch = 'D') or (Ch = #$041D) or (Ch = #$043D) then // Н/н
    Exit(cDlgCmdNo);
  Result := '';
end;

function EditorAskSaveAction(const AControlId: string): TEditorAskSaveAction;
begin
  if DialogCmdIsYes(AControlId) then
    Result := esaYes
  else if DialogCmdIsNo(AControlId) then
    Result := esaNo
  else
    Result := esaCancel;
end;

function EditorReplaceAction(const AControlId: string): TEditorReplaceAction;
begin
  if DialogCmdIs(AControlId, cDlgCmdReplaceOne) then
    Result := eraOne
  else if DialogCmdIs(AControlId, cDlgCmdReplaceAll) then
    Result := eraAll
  else
    Result := eraNone;
end;

function EditorReplaceShouldRun(const AControlId, AFindText: string): Boolean;
begin
  Result := (EditorReplaceAction(AControlId) <> eraNone) and (Trim(AFindText) <> '');
end;

function EditorEncodingAccepted(const AControlId: string): Boolean;
begin
  Result := DialogCmdIsAccept(AControlId) or DialogCmdIs(AControlId, 'encoding');
end;

procedure EditorMergeEncodingJson(const AValuesJson: string; var AName: string;
  var AIdx: Integer);
var
  Root: TJSONValue;
  Obj: TJSONObject;
  V: TJSONValue;
begin
  if Trim(AValuesJson) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AValuesJson);
  if not Assigned(Root) then
    Exit;
  try
    if Root is TJSONObject then
    begin
      Obj := TJSONObject(Root);
      V := Obj.Values['encoding'];
      if V is TJSONString then
        AName := TJSONString(V).Value
      else if V is TJSONNumber then
        AIdx := TJSONNumber(V).AsInt;
    end;
  finally
    Root.Free;
  end;
end;

constructor TEditorDialogController.Create(ADialog: TDialogHost;
  const AOnNotify, AOnSetConfirmNone, AOnSaveAndMaybeClose,
  AOnForceClose: TEditorNotifyProc;
  const AOnGotoLine: TEditorGotoLineProc;
  const AOnApplyPendingEncoding: TEditorNotifyProc;
  const AOnRequestEncoding: TEditorRequestEncodingProc;
  const AOnReplace: TEditorReplaceProc);
begin
  inherited Create;
  FDialog := ADialog;
  FOnNotify := AOnNotify;
  FOnSetConfirmNone := AOnSetConfirmNone;
  FOnSaveAndMaybeClose := AOnSaveAndMaybeClose;
  FOnForceClose := AOnForceClose;
  FOnGotoLine := AOnGotoLine;
  FOnApplyPendingEncoding := AOnApplyPendingEncoding;
  FOnRequestEncoding := AOnRequestEncoding;
  FOnReplace := AOnReplace;
end;

procedure TEditorDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TEditorDialogController.ClearConfirm;
begin
  if Assigned(FOnSetConfirmNone) then
    FOnSetConfirmNone();
end;

procedure TEditorDialogController.CloseDialog;
begin
  if Assigned(FDialog) then
    FDialog.Close;
end;

procedure TEditorDialogController.OpenAskSave(const AFileName: string);
begin
  // Open declaration directly (no JSON round-trip) so button ids / default /
  // cancel flags stay intact for AskSaveCommand.
  FDialog.Open(BuildAskSaveDialog(AFileName), AskSaveCommand);
  Notify;
end;

procedure TEditorDialogController.OpenDiscardEncoding;
begin
  FDialog.Open(BuildConfirmDialog(T('ui.editor.reloadEncodingTitle', 'Reload encoding?'),
    T('ui.editor.reloadEncodingMsg', 'Discard unsaved changes and re-decode?')), DiscardEncodingCommand);
  Notify;
end;

procedure TEditorDialogController.OpenGoto(ALine1Based: Integer);
begin
  if not FDialog.OpenJson(DeclarationToJson(BuildGotoLineDialog(ALine1Based)),
      GotoLineCommand) then
    FDialog.Open(BuildGotoLineDialog(ALine1Based), GotoLineCommand);
  Notify;
end;

procedure TEditorDialogController.OpenEncoding(const ACurrentName: string);
begin
  // Prefer in-process declaration (avoids JSON list round-trip).
  FDialog.Open(BuildEncodingDialog(ACurrentName), EncodingDialogCommand);
  Notify;
end;

procedure TEditorDialogController.OpenReplace(const AFindText: string);
begin
  FDialog.Open(BuildReplaceDialog(AFindText, ''), ReplaceDialogCommand);
  Notify;
end;

procedure TEditorDialogController.AskSaveCommand(const AControlId, AValuesJson: string);
begin
  ClearConfirm;
  CloseDialog;
  case EditorAskSaveAction(AControlId) of
    esaYes:
      if Assigned(FOnSaveAndMaybeClose) then
        FOnSaveAndMaybeClose();
    esaNo:
      if Assigned(FOnForceClose) then
        FOnForceClose();
  else
    Notify;
  end;
end;

procedure TEditorDialogController.DiscardEncodingCommand(const AControlId,
  AValuesJson: string);
begin
  ClearConfirm;
  CloseDialog;
  if DialogCmdIsAccept(AControlId) and Assigned(FOnApplyPendingEncoding) then
    FOnApplyPendingEncoding();
  Notify;
end;

procedure TEditorDialogController.GotoLineCommand(const AControlId,
  AValuesJson: string);
var
  S: string;
  N: Integer;
begin
  S := Trim(FDialog.GetInputValue('line'));
  CloseDialog;
  if DialogCmdIsOk(AControlId) and TryStrToInt(S, N) and Assigned(FOnGotoLine) then
    FOnGotoLine(N);
  Notify;
end;

procedure TEditorDialogController.EncodingDialogCommand(const AControlId,
  AValuesJson: string);
var
  Enc: TTextFileEncoding;
  Name: string;
  Idx: Integer;
begin
  // Snapshot from host mirror / declaration before Close.
  Name := FDialog.GetListSelectedText('encoding');
  Idx := FDialog.GetListSelectedIndex('encoding');
  EditorMergeEncodingJson(AValuesJson, Name, Idx);
  CloseDialog;
  // Enter / list accept → ok; Esc / outside click → cancel.
  if not EditorEncodingAccepted(AControlId) then
  begin
    Notify;
    Exit;
  end;
  if not TryTextEncodingFromName(Name, Enc) then
    if not TryTextEncodingFromListIndex(Idx, Enc) then
    begin
      Notify;
      Exit;
    end;
  if Assigned(FOnRequestEncoding) then
    FOnRequestEncoding(Enc);
  Notify;
end;

procedure TEditorDialogController.ReplaceDialogCommand(const AControlId,
  AValuesJson: string);
var
  FindText, ReplText: string;
  Act: TEditorReplaceAction;
begin
  FindText := FDialog.GetInputValue('find');
  ReplText := FDialog.GetInputValue('replace');
  if not EditorReplaceShouldRun(AControlId, FindText) then
  begin
    if EditorReplaceAction(AControlId) = eraNone then
      CloseDialog;
    Notify;
    Exit;
  end;
  CloseDialog;
  Act := EditorReplaceAction(AControlId);
  if Assigned(FOnReplace) then
    FOnReplace(FindText, ReplText, Act = eraAll);
  Notify;
end;

function TEditorDialogController.HandleAskSaveInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  BtnId: string;

  procedure Finish(const ACmd: string);
  begin
    AskSaveCommand(ACmd, '');
    AKey := 0;
    AKeyChar := #0;
  end;

begin
  // Y/N/Esc + Enter/Space on the focused button are resolved here. Tab/arrows
  // still go to DialogHost so the focus ring moves.
  Result := True;
  if (AKeyChar = #13) or (AKeyChar = #10) then
    AKey := vkReturn;
  if (AKey = 10) or (AKey = 13) or (AKey = vkAccept) then
    AKey := vkReturn;

  if AKey = vkEscape then
  begin
    Finish(cDlgCmdCancel);
    Exit;
  end;

  if (AKey = vkReturn) or (AKey = vkSpace) or (AKeyChar = ' ') then
  begin
    BtnId := '';
    if Assigned(FDialog) and FDialog.Visible then
      BtnId := FDialog.FocusedOrDefaultButtonId;
    if BtnId = '' then
      BtnId := cDlgCmdYes;
    Finish(BtnId);
    Exit;
  end;

  BtnId := EditorAskSaveHotkey(AKey, AKeyChar);
  if BtnId <> '' then
  begin
    Finish(BtnId);
    Exit;
  end;

  if Assigned(FDialog) and FDialog.Visible then
    Exit(FDialog.HandleInput(AKey, AShift, AKeyChar));

  AKey := 0;
  AKeyChar := #0;
end;

end.
