unit uHelpViewer;

{ F1 Help window. Topics are Markdown files in <exe dir>\help\<language>\
  (index.md is the title page; languages without a folder fall back to en,
  then ru). One embedded TEditorWindow in HelpMode renders the current topic
  inside a modal window that the Dual Panel host paints over everything.

  Links ([text](target)): "topic.md", "topic.md#anchor" or "#anchor", where
  anchor is the GitHub-style slug of a heading ("## Верхнее меню (F9)" ->
  "верхнее-меню-f9"). Keys: Tab / Shift+Tab select a link, Enter or a click
  follows it, BkSp / Alt+Left go back, F1 opens the title page, Esc / F10
  close. Scrolling, text selection, copy and F7 search are the Viewer's own;
  keys that would edit, re-encode or leave the rendered view are dropped. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uEditorWindow;

type
  THelpViewer = class
  private type
    TPlace = record
      FileName: string;
      TopLine, Row, Col: Integer;
    end;
  private
    FTheme: IThemeRenderer;
    FViewer: TEditorWindow;
    FVisible: Boolean;
    FFileName: string;
    FHistory: TList<TPlace>;
    FPendingAnchor: string;
    FPendingPlace: Boolean;
    FPlace: TPlace;
    FBounds: TRectI; // host-local cells of the last Paint
    FPressTarget: string;
    FOnChanged: TNotifyEvent;
    procedure Changed;
    procedure ViewerChanged(Sender: TObject);
    procedure ViewerCloseRequest(Sender: TObject);
    function CurrentPlace: TPlace;
    function FindAnchorLine(const AAnchor: string): Integer;
    procedure ShowFile(const AFileName, AAnchor: string;
      const APlace: TPlace; AUsePlace: Boolean);
    procedure FollowLink(const ATarget: string);
    procedure GoBack;
    function PassToViewer(AKey: Word; AShift: TShiftState; AKeyChar: Char): Boolean;
  public
    constructor Create(const ATheme: IThemeRenderer);
    destructor Destroy; override;
    /// <summary>Folder of the current UI language's topics ('' if none).</summary>
    class function TopicDir: string; static;
    /// <summary>GitHub-style heading anchor: lower case, spaces to '-',
    /// punctuation dropped.</summary>
    class function HeadingSlug(const AHeading: string): string; static;
    /// <summary>Shows ATopic (file name relative to TopicDir, optionally with
    /// '#anchor'); '' = the title page. False if the topic is missing.</summary>
    function Open(const ATopic: string = ''): Boolean;
    procedure Close;
    /// <summary>Paints the window centred in the host area (AHostW x AHostH
    /// cells); AAbsLeft/Top is the host's compositor origin.</summary>
    procedure Paint(const AGrid: TTerminalGrid; AHostW, AHostH, AAbsLeft, AAbsTop: Integer);
    function HandleInput(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function HandleMouseDown(AHostCol, AHostRow: Integer; AShift: TShiftState): Boolean;
    function HandleMouseMove(AHostCol, AHostRow: Integer): Boolean;
    function HandleMouseUp: Boolean;
    function SetKeyModifiers(AShift: TShiftState): Boolean;
    property Visible: Boolean read FVisible;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.IOUtils, System.Math, System.StrUtils, System.Character,
  uThemeDrawing, uFunctionBar, uStrings, uVfsTypes;

const
  cIndexTopic = 'index.md';
  cMargin = 10;   // cells between the host edges and the window, each side
  cMinWidth = 24;
  cMinHeight = 8;

constructor THelpViewer.Create(const ATheme: IThemeRenderer);
begin
  inherited Create;
  FTheme := ATheme;
  FHistory := TList<TPlace>.Create;
  FViewer := TEditorWindow.Create(ATheme, High(Cardinal));
  FViewer.HelpMode := True;
  FViewer.Embedded := True;
  FViewer.OnContentChanged := ViewerChanged;
  FViewer.OnCloseRequest := ViewerCloseRequest;
  FBounds := TRectI.Make(0, 0, -1, -1);
end;

destructor THelpViewer.Destroy;
begin
  FViewer.OnContentChanged := nil;
  FViewer.OnCloseRequest := nil;
  FreeAndNil(FViewer);
  FreeAndNil(FHistory);
  inherited;
end;

class function THelpViewer.TopicDir: string;
var
  Root, Lang: string;
begin
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'help');
  for Lang in TArray<string>.Create(CurrentLocale, 'en', 'ru') do
  begin
    Result := TPath.Combine(Root, Lang);
    if FileExists(TPath.Combine(Result, cIndexTopic)) then
      Exit;
  end;
  Result := '';
end;

class function THelpViewer.HeadingSlug(const AHeading: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in Trim(AHeading).ToLower do
    if Ch.IsLetterOrDigit or (Ch = '_') or (Ch = '-') then
      Result := Result + Ch
    else if Ch = ' ' then
      Result := Result + '-';
end;

procedure THelpViewer.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function THelpViewer.CurrentPlace: TPlace;
begin
  Result.FileName := FFileName;
  FViewer.GetViewPos(Result.TopLine, Result.Row, Result.Col);
end;

function THelpViewer.FindAnchorLine(const AAnchor: string): Integer;
var
  I: Integer;
  Line, Want: string;
begin
  Want := AAnchor.ToLower;
  for I := 0 to FViewer.LineCount - 1 do
  begin
    Line := TrimLeft(FViewer.LineText(I));
    if StartsStr('#', Line) and (HeadingSlug(Line.TrimLeft(['#'])) = Want) then
      Exit(I);
  end;
  Result := -1;
end;

procedure THelpViewer.ViewerChanged(Sender: TObject);
var
  Line: Integer;
  Anchor: string;
begin
  // Topics load asynchronously: a pending anchor / Back position is applied
  // on the first notification that finds the document ready. Cleared first
  // -- SetViewPos notifies again.
  if FViewer.DocReady then
  begin
    if FPendingPlace then
    begin
      FPendingPlace := False;
      FViewer.SetViewPos(FPlace.TopLine, FPlace.Row, FPlace.Col);
    end
    else if FPendingAnchor <> '' then
    begin
      Anchor := FPendingAnchor;
      FPendingAnchor := '';
      Line := FindAnchorLine(Anchor);
      if Line >= 0 then
        FViewer.SetViewPos(Line, Line, 0);
    end;
  end;
  Changed;
end;

procedure THelpViewer.ViewerCloseRequest(Sender: TObject);
begin
  Close;
end;

procedure THelpViewer.ShowFile(const AFileName, AAnchor: string;
  const APlace: TPlace; AUsePlace: Boolean);
begin
  // Pending state first: the load may complete before Open returns.
  FFileName := AFileName;
  FPendingAnchor := AAnchor;
  FPlace := APlace;
  FPendingPlace := AUsePlace;
  FViewer.Open(PathToFileUri(AFileName), True);
end;

function THelpViewer.Open(const ATopic: string): Boolean;
var
  Dir, Topic, Anchor, FileName: string;
  P: Integer;
begin
  Result := False;
  Dir := TopicDir;
  if Dir = '' then
    Exit;
  Topic := ATopic;
  Anchor := '';
  P := Pos('#', Topic);
  if P > 0 then
  begin
    Anchor := Copy(Topic, P + 1, MaxInt);
    Topic := Copy(Topic, 1, P - 1);
  end;
  if Topic = '' then
    Topic := cIndexTopic;
  FileName := TPath.Combine(Dir, Topic);
  if not FileExists(FileName) then
    FileName := TPath.Combine(Dir, cIndexTopic);
  FHistory.Clear;
  FVisible := True;
  ShowFile(FileName, Anchor, Default(TPlace), False);
  Changed;
  Result := True;
end;

procedure THelpViewer.Close;
begin
  if not FVisible then
    Exit;
  FVisible := False;
  FHistory.Clear;
  FPressTarget := '';
  Changed;
end;

procedure THelpViewer.FollowLink(const ATarget: string);
var
  Topic, Anchor, FileName: string;
  P, Line: Integer;
begin
  if (ATarget = '') or (Pos('://', ATarget) > 0) or StartsText('mailto:', ATarget) then
    Exit;
  Topic := ATarget;
  Anchor := '';
  P := Pos('#', Topic);
  if P > 0 then
  begin
    Anchor := Copy(Topic, P + 1, MaxInt);
    Topic := Copy(Topic, 1, P - 1);
  end;
  if Topic = '' then
  begin
    // Same topic: jump now (the document is already loaded).
    Line := FindAnchorLine(Anchor);
    if Line < 0 then
      Exit;
    FHistory.Add(CurrentPlace);
    FViewer.SetViewPos(Line, Line, 0);
    Exit;
  end;
  FileName := TPath.GetFullPath(TPath.Combine(ExtractFilePath(FFileName),
    StringReplace(Topic, '/', PathDelim, [rfReplaceAll])));
  if not FileExists(FileName) then
    Exit;
  FHistory.Add(CurrentPlace);
  ShowFile(FileName, Anchor, Default(TPlace), False);
end;

procedure THelpViewer.GoBack;
var
  Place: TPlace;
begin
  if FHistory.Count = 0 then
    Exit;
  Place := FHistory.Last;
  FHistory.Delete(FHistory.Count - 1);
  if SameText(Place.FileName, FFileName) and FViewer.DocReady then
  begin
    FViewer.SetViewPos(Place.TopLine, Place.Row, Place.Col);
    Exit;
  end;
  ShowFile(Place.FileName, '', Place, True);
end;

function THelpViewer.PassToViewer(AKey: Word; AShift: TShiftState; AKeyChar: Char): Boolean;
var
  Mods: TShiftState;
begin
  Mods := AShift * [ssShift, ssAlt, ssCtrl];
  case AKey of
    vkUp, vkDown, vkLeft, vkRight, vkPrior, vkNext, vkHome, vkEnd:
      Exit(not (ssAlt in Mods));
    // F7 find; Shift/Alt+F7 and F3/Shift+F3 next/previous match -- only
    // after a search: the Viewer would open the prompt for them instead.
    vkF7:
      Exit((Mods = []) or
        ((Mods * [ssShift, ssAlt] <> []) and not (ssCtrl in Mods) and
         not FViewer.SearchEmpty));
    vkF3:
      Exit((Mods - [ssShift] = []) and not FViewer.SearchEmpty);
    vkInsert:
      Exit(Mods = [ssCtrl]); // copy
  end;
  if Mods = [ssCtrl] then
    Exit((AKey = Ord('A')) or (AKey = Ord('C')) or (AKey = Ord('F')));
  Result := (AKeyChar = '/') and (Mods - [ssShift] = []);
end;

function THelpViewer.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Mods: TShiftState;
  Target: string;
begin
  Result := True;
  if not FVisible then
    Exit(False);
  if (AKey = 0) and ((AKeyChar = #13) or (AKeyChar = #10)) then
    AKey := vkReturn;
  if (AKey = 0) and (AKeyChar = #9) then
    AKey := vkTab;
  Mods := AShift * [ssShift, ssAlt, ssCtrl];
  try
    // The F7 prompt owns every key until Enter/Esc.
    if FViewer.FindPromptOpen then
    begin
      FViewer.HandleInput(AKey, AShift, AKeyChar);
      Exit;
    end;
    if ((AKey = vkEscape) or (AKey = vkF10)) and (Mods = []) then
      Close
    else if (AKey = vkF1) and (Mods = []) then
    begin
      if not SameText(ExtractFileName(FFileName), cIndexTopic) then
      begin
        FHistory.Add(CurrentPlace);
        ShowFile(TPath.Combine(TopicDir, cIndexTopic), '', Default(TPlace), False);
      end
      else
        FViewer.SetViewPos(0, 0, 0);
    end
    else if (AKey = vkTab) and ((Mods = []) or (Mods = [ssShift])) then
      FViewer.SelectMarkdownLink(Mods = [])
    else if (AKey = vkReturn) and (Mods = []) then
    begin
      if FViewer.LinkAtCursor(Target) then
        FollowLink(Target);
    end
    else if ((AKey = vkBack) and (Mods = [])) or
            ((AKey = vkLeft) and (Mods = [ssAlt])) then
      GoBack
    else if PassToViewer(AKey, AShift, AKeyChar) then
      FViewer.HandleInput(AKey, AShift, AKeyChar);
  finally
    AKey := 0;
    AKeyChar := #0;
    Changed;
  end;
end;

procedure THelpViewer.Paint(const AGrid: TTerminalGrid; AHostW, AHostH,
  AAbsLeft, AAbsTop: Integer);
var
  W, H, L, T: Integer;
begin
  if not FVisible then
    Exit;
  // cMargin on every side; a host too small for that gives up margin first,
  // then refuses to paint below the minimum size.
  L := EnsureRange((AHostW - cMinWidth) div 2, 0, cMargin);
  T := EnsureRange((AHostH - cMinHeight) div 2, 0, cMargin);
  W := AHostW - 2 * L;
  H := AHostH - 2 * T;
  if (W < cMinWidth) or (H < cMinHeight) then
  begin
    FBounds := TRectI.Make(0, 0, -1, -1);
    Exit;
  end;
  FBounds := TRectI.Make(L, T, L + W - 1, T + H - 1);
  FViewer.PaintEmbedded(AGrid, L, T, W, H, AAbsLeft + L, AAbsTop + T);
  DrawDialogShadow(AGrid, FBounds);
end;

function THelpViewer.HandleMouseDown(AHostCol, AHostRow: Integer;
  AShift: TShiftState): Boolean;
var
  LC, LR: Integer;
  Items, Letters: TArray<string>;
  Hit: TFunctionBarHit;
  Key: Word;
  KeyChar: Char;
  Shift: TShiftState;
begin
  Result := FVisible;
  FPressTarget := '';
  // Modal: a click outside the window is swallowed.
  if not FVisible or not FBounds.Contains(AHostCol, AHostRow) then
    Exit;
  LC := AHostCol - FBounds.Left;
  LR := AHostRow - FBounds.Top;
  if (LR = FBounds.Height - 2) and not FViewer.FindPromptOpen then
  begin
    if FViewer.SearchEmpty then
      FunctionBarGetItems(fbcHelp, AShift, Items, Letters)
    else
      FunctionBarGetItems(fbcHelpSearch, AShift, Items, Letters);
    Hit := FunctionBarHitTest(LC, FBounds.Width, Items, Letters, AShift,
      Assigned(FTheme));
    if FunctionBarHitToInput(Hit, AShift, Key, KeyChar, Shift) then
      HandleInput(Key, Shift, KeyChar);
    Exit;
  end;
  FViewer.HandleMouseDown(LC, LR, AShift);
  if FVisible and not (ssShift in AShift) and not FViewer.HasSelection then
    FViewer.LinkAtCursor(FPressTarget);
  Changed;
end;

function THelpViewer.HandleMouseMove(AHostCol, AHostRow: Integer): Boolean;
begin
  Result := FVisible;
  if FVisible and FViewer.HandleMouseMove(AHostCol - FBounds.Left,
     AHostRow - FBounds.Top) then
    Changed;
end;

function THelpViewer.HandleMouseUp: Boolean;
var
  Target: string;
begin
  Result := FVisible;
  if not FVisible then
    Exit;
  FViewer.HandleMouseUp;
  // A plain click (no drag selection) on a link follows it.
  if (FPressTarget <> '') and not FViewer.HasSelection and
     FViewer.LinkAtCursor(Target) and (Target = FPressTarget) then
    FollowLink(Target);
  FPressTarget := '';
  Changed;
end;

function THelpViewer.SetKeyModifiers(AShift: TShiftState): Boolean;
begin
  Result := FVisible and FViewer.SetKeyModifiers(AShift);
end;

end.
