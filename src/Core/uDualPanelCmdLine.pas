unit uDualPanelCmdLine;

{ Dual Panel Command Line Manager: input handling, Tab-complete, and history. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uInputLine, uDualPanelCmd, uHistoryPopup;

type
  TCmdLineSubmitEvent = reference to procedure(const ACommand: string);
  /// <summary>Names from the active panel list (no "..").</summary>
  TCmdLineGetNamesEvent = reference to function: TArray<string>;
  /// <summary>Local folder of the active panel ('' if not on disk):
  /// relative path tokens complete from there.</summary>
  TCmdLineGetBaseDirEvent = reference to function: string;

  TDualPanelCmdLineManager = class
  private
    FCmd: TInputLine;
    FFocused: Boolean;
    FConsoleMode: Boolean;
    FOnSubmit: TCmdLineSubmitEvent;
    FOnInvalidate: TProc;
    FOnGetNames: TCmdLineGetNamesEvent;
    FOnGetBaseDir: TCmdLineGetBaseDirEvent;
    FOnOpenHistoryPopup: TProc;
    FPopup: THistoryPopup;
    FHistory: TStringList;
    FHistIndex: Integer; // -1 = live edit; else index into FHistory
    FDraft: string;
    FMatches: TArray<string>;
    FMatchIndex: Integer;
    FMatchPrefix: string;
    FMatchTokenStart: Integer;
    FClicks: TMouseClickCounter;
    procedure SetFocused(AValue: Boolean);
    procedure SetConsoleMode(AValue: Boolean);
    procedure Invalidate;
    procedure ResetCompletion;
    procedure PushHistory(const ACommand: string);
    procedure HistoryUp;
    procedure HistoryDown;
    procedure DoTabComplete;
    procedure LoadHistory;
    procedure SaveHistory;
    procedure RemoveHistory(const ACommand: string);
  public
    constructor Create(const AOnSubmit: TCmdLineSubmitEvent;
      const AOnInvalidate: TProc);
    destructor Destroy; override;

    procedure Focus;
    /// <summary>Left click on the edit field; ARelCol is relative to the
    /// field start (DualPanelCmdLineEditX). Places the caret; a double click
    /// selects the word, the next quick click the whole line; AExtendSel
    /// (Shift+click) extends the selection to the clicked cell.</summary>
    procedure HandleClick(ARelCol: Integer; AExtendSel: Boolean = False);
    procedure Clear;
    procedure Reset;
    procedure InsertText(const AText: string);
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    /// <summary>Replace the whole command line (Alt+F8 history picker), cursor at end.</summary>
    procedure SetText(const AText: string);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;

    property Focused: Boolean read FFocused write SetFocused;
    property ConsoleMode: Boolean read FConsoleMode write SetConsoleMode;
    property Cmd: TInputLine read FCmd write FCmd;
    property Text: string read FCmd.Text;
    property OnGetNames: TCmdLineGetNamesEvent read FOnGetNames write FOnGetNames;
    property OnGetBaseDir: TCmdLineGetBaseDirEvent read FOnGetBaseDir write FOnGetBaseDir;
    /// <summary>Ctrl+Down / Alt+Down in the focused line: the host opens
    /// HistoryPopup where the line is on screen (it knows the geometry).</summary>
    property OnOpenHistoryPopup: TProc read FOnOpenHistoryPopup write FOnOpenHistoryPopup;
    /// <summary>History drop-down (newest first). Del there removes the
    /// command from the history.</summary>
    property HistoryPopup: THistoryPopup read FPopup;
    /// <summary>A click picked APicked in the history list.</summary>
    procedure PickFromHistory(const ACommand: string);
    /// <summary>Test helper: history entry count.</summary>
    function HistoryCount: Integer;
    /// <summary>All history entries, newest first (Alt+F8 history picker).</summary>
    function GetHistoryItems: TArray<string>;
    /// <summary>Records a command that ran outside this manager's own edit
    /// line (typed directly at a console/terminal shell prompt) into the
    /// same shared history.</summary>
    procedure RecordExternalCommand(const ACommand: string);
  end;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections, uConfigLocation;

const
  cMaxHistory = 100;
  cHistoryFile = 'history.json';

constructor TDualPanelCmdLineManager.Create(const AOnSubmit: TCmdLineSubmitEvent;
  const AOnInvalidate: TProc);
begin
  inherited Create;
  FCmd := InputLineEmpty;
  FFocused := False;
  FConsoleMode := False;
  FOnSubmit := AOnSubmit;
  FOnInvalidate := AOnInvalidate;
  FHistory := TStringList.Create;
  FHistory.StrictDelimiter := True;
  FHistIndex := -1;
  FDraft := '';
  FMatchIndex := -1;
  FMatchTokenStart := -1;
  FPopup := THistoryPopup.Create;
  FPopup.OnRemove :=
    procedure(ACommand: string)
    begin
      RemoveHistory(ACommand);
    end;
  LoadHistory;
end;

destructor TDualPanelCmdLineManager.Destroy;
begin
  SaveHistory;
  FHistory.Free;
  FPopup.Free;
  inherited Destroy;
end;

procedure TDualPanelCmdLineManager.Invalidate;
begin
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TDualPanelCmdLineManager.ResetCompletion;
begin
  SetLength(FMatches, 0);
  FMatchIndex := -1;
  FMatchPrefix := '';
  FMatchTokenStart := -1;
end;

procedure TDualPanelCmdLineManager.SetFocused(AValue: Boolean);
begin
  if FFocused = AValue then
    Exit;
  FFocused := AValue;
  InputLineClearSelection(FCmd);
  if not FFocused then
  begin
    FHistIndex := -1;
    ResetCompletion;
    FPopup.Close;
  end;
  Invalidate;
end;

procedure TDualPanelCmdLineManager.SetConsoleMode(AValue: Boolean);
begin
  if FConsoleMode = AValue then
    Exit;
  FConsoleMode := AValue;
  if AValue then
    SetFocused(False);
  Invalidate;
end;

procedure TDualPanelCmdLineManager.Focus;
begin
  SetFocused(True);
  FCmd.Cursor := Length(FCmd.Text);
  InputLineClearSelection(FCmd);
  Invalidate;
end;

procedure TDualPanelCmdLineManager.HandleClick(ARelCol: Integer; AExtendSel: Boolean);
begin
  SetFocused(True);
  if AExtendSel then
  begin
    FClicks.Reset;
    InputLineMouseClick(FCmd, ARelCol, 1, True);
  end
  else
    InputLineMouseClick(FCmd, ARelCol, FClicks.Hit(ARelCol, 0));
  Invalidate;
end;

procedure TDualPanelCmdLineManager.Clear;
begin
  InputLineReset(FCmd);
  FHistIndex := -1;
  FDraft := '';
  ResetCompletion;
  Invalidate;
end;

procedure TDualPanelCmdLineManager.Reset;
begin
  InputLineReset(FCmd);
  FFocused := False;
  FHistIndex := -1;
  FDraft := '';
  ResetCompletion;
  Invalidate;
end;

procedure TDualPanelCmdLineManager.InsertText(const AText: string);
begin
  Focus;
  FHistIndex := -1;
  ResetCompletion;
  InputLineInsert(FCmd, AText);
  Invalidate;
end;

procedure TDualPanelCmdLineManager.CopyToClipboard;
begin
  InputLineCopy(FCmd);
end;

procedure TDualPanelCmdLineManager.CutToClipboard;
begin
  FHistIndex := -1;
  ResetCompletion;
  InputLineCut(FCmd);
  Invalidate;
end;

procedure TDualPanelCmdLineManager.PasteFromClipboard;
begin
  Focus;
  FHistIndex := -1;
  ResetCompletion;
  InputLinePaste(FCmd);
  Invalidate;
end;

procedure TDualPanelCmdLineManager.SetText(const AText: string);
begin
  Focus;
  FHistIndex := -1;
  FDraft := '';
  ResetCompletion;
  InputLineSetText(FCmd, AText, True);
  Invalidate;
end;

function TDualPanelCmdLineManager.HistoryCount: Integer;
begin
  Result := FHistory.Count;
end;

function TDualPanelCmdLineManager.GetHistoryItems: TArray<string>;
var
  I, N: Integer;
begin
  N := FHistory.Count;
  SetLength(Result, N);
  // Newest first for the picker dialog.
  for I := 0 to N - 1 do
    Result[I] := FHistory[N - 1 - I];
end;

procedure TDualPanelCmdLineManager.RemoveHistory(const ACommand: string);
var
  I: Integer;
begin
  for I := FHistory.Count - 1 downto 0 do
    if SameText(FHistory[I], ACommand) then
      FHistory.Delete(I);
  FHistIndex := -1;
  try
    SaveHistory;
  except
    // Ignore disk errors — history is best-effort.
  end;
  Invalidate;
end;

procedure TDualPanelCmdLineManager.PickFromHistory(const ACommand: string);
begin
  // Put it on the line, do not run it: the user may still edit it.
  SetText(ACommand);
end;

procedure TDualPanelCmdLineManager.RecordExternalCommand(const ACommand: string);
begin
  PushHistory(ACommand);
end;

procedure TDualPanelCmdLineManager.LoadHistory;
var
  Path, Content: string;
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONValue;
begin
  FHistory.Clear;
  Path := GetConfigFilePath(cHistoryFile);
  if not TFile.Exists(Path) then
    Exit;
  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);
    Root := TJSONObject.ParseJSONValue(Content);
    if Root = nil then
      Exit;
    try
      if Root is TJSONArray then
        Arr := TJSONArray(Root)
      else if (Root is TJSONObject) and
              (TJSONObject(Root).Values['commands'] is TJSONArray) then
        Arr := TJSONArray(TJSONObject(Root).Values['commands'])
      else
        Exit;
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I];
        if (Item <> nil) and (Item.Value <> '') then
          FHistory.Add(Item.Value);
      end;
      while FHistory.Count > cMaxHistory do
        FHistory.Delete(0);
    finally
      Root.Free;
    end;
  except
    // Corrupt history — start empty.
    FHistory.Clear;
  end;
