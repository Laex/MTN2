unit uDualPanelSearch;

{ Find-file overlay (Alt+F7). Extracted from TDualPanelWindow. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uDualPanelUiTypes, uDualPanelOverlays,
  uVfsTypes, uFileFind, uFindSession;

type
  TSearchGotoEvent = reference to procedure(const AFilePath: string);
  TSearchFindNavigateEvent = reference to function(const ARoot, AMask: string;
    const AHits: TArray<TFindHit>): Boolean;

  TSearchController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FOnGoto: TSearchGotoEvent;
    FOnNavigateFindResults: TSearchFindNavigateEvent;
    FOnAfterClose: TProc;
    FSearch: TSearchState;
    FAlive: Boolean;
    procedure HandleSearchInputDialog(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char);
    procedure HandleSearchInputRunning(var AKey: Word; var AKeyChar: Char);
    procedure HandleSearchInputResults(var AKey: Word; var AKeyChar: Char);
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AOnGoto: TSearchGotoEvent;
      const AOnNavigateFindResults: TSearchFindNavigateEvent;
      const AOnAfterClose: TProc = nil);
    destructor Destroy; override;
    procedure SetTheme(const ATheme: IThemeRenderer);
    procedure CloseSearchUi;
    procedure LayoutSearchUi(AClientWidth, AClientHeight: Integer);
    procedure DrawSearchUi(const AGrid: TTerminalGrid;
      AClientWidth, AClientHeight: Integer);
    procedure StartSearch;
    procedure CancelSearch;
    procedure GotoSearchResult;
    function HandleSearchInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function GetActive: Boolean;
    property Phase: TSearchPhase read FSearch.Phase write FSearch.Phase;
    property Mask: string read FSearch.Mask write FSearch.Mask;
    property ContainingText: string read FSearch.ContainingText write FSearch.ContainingText;
    property Subdirs: Boolean read FSearch.Subdirs write FSearch.Subdirs;
    property CaseSensitive: Boolean read FSearch.CaseSensitive write FSearch.CaseSensitive;
    property WholeWords: Boolean read FSearch.WholeWords write FSearch.WholeWords;
    property SearchFolders: Boolean read FSearch.SearchFolders write FSearch.SearchFolders;
    property UseRegex: Boolean read FSearch.UseRegex write FSearch.UseRegex;
    property RootPath: string read FSearch.RootPath write FSearch.RootPath;
    property FocusField: Integer read FSearch.FocusField write FSearch.FocusField;
    property Message: string read FSearch.Message;
    property FoundCount: Integer read FSearch.FoundCount;
    property CurrentDir: string read FSearch.CurrentDir;
    property Bounds: TRectI read FSearch.Bounds;
    property Active: Boolean read GetActive;
    property State: TSearchState read FSearch;
  end;

implementation

uses
  uStrings;

const
  cCursorFg = TAlphaColor($FF000000);
  cCursorBg = TAlphaColor($FF00AAAA);
  cFileFg   = TAlphaColor($FFAAAAAA);
  cPanelBg  = TAlphaColor($FF0000AA);
  cFrameActive = TAlphaColor($FF55FFFF);
  cMenuHot  = TAlphaColor($FFFFFF55);
  cDirFg    = TAlphaColor($FFFFFFFF);
  // U+2026 by codepoint rather than a pasted '…'. The file carries a UTF-8 BOM
  // now, so a literal would compile correctly too — but it did not when this
  // truncation was written, and the compiler then read the ellipsis as 3 ANSI
  // chars, making the clipped path 2 cells wider than the frame's inner span
  // and spilling it past the right border. Stated by codepoint the width math
  // cannot regress if the encoding is ever lost again. (chBoxH in
  // uTerminalTypes.pas uses the same convention.)
  cEllipsis = #$2026;

constructor TSearchController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AOnGoto: TSearchGotoEvent;
  const AOnNavigateFindResults: TSearchFindNavigateEvent;
  const AOnAfterClose: TProc);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FOnGoto := AOnGoto;
  FOnNavigateFindResults := AOnNavigateFindResults;
  FOnAfterClose := AOnAfterClose;
  FAlive := True;
  FSearch.Phase := spNone;
  FSearch.Mask := '*.*';
  FSearch.ContainingText := '';
  FSearch.Subdirs := True;
  FSearch.CaseSensitive := False;
  FSearch.WholeWords := False;
  FSearch.SearchFolders := False;
  FSearch.UseRegex := False;
  FSearch.FocusField := 0;
end;

destructor TSearchController.Destroy;
begin
  FAlive := False;
  if Assigned(FSearch.Cancel) then
    FSearch.Cancel.Cancel;
  inherited;
end;

procedure TSearchController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

function TSearchController.GetActive: Boolean;
begin
  Result := FSearch.Phase <> spNone;
end;

procedure TSearchController.CloseSearchUi;
begin
  if Assigned(FSearch.Cancel) then
    FSearch.Cancel.Cancel;
  FSearch.Cancel := nil;
  FSearch.Phase := spNone;
  SetLength(FSearch.Results, 0);
  FSearch.FoundCount := 0;
  FSearch.CurrentDir := '';
  FSearch.Message := '';
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
  if Assigned(FOnAfterClose) then
    FOnAfterClose;
end;

procedure TSearchController.LayoutSearchUi(AClientWidth, AClientHeight: Integer);
var
  W, H, PanelW, Left, Top: Integer;
begin
  PanelW := AClientWidth;
  case FSearch.Phase of
    spDialog:
      begin
        W := Min(52, Max(PanelW - 2, 32));
        H := 9;
      end;
    spRunning:
      begin
        W := Min(56, Max(PanelW - 2, 32));
        H := 7;
      end;
    spResults:
      begin
        W := Min(70, Max(PanelW - 2, 36));
        H := Min(Max(AClientHeight - 6, 10), 20);
      end;
  else
    Exit;
  end;
  Left := (PanelW - W) div 2;
  Top := Max(AClientHeight div 2 - H div 2, 3);
  if Left + W > PanelW then
    Left := Max(PanelW - W, 0);
  if Top + H > AClientHeight then
    Top := Max(AClientHeight - H, 1);
  FSearch.Bounds := TRectI.Make(Left, Top, Left + W - 1, Top + H - 1);
end;

procedure TSearchController.StartSearch;
var
  Mask, Root, RegexError: string;
  Token: IJobCancelToken;
  Opts: TFindOptions;
begin
  Mask := Trim(FSearch.Mask);
  if Mask = '' then
    Mask := '*.*';
  FSearch.Mask := Mask;
  Root := Trim(FSearch.RootPath);
  if (Root <> '') and (Length(Root) = 2) and (Root[2] = ':') then
    Root := Root + PathDelim;
  FSearch.RootPath := Root;
  if Root = '' then
  begin
    FSearch.Message := 'No search path';
    FSearch.Phase := spResults;
    SetLength(FSearch.Results, 0);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;

  // Validate the regex once up front — a bad pattern is reported instantly
  // instead of silently matching nothing on every file in the walk.
  if FSearch.UseRegex and (Trim(FSearch.ContainingText) <> '') and
     not ValidateRegexPattern(FSearch.ContainingText, RegexError) then
  begin
    FSearch.Message := 'Invalid regex: ' + RegexError;
    FSearch.Phase := spResults;
    SetLength(FSearch.Results, 0);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;

  Token := TJobCancelToken.Create;
  FSearch.Cancel := Token;
  FSearch.Phase := spRunning;
  FSearch.FoundCount := 0;
  FSearch.CurrentDir := Root;
  FSearch.Message := '';
  SetLength(FSearch.Results, 0);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;

  Opts := DefaultFindOptions(Root, Mask, FSearch.Subdirs);
  Opts.ContainingText := FSearch.ContainingText;
  Opts.CaseSensitive := FSearch.CaseSensitive;
  Opts.WholeWords := FSearch.WholeWords;
  Opts.SearchFolders := FSearch.SearchFolders;
  Opts.UseRegex := FSearch.UseRegex;

  FindFilesAsync(Opts, Token,
    procedure(AFoundCount: Integer; const ACurrentDir: string)
    begin
      if not FAlive or (FSearch.Phase <> spRunning) then
        Exit;
      FSearch.FoundCount := AFoundCount;
      FSearch.CurrentDir := ACurrentDir;
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if FSearch.Phase <> spRunning then
        Exit;
      FSearch.Cancel := nil;
      if AError.Code = vecCancelled then
      begin
        FSearch.Phase := spNone;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        Exit;
      end;
      if (AError.Code = vecOk) and (Length(AHits) > 0) then
      begin
        CloseSearchUi;
        if Assigned(FOnNavigateFindResults) and
           FOnNavigateFindResults(Root, Mask, AHits) then
          Exit;
      end;
      FSearch.Results := AHits;
      FSearch.FoundCount := Length(AHits);
      FSearch.Cursor := 0;
      FSearch.Scroll := 0;
      if AError.Code <> vecOk then
        FSearch.Message := AError.Message
      else
        FSearch.Message := 'No files found';
      FSearch.Phase := spResults;
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end);
end;