end;

procedure TDualPanelCmdLineManager.SaveHistory;
var
  Path: string;
  Arr: TJSONArray;
  I: Integer;
begin
  Path := GetConfigFilePath(cHistoryFile);
  Arr := TJSONArray.Create;
  try
    for I := 0 to FHistory.Count - 1 do
      Arr.Add(FHistory[I]);
    TFile.WriteAllText(Path, Arr.ToJSON, TEncoding.UTF8);
  finally
    Arr.Free;
  end;
end;

procedure TDualPanelCmdLineManager.PushHistory(const ACommand: string);
var
  Cmd: string;
begin
  Cmd := Trim(ACommand);
  if Cmd = '' then
    Exit;
  if (FHistory.Count > 0) and SameText(FHistory[FHistory.Count - 1], Cmd) then
    Exit;
  FHistory.Add(Cmd);
  while FHistory.Count > cMaxHistory do
    FHistory.Delete(0);
  FHistIndex := -1;
  FDraft := '';
  try
    SaveHistory;
  except
    // Ignore disk errors — history is best-effort.
  end;
end;

procedure TDualPanelCmdLineManager.HistoryUp;
begin
  if FHistory.Count = 0 then
    Exit;
  if FHistIndex < 0 then
  begin
    FDraft := FCmd.Text;
    FHistIndex := FHistory.Count - 1;
  end
  else if FHistIndex > 0 then
    Dec(FHistIndex)
  else
    Exit;
  InputLineSetText(FCmd, FHistory[FHistIndex], True);
  ResetCompletion;
  Invalidate;
end;

procedure TDualPanelCmdLineManager.HistoryDown;
begin
  if FHistIndex < 0 then
    Exit;
  if FHistIndex < FHistory.Count - 1 then
  begin
    Inc(FHistIndex);
    InputLineSetText(FCmd, FHistory[FHistIndex], True);
  end
  else
  begin
    FHistIndex := -1;
    InputLineSetText(FCmd, FDraft, True);
    FDraft := '';
  end;
  ResetCompletion;
  Invalidate;
end;

procedure TDualPanelCmdLineManager.DoTabComplete;
var
  Prefix: string;
  Names, Matches: TArray<string>;
  TokStart, TokEnd, NewCur: Integer;
  NewText: string;
  Cycling: Boolean;
  BaseDir: string;
begin
  Prefix := CmdLineExtractToken(FCmd.Text, FCmd.Cursor);
  if not Assigned(FOnGetNames) and not CmdLineTokenIsPath(Prefix) then
    Exit;
  CmdLineTokenBounds(FCmd.Text, FCmd.Cursor, TokStart, TokEnd);

  Cycling := (FMatchIndex >= 0) and (Length(FMatches) > 0) and
    (TokStart = FMatchTokenStart) and
    ((FMatchIndex <= High(FMatches)) and SameText(Prefix, FMatches[FMatchIndex]));

  if Cycling then
    FMatchIndex := (FMatchIndex + 1) mod Length(FMatches)
  else
  begin
    // A path token ("..\sr", "C:\Pro", "src/co") completes from the disk;
    // a bare name from the active panel's list, as before.
    if CmdLineTokenIsPath(Prefix) then
    begin
      BaseDir := '';
      if Assigned(FOnGetBaseDir) then
        BaseDir := FOnGetBaseDir();
      Matches := CmdLinePathCompletions(Prefix, BaseDir);
    end
    else
    begin
      Names := FOnGetNames();
      Matches := FilterCompletions(Names, Prefix);
    end;
    if Length(Matches) = 0 then
    begin
      ResetCompletion;
      Exit;
    end;
    FMatches := Matches;
    FMatchPrefix := Prefix;
    FMatchTokenStart := TokStart;
    FMatchIndex := 0;
  end;

  if not CmdLineApplyCompletion(FCmd.Text, FCmd.Cursor, FMatches[FMatchIndex],
    NewText, NewCur) then
    Exit;
  InputLineSetText(FCmd, NewText, False);
  FCmd.Cursor := NewCur;
  InputLineClearSelection(FCmd);
  Invalidate;