procedure TSearchController.CancelSearch;
begin
  if FSearch.Phase = spRunning then
  begin
    if Assigned(FSearch.Cancel) then
      FSearch.Cancel.Cancel;
  end
  else
    CloseSearchUi;
end;

procedure TSearchController.GotoSearchResult;
var
  Path: string;
begin
  if (FSearch.Phase <> spResults) or (Length(FSearch.Results) = 0) then
    Exit;
  FSearch.Cursor := EnsureRange(FSearch.Cursor, 0, High(FSearch.Results));
  Path := FSearch.Results[FSearch.Cursor].Path;
  CloseSearchUi;
  if Assigned(FOnGoto) then
    FOnGoto(Path);
end;

procedure TSearchController.DrawSearchUi(const AGrid: TTerminalGrid;
  AClientWidth, AClientHeight: Integer);
var
  R: TRectI;
  Y, ViewH, Idx, MaxW: Integer;
  Line, Path, Rel: string;
  Title: string;
  Fg, Bg: TAlphaColor;
begin
  if FSearch.Phase = spNone then
    Exit;
  if FSearch.Phase = spDialog then
    Exit;
  LayoutSearchUi(AClientWidth, AClientHeight);
  R := FSearch.Bounds;
  if (R.Width < 12) or (R.Height < 5) then
    Exit;

  case FSearch.Phase of
    spRunning:
      Title := T('ui.search.running', 'Searching') + cEllipsis;
    spResults:
      Title := T('ui.search.results', 'Results: %d', [Length(FSearch.Results)]);
  else
    Title := T('ui.search.title', 'Find');
  end;
  DrawHostOverlayFrame(AGrid, FTheme, R, Title,
    cFileFg, cPanelBg, cFrameActive, cCursorFg);

  case FSearch.Phase of
    spRunning:
      begin
        PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 2,
          Format('Found: %d', [FSearch.FoundCount]),
          False, False, False, cFileFg, cPanelBg);
        Line := FSearch.CurrentDir;
        // Text starts at R.Left + 1 and the frame owns R.Left / R.Right, so
        // only R.Width - 2 cells are writable. Keep the tail: the deep end of
        // the path is the part that actually changes while scanning.
        MaxW := R.Width - 2;
        if (MaxW > 1) and (Length(Line) > MaxW) then
          Line := cEllipsis + Copy(Line, Length(Line) - MaxW + 2, MaxInt);
        PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 3, Line,
          True, False, False, cDirFg, cPanelBg);
        PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 5, 'Esc=Cancel',
          True, False, False, cMenuHot, cPanelBg);
      end;
    spResults:
      begin
        if FSearch.Message <> '' then
          PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 1, FSearch.Message,
            True, False, False, cMenuHot, cPanelBg)
        else
          PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 1,
            'Enter=Go to  Esc=Close', True, False, False, cMenuHot, cPanelBg);

        ViewH := Max(R.Height - 4, 1);
        if FSearch.Cursor < FSearch.Scroll then
          FSearch.Scroll := FSearch.Cursor;
        if FSearch.Cursor >= FSearch.Scroll + ViewH then
          FSearch.Scroll := FSearch.Cursor - ViewH + 1;
        if FSearch.Scroll < 0 then
          FSearch.Scroll := 0;

        for Y := 0 to ViewH - 1 do
        begin
          Idx := FSearch.Scroll + Y;
          if Idx > High(FSearch.Results) then
          begin
            ResolveOverlayTextColors(FTheme, False, False, False,
              cFileFg, cPanelBg, Fg, Bg);
            FillGridRect(AGrid, R.Left + 1, R.Top + 2 + Y,
              R.Right - 1, R.Top + 2 + Y, ' ', Fg, Bg);
            Continue;
          end;
          Path := FSearch.Results[Idx].Path;
          Rel := Path;
          if FSearch.RootPath <> '' then
          begin
            if Rel.StartsWith(IncludeTrailingPathDelimiter(FSearch.RootPath), True) then
              Rel := Copy(Rel, Length(IncludeTrailingPathDelimiter(FSearch.RootPath)) + 1,
                MaxInt)
            else if SameText(Rel, FSearch.RootPath) then
              Rel := ExtractFileName(Rel);
          end;
          if Length(Rel) > R.Width - 2 then
            Rel := Copy(Rel, 1, R.Width - 3) + '~';
          if Idx = FSearch.Cursor then
            PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 2 + Y, Rel,
              False, False, True, cCursorFg, cCursorBg)
          else
            PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 2 + Y, Rel,
              False, False, False, cFileFg, cPanelBg);
        end;
      end;
  end;
end;

procedure TSearchController.HandleSearchInputDialog(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char);
begin
  if AKey = vkEscape then
  begin
    CloseSearchUi;
    AKey := 0;
    Exit;
  end;
  if AKey = vkTab then
  begin
    FSearch.FocusField := 1 - FSearch.FocusField;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkReturn then
  begin
    StartSearch;
    AKey := 0;
    Exit;
  end;
  if FSearch.FocusField = 1 then
  begin
    if (AKey = vkSpace) or (AKeyChar = ' ') then
    begin
      FSearch.Subdirs := not FSearch.Subdirs;
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if AKey = vkBack then
  begin
    if FSearch.Mask <> '' then
    begin
      Delete(FSearch.Mask, Length(FSearch.Mask), 1);
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end;
    AKey := 0;
    Exit;
  end;
  if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
     not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    FSearch.Mask := FSearch.Mask + AKeyChar;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  AKey := 0;
  AKeyChar := #0;
end;

procedure TSearchController.HandleSearchInputRunning(var AKey: Word;
  var AKeyChar: Char);
begin
  if AKey = vkEscape then
  begin
    CancelSearch;
    AKey := 0;
  end
  else
  begin
    AKey := 0;
    AKeyChar := #0;
  end;
end;

procedure TSearchController.HandleSearchInputResults(var AKey: Word;
  var AKeyChar: Char);
var
  ViewH: Integer;
begin
  ViewH := Max(FSearch.Bounds.Height - 4, 1);
  case AKey of
    vkEscape:
      begin
        CloseSearchUi;
        AKey := 0;
      end;
    vkReturn:
      begin
        GotoSearchResult;
        AKey := 0;
      end;
    vkUp:
      begin
        if FSearch.Cursor > 0 then
          Dec(FSearch.Cursor);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkDown:
      begin
        if FSearch.Cursor < High(FSearch.Results) then
          Inc(FSearch.Cursor);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkPrior:
      begin
        Dec(FSearch.Cursor, ViewH);
        if FSearch.Cursor < 0 then
          FSearch.Cursor := 0;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkNext:
      begin
        Inc(FSearch.Cursor, ViewH);
        if FSearch.Cursor > High(FSearch.Results) then
          FSearch.Cursor := Max(High(FSearch.Results), 0);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkHome:
      begin
        FSearch.Cursor := 0;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkEnd:
      begin
        FSearch.Cursor := Max(High(FSearch.Results), 0);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
  else
    AKey := 0;
    AKeyChar := #0;
  end;
end;

function TSearchController.HandleSearchInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := True;
  case FSearch.Phase of
    spDialog: HandleSearchInputDialog(AKey, AShift, AKeyChar);
    spRunning: HandleSearchInputRunning(AKey, AKeyChar);
    spResults: HandleSearchInputResults(AKey, AKeyChar);
  else
    Result := False;
  end;
end;

end.