end;

function TDualPanelCmdLineManager.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Picked: string;
begin
  // Open history list first: it owns the arrows, Enter, Del and Esc.
  case FPopup.HandleKey(AKey, AShift, AKeyChar, Picked) of
    hpkHandled:
      begin
        Invalidate;
        Exit(True);
      end;
    hpkPicked:
      begin
        PickFromHistory(Picked);
        Exit(True);
      end;
  end;

  // Ctrl+Down / Alt+Down: history as a drop-down list.
  if (AKey = vkDown) and ((ssCtrl in AShift) or (ssAlt in AShift)) and
     not (ssShift in AShift) and not FConsoleMode then
  begin
    if (FHistory.Count > 0) and Assigned(FOnOpenHistoryPopup) then
      FOnOpenHistoryPopup();
    AKey := 0;
    AKeyChar := #0;
    Invalidate;
    Exit(True);
  end;

  // Tab-complete (no modifiers).
  if (AKey = vkTab) and not (ssCtrl in AShift) and not (ssAlt in AShift) and
     not (ssShift in AShift) then
  begin
    DoTabComplete;
    AKey := 0;
    AKeyChar := #0;
    Result := True;
    Exit;
  end;

  // Command history (Up/Down without Ctrl/Alt). Prefer history over console
  // scroll while the cmdline has focus.
  if (AKey = vkUp) and not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    HistoryUp;
    AKey := 0;
    Result := True;
    Exit;
  end;
  if (AKey = vkDown) and not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    HistoryDown;
    AKey := 0;
    Result := True;
    Exit;
  end;

  // Ctrl+Up — return focus to the file panel (inverse of Ctrl+Down).
  if (AKey = vkUp) and (ssCtrl in AShift) and not (ssAlt in AShift) and
     not (ssShift in AShift) then
  begin
    SetFocused(False);
    AKey := 0;
    AKeyChar := #0;
    Result := True;
    Exit;
  end;

  // Typing / editing leaves history browse and completion cycle.
  if ((AKeyChar >= ' ') and (Ord(AKeyChar) <> 127)) or
     (AKey = vkBack) or (AKey = vkDelete) or (AKey = vkLeft) or
     (AKey = vkRight) or (AKey = vkHome) or (AKey = vkEnd) then
  begin
    if FHistIndex >= 0 then
      FHistIndex := -1;
    if AKey <> vkTab then
      ResetCompletion;
  end;

  case InputLineHandleInput(FCmd, AKey, AShift, AKeyChar, FConsoleMode) of
    ilrSubmit:
      begin
        PushHistory(FCmd.Text);
        if Assigned(FOnSubmit) then
          FOnSubmit(FCmd.Text);
        Result := True;
      end;
    ilrCancel:
      begin
        SetFocused(False);
        Result := True;
      end;
    ilrPassThrough:
      Result := False;
  else
    Invalidate;
    Result := True;
  end;
end;

end.
