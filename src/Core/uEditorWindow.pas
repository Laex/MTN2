unit uEditorWindow;

{ MDI Editor/Viewer window: edit small text files in memory, save via async VFS.
  F4 = editable Editor; F3 = same window in ViewOnly (no mutations).
  Binary / Hex: F3 opens Hex dump when file has NULs; F4 / Ctrl+H toggles Hex<->Text.
  Far-core keys: F6 View<->Edit, F8/Shift+F8 encoding, Alt+F8 goto, Shift/Alt+F7 find,
  Ctrl+F7 replace, Ctrl+D/Y line delete, Ctrl+K to EOL, Ctrl+N blank line,
  Ctrl+Left/Right words, Ctrl+Home/End file ends, Ctrl+U clear sel.
  Clipboard Ctrl+C/X/V; Undo Ctrl+Z; Redo Ctrl+Shift+Z (Ctrl+Y = Far delete line).
  Find: F7 or / - prompt; Enter/F3 - next; Shift+F3 - previous. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.Rtti,
  System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uTerminalWindow, uEditorDoc, uVfsTypes,
  uTextEncoding, uFunctionBar, uDialogHost, uDialogTypes, uInputLine,
  uEditorUndo, uEditorSearch, uEditorHexView, uEditorPainter, uEditorLayout, uEditorDialogs,
  uEditorInput, uFilePositions, uMarkdownParser, uMarkdownIndex, uMarkdownPainter,
  uHistoryPopup, uKeymap;

type
  TEditorConfirm = (ecNone, ecAskSave, ecDiscardEncoding, ecClearReadOnly,
    ecOpenLink, ecNotFound, ecReplaceAsk, ecReplaceWrap);

  /// <summary>A step-by-step replace in progress (the Replace button of the
  /// Replace dialog): one match is shown at a time and answered with Replace,
  /// All, Skip or Cancel.</summary>
  TReplaceSession = record
    Active: Boolean;
    /// <summary>All was answered: the rest is replaced without asking.</summary>
    AllMode: Boolean;
    Forward: Boolean;
    /// <summary>The pass that went on from the other end of the text.</summary>
    Wrapped: Boolean;
    /// <summary>The undo entry of the whole session was made.</summary>
    UndoPushed: Boolean;
    /// <summary>A match was shown at least once.</summary>
    AnyMatch: Boolean;
    Find, Repl: string;
    Opts: TSearchOptions;
    Count: Integer;
    /// <summary>Where the search began (after the wrap it stops there) and
    /// where the cursor was, which is put back at the end.</summary>
    StartRow, StartCol, SavedRow, SavedCol: Integer;
    /// <summary>Where the next match is looked for from.</summary>
    PosRow, PosCol: Integer;
    MatchRow, MatchCol, MatchLen: Integer;
  end;

  TMdImageSize = record
    W, H: Integer; // pixels; 0 = unknown
  end;

  TEditorWindow = class(TTerminalWindow)
  private
    FDoc: TEditorDoc;
    FURI: string;
    FViewOnly: Boolean;
    FHexMode: Boolean;
    FHexHighNibble: Boolean;
    // Body colors come from the theme, so a theme switch recolors the
    // content, not only the frame. Refreshed from Theme.ResolveEditorColors
    // at the top of every DrawContent call (cheap; mirrors how every other
    // window re-reads Theme fresh each frame rather than caching across a
    // live theme switch - see uThemeProxy.pas), so every Draw*Content /
    // DrawScrollBar / DrawFunctionKeys / DrawAppStatusLine call reached from
    // within that same DrawContent sees the current theme's colors.
    FThemeColors: TEditorThemeColors;
    // Cell-aware Markdown render mode (F3 on .md, view-only).
    // Mutually exclusive with FHexMode by construction - never both True.
    FMarkdownMode: Boolean;
    FMdFenceIdx: TMarkdownFenceIndex;
    FMdLineCache: TDictionary<Integer, TMdLine>;
    FMdLineCacheOrder: TQueue<Integer>;
    // Resolving an image ref probes the filesystem (uMarkdownParser.
    // MarkdownResolveImageFile) -- memoized by ImagePath since the same
    // image line is re-resolved on every scroll/cursor-move/redraw
    // (MapMarkdownViewToPos, EnsureMarkdownCursorVisible, DrawMarkdownContent
    // all funnel through MarkdownLineScreenRows). Cleared alongside
    // FMdLineCache wherever the document's content changes underneath it;
    // unlike FMdLineCache it does not depend on TextWidth.
    FMdImageUriCache: TDictionary<string, string>;
    // Image pixel size by resolved URI (header read, see
    // ReadImagePixelSize); (0,0) = unknown format. Cleared with the URI cache.
    FMdImageSizeCache: TDictionary<string, TMdImageSize>;
    // Table rows now bake the viewport's TextWidth into their wrapped
    // DisplayText (see FormatPipeTableLine), so a cached TMdLine is only
    // valid for the width it was built at - a resize must invalidate it.
    FMdLineCacheWidth: Integer;
    // Layout (columns, alignment, fitted widths) of the pipe-table block
    // rows were last formatted from, keyed by the block's first/last line
    // and the width it was fitted to. Measuring every cell of the block is
    // what made each new table row cost the whole block (a 256-row table:
    // ~0.6 s to show all of it); with this each row costs itself. Reset with
    // FMdLineCache (FMdTableLayoutStart := -1).
    FMdTableLayoutStart, FMdTableLayoutEnd, FMdTableLayoutWidth: Integer;
    FMdTableLayout: TMdTableLayout;
    // Last FDoc.ContentGen this window's markdown caches were built against
    // - a live reload (FDoc's own file-watcher) bumps ContentGen without
    // going through Open, so DocChanged compares against this to know when
    // the fence index / line cache now point at stale content.
    FLastMdContentGen: Cardinal;
    // True only while DrawMarkdownContent has an active Overlay request for
    // an image line in the current viewport - read by uMainForm.FormPaint
    // (MarkdownImageOverlayVisible) to decide whether to run the Overlay
    // Canvas pass for this window, mirroring TDualPanelWindow.QuickViewVisible.
    FMdOverlayShowing: Boolean;
    FEmbedded: Boolean;
    // F1 Help window (uHelpViewer): fbcHelp chrome, "Help" title, no saved
    // file position (the host positions the topic itself).
    FHelpMode: Boolean;
    // Ctrl+Q text Quick View (uQuickTextView): content only -- no frame,
    // F-keys or status line (the panel keeps its own frame), no caret, no
    // saved file position, Markdown images as text placeholders (the image
    // Overlay belongs to the picture Quick View).
    FChromeless: Boolean;
    FTopLine: Integer;
    /// <summary>Markdown view only: screen row inside FTopLine's wrapped
    /// rows where the view starts, so scrolling goes by rows, not paragraphs.</summary>
    FTopSubRow: Integer;
    FLeftCol: Integer;
    FCursorRow: Integer;
    FCursorCol: Integer;
    FSelAnchorRow: Integer; // -1 = no selection
    FSelAnchorCol: Integer;
    FCursorVisible: Boolean;
    FAlive: Boolean;
    FConfirm: TEditorConfirm;
    FPendingEncoding: TTextFileEncoding;
    FDialog: TDialogHost;
    FCloseAfterSave: Boolean;
    FUndoBuffer: TEditorUndoBuffer;
    FCoalesceInsert: Boolean;
    /// <summary>Text of the last search, which F3 / Shift+F3 look for again.
    /// The Find and Replace dialogs fill it; when nothing was searched in this
    /// editor yet it starts from the latest saved search (uDialogHistory
    /// 'editfind').</summary>
    FFindText: string;
    FFindStatus: string;
    FRepl: TReplaceSession;
    FMouseSelecting: Boolean;
    // Markdown link under a plain mouse press; the release on the same link
    // (no drag selection in between) follows it.
    FPressLink: string;
    FClicks: TMouseClickCounter; // double = word, triple = line
    FWordWrap: Boolean;
    FPositionRestored: Boolean;
    FOnCloseRequest: TNotifyEvent;
    FOnContentChanged: TNotifyEvent;
    FDialogs: TEditorDialogController;
    FKeymapHost: TEditorKeymapHost;
    procedure BindKeymapHost;
    procedure SaveDoc;
    function FindNeedleEmpty: Boolean;
    function EditorIsViewOnly: Boolean;
    function EditorIsMarkdownMode: Boolean;
    procedure FindNextOrPrev(AForward: Boolean);
    procedure GotoFileHome(AExtendSel: Boolean);
    procedure GotoFileEnd(AExtendSel: Boolean);
    procedure GotoLineHome(AExtendSel: Boolean);
    procedure GotoLineEnd(AExtendSel: Boolean);
    procedure RestoreSavedPosition;
    procedure SaveCurrentPosition;
    procedure DocChanged(Sender: TObject);
    procedure NotifyHost;
    function ModeTitle: string;
    function CanEdit: Boolean;
    function TryUnlockEdit: Boolean;
    procedure OfferClearReadOnly;
    procedure HexTypeChar(ACh: Char);
    procedure HexDeleteAtCursor(ABackspace: Boolean);
    procedure HexInsertZero;
    function ChromeContext: TFunctionBarContext;
    function ViewHeight: Integer;
    function TextWidth: Integer;
    function ContentRowCount: Integer;
    function GetWrappedRowCount(ATextW: Integer): Integer;
    function MapDisplayRowToLine(ADisplayRow, ATextW: Integer; out ALineIdx, ACharOffset: Integer): Boolean;
    function MapLineToDisplayRow(ALineIdx, ACharOffset, ATextW: Integer): Integer;
    function MarkdownLineScreenRows(ALineIdx, ATextW, ARemainRows: Integer): Integer;
    function MarkdownTopSubRow: Integer;
    function MarkdownCursorChunk(ALineIdx, ACol, ATextW: Integer): Integer;
    function MarkdownChunkCount(ALineIdx, ATextW: Integer): Integer;
    procedure ScrollMarkdownRows(ADelta: Integer);
    procedure MoveMarkdownCursorRows(ARowDelta, ATextW: Integer);
    function MapMarkdownViewToPos(AViewRow, AViewCol: Integer;
      out ALineIdx, ACol: Integer): Boolean;
    procedure ToggleWordWrap;
    function HexBytesPerRow: Integer;
    function HexRowCount: Integer;
    function FormatHexLine(ARow: Integer): string;
    procedure DrawHexContent;
    function IsMarkdownFile: Boolean;
    function GetMdLine(ALineIdx: Integer): TMdLine;
    procedure CacheMdLine(AIndex: Integer; const AValue: TMdLine);
    function MarkdownWrapStarts(const ALine: TMdLine; ATextW: Integer): TArray<Integer>;
    function ResolveMarkdownImageUri(const AImagePath: string): string;
    /// <summary>Screen block for a standalone image. The image is shown at
    /// its own pixel size, or at the size the line requests (ReqW/ReqH,
    /// pixels); when that is wider than the text area (ATextW) it shrinks
    /// proportionally to it. Rows follow from the result and are capped to
    /// AViewH (the width then shrinks to keep the proportions). AScale is
    /// the device-pixel scale to draw at (0 when the image size is unknown).</summary>
    function MarkdownImageBlock(const AImageUri: string; AReqW, AReqH, ATextW, AViewH: Integer;
      out ACols: Integer; out AScale: Single): Integer;
    procedure DrawMarkdownContent;
    procedure LeaveMarkdownOverlay;
    procedure EnsureMarkdownCursorVisible(AViewH, ATextW: Integer);
    procedure EnsureCursorVisible;
    procedure ClampCursor;
    procedure ClampDocPos(var ARow, ACol: Integer);
    function HitTextCell(ALocalCol, ALocalRow: Integer;
      out ARow, ACol: Integer): Boolean;
    procedure SetCursorPos(ARow, ACol: Integer; AExtendSel: Boolean);
    procedure SelectClickRange(ARow, ACol: Integer; AWholeLine: Boolean);
    procedure RequestClose;
    procedure ForceClose;
    procedure SaveAndMaybeClose;
    procedure DialogChanged(Sender: TObject);
    function FrameBorderColor: TAlphaColor;
    procedure DrawWindowBottomBorder(AY, AWidth: Integer);
    procedure DrawFunctionKeys(AY, AWidth: Integer);
    procedure DrawAppStatusLine(AY, AWidth: Integer);
    procedure DrawScrollBar;
    function ContentBottomRow: Integer;
    procedure ScrollBy(ADelta: Integer);
    procedure ScrollTo(ATop: Integer);
    procedure ClearSelection;
    procedure EnsureSelAnchor;
    procedure GetSelRange(out ARow1, ACol1, ARow2, ACol2: Integer);
    function SelectedText: string;
    /// <summary>The text cursor columns count in: the displayed text in the
    /// Markdown view (marks hidden, table rows padded), the source line otherwise.</summary>
    function CursorLineText(ALineIdx: Integer): string;
    function DeleteSelection: Boolean;
    procedure SelectAll;
    function IsCellSelected(ARow, ACol: Integer): Boolean;
    procedure PaintVisibleSelection(AY, ALineIdx, AAbsBase: Integer; const AVis: string);
    procedure MoveCursor(ARowDelta, AColDelta: Integer; AExtendSel: Boolean = False);
    procedure MoveWord(AForward: Boolean; AExtendSel: Boolean);
    procedure GotoLine(ALine1Based: Integer);
    procedure ToggleViewMode;
    procedure RequestEncoding(AEncoding: TTextFileEncoding; ARedecode: Boolean);
    procedure CycleEncoding;
    /// <summary>Clears the line if it's the only one, else deletes it and
    /// clamps the cursor row/col - the shared tail of DeleteCurrentLine and
    /// CutSelectionOrLine's no-selection path. Caller must PushUndo (and
    /// copy to clipboard, for Cut) first.</summary>
    procedure RemoveCurrentLine;
    procedure DeleteCurrentLine;
    procedure DeleteToEndOfLine;
    procedure InsertBlankLineBelow;
    procedure ReplaceInDocument(const AFind, AReplace: string; AAll: Boolean);
    procedure BeginReplaceSession(const AFind, AReplace: string);
    /// <summary>Looks for the next match from FRepl.Pos and asks about it (or
    /// replaces it when All was answered); at the end of the text asks to go
    /// on from the other end, then finishes.</summary>
    procedure ReplaceNextMatch;
    function ReplaceFindMatch(out AHit: TSearchResult): Boolean;
    function ReplaceCanWrap: Boolean;
    procedure ReplaceAsk;
    procedure ReplaceAskCommand(const AControlId: string);
    procedure ReplaceWrapAsk;
    procedure ReplaceCurrentMatch;
    procedure ReplaceSkipMatch;
    procedure EndReplaceSession;
    /// <summary>The line of the match cut to the room of the question: the text
    /// before the match, the match and the text after it.</summary>
    procedure ReplaceContext(ARow, ACol, ALen: Integer; out APre, AHit, APost: string);
    procedure SearchMessage(const AMessage, ADetails: string);
    procedure InsertChar(ACh: Char);
    procedure DoBackspace;
    procedure DoDelete;
    procedure DoEnter;
    procedure ClearHistory;
    /// <summary>Fills an empty Find field with the latest saved search.</summary>
    procedure SeedFindFromHistory;
    procedure PushUndo;
    procedure ApplySnapshot(const AEntry: TEditorUndoEntry);
    procedure BreakInsertCoalesce;
    function ClipboardGetText: string;
    procedure ClipboardSetText(const AText: string);
    function FindMatch(AForward: Boolean): Boolean;
    /// <summary>The word under the cursor (Word button of the Find dialogs).</summary>
    function WordAtCursor: string;
    /// <summary>First line of the selection, or the current line when nothing
    /// is selected (Selection button of the Find dialogs).</summary>
    function SelectionForSearch: string;
    /// <summary>Says why a regular expression cannot be searched.</summary>
    procedure BadPatternMessage(const AError: string);
  protected
    procedure DrawContent; override;
  public
    constructor Create(const ATheme: IThemeRenderer; AId: Cardinal);
    destructor Destroy; override;
    procedure RebuildBuffer; override;
    procedure Open(const AURI: string; AViewOnly: Boolean = False);
    procedure BeginClose;
    /// <summary>Blit this editor into a Dual Panel workspace. ADestLeft/Top
    /// are window-local cells in ADest; AAbsLeft/Top are the same origin in
    /// compositor (absolute) cells so Markdown Overlay bounds match the
    /// pixels FormPaint uses.</summary>
    procedure PaintEmbedded(const ADest: TTerminalGrid;
      ADestLeft, ADestTop, AWidth, AHeight, AAbsLeft, AAbsTop: Integer);
    function TabCaption: string;
    function IsDirty: Boolean;
    function HandleFunctionBarClick(ALocalCol: Integer;
      AShift: TShiftState): Boolean;
    function HandleClick(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState = []): Boolean;
    function HandleMouseDown(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState): Boolean;
    function HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
    function HandleMouseUp: Boolean;
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean; override;
    /// <summary>Keymap contexts this document looks keys up in (Markdown /
    /// Viewer or Editor / Document), most specific first.</summary>
    function KeymapChain: TArray<TKeymapContext>;
    procedure ToggleHexMode;
    procedure ToggleMarkdownMode;
    function MarkdownImageOverlayVisible: Boolean;
    procedure OpenGotoDialog;
    procedure OpenFindDialog;
    procedure OpenReplaceDialog;
    procedure OpenEncodingDialog;
    procedure UndoEdit;
    procedure RedoEdit;
    procedure CopySelectionOrLine;
    procedure CutSelectionOrLine;
    procedure PasteText;
    function MenuDocReady: Boolean;
    function MenuCanEdit: Boolean;
    function MenuHexBinaryLocked: Boolean;
    function MenuCanUndo: Boolean;
    function MenuCanRedo: Boolean;
    function HasSelection: Boolean;
    /// <summary>The selected text; in the Markdown view it is the displayed text.</summary>
    function SelectionText: string;
    // Help viewer API (uHelpViewer). Positions are line index / display
    // column in Markdown mode.
    function DocReady: Boolean;
    function LineCount: Integer;
    function LineText(AIndex: Integer): string;
    /// <summary>Nothing searched for yet (the Find dialog never took text).</summary>
    function SearchEmpty: Boolean;
    procedure GetViewPos(out ATopLine, ARow, ACol: Integer);
    procedure SetViewPos(ATopLine, ARow, ACol: Integer);
    /// <summary>Target of the Markdown link under the cursor.</summary>
    function LinkAtCursor(out ATarget: string): Boolean;
    /// <summary>Selects the next/previous Markdown link (wrapping around the
    /// document) and puts the cursor on its first character.</summary>
    function SelectMarkdownLink(AForward: Boolean): Boolean;
    /// <summary>ATarget carries a URI scheme ("https:", "mailto:", ...) --
    /// not a local topic / file / "#anchor".</summary>
    class function IsExternalLink(const ATarget: string): Boolean; static;
    /// <summary>Asks whether to open AUrl and, on OK, hands it to the OS
    /// default handler (the browser for http/https).</summary>
    procedure OpenExternalLink(const AUrl: string);
    /// <summary>A modal dialog (e.g. the open-link question) owns the input.</summary>
    function DialogOpen: Boolean;
    procedure NotFoundMessage(const ANeedle: string);
    property HelpMode: Boolean read FHelpMode write FHelpMode;
    property Chromeless: Boolean read FChromeless write FChromeless;
    /// <summary>Drops the document (cancels a load in flight, stops the file
    /// watcher) without firing OnCloseRequest. Open starts a new one.</summary>
    procedure CloseDocument;
    procedure ScrollLines(ADelta: Integer);
    property URI: string read FURI;
    property ViewOnly: Boolean read FViewOnly;
    property Embedded: Boolean read FEmbedded write FEmbedded;
    property OnCloseRequest: TNotifyEvent read FOnCloseRequest write FOnCloseRequest;
    property OnContentChanged: TNotifyEvent read FOnContentChanged write FOnContentChanged;
    procedure SetCursorVisible(AVisible: Boolean);
    property CursorVisible: Boolean read FCursorVisible;
  end;

implementation

uses
  System.IOUtils, System.StrUtils, FMX.Platform,
  uOverlayRenderer, uStrings, uDialogHistory, uDialogResources, uNotice,
  uShellAssoc, uKeyChord, uChromeRows;

const
  /// <summary>uDialogHistory key of the Find dialog; replace.json's Find field
  /// uses the same one.</summary>
  cEditFindHistory = 'editfind';

const
  cMaxUndo     = 100;
  // Rows reserved for a standalone "![alt](path)" image line when
  // its extension/path resolve to something the Overlay can preview - the
  // one deliberate break from "one source line = one screen line" (see
  // uMarkdownParser header), because a 1-cell-tall image isn't useful.
  cMdImageRows = 8;
  cMdLineCacheCap = 4000; // mirrors TEditorDoc.cStreamCacheCap
  cMdTableMaxRows = 256;

constructor TEditorWindow.Create(const ATheme: IThemeRenderer; AId: Cardinal);
begin
  inherited Create(ATheme, AId);
  FAlive := True;
  FDoc := TEditorDoc.Create;
  FDoc.OnChanged := DocChanged;
  FDialog := TDialogHost.Create(ATheme);
  FDialog.OnChanged := DialogChanged;
  FUndoBuffer := TEditorUndoBuffer.Create;
  FSelAnchorRow := -1;
  FSelAnchorCol := 0;
  FViewOnly := False;
  FHexMode := False;
  FMarkdownMode := False;
  FMdFenceIdx := TMarkdownFenceIndex.Create;
  FMdLineCache := TDictionary<Integer, TMdLine>.Create;
  FMdTableLayoutStart := -1;
  FMdLineCacheOrder := TQueue<Integer>.Create;
  FMdImageUriCache := TDictionary<string, string>.Create;
  FMdImageSizeCache := TDictionary<string, TMdImageSize>.Create;
  FMdLineCacheWidth := -1;
  FLastMdContentGen := 0;
  FMdOverlayShowing := False;
  FFindText := '';
  FFindStatus := '';
  FRepl := Default(TReplaceSession);
  FMouseSelecting := False;
  FEmbedded := False;
  Title := T('ui.window.editor', 'Editor');
  FConfirm := ecNone;
  FDialogs := TEditorDialogController.Create(FDialog,
    procedure begin NotifyHost; end,
    procedure begin FConfirm := ecNone; end,
    procedure begin SaveAndMaybeClose; end,
    procedure begin ForceClose; end,
    procedure(ALine: Integer) begin GotoLine(ALine); end,
    procedure
    begin
      FDoc.ApplyEncoding(FPendingEncoding, True);
      FHexMode := False;
      ClampCursor;
      EnsureCursorVisible;
      Title := ModeTitle + ' - ' + ExtractFileName(FDoc.Path);
    end,
    procedure(AEnc: TTextFileEncoding) begin RequestEncoding(AEnc, True); end,
    procedure(const AFind, ARepl: string; AAll: Boolean)
    begin
      ReplaceInDocument(AFind, ARepl, AAll);
    end,
    procedure(const AFind: string)
    begin
      FFindText := AFind;
      FindMatch(True);
    end,
    function: string
    begin
      Result := WordAtCursor;
    end,
    function: string
    begin
      Result := SelectionForSearch;
    end);
  BindKeymapHost;
end;

procedure TEditorWindow.RebuildBuffer;
var
  Local: TRectI;
begin
  if not FEmbedded then
  begin
    inherited;
    Exit;
  end;
  // Embedded under Dual Panel menu/tabs: still draw a full double-line frame
  // (top + left/right). Bottom of the frame is overwritten by F-keys/status;
  // DrawWindowBottomBorder closes the text area above chrome.
  if (Area.Width < 2) or (Area.Height < 2) then
  begin
    FNeedRebuild := False;
    Exit;
  end;
  Local := TRectI.Make(0, 0, Area.Width - 1, Area.Height - 1);
  ClearBodyBuffer;
  if Assigned(Theme) and not FChromeless then
    Theme.DrawWindowFrame(Buffer, Local, Title, WidgetState);
  DrawContent;
  FNeedRebuild := False;
end;

procedure TEditorWindow.PaintEmbedded(const ADest: TTerminalGrid;
  ADestLeft, ADestTop, AWidth, AHeight, AAbsLeft, AAbsTop: Integer);
var
  X, Y, DstX, DstY: Integer;
begin
  FEmbedded := True;
  if (AWidth < 2) or (AHeight < 2) then
    Exit;
  // Overlay Request uses Area as compositor cells (same as Quick View's
  // DualPanel.Area + panel inset). Dest blit stays window-local.
  Area := TRectI.Make(AAbsLeft, AAbsTop, AAbsLeft + AWidth - 1, AAbsTop + AHeight - 1);
  IsFocused := True;
  if FNeedRebuild then
    RebuildBuffer;
  for Y := 0 to High(FBuffer) do
  begin
    // Chromeless: the outer ring is the host panel's own frame -- leave it.
    if FChromeless and ((Y = 0) or (Y = High(FBuffer))) then
      Continue;
    DstY := ADestTop + Y;
    if (DstY < 0) or (DstY > High(ADest)) then
      Continue;
    for X := 0 to High(FBuffer[Y]) do
    begin
      if FChromeless and ((X = 0) or (X = High(FBuffer[Y]))) then
        Continue;
      DstX := ADestLeft + X;
      if (DstX < 0) or (DstX > High(ADest[DstY])) then
        Continue;
      ADest[DstY][DstX] := FBuffer[Y][X];
    end;
  end;
end;

function TEditorWindow.TabCaption: string;
var
  Name: string;
begin
  Name := ExtractFileName(FDoc.Path);
  if Name = '' then
    Name := FileUriTitle(FURI);
  if Name = '' then
    Name := ModeTitle;
  if (not FViewOnly) and FDoc.Dirty then
    Result := '*' + Name
  else
    Result := Name;
end;

function TEditorWindow.IsDirty: Boolean;
begin
  Result := (not FViewOnly) and FDoc.Dirty;
end;

procedure TEditorWindow.BeginClose;
begin
  RequestClose;
end;

function TEditorWindow.ModeTitle: string;
begin
  if FHelpMode then
    Result := T('ui.window.help', 'Help')
  else
    Result := EditorModeTitle(FHexMode, FMarkdownMode, FViewOnly);
end;

function TEditorWindow.CanEdit: Boolean;
begin
  if FHexMode then
    Result := EditorCanHexEdit(FViewOnly, FDoc.Ready, FDoc.ReadOnly,
      FDoc.Saving, FDoc.Loading)
  else
    Result := EditorCanEdit(FViewOnly, FHexMode, FMarkdownMode, FDoc.Binary,
      FDoc.Ready, FDoc.ReadOnly, FDoc.Saving, FDoc.Loading);
end;

function TEditorWindow.TryUnlockEdit: Boolean;
begin
  Result := CanEdit;
  if Result or FViewOnly or (not FDoc.Ready) then
    Exit;
  if FDoc.Streaming then
  begin
    Result := FDoc.TryPromoteStreaming;
    if Result and FDoc.Binary then
      FHexMode := True;
    NotifyHost;
    Exit;
  end;
  if FDoc.ReadOnly and (not HasArchiveChain(FDoc.URI)) then
  begin
    OfferClearReadOnly;
    Exit;
  end;
end;

procedure TEditorWindow.OfferClearReadOnly;
begin
  if FConfirm <> ecNone then
    Exit;
  FConfirm := ecClearReadOnly;
  FDialog.Open(BuildConfirmDialog(T('ui.editor.readOnlyTitle', 'Read-only file'),
    T('ui.editor.readOnlyMsg', 'Clear the OS read-only attribute and edit?')),
    procedure(const AControlId, AValuesJson: string)
    var
      Err: string;
    begin
      FDialog.Close;
      FConfirm := ecNone;
      if DialogCmdIsOk(AControlId) then
        FDoc.TryClearOsReadOnly(Err);
      NotifyHost;
    end);
  NotifyHost;
end;

procedure TEditorWindow.HexTypeChar(ACh: Char);
var
  Digit, Per, AbsIdx: Integer;
  Value: Byte;
begin
  Digit := TEditorHexFormatter.HexDigitValue(ACh);
  if Digit < 0 then
    Exit;
  if not CanEdit then
    Exit;
  Per := HexBytesPerRow;
  AbsIdx := TEditorHexFormatter.AbsoluteByteIndex(FCursorRow, FCursorCol, Per);
  if (AbsIdx < 0) or (AbsIdx >= FDoc.ByteCount) then
    Exit;
  if not FCoalesceInsert then
  begin
    PushUndo;
    FCoalesceInsert := True;
  end;
  Value := TEditorHexFormatter.ApplyNibble(FDoc.GetByte(AbsIdx), Digit, FHexHighNibble);
  FDoc.SetByte(AbsIdx, Value);
  if FHexHighNibble then
    FHexHighNibble := False
  else
  begin
    FHexHighNibble := True;
    if AbsIdx < FDoc.ByteCount - 1 then
    begin
      Inc(AbsIdx);
      FCursorRow := AbsIdx div Per;
      FCursorCol := AbsIdx mod Per;
    end;
  end;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.HexInsertZero;
var
  Per, AbsIdx: Integer;
begin
  if not CanEdit then
    Exit;
  Per := HexBytesPerRow;
  AbsIdx := TEditorHexFormatter.AbsoluteByteIndex(FCursorRow, FCursorCol, Per);
  if AbsIdx < 0 then
    AbsIdx := FDoc.ByteCount;
  PushUndo;
  FDoc.InsertByte(AbsIdx, 0);
  FHexHighNibble := True;
  FCursorRow := AbsIdx div Per;
  FCursorCol := AbsIdx mod Per;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.HexDeleteAtCursor(ABackspace: Boolean);
var
  Per, AbsIdx: Integer;
begin
  if not CanEdit then
    Exit;
  Per := HexBytesPerRow;
  AbsIdx := TEditorHexFormatter.AbsoluteByteIndex(FCursorRow, FCursorCol, Per);
  if ABackspace then
  begin
    if AbsIdx <= 0 then
      Exit;
    Dec(AbsIdx);
  end;
  if (AbsIdx < 0) or (AbsIdx >= FDoc.ByteCount) then
    Exit;
  PushUndo;
  FDoc.DeleteByte(AbsIdx);
  if AbsIdx >= FDoc.ByteCount then
    AbsIdx := FDoc.ByteCount - 1;
  if AbsIdx < 0 then
    AbsIdx := 0;
  FHexHighNibble := True;
  if Per > 0 then
  begin
    FCursorRow := AbsIdx div Per;
    FCursorCol := AbsIdx mod Per;
  end;
  EnsureCursorVisible;
  NotifyHost;
end;

function TEditorWindow.MenuDocReady: Boolean;
begin
  Result := Assigned(FDoc) and FDoc.Ready;
end;

function TEditorWindow.MenuCanEdit: Boolean;
begin
  Result := CanEdit;
end;

function TEditorWindow.MenuHexBinaryLocked: Boolean;
begin
  Result := FHexMode and Assigned(FDoc) and FDoc.Binary;
end;

function TEditorWindow.MenuCanUndo: Boolean;
begin
  Result := CanEdit and Assigned(FUndoBuffer) and FUndoBuffer.CanUndo;
end;

function TEditorWindow.MenuCanRedo: Boolean;
begin
  Result := CanEdit and Assigned(FUndoBuffer) and FUndoBuffer.CanRedo;
end;

function TEditorWindow.ChromeContext: TFunctionBarContext;
begin
  if Assigned(FDialog) and FDialog.Visible then
  begin
    if FConfirm = ecAskSave then
      Exit(fbcEditorAskSave);
    if FConfirm = ecDiscardEncoding then
      Exit(fbcStubEdit);
    Exit(FDialog.ChromeContext);
  end;
  if FHelpMode then
  begin
    if FindNeedleEmpty then
      Exit(fbcHelp);
    Exit(fbcHelpSearch);
  end;
  if FHexMode and FViewOnly then
    Result := fbcViewerHex
  else if FHexMode then
    Result := fbcEditor
  else if FMarkdownMode then
    Result := fbcViewerMarkdown
  else if FViewOnly then
    Result := fbcViewer
  else
    Result := fbcEditor;
end;

destructor TEditorWindow.Destroy;
begin
  FAlive := False;
  if FMdOverlayShowing then
    ClearOverlayPreview;
  FreeAndNil(FDialogs);
  if Assigned(FDialog) then
  begin
    FDialog.OnChanged := nil;
    FDialog.Close;
    FreeAndNil(FDialog);
  end;
  FDoc.OnChanged := nil;
  FreeAndNil(FUndoBuffer);
  FreeAndNil(FDoc);
  FreeAndNil(FMdFenceIdx);
  FreeAndNil(FMdLineCache);
  FreeAndNil(FMdLineCacheOrder);
  FreeAndNil(FMdImageUriCache);
  FreeAndNil(FMdImageSizeCache);
  inherited Destroy;
end;

procedure TEditorWindow.NotifyHost;
begin
  Invalidate;
  if Assigned(FOnContentChanged) then
    FOnContentChanged(Self);
end;

procedure TEditorWindow.DocChanged(Sender: TObject);
var
  Star: string;
  JustRestored, Replaced: Boolean;
begin
  if not FAlive then
    Exit;
  // A live reload (FDoc's own file-watcher) replaces the document's content
  // without going through Open, so the markdown fence index / line cache -
  // keyed by line index into content that just changed underneath - would
  // otherwise keep serving stale parses for lines whose text didn't shift
  // but whose meaning did (or worse, serve a cached table block that no
  // longer matches its (now different) source rows).
  Replaced := FDoc.Ready and (FDoc.ContentGen <> FLastMdContentGen);
  if Replaced then
  begin
    FLastMdContentGen := FDoc.ContentGen;
    FMdFenceIdx.Reset;
    FMdLineCache.Clear;
    FMdTableLayoutStart := -1;
    FMdLineCacheOrder.Clear;
    FMdImageUriCache.Clear;
    FMdImageSizeCache.Clear;
  end;
  // Auto Hex for binary payloads. F3 stays view-only; F4 keeps hex editable.
  if FDoc.Ready and FDoc.Binary then
    FHexMode := True;
  JustRestored := False;
  if FDoc.Ready and not FPositionRestored then
  begin
    FPositionRestored := True;
    RestoreSavedPosition;
    JustRestored := True;
    // Default F3 on a .md file to the rendered view - only on this
    // one-time "doc just became ready" tick, so a later Ctrl+M (raw text)
    // isn't silently undone by an unrelated DocChanged (dirty/saving state
    // changes fire this same event). Never for F4/Editor - raw source only.
    if (not FDoc.Binary) and FViewOnly and IsMarkdownFile then
      FMarkdownMode := True;
  end;
  // The editor's own edits (SetLine / InsertLine / DeleteLine inside a
  // command) fire this too, halfway through: the line is already changed but
  // the command has not moved the cursor yet. Clamping then would move the
  // cursor a second time (Backspace at the end of a line would land one column
  // short). Each command places the cursor itself; only content replaced
  // underneath it (load, reload) needs clamping here.
  if Replaced or JustRestored or not FDoc.Ready then
  begin
    ClampCursor;
    // EnsureCursorVisible re-anchors FTopLine/FLeftCol to keep the cursor in
    // view - exactly the opposite of what a just-restored position wants:
    // the saved top-left corner is authoritative, the cursor is drawn
    // wherever it falls relative to it (it was saved from the same session,
    // so normally it's already inside that view). Skip it for this one tick
    // only.
    if not JustRestored then
      EnsureCursorVisible;
  end;
  if (not FViewOnly) and FDoc.Dirty then
    Star := '* '
  else
    Star := '';
  if FDoc.Ready and FHelpMode and (FDoc.LineCount > 0) and
     StartsText('#', TrimLeft(FDoc.GetLine(0))) then
    // Help topic: its "# Heading" names the window, not the file name.
    Title := ModeTitle + ' - ' + Trim(TrimLeft(FDoc.GetLine(0)).TrimLeft(['#']))
  else if FDoc.Ready then
    Title := ModeTitle + ' - ' + Star + ExtractFileName(FDoc.Path)
  else if FDoc.Loading then
    Title := ModeTitle + ' - loading...'
  else if FDoc.Error <> '' then
    Title := ModeTitle + ' - error'
  else
    Title := ModeTitle;

  if FCloseAfterSave and (not FDoc.Saving) then
  begin
    if (not FDoc.Dirty) and (FDoc.Error = '') then
    begin
      FCloseAfterSave := False;
      ForceClose;
      Exit;
    end;
    FCloseAfterSave := False;
  end;
  NotifyHost;
end;

procedure TEditorWindow.Open(const AURI: string; AViewOnly: Boolean);
begin
  FURI := AURI;
  FViewOnly := AViewOnly;
  FHexMode := False;
  FHexHighNibble := True;
  FMarkdownMode := False;
  FMdFenceIdx.Reset;
  FMdLineCache.Clear;
  FMdTableLayoutStart := -1;
  FMdLineCacheOrder.Clear;
  FMdImageUriCache.Clear;
  FMdImageSizeCache.Clear;
  LeaveMarkdownOverlay;
  FTopLine := 0;
  FTopSubRow := 0;
  FLeftCol := 0;
  FCursorRow := 0;
  FCursorCol := 0;
  // Applied once the async load reaches Ready (DocChanged) - the document
  // has no lines/bytes to clamp against before then.
  FPositionRestored := False;
  ClearSelection;
  FConfirm := ecNone;
  if Assigned(FDialog) then
    FDialog.Close;
  FCloseAfterSave := False;
  FCoalesceInsert := False;
  FCursorVisible := not FChromeless;
  FFindStatus := '';
  FFindText := '';
  FRepl.Active := False;
  FMouseSelecting := False;
  ClearHistory;
  Title := ModeTitle + ' - ' + FileUriTitle(AURI);
  FDoc.OpenAsync(AURI, not AViewOnly);
  NotifyHost;
end;

/// <summary>Called from DocChanged once the async load reaches Ready.
/// Applies the saved top-left scroll corner, cursor, and (if any)
/// selection alike in Viewer and Editor.</summary>
procedure TEditorWindow.RestoreSavedPosition;
var
  Pos: TFilePosition;
begin
  if FHelpMode or FChromeless or not TryGetFilePosition(FURI, Pos) then
    Exit;
  if FViewOnly and (Pos.WordWrap <> fwwKeep) then
    FWordWrap := Pos.WordWrap = fwwOn;
  FTopLine := Pos.TopLine;
  FTopSubRow := 0;
  FLeftCol := Pos.LeftCol;
  FCursorRow := Pos.CursorRow;
  FCursorCol := Pos.CursorCol;
  if Pos.HasSelection then
  begin
    FSelAnchorRow := Pos.SelAnchorRow;
    FSelAnchorCol := Pos.SelAnchorCol;
  end
  else
    ClearSelection;
end;

/// <summary>Called right before the window closes (ForceClose).</summary>
procedure TEditorWindow.SaveCurrentPosition;
var
  Wrap: TFileWordWrap;
begin
  if FHelpMode or FChromeless or (Trim(FURI) = '') or not FDoc.Ready then
    Exit;
  // Only the Viewer wraps lines (F2), so only it records the mode.
  if not FViewOnly then
    Wrap := fwwKeep
  else if FWordWrap then
    Wrap := fwwOn
  else
    Wrap := fwwOff;
  SaveFilePosition(FURI, FTopLine, FLeftCol, FCursorRow, FCursorCol,
    HasSelection, FSelAnchorRow, FSelAnchorCol, Wrap);
end;

function TEditorWindow.ViewHeight: Integer;
begin
  // Row 0 = title; ...; bottom frame; F-keys; status line (uChromeRows,
  // each can be hidden). Chromeless: rows 1..H-2 inside the host's frame.
  if FChromeless then
    Exit(Max(Area.Height - 2, 1));
  Result := Max(Area.Height - 2 - ChromeBottomRows, 1);
end;

function TEditorWindow.ContentBottomRow: Integer;
begin
  // Last content row above the bottom window border (= ViewHeight).
  Result := ViewHeight;
end;

function TEditorWindow.FrameBorderColor: TAlphaColor;
begin
  if IsFocused then
    Result := FThemeColors.FrameFocus
  else
    Result := FThemeColors.FrameIdle;
end;

procedure TEditorWindow.DrawWindowBottomBorder(AY, AWidth: Integer);
var
  X: Integer;
  Border: TAlphaColor;
  UseDouble: Boolean;
  GlyphBL, GlyphBR, GlyphH: Char;
begin
  Border := FrameBorderColor;
  // This bottom edge is Host-drawn (the F-key bar/status line occupy the
  // window's own bottom border, so Theme.DrawWindowFrame - which already
  // correctly picks single vs double line per theme for the top/sides -
  // never reaches this row). Always closing it with double-line glyphs
  // would only match NDN/TotalCommander/HighContrast. Same as the
  // panel divider: ask the theme, and only use
  // double-line while this window is the focused one (idle stays single
  // even on themes that support double, matching the rest of the app).
  UseDouble := Assigned(Theme) and Theme.UsesDoubleLineForActivePanel and IsFocused;
  if UseDouble then
  begin
    GlyphBL := chDblBL;
    GlyphBR := chDblBR;
    GlyphH := chDblH;
  end
  else
  begin
    GlyphBL := chBoxBL;
    GlyphBR := chBoxBR;
    GlyphH := chBoxH;
  end;
  DrawGridChar(Buffer, 0, AY, GlyphBL, Border, FThemeColors.BodyBg);
  DrawGridChar(Buffer, AWidth - 1, AY, GlyphBR, Border, FThemeColors.BodyBg);
  for X := 1 to AWidth - 2 do
    DrawGridChar(Buffer, X, AY, GlyphH, Border, FThemeColors.BodyBg);
end;

function TEditorWindow.TextWidth: Integer;
begin
  // Leave right column inside the frame for the scrollbar.
  Result := Max(Area.Width - 3, 4);
end;

function TEditorWindow.HexBytesPerRow: Integer;
begin
  Result := TEditorHexFormatter.BytesPerRow(TextWidth);
end;

function TEditorWindow.HexRowCount: Integer;
begin
  Result := TEditorHexFormatter.HexRowCount(FDoc.ByteCount, TextWidth);
end;

function TEditorWindow.GetWrappedRowCount(ATextW: Integer): Integer;
begin
  Result := CountWrappedRows(FDoc.LineCount, ATextW,
    function(AIndex: Integer): Integer
    begin
      Result := Length(FDoc.GetLine(AIndex));
    end);
end;

function TEditorWindow.MapDisplayRowToLine(ADisplayRow, ATextW: Integer; out ALineIdx, ACharOffset: Integer): Boolean;
begin
  Result := MapWrappedDisplayToLine(FDoc.LineCount, ADisplayRow, ATextW,
    function(AIndex: Integer): Integer
    begin
      Result := Length(FDoc.GetLine(AIndex));
    end, ALineIdx, ACharOffset);
end;

function TEditorWindow.MapLineToDisplayRow(ALineIdx, ACharOffset, ATextW: Integer): Integer;
begin
  if not FDoc.Ready then
    Exit(0);
  Result := MapWrappedLineToDisplay(FDoc.LineCount, ALineIdx, ACharOffset, ATextW,
    function(AIndex: Integer): Integer
    begin
      Result := Length(FDoc.GetLine(AIndex));
    end);
end;

function TEditorWindow.MarkdownLineScreenRows(ALineIdx, ATextW, ARemainRows: Integer): Integer;
var
  MdLine: TMdLine;
  ImgUri: string;
  ImgCols: Integer;
  ImgScale: Single;
begin
  MdLine := GetMdLine(ALineIdx);
  if MdLine.IsImage and not FChromeless then
  begin
    ImgUri := ResolveMarkdownImageUri(MdLine.ImagePath);
    if (ImgUri <> '') and IsOverlayImageExtension(ExtractFileExt(MdLine.ImagePath)) then
      Exit(Min(MarkdownImageBlock(ImgUri, MdLine.ImageWidth, MdLine.ImageHeight,
        ATextW, ViewHeight, ImgCols, ImgScale),
        Max(ARemainRows, 1)));
  end;
  Result := Length(MarkdownWrapStarts(MdLine, ATextW));
  if Result < 1 then
    Result := 1;
end;

// Rows a line is scrolled and walked by: the wrapped rows of its text; a
// picture is one step.
function TEditorWindow.MarkdownChunkCount(ALineIdx, ATextW: Integer): Integer;
var
  MdLine: TMdLine;
begin
  MdLine := GetMdLine(ALineIdx);
  if MdLine.IsImage and not FChromeless then
    Exit(1);
  Result := Max(Length(MarkdownWrapStarts(MdLine, ATextW)), 1);
end;

// FTopSubRow kept inside the top line's rows (the width may have changed).
function TEditorWindow.MarkdownTopSubRow: Integer;
begin
  if (FTopLine < 0) or (FTopLine >= FDoc.LineCount) then
    Exit(0);
  Result := EnsureRange(FTopSubRow, 0, MarkdownChunkCount(FTopLine, TextWidth) - 1);
end;

// Index of the wrapped row of a line that holds column ACol.
function TEditorWindow.MarkdownCursorChunk(ALineIdx, ACol, ATextW: Integer): Integer;
var
  MdLine: TMdLine;
  Starts: TArray<Integer>;
  I: Integer;
begin
  Result := 0;
  MdLine := GetMdLine(ALineIdx);
  if MdLine.IsImage and not FChromeless then
    Exit;
  Starts := MarkdownWrapStarts(MdLine, ATextW);
  for I := High(Starts) downto 0 do
    if Starts[I] <= ACol + 1 then
      Exit(I);
end;

// Up/Down/PgUp/PgDn in the Markdown view walk screen rows, keeping the
// column inside the wrapped row, so a long paragraph is read to its end.
procedure TEditorWindow.MoveMarkdownCursorRows(ARowDelta, ATextW: Integer);
var
  Line, Pos, Rows, SegCol, ChunkEnd, Remaining: Integer;
  MdLine: TMdLine;
  Starts: TArray<Integer>;
begin
  Line := EnsureRange(FCursorRow, 0, Max(FDoc.LineCount - 1, 0));
  Pos := MarkdownCursorChunk(Line, FCursorCol, ATextW);
  MdLine := GetMdLine(Line);
  Starts := MarkdownWrapStarts(MdLine, ATextW);
  if Pos <= High(Starts) then
    SegCol := FCursorCol - (Starts[Pos] - 1)
  else
    SegCol := FCursorCol;
  Remaining := ARowDelta;
  while Remaining > 0 do
  begin
    Rows := MarkdownChunkCount(Line, ATextW);
    if Pos + Remaining < Rows then
    begin
      Inc(Pos, Remaining);
      Remaining := 0;
    end
    else if Line >= FDoc.LineCount - 1 then
    begin
      Pos := Rows - 1;
      Remaining := 0;
    end
    else
    begin
      Dec(Remaining, Rows - Pos);
      Inc(Line);
      Pos := 0;
    end;
  end;
  while Remaining < 0 do
  begin
    if Pos + Remaining >= 0 then
    begin
      Inc(Pos, Remaining);
      Remaining := 0;
    end
    else if Line = 0 then
    begin
      Pos := 0;
      Remaining := 0;
    end
    else
    begin
      Inc(Remaining, Pos + 1);
      Dec(Line);
      Pos := MarkdownChunkCount(Line, ATextW) - 1;
    end;
  end;
  MdLine := GetMdLine(Line);
  FCursorRow := Line;
  if MdLine.IsImage and not FChromeless then
  begin
    FCursorCol := 0;
    Exit;
  end;
  Starts := MarkdownWrapStarts(MdLine, ATextW);
  if (Pos > High(Starts)) or (Length(Starts) = 0) then
  begin
    FCursorCol := 0;
    Exit;
  end;
  if Pos < High(Starts) then
    ChunkEnd := Starts[Pos + 1] - 2
  else
    ChunkEnd := Length(MdLine.DisplayText);
  FCursorCol := Min(Starts[Pos] - 1 + Max(SegCol, 0), ChunkEnd);
end;

function TEditorWindow.MapMarkdownViewToPos(AViewRow, AViewCol: Integer;
  out ALineIdx, ACol: Integer): Boolean;
var
  TextW, ViewH, Y, LineIdx, Rows, RowInLine, ChunkStart, DisplayLen: Integer;
  MdLine: TMdLine;
  WrapStarts: TArray<Integer>;
begin
  Result := False;
  ALineIdx := 0;
  ACol := 0;
  if not FDoc.Ready or (AViewRow < 0) then
    Exit;
  TextW := TextWidth;
  ViewH := ViewHeight;
  Y := -MarkdownTopSubRow;
  LineIdx := FTopLine;
  while (Y < ViewH) and (LineIdx < FDoc.LineCount) do
  begin
    Rows := MarkdownLineScreenRows(LineIdx, TextW, ViewH - Y);
    if AViewRow < Y + Rows then
    begin
      ALineIdx := LineIdx;
      MdLine := GetMdLine(LineIdx);
      WrapStarts := MarkdownWrapStarts(MdLine, TextW);
      DisplayLen := Length(MdLine.DisplayText);
      RowInLine := AViewRow - Y;
      if Length(WrapStarts) = 0 then
        ACol := 0
      else
      begin
        if RowInLine > High(WrapStarts) then
          RowInLine := High(WrapStarts);
        ChunkStart := WrapStarts[RowInLine];
        ACol := ChunkStart - 1 + Max(AViewCol, 0);
      end;
      if ACol > DisplayLen then
        ACol := DisplayLen;
      if ACol < 0 then
        ACol := 0;
      Exit(True);
    end;
    Inc(Y, Rows);
    Inc(LineIdx);
  end;
end;

procedure TEditorWindow.ToggleWordWrap;
begin
  FWordWrap := not FWordWrap;
  FLeftCol := 0;
  FTopLine := 0;
  FTopSubRow := 0;
  EnsureCursorVisible;
  NotifyHost;
end;

function TEditorWindow.ContentRowCount: Integer;
begin
  if FHexMode and FDoc.Ready then
    Result := HexRowCount
  else if FWordWrap and FViewOnly and FDoc.Ready and (TextWidth > 0) then
    Result := GetWrappedRowCount(TextWidth)
  else if FDoc.Ready then
    Result := Max(FDoc.LineCount, 1)
  else
    Result := 1;
end;

function TEditorWindow.FormatHexLine(ARow: Integer): string;
begin
  Result := TEditorHexFormatter.FormatHexLine(ARow, TextWidth, FDoc.ByteCount,
    function(AIdx: Integer): Byte
    begin
      Result := FDoc.GetByte(AIdx);
    end);
end;

procedure TEditorWindow.ScrollTo(ATop: Integer);
var
  MaxTop: Integer;
begin
  MaxTop := Max(ContentRowCount - ViewHeight, 0);
  if ATop < 0 then
    ATop := 0;
  if ATop > MaxTop then
    ATop := MaxTop;
  if (ATop = FTopLine) and (FTopSubRow = 0) then
    Exit;
  FTopLine := ATop;
  FTopSubRow := 0;
  NotifyHost;
end;

procedure TEditorWindow.ScrollBy(ADelta: Integer);
begin
  if FMarkdownMode and FDoc.Ready and not FHexMode then
    ScrollMarkdownRows(ADelta)
  else
    ScrollTo(FTopLine + ADelta);
end;

// A Markdown paragraph wraps into several screen rows; the wheel and the
// cursor keys move the view one row at a time instead of one paragraph.
procedure TEditorWindow.ScrollMarkdownRows(ADelta: Integer);
var
  TextW, Rows, OldTop, OldSub: Integer;
begin
  OldTop := FTopLine;
  OldSub := FTopSubRow;
  TextW := TextWidth;
  FTopSubRow := MarkdownTopSubRow;
  while ADelta > 0 do
  begin
    Rows := MarkdownChunkCount(FTopLine, TextW);
    if FTopSubRow + ADelta < Rows then
    begin
      Inc(FTopSubRow, ADelta);
      ADelta := 0;
    end
    else if FTopLine >= FDoc.LineCount - 1 then
    begin
      FTopSubRow := Rows - 1;
      ADelta := 0;
    end
    else
    begin
      Dec(ADelta, Rows - FTopSubRow);
      Inc(FTopLine);
      FTopSubRow := 0;
    end;
  end;
  while ADelta < 0 do
  begin
    if FTopSubRow + ADelta >= 0 then
    begin
      Inc(FTopSubRow, ADelta);
      ADelta := 0;
    end
    else if FTopLine = 0 then
    begin
      FTopSubRow := 0;
      ADelta := 0;
    end
    else
    begin
      Inc(ADelta, FTopSubRow + 1);
      Dec(FTopLine);
      FTopSubRow := MarkdownChunkCount(FTopLine, TextW) - 1;
    end;
  end;
  if (FTopLine <> OldTop) or (FTopSubRow <> OldSub) then
    NotifyHost;
end;

procedure TEditorWindow.ClampCursor;
begin
  if not FDoc.Ready then
  begin
    FCursorRow := 0;
    FCursorCol := 0;
    Exit;
  end;
  ClampDocPos(FCursorRow, FCursorCol);
  if FHexMode then
    FLeftCol := 0;
end;

// A Markdown line can take several screen rows (wrapped table cells), so
// "cursor line vs. FTopLine + ViewHeight" (the plain-text rule: 1 line =
// 1 row) cannot tell whether the cursor's line is visible. FTopLine stays a
// line index (DrawMarkdownContent starts each frame at a line boundary);
// this decides how far FTopLine moves to show the cursor. Both walks below
// take at most AViewH steps (every line is at least 1 row), whatever the
// document size or how far the cursor jumped.
procedure TEditorWindow.EnsureMarkdownCursorVisible(AViewH, ATextW: Integer);
var
  Line, RowsFromTop, Rows, Sub, Remaining, CursorChunk, Below: Integer;
begin
  CursorChunk := MarkdownCursorChunk(FCursorRow, FCursorCol, ATextW);
  // A picture is one step for the cursor but several rows on the screen: with
  // the cursor on it, its rows below the first one must be in view too.
  Below := Min(Max(MarkdownLineScreenRows(FCursorRow, ATextW, AViewH) -
    MarkdownChunkCount(FCursorRow, ATextW), 0), Max(AViewH - 1, 0));
  Sub := MarkdownTopSubRow;
  if (FCursorRow < FTopLine) or ((FCursorRow = FTopLine) and (CursorChunk < Sub)) then
  begin
    FTopLine := FCursorRow;
    FTopSubRow := CursorChunk;
    Exit;
  end;
  RowsFromTop := -Sub;
  Line := FTopLine;
  while Line < FCursorRow do
  begin
    if RowsFromTop >= AViewH then
      Break;
    Inc(RowsFromTop, MarkdownLineScreenRows(Line, ATextW, MaxInt));
    Inc(Line);
  end;
  if (Line = FCursorRow) and (RowsFromTop + CursorChunk + Below < AViewH) then
  begin
    FTopSubRow := Sub;
    Exit; // the cursor's row is already inside the visible window
  end;

  // Not visible: walk back from the cursor's own row until it is the last
  // row of the window.
  Line := FCursorRow;
  Sub := CursorChunk;
  Remaining := AViewH - 1 - Below;
  while Remaining > 0 do
  begin
    if Sub >= Remaining then
    begin
      Dec(Sub, Remaining);
      Break;
    end;
    Dec(Remaining, Sub);
    Sub := 0;
    if (Remaining = 0) or (Line = 0) then
      Break;
    Dec(Line);
    Rows := MarkdownLineScreenRows(Line, ATextW, MaxInt);
    if Rows > MarkdownChunkCount(Line, ATextW) then
    begin
      // A picture is shown whole or not at all: when it does not fit above
      // the cursor the window starts just below it.
      if Rows > Remaining then
      begin
        Inc(Line);
        Break;
      end;
      Dec(Remaining, Rows);
      Continue;
    end;
    Dec(Remaining);
    Sub := MarkdownChunkCount(Line, ATextW) - 1;
  end;
  FTopLine := Line;
  FTopSubRow := Sub;
end;

procedure TEditorWindow.EnsureCursorVisible;
var
  ViewH, TextW, TargetRow: Integer;
begin
  ViewH := ViewHeight;
  TextW := TextWidth;
  if FMarkdownMode then
  begin
    EnsureMarkdownCursorVisible(ViewH, TextW);
    Exit;
  end;
  if FWordWrap and FViewOnly and (TextW > 0) then
  begin
    FLeftCol := 0;
    TargetRow := MapLineToDisplayRow(FCursorRow, FCursorCol, TextW);
    if TargetRow < FTopLine then
      FTopLine := TargetRow;
    if TargetRow >= FTopLine + ViewH then
      FTopLine := TargetRow - ViewH + 1;
    if FTopLine < 0 then
      FTopLine := 0;
    Exit;
  end;

  if FCursorRow < FTopLine then
    FTopLine := FCursorRow;
  if FCursorRow >= FTopLine + ViewH then
    FTopLine := FCursorRow - ViewH + 1;
  if FTopLine < 0 then
    FTopLine := 0;
  if FHexMode then
  begin
    FLeftCol := 0;
    Exit;
  end;
  if FCursorCol < FLeftCol then
    FLeftCol := FCursorCol;
  if FCursorCol >= FLeftCol + TextW then
    FLeftCol := FCursorCol - TextW + 1;
  if FLeftCol < 0 then
    FLeftCol := 0;
end;

procedure TEditorWindow.ClampDocPos(var ARow, ACol: Integer);
var
  LineLen, Per, Off, MaxOff, Rows: Integer;
begin
  if not FDoc.Ready then
  begin
    ARow := 0;
    ACol := 0;
    Exit;
  end;
  if FHexMode then
  begin
    Per := HexBytesPerRow;
    if Per < 1 then
      Per := 16;
    Off := ARow * Per + ACol;
    if Off < 0 then
      Off := 0;
    MaxOff := Max(FDoc.ByteCount - 1, 0);
    if FDoc.ByteCount = 0 then
      Off := 0
    else if Off > MaxOff then
      Off := MaxOff;
    ARow := Off div Per;
    ACol := Off mod Per;
    Rows := HexRowCount;
    if ARow >= Rows then
      ARow := Max(Rows - 1, 0);
    Exit;
  end;
  if FDoc.LineCount = 0 then
    FDoc.EnsureLine(0);
  if ARow < 0 then
    ARow := 0;
  if ARow >= FDoc.LineCount then
    ARow := FDoc.LineCount - 1;
  // The Markdown view walks columns of the displayed text, which can be
  // longer than the source line (a wrapped table row).
  if FMarkdownMode and not FHexMode then
    LineLen := Length(GetMdLine(ARow).DisplayText)
  else
    LineLen := Length(FDoc.GetLine(ARow));
  if ACol < 0 then
    ACol := 0;
  if ACol > LineLen then
    ACol := LineLen;
end;

function TEditorWindow.HitTextCell(ALocalCol, ALocalRow: Integer;
  out ARow, ACol: Integer): Boolean;
var
  Bottom, TextW, Per, AscStart, SIdx, CharOffset: Integer;
begin
  Result := False;
  ARow := 0;
  ACol := 0;
  if not FDoc.Ready or (FConfirm <> ecNone) then
    Exit;
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  Bottom := ContentBottomRow;
  TextW := TextWidth;
  // Content cells: cols 1..TextW, rows 1..Bottom (scrollbar is Width-2).
  if (ALocalRow < 1) or (ALocalRow > Bottom) then
    Exit;
  if (ALocalCol < 1) or (ALocalCol > TextW) then
    Exit;

  if FHexMode then
  begin
    ARow := FTopLine + (ALocalRow - 1);
    Per := HexBytesPerRow;
    AscStart := TEditorHexFormatter.AsciiColStart(Per);
    SIdx := ALocalCol; // 1-based index into drawn line
    if SIdx >= AscStart + 1 then
      ACol := SIdx - (AscStart + 1)
    else if SIdx >= TEditorHexFormatter.HexColStart + 1 then
      ACol := (SIdx - (TEditorHexFormatter.HexColStart + 1)) div 3
    else
      ACol := 0;
    if ACol >= Per then
      ACol := Per - 1;
    if ACol < 0 then
      ACol := 0;
    ClampDocPos(ARow, ACol);
    Result := True;
    Exit;
  end;

  if FMarkdownMode then
  begin
    if MapMarkdownViewToPos(ALocalRow - 1, ALocalCol - 1, ARow, ACol) then
    begin
      ClampDocPos(ARow, ACol);
      Result := True;
    end;
    Exit;
  end;

  if FWordWrap and FViewOnly and (TextW > 0) then
  begin
    if MapDisplayRowToLine(FTopLine + (ALocalRow - 1), TextW, ARow, CharOffset) then
    begin
      ACol := CharOffset + (ALocalCol - 1);
      ClampDocPos(ARow, ACol);
      Result := True;
      Exit;
    end;
  end;

  ARow := FTopLine + (ALocalRow - 1);
  ACol := FLeftCol + (ALocalCol - 1);
  ClampDocPos(ARow, ACol);
  Result := True;
end;

procedure TEditorWindow.SetCursorPos(ARow, ACol: Integer; AExtendSel: Boolean);
begin
  ClampDocPos(ARow, ACol);
  BreakInsertCoalesce;
  if AExtendSel then
    EnsureSelAnchor
  else
  begin
    FSelAnchorRow := ARow;
    FSelAnchorCol := ACol;
  end;
  FCursorRow := ARow;
  FCursorCol := ACol;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.SelectClickRange(ARow, ACol: Integer; AWholeLine: Boolean);
var
  Line: string;
  WStart, WEnd: Integer;
begin
  ClampDocPos(ARow, ACol);
  BreakInsertCoalesce;
  Line := CursorLineText(ARow);
  if AWholeLine then
  begin
    FSelAnchorRow := ARow;
    FSelAnchorCol := 0;
    // Include the line break when there is a next line, so copy/delete of a
    // triple-clicked line behaves like a whole-line block.
    if ARow < FDoc.LineCount - 1 then
    begin
      FCursorRow := ARow + 1;
      FCursorCol := 0;
    end
    else
    begin
      FCursorRow := ARow;
      FCursorCol := Length(Line);
    end;
  end
  else
  begin
    TextWordRangeAt(Line, ACol, WStart, WEnd);
    FSelAnchorRow := ARow;
    FSelAnchorCol := WStart;
    FCursorRow := ARow;
    FCursorCol := WEnd;
  end;
  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.ForceClose;
begin
  SaveCurrentPosition;
  FConfirm := ecNone;
  FMouseSelecting := False;
  LeaveMarkdownOverlay;
  if Assigned(FDialog) then
    FDialog.Close;
  FDoc.Close;
  if Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self);
end;

procedure TEditorWindow.RequestClose;
var
  Name: string;
begin
  if FDoc.Saving or FDoc.Loading then
    Exit;
  if (not FViewOnly) and FDoc.Dirty then
  begin
    FConfirm := ecAskSave;
    Name := ExtractFileName(FDoc.Path);
    if Name = '' then
      Name := FileUriTitle(FURI);
    FDialogs.OpenAskSave(Name);
  end
  else
    ForceClose;
end;

procedure TEditorWindow.SaveAndMaybeClose;
begin
  FCloseAfterSave := True;
  FDoc.SaveAsync(FHexMode);
  NotifyHost;
end;

procedure TEditorWindow.SaveDoc;
begin
  FDoc.SaveAsync(FHexMode);
end;

function TEditorWindow.FindNeedleEmpty: Boolean;
begin
  SeedFindFromHistory;
  Result := Trim(FFindText) = '';
end;

procedure TEditorWindow.SeedFindFromHistory;
var
  Items: TArray<string>;
begin
  if Trim(FFindText) <> '' then
    Exit;
  // Nothing searched in this editor yet: start from the latest search, which
  // includes the "Containing text" of a file search (Alt+F7).
  Items := DialogHistoryItems(cEditFindHistory);
  if Length(Items) > 0 then
    FFindText := Items[0];
end;

function TEditorWindow.EditorIsViewOnly: Boolean;
begin
  Result := FViewOnly;
end;

function TEditorWindow.EditorIsMarkdownMode: Boolean;
begin
  Result := FMarkdownMode;
end;

procedure TEditorWindow.FindNextOrPrev(AForward: Boolean);
begin
  FindMatch(AForward);
end;

procedure TEditorWindow.GotoFileHome(AExtendSel: Boolean);
begin
  BreakInsertCoalesce;
  if AExtendSel then
    EnsureSelAnchor
  else
    ClearSelection;
  FCursorRow := 0;
  FCursorCol := 0;
  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.GotoFileEnd(AExtendSel: Boolean);
begin
  BreakInsertCoalesce;
  if AExtendSel then
    EnsureSelAnchor
  else
    ClearSelection;
  if FHexMode then
  begin
    FCursorRow := Max(HexRowCount - 1, 0);
    FCursorCol := HexBytesPerRow - 1;
  end
  else
  begin
    FCursorRow := Max(FDoc.LineCount - 1, 0);
    FCursorCol := Length(CursorLineText(FCursorRow));
  end;
  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.GotoLineHome(AExtendSel: Boolean);
begin
  BreakInsertCoalesce;
  if AExtendSel then
    EnsureSelAnchor
  else
    ClearSelection;
  FCursorCol := 0;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.GotoLineEnd(AExtendSel: Boolean);
begin
  BreakInsertCoalesce;
  ClampCursor;
  if AExtendSel then
    EnsureSelAnchor
  else
    ClearSelection;
  FCursorCol := Length(CursorLineText(FCursorRow));
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.BindKeymapHost;
begin
  FKeymapHost.CanEdit := CanEdit;
  FKeymapHost.ViewOnly := EditorIsViewOnly;
  FKeymapHost.MarkdownMode := EditorIsMarkdownMode;
  FKeymapHost.FindNeedleEmpty := FindNeedleEmpty;
  FKeymapHost.ToggleViewMode := ToggleViewMode;
  FKeymapHost.ToggleHexMode := ToggleHexMode;
  FKeymapHost.ToggleMarkdownMode := ToggleMarkdownMode;
  FKeymapHost.OpenEncodingDialog := OpenEncodingDialog;
  FKeymapHost.CycleEncoding := CycleEncoding;
  FKeymapHost.OpenGotoDialog := OpenGotoDialog;
  FKeymapHost.OpenReplaceDialog := OpenReplaceDialog;
  FKeymapHost.OpenFindDialog := OpenFindDialog;
  FKeymapHost.FindNextOrPrev := FindNextOrPrev;
  FKeymapHost.SaveDoc := SaveDoc;
  FKeymapHost.ToggleWordWrap := ToggleWordWrap;
  FKeymapHost.CopySelectionOrLine := CopySelectionOrLine;
  FKeymapHost.PasteText := PasteText;
  FKeymapHost.CutSelectionOrLine := CutSelectionOrLine;
  FKeymapHost.SelectAll := SelectAll;
  FKeymapHost.ClearSelection := ClearSelection;
  FKeymapHost.NotifyHost := NotifyHost;
  FKeymapHost.UndoEdit := UndoEdit;
  FKeymapHost.RedoEdit := RedoEdit;
  FKeymapHost.DeleteCurrentLine := DeleteCurrentLine;
  FKeymapHost.DeleteToEndOfLine := DeleteToEndOfLine;
  FKeymapHost.InsertBlankLineBelow := InsertBlankLineBelow;
  FKeymapHost.MoveWord := MoveWord;
  FKeymapHost.MoveCursor := MoveCursor;
  FKeymapHost.BreakInsertCoalesce := BreakInsertCoalesce;
  FKeymapHost.GotoFileHome := GotoFileHome;
  FKeymapHost.GotoFileEnd := GotoFileEnd;
  FKeymapHost.GotoLineHome := GotoLineHome;
  FKeymapHost.GotoLineEnd := GotoLineEnd;
  FKeymapHost.RequestClose := RequestClose;
  FKeymapHost.DoBackspace := DoBackspace;
  FKeymapHost.DoDelete := DoDelete;
  FKeymapHost.DoEnter := DoEnter;
  FKeymapHost.InsertChar := InsertChar;
end;

procedure TEditorWindow.GotoLine(ALine1Based: Integer);
var
  Row, Per, Off: Integer;
begin
  if not FDoc.Ready then
    Exit;
  if FHexMode then
  begin
    // Treat input as byte offset (1-based UI still ok: use as 0-based offset).
    Off := ALine1Based;
    if Off < 0 then
      Off := 0;
    if Off >= FDoc.ByteCount then
      Off := Max(FDoc.ByteCount - 1, 0);
    Per := HexBytesPerRow;
    if Per < 1 then
      Per := 16;
    FCursorRow := Off div Per;
    FCursorCol := Off mod Per;
    BreakInsertCoalesce;
    ClearSelection;
    EnsureCursorVisible;
    NotifyHost;
    Exit;
  end;
  Row := ALine1Based - 1;
  if Row < 0 then
    Row := 0;
  if Row >= FDoc.LineCount then
    Row := FDoc.LineCount - 1;
  BreakInsertCoalesce;
  ClearSelection;
  FCursorRow := Row;
  FCursorCol := 0;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.LeaveMarkdownOverlay;
begin
  if FMdOverlayShowing then
  begin
    ClearOverlayPreview;
    FMdOverlayShowing := False;
  end;
end;

procedure TEditorWindow.ToggleViewMode;
begin
  if not FDoc.Ready then
    Exit;
  if FViewOnly then
  begin
    FViewOnly := False;
    FMarkdownMode := False;
    LeaveMarkdownOverlay;
    TryUnlockEdit;
  end
  else
  begin
    FViewOnly := True;
    if (not FDoc.Binary) and (not FHexMode) and IsMarkdownFile then
      FMarkdownMode := True;
  end;
  Title := ModeTitle + ' - ' + ExtractFileName(FDoc.Path);
  NotifyHost;
end;

procedure TEditorWindow.ToggleMarkdownMode;
begin
  if not FDoc.Ready then
    Exit;
  if not FViewOnly then
    Exit;
  if FDoc.Binary or FHexMode then
    Exit;
  if not IsMarkdownFile then
    Exit;
  FMarkdownMode := not FMarkdownMode;
  FTopSubRow := 0;
  if not FMarkdownMode then
    LeaveMarkdownOverlay;
  Title := ModeTitle + ' - ' + ExtractFileName(FDoc.Path);
  NotifyHost;
end;

function TEditorWindow.MarkdownImageOverlayVisible: Boolean;
begin
  // The Overlay is a Canvas pass on top of the whole grid: it would cover a
  // dialog (open-link question, Go to line, ...) drawn into the cells.
  Result := FMarkdownMode and FMdOverlayShowing and not DialogOpen;
end;

procedure TEditorWindow.ToggleHexMode;
begin
  if not FDoc.Ready then
    Exit;
  if FHexMode then
  begin
    // F-bar Hex viewer: F4 = Text. Binary files have no line buffer until
    // we force-decode raw bytes (same path as F8, without cycling encoding).
    if FDoc.Binary then
    begin
      if FDoc.ByteCount = 0 then
        Exit;
      RequestEncoding(FDoc.Encoding, True);
      Title := ModeTitle + ' - ' + ExtractFileName(FDoc.Path);
      NotifyHost;
      Exit;
    end;
    FHexMode := False;
  end
  else
  begin
    if FDoc.ByteCount = 0 then
      Exit;
    FHexMode := True;
    FMarkdownMode := False;
    LeaveMarkdownOverlay;
    ClearSelection;
    FLeftCol := 0;
  end;
  ClampCursor;
  EnsureCursorVisible;
  Title := ModeTitle + ' - ' + ExtractFileName(FDoc.Path);
  NotifyHost;
end;

procedure TEditorWindow.RequestEncoding(AEncoding: TTextFileEncoding; ARedecode: Boolean);
begin
  if not FDoc.Ready then
    Exit;
  if ARedecode and FDoc.Dirty then
  begin
    // Re-decode from raw bytes would drop unsaved edits - ask first.
    FPendingEncoding := AEncoding;
    FConfirm := ecDiscardEncoding;
    FDialogs.OpenDiscardEncoding;
    Exit;
  end;
  FConfirm := ecNone;
  FDoc.ApplyEncoding(AEncoding, ARedecode);
  if ARedecode then
  begin
    FHexMode := False;
    // Re-decoded line text invalidates every cached TMdLine (spans point
    // into the previous decode) and the fence-state checkpoints (built by
    // scanning that old text) alike.
    FMdFenceIdx.Reset;
    FMdLineCache.Clear;
    FMdTableLayoutStart := -1;
    FMdLineCacheOrder.Clear;
    FMdImageUriCache.Clear;
    FMdImageSizeCache.Clear;
  end;
  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.CycleEncoding;
begin
  if not FDoc.Ready then
    Exit;
  // Re-decode leaves Hex and shows text (also how to exit binary Hex).
  if FHexMode then
    FHexMode := False;
  RequestEncoding(NextTextEncoding(FDoc.Encoding), True);
end;

procedure TEditorWindow.OpenEncodingDialog;
begin
  if not FDoc.Ready then
    Exit;
  FDialogs.OpenEncoding(TextEncodingName(FDoc.Encoding));
end;

procedure TEditorWindow.OpenGotoDialog;
begin
  if not FDoc.Ready then
    Exit;
  FDialogs.OpenGoto(FCursorRow + 1);
end;

procedure TEditorWindow.OpenReplaceDialog;
begin
  if not CanEdit then
    Exit;
  SeedFindFromHistory;
  FDialogs.OpenReplace(FFindText);
end;

// Ctrl+Left/Right (Shift grows/shrinks the selection from its anchor): one
// step goes to the next delimiter within the line (TextWordStepRight/Left);
// at a line edge the step is just the line break itself.
procedure TEditorWindow.MoveWord(AForward: Boolean; AExtendSel: Boolean);
var
  Line: string;
  Col, Row: Integer;
begin
  if not FDoc.Ready then
    Exit;
  BreakInsertCoalesce;
  if AExtendSel then
    EnsureSelAnchor
  else
    ClearSelection;
  ClampCursor;
  Row := FCursorRow;
  Col := FCursorCol;
  Line := CursorLineText(Row);
  if AForward then
  begin
    if Col >= Length(Line) then
    begin
      if Row < FDoc.LineCount - 1 then
      begin
        Inc(Row);
        Col := 0;
      end;
    end
    else
      Col := TextWordStepRight(Line, Col);
  end
  else
  begin
    if Col = 0 then
    begin
      if Row > 0 then
      begin
        Dec(Row);
        Col := Length(CursorLineText(Row));
      end;
    end
    else
      Col := TextWordStepLeft(Line, Col);
  end;
  FCursorRow := Row;
  FCursorCol := Col;
  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.RemoveCurrentLine;
begin
  if FDoc.LineCount <= 1 then
  begin
    FDoc.SetLine(0, '');
    FCursorCol := 0;
  end
  else
  begin
    FDoc.DeleteLine(FCursorRow);
    if FCursorRow >= FDoc.LineCount then
      FCursorRow := FDoc.LineCount - 1;
    FCursorCol := 0;
  end;
  ClearSelection;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.DeleteCurrentLine;
begin
  if not CanEdit then
    Exit;
  ClampCursor;
  BreakInsertCoalesce;
  PushUndo;
  RemoveCurrentLine;
end;

procedure TEditorWindow.DeleteToEndOfLine;
var
  Line: string;
begin
  if not CanEdit then
    Exit;
  ClampCursor;
  BreakInsertCoalesce;
  Line := FDoc.GetLine(FCursorRow);
  if FCursorCol >= Length(Line) then
    Exit;
  PushUndo;
  FDoc.SetLine(FCursorRow, Copy(Line, 1, FCursorCol));
  ClearSelection;
  NotifyHost;
end;

procedure TEditorWindow.InsertBlankLineBelow;
begin
  if not CanEdit then
    Exit;
  ClampCursor;
  BreakInsertCoalesce;
  PushUndo;
  FDoc.InsertLine(FCursorRow + 1, '');
  Inc(FCursorRow);
  FCursorCol := 0;
  ClearSelection;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.ReplaceInDocument(const AFind, AReplace: string; AAll: Boolean);
var
  Err, NewLine: string;
  I, Count, N: Integer;
  Lines, Fresh: TArray<string>;
  Opts: TSearchOptions;
begin
  if not CanEdit then
    Exit;
  if AFind = '' then
    Exit;
  Opts := GEditorSearchOptions;
  Err := TEditorSearchEngine.QueryError(AFind, Opts);
  if Err <> '' then
  begin
    BadPatternMessage(Err);
    Exit;
  end;
  FFindText := AFind;
  if not AAll then
  begin
    BeginReplaceSession(AFind, AReplace);
    Exit;
  end;

  // Every match of the text at once; the cursor stays where it was.
  BreakInsertCoalesce;
  Count := 0;
  SetLength(Lines, FDoc.LineCount);
  for I := 0 to FDoc.LineCount - 1 do
    Lines[I] := FDoc.GetLine(I);
  Fresh := Copy(Lines);
  for I := 0 to High(Lines) do
  begin
    NewLine := TEditorSearchEngine.ReplaceAllInLine(Lines[I], AFind, AReplace,
      Opts, N);
    if N > 0 then
    begin
      Fresh[I] := NewLine;
      Inc(Count, N);
    end;
  end;
  if Count > 0 then
  begin
    PushUndo;
    for I := 0 to High(Lines) do
      if Fresh[I] <> Lines[I] then
        FDoc.SetLine(I, Fresh[I]);
    FFindStatus := Format('replaced %d', [Count]);
    ClearSelection;
    ClampCursor;
    EnsureCursorVisible;
  end
  else
    FFindStatus := 'not found';
  NotifyHost;
  if Count > 0 then
    SearchMessage(T('ui.editor.replacedCount', 'Replaced: %d', [Count]), '')
  else
    NotFoundMessage(AFind);
end;

procedure TEditorWindow.BeginReplaceSession(const AFind, AReplace: string);
var
  R1, C1, R2, C2: Integer;
begin
  ClampCursor;
  FRepl := Default(TReplaceSession);
  FRepl.Active := True;
  FRepl.Find := AFind;
  FRepl.Repl := AReplace;
  FRepl.Opts := GEditorSearchOptions;
  FRepl.Forward := not FRepl.Opts.SearchBackwards;
  FRepl.SavedRow := FCursorRow;
  FRepl.SavedCol := FCursorCol;
  FRepl.StartRow := FCursorRow;
  FRepl.StartCol := FCursorCol;
  // A found match is selected with the cursor at its end; backwards the
  // search goes on from the start of the selection.
  if (not FRepl.Forward) and HasSelection then
  begin
    GetSelRange(R1, C1, R2, C2);
    FRepl.StartRow := R1;
    FRepl.StartCol := C1;
  end;
  FRepl.PosRow := FRepl.StartRow;
  FRepl.PosCol := FRepl.StartCol;
  ReplaceNextMatch;
end;

function TEditorWindow.ReplaceFindMatch(out AHit: TSearchResult): Boolean;
var
  I, C, Len, Start, Limit: Integer;
  Line: string;
begin
  AHit := Default(TSearchResult);
  if FRepl.Forward then
  begin
    for I := FRepl.PosRow to FDoc.LineCount - 1 do
    begin
      Line := FDoc.GetLine(I);
      if I = FRepl.PosRow then
        Start := FRepl.PosCol
      else
        Start := 0;
      if TEditorSearchEngine.FindInLine(Line, FRepl.Find, Start, FRepl.Opts, C, Len) then
      begin
        AHit.Found := True;
        AHit.LineIndex := I;
        AHit.ColIndex := C;
        AHit.Length := Len;
        Break;
      end;
    end;
  end
  else
    for I := Min(FRepl.PosRow, FDoc.LineCount - 1) downto 0 do
    begin
      Line := FDoc.GetLine(I);
      if I = FRepl.PosRow then
        Limit := FRepl.PosCol
      else
        Limit := Length(Line);
      if TEditorSearchEngine.FindLastInLine(Line, FRepl.Find, Limit, FRepl.Opts, C, Len) then
      begin
        AHit.Found := True;
        AHit.LineIndex := I;
        AHit.ColIndex := C;
        AHit.Length := Len;
        Break;
      end;
    end;
  Result := AHit.Found;
  // After the wrap only the part not looked at yet counts.
  if Result and FRepl.Wrapped then
  begin
    if FRepl.Forward then
      Result := (AHit.LineIndex < FRepl.StartRow) or
        ((AHit.LineIndex = FRepl.StartRow) and (AHit.ColIndex < FRepl.StartCol))
    else
      Result := (AHit.LineIndex > FRepl.StartRow) or
        ((AHit.LineIndex = FRepl.StartRow) and (AHit.ColIndex >= FRepl.StartCol));
  end;
end;

function TEditorWindow.ReplaceCanWrap: Boolean;
begin
  if FRepl.Wrapped then
    Exit(False);
  if FRepl.Forward then
    Result := (FRepl.StartRow > 0) or (FRepl.StartCol > 0)
  else
    Result := (FRepl.StartRow < FDoc.LineCount - 1) or
      (FRepl.StartCol < Length(FDoc.GetLine(FRepl.StartRow)));
end;

procedure TEditorWindow.ReplaceNextMatch;
var
  Hit: TSearchResult;
begin
  while FRepl.Active do
  begin
    if not ReplaceFindMatch(Hit) then
    begin
      if ReplaceCanWrap then
        ReplaceWrapAsk
      else
        EndReplaceSession;
      Exit;
    end;
    FRepl.AnyMatch := True;
    FRepl.MatchRow := Hit.LineIndex;
    FRepl.MatchCol := Hit.ColIndex;
    FRepl.MatchLen := Hit.Length;
    if FRepl.AllMode then
      ReplaceCurrentMatch
    else
    begin
      // The match is shown selected, behind the question.
      FSelAnchorRow := Hit.LineIndex;
      FSelAnchorCol := Hit.ColIndex;
      FCursorRow := Hit.LineIndex;
      FCursorCol := Hit.ColIndex + Hit.Length;
      EnsureCursorVisible;
      ReplaceAsk;
      Exit;
    end;
  end;
end;

function ClipForDialog(const AText: string; AWidth: Integer): string;
begin
  Result := StringReplace(AText, #9, ' ', [rfReplaceAll]);
  if Length(Result) > AWidth then
    Result := Copy(Result, 1, AWidth - 3) + '...';
end;

procedure TEditorWindow.ReplaceContext(ARow, ACol, ALen: Integer;
  out APre, AHit, APost: string);
const
  cRoom = 42;
  cPreMax = 14;
  cHitMax = 24;
var
  Line: string;
  PreLen, PostRoom: Integer;
begin
  Line := StringReplace(FDoc.GetLine(ARow), #9, ' ', [rfReplaceAll]);
  AHit := Copy(Line, ACol + 1, ALen);
  if Length(AHit) > cHitMax then
    AHit := Copy(AHit, 1, cHitMax - 3) + '...';
  PreLen := Min(ACol, Min(cPreMax, cRoom - Length(AHit)));
  if ACol > PreLen then
    APre := '...' + Copy(Line, ACol - PreLen + 4, PreLen - 3)
  else
    APre := Copy(Line, ACol - PreLen + 1, PreLen);
  PostRoom := cRoom - Length(APre) - Length(AHit);
  APost := Copy(Line, ACol + ALen + 1, PostRoom);
  if ACol + ALen + PostRoom < Length(Line) then
    APost := Copy(APost, 1, Max(Length(APost) - 3, 0)) + '...';
end;

procedure TEditorWindow.ReplaceAsk;
var
  Line, NewLine, Pre, Hit, Post: string;
  NewLen: Integer;
begin
  Line := FDoc.GetLine(FRepl.MatchRow);
  NewLine := TEditorSearchEngine.ReplaceMatch(Line, FRepl.Find, FRepl.Repl,
    FRepl.MatchCol, FRepl.MatchLen, FRepl.Opts, NewLen);
  ReplaceContext(FRepl.MatchRow, FRepl.MatchCol, FRepl.MatchLen, Pre, Hit, Post);
  FConfirm := ecReplaceAsk;
  FDialog.Open(BuildReplaceAskDialog(ClipForDialog(FRepl.Find, 40),
    ClipForDialog(Copy(NewLine, FRepl.MatchCol + 1, NewLen), 40),
    FRepl.MatchRow + 1, Pre, Hit, Post),
    procedure(const AControlId, AValuesJson: string)
    begin
      ReplaceAskCommand(AControlId);
    end);
  NotifyHost;
end;

procedure TEditorWindow.ReplaceAskCommand(const AControlId: string);
begin
  FDialog.Close;
  FConfirm := ecNone;
  if not FRepl.Active then
  begin
    NotifyHost;
    Exit;
  end;
  if DialogCmdIs(AControlId, 'replace') then
  begin
    ReplaceCurrentMatch;
    ReplaceNextMatch;
  end
  else if DialogCmdIs(AControlId, 'skip') then
  begin
    ReplaceSkipMatch;
    ReplaceNextMatch;
  end
  else if DialogCmdIs(AControlId, 'all') then
  begin
    FRepl.AllMode := True;
    ReplaceCurrentMatch;
    ReplaceNextMatch;
  end
  else
    EndReplaceSession;
end;

procedure TEditorWindow.ReplaceWrapAsk;
var
  Msg: string;
begin
  if FRepl.Forward then
    Msg := T('ui.editor.replaceWrapForward', 'Continue from the beginning?')
  else
    Msg := T('ui.editor.replaceWrapBackward', 'Continue from the end?');
  FConfirm := ecReplaceWrap;
  FDialog.Open(BuildConfirmDialog(T('ui.editor.replaceAskReplace', 'Replace'), Msg),
    procedure(const AControlId, AValuesJson: string)
    begin
      FDialog.Close;
      FConfirm := ecNone;
      if not FRepl.Active then
      begin
        NotifyHost;
        Exit;
      end;
      if not DialogCmdIsAccept(AControlId) then
      begin
        EndReplaceSession;
        Exit;
      end;
      FRepl.Wrapped := True;
      if FRepl.Forward then
      begin
        FRepl.PosRow := 0;
        FRepl.PosCol := 0;
      end
      else
      begin
        FRepl.PosRow := FDoc.LineCount - 1;
        FRepl.PosCol := Length(FDoc.GetLine(FRepl.PosRow));
      end;
      ReplaceNextMatch;
    end);
  NotifyHost;
end;

procedure TEditorWindow.ReplaceCurrentMatch;
var
  Line, NewLine: string;
  NewLen, Delta: Integer;
begin
  Line := FDoc.GetLine(FRepl.MatchRow);
  NewLine := TEditorSearchEngine.ReplaceMatch(Line, FRepl.Find, FRepl.Repl,
    FRepl.MatchCol, FRepl.MatchLen, FRepl.Opts, NewLen);
  if not FRepl.UndoPushed then
  begin
    BreakInsertCoalesce;
    PushUndo;
    FRepl.UndoPushed := True;
  end;
  FDoc.SetLine(FRepl.MatchRow, NewLine);
  Inc(FRepl.Count);
  Delta := NewLen - FRepl.MatchLen;
  // A replacement before the start of the search or the saved cursor on the
  // same line moves them along.
  if (FRepl.MatchRow = FRepl.StartRow) and (FRepl.MatchCol < FRepl.StartCol) then
    Inc(FRepl.StartCol, Delta);
  if (FRepl.MatchRow = FRepl.SavedRow) and (FRepl.MatchCol < FRepl.SavedCol) then
    Inc(FRepl.SavedCol, Delta);
  FRepl.PosRow := FRepl.MatchRow;
  if FRepl.Forward then
    FRepl.PosCol := FRepl.MatchCol + NewLen
  else
    FRepl.PosCol := FRepl.MatchCol;
end;

procedure TEditorWindow.ReplaceSkipMatch;
begin
  FRepl.PosRow := FRepl.MatchRow;
  if FRepl.Forward then
    FRepl.PosCol := FRepl.MatchCol + FRepl.MatchLen
  else
    FRepl.PosCol := FRepl.MatchCol;
end;

procedure TEditorWindow.EndReplaceSession;
var
  Count: Integer;
  AllMode, AnyMatch: Boolean;
  Find: string;
begin
  if not FRepl.Active then
    Exit;
  Count := FRepl.Count;
  AllMode := FRepl.AllMode;
  AnyMatch := FRepl.AnyMatch;
  Find := FRepl.Find;
  FRepl.Active := False;
  FFindText := Find;
  // The cursor goes back to where it was before the replace.
  FCursorRow := FRepl.SavedRow;
  FCursorCol := FRepl.SavedCol;
  ClearSelection;
  ClampCursor;
  EnsureCursorVisible;
  if Count > 0 then
    FFindStatus := Format('replaced %d', [Count])
  else
    FFindStatus := 'not found';
  NotifyHost;
  if not AnyMatch then
    NotFoundMessage(Find)
  else if AllMode and (Count > 0) then
    SearchMessage(T('ui.editor.replacedCount', 'Replaced: %d', [Count]), '');
end;

procedure TEditorWindow.DialogChanged(Sender: TObject);
begin
  NotifyHost;
end;

procedure TEditorWindow.ClearSelection;
begin
  FSelAnchorRow := -1;
  FSelAnchorCol := 0;
end;

function TEditorWindow.HasSelection: Boolean;
begin
  Result := (FSelAnchorRow >= 0) and
    ((FSelAnchorRow <> FCursorRow) or (FSelAnchorCol <> FCursorCol));
end;

procedure TEditorWindow.CloseDocument;
begin
  LeaveMarkdownOverlay;
  FDoc.Close;
  FURI := '';
  FTopLine := 0;
  FTopSubRow := 0;
  FLeftCol := 0;
  FCursorRow := 0;
  FCursorCol := 0;
  ClearSelection;
  NotifyHost;
end;

procedure TEditorWindow.ScrollLines(ADelta: Integer);
begin
  ScrollBy(ADelta);
end;

function TEditorWindow.DocReady: Boolean;
begin
  Result := FDoc.Ready;
end;

function TEditorWindow.LineCount: Integer;
begin
  if FDoc.Ready then
    Result := FDoc.LineCount
  else
    Result := 0;
end;

function TEditorWindow.LineText(AIndex: Integer): string;
begin
  if FDoc.Ready and (AIndex >= 0) and (AIndex < FDoc.LineCount) then
    Result := FDoc.GetLine(AIndex)
  else
    Result := '';
end;

function TEditorWindow.SearchEmpty: Boolean;
begin
  Result := FindNeedleEmpty;
end;

procedure TEditorWindow.GetViewPos(out ATopLine, ARow, ACol: Integer);
begin
  ATopLine := FTopLine;
  ARow := FCursorRow;
  ACol := FCursorCol;
end;

procedure TEditorWindow.SetViewPos(ATopLine, ARow, ACol: Integer);
begin
  if not FDoc.Ready then
    Exit;
  ClearSelection;
  FCursorRow := ARow;
  FCursorCol := ACol;
  ClampCursor;
  FTopLine := EnsureRange(ATopLine, 0, Max(FDoc.LineCount - 1, 0));
  FTopSubRow := 0;
  EnsureCursorVisible;
  NotifyHost;
end;

function TEditorWindow.LinkAtCursor(out ATarget: string): Boolean;
var
  MdLine: TMdLine;
  Span: TMdSpan;
begin
  Result := False;
  ATarget := '';
  if not (FMarkdownMode and FDoc.Ready) or (FCursorRow < 0) or
     (FCursorRow >= FDoc.LineCount) then
    Exit;
  MdLine := GetMdLine(FCursorRow);
  for Span in MdLine.Spans do
    if (Span.Kind = mskLink) and (Span.Target <> '') and
       (FCursorCol + 1 >= Span.StartCol) and
       (FCursorCol + 1 < Span.StartCol + Span.Len) then
    begin
      ATarget := Span.Target;
      Exit(True);
    end;
end;

function TEditorWindow.SelectMarkdownLink(AForward: Boolean): Boolean;
var
  Count, Line, Step, I, SpanCol, BestIdx, BestCol: Integer;
  MdLine: TMdLine;
  Better: Boolean;
begin
  Result := False;
  if not (FMarkdownMode and FDoc.Ready) or (FDoc.LineCount = 0) then
    Exit;
  Count := FDoc.LineCount;
  Line := EnsureRange(FCursorRow, 0, Count - 1);
  // Step 0 looks only past the cursor on its own line; Step = Count comes
  // back to that line from the other side (wrap-around).
  for Step := 0 to Count do
  begin
    MdLine := GetMdLine(Line);
    BestIdx := -1;
    BestCol := 0;
    for I := 0 to High(MdLine.Spans) do
    begin
      if (MdLine.Spans[I].Kind <> mskLink) or (MdLine.Spans[I].Target = '') then
        Continue;
      SpanCol := MdLine.Spans[I].StartCol - 1;
      if AForward then
        Better := ((Step > 0) or (SpanCol > FCursorCol)) and
          ((BestIdx < 0) or (SpanCol < BestCol))
      else
        Better := ((Step > 0) or (SpanCol < FCursorCol)) and
          ((BestIdx < 0) or (SpanCol > BestCol));
      if Better then
      begin
        BestIdx := I;
        BestCol := SpanCol;
      end;
    end;
    if BestIdx >= 0 then
    begin
      // Anchor at the end, cursor on the first char: the link is shown
      // selected and LinkAtCursor still finds it.
      FSelAnchorRow := Line;
      FSelAnchorCol := BestCol + MdLine.Spans[BestIdx].Len;
      FCursorRow := Line;
      FCursorCol := BestCol;
      EnsureCursorVisible;
      NotifyHost;
      Exit(True);
    end;
    if AForward then
      Line := (Line + 1) mod Count
    else
      Line := (Line - 1 + Count) mod Count;
  end;
end;

class function TEditorWindow.IsExternalLink(const ATarget: string): Boolean;
var
  P, I: Integer;
begin
  // RFC 3986 scheme: a letter, then letters / digits / "+-.". Two chars at
  // least, so "C:\docs\a.md" stays a local path.
  P := Pos(':', ATarget);
  if (P < 3) or not CharInSet(ATarget[1], ['A'..'Z', 'a'..'z']) then
    Exit(False);
  for I := 2 to P - 1 do
    if not CharInSet(ATarget[I], ['A'..'Z', 'a'..'z', '0'..'9', '+', '-', '.']) then
      Exit(False);
  Result := True;
end;

procedure TEditorWindow.OpenExternalLink(const AUrl: string);
const
  cShownUrl = 54; // the "details" label of updatemsg.json
var
  Url, Shown: string;
  Decl: TDialogDeclaration;
begin
  Url := Trim(AUrl);
  // Chromeless (Quick View) draws no dialogs.
  if (Url = '') or FChromeless or (FConfirm <> ecNone) or FDialog.Visible then
    Exit;
  // The whole address matters when deciding: keep both ends of a long one.
  Shown := Url;
  if Length(Shown) > cShownUrl then
    Shown := Copy(Shown, 1, cShownUrl - 16) + '...' +
      Copy(Shown, Length(Shown) - 12, 13);
  Decl := BuildUpdateMessageDialog(
    T('ui.editor.openLinkMsg', 'Open the link in the default application?'),
    Shown, T('ui.editor.openLinkOk', 'Open'), True);
  DialogSetTitle(Decl, T('ui.editor.openLinkTitle', 'Open link'));
  FConfirm := ecOpenLink;
  FDialog.Open(Decl,
    procedure(const AControlId, AValuesJson: string)
    begin
      FDialog.Close;
      FConfirm := ecNone;
      if DialogCmdIsOk(AControlId) and not ShellOpenUrl(Url) then
        Notice(T('ui.editor.openLinkFailed', 'Cannot open %s'), Url, tkWarning);
      NotifyHost;
    end);
  NotifyHost;
end;

function TEditorWindow.DialogOpen: Boolean;
begin
  Result := Assigned(FDialog) and FDialog.Visible;
end;

procedure TEditorWindow.EnsureSelAnchor;
begin
  if FSelAnchorRow < 0 then
  begin
    FSelAnchorRow := FCursorRow;
    FSelAnchorCol := FCursorCol;
  end;
end;

procedure TEditorWindow.GetSelRange(out ARow1, ACol1, ARow2, ACol2: Integer);
begin
  if (FSelAnchorRow < FCursorRow) or
     ((FSelAnchorRow = FCursorRow) and (FSelAnchorCol <= FCursorCol)) then
  begin
    ARow1 := FSelAnchorRow;
    ACol1 := FSelAnchorCol;
    ARow2 := FCursorRow;
    ACol2 := FCursorCol;
  end
  else
  begin
    ARow1 := FCursorRow;
    ACol1 := FCursorCol;
    ARow2 := FSelAnchorRow;
    ACol2 := FSelAnchorCol;
  end;
end;

function TEditorWindow.IsCellSelected(ARow, ACol: Integer): Boolean;
var
  R1, C1, R2, C2: Integer;
begin
  Result := False;
  if not HasSelection then
    Exit;
  GetSelRange(R1, C1, R2, C2);
  if (ARow < R1) or (ARow > R2) then
    Exit;
  if R1 = R2 then
    Result := (ACol >= C1) and (ACol < C2)
  else if ARow = R1 then
    Result := ACol >= C1
  else if ARow = R2 then
    Result := ACol < C2
  else
    Result := True;
end;

procedure TEditorWindow.PaintVisibleSelection(AY, ALineIdx, AAbsBase: Integer;
  const AVis: string);
var
  I: Integer;
begin
  // Panel file-mark cSelected* often shares BodyBg. Text selection uses
  // SelFg/SelBg, which themes fill with a pair that contrasts the body.
  for I := 1 to Length(AVis) do
    if IsCellSelected(ALineIdx, AAbsBase + I - 1) then
      PutGridText(Buffer, I, AY, AVis[I], FThemeColors.SelFg, FThemeColors.SelBg);
end;

function TEditorWindow.SelectionText: string;
begin
  Result := SelectedText;
end;

function TEditorWindow.CursorLineText(ALineIdx: Integer): string;
begin
  if FMarkdownMode and not FHexMode then
    Result := GetMdLine(ALineIdx).DisplayText
  else
    Result := FDoc.GetLine(ALineIdx);
end;

function TEditorWindow.SelectedText: string;
var
  R1, C1, R2, C2, R: Integer;
  Line: string;
  Parts: TArray<string>;
begin
  Result := '';
  if not HasSelection then
    Exit;
  GetSelRange(R1, C1, R2, C2);
  if R1 = R2 then
  begin
    Line := CursorLineText(R1);
    Result := Copy(Line, C1 + 1, C2 - C1);
    Exit;
  end;
  SetLength(Parts, R2 - R1 + 1);
  Line := CursorLineText(R1);
  Parts[0] := Copy(Line, C1 + 1, MaxInt);
  for R := R1 + 1 to R2 - 1 do
    Parts[R - R1] := CursorLineText(R);
  Line := CursorLineText(R2);
  Parts[R2 - R1] := Copy(Line, 1, C2);
  Result := string.Join(#10, Parts);
end;

function TEditorWindow.DeleteSelection: Boolean;
var
  R1, C1, R2, C2, R: Integer;
  First, Last, Merged: string;
begin
  Result := False;
  if not HasSelection then
    Exit;
  GetSelRange(R1, C1, R2, C2);
  First := FDoc.GetLine(R1);
  Last := FDoc.GetLine(R2);
  if R1 = R2 then
  begin
    Delete(First, C1 + 1, C2 - C1);
    FDoc.SetLine(R1, First);
  end
  else
  begin
    Merged := Copy(First, 1, C1) + Copy(Last, C2 + 1, MaxInt);
    FDoc.SetLine(R1, Merged);
    for R := R2 downto R1 + 1 do
      FDoc.DeleteLine(R);
  end;
  FCursorRow := R1;
  FCursorCol := C1;
  ClearSelection;
  ClampCursor;
  Result := True;
end;

procedure TEditorWindow.SelectAll;
begin
  if not FDoc.Ready then
    Exit;
  FSelAnchorRow := 0;
  FSelAnchorCol := 0;
  if FHexMode then
    TEditorHexFormatter.SelectAllEnd(FDoc.ByteCount, TextWidth, FCursorRow, FCursorCol)
  else
  begin
    FCursorRow := Max(FDoc.LineCount - 1, 0);
    FCursorCol := Length(CursorLineText(FCursorRow));
  end;
  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.MoveCursor(ARowDelta, AColDelta: Integer; AExtendSel: Boolean);
var
  TextW, CurDisp, TargetDisp, NewRow, CharOffset, SegCol, MaxDisp: Integer;
begin
  BreakInsertCoalesce;
  if AExtendSel then
    EnsureSelAnchor
  else
    ClearSelection;

  TextW := TextWidth;
  if FMarkdownMode and FDoc.Ready and (TextW > 0) and (ARowDelta <> 0) then
  begin
    MoveMarkdownCursorRows(ARowDelta, TextW);
    Inc(FCursorCol, AColDelta);
  end
  else if FWordWrap and FViewOnly and (TextW > 0) and (ARowDelta <> 0) then
  begin
    CurDisp := MapLineToDisplayRow(FCursorRow, FCursorCol, TextW);
    TargetDisp := CurDisp + ARowDelta;
    if TargetDisp < 0 then
      TargetDisp := 0;
    MaxDisp := Max(GetWrappedRowCount(TextW) - 1, 0);
    if TargetDisp > MaxDisp then
      TargetDisp := MaxDisp;

    if MapDisplayRowToLine(TargetDisp, TextW, NewRow, CharOffset) then
    begin
      SegCol := FCursorCol mod TextW;
      FCursorRow := NewRow;
      FCursorCol := CharOffset + SegCol;
    end;
  end
  else
  begin
    Inc(FCursorRow, ARowDelta);
    Inc(FCursorCol, AColDelta);
  end;

  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.ClearHistory;
begin
  if Assigned(FUndoBuffer) then
    FUndoBuffer.Clear;
  FCoalesceInsert := False;
end;

procedure TEditorWindow.BreakInsertCoalesce;
begin
  FCoalesceInsert := False;
end;

procedure TEditorWindow.PushUndo;
var
  E: TEditorUndoEntry;
begin
  if not Assigned(FUndoBuffer) then
    Exit;
  if FHexMode then
    E.Bytes := FDoc.SnapshotBytes
  else
    E.Lines := FDoc.SnapshotLines;
  E.HexMode := FHexMode;
  E.CursorRow := FCursorRow;
  E.CursorCol := FCursorCol;
  FUndoBuffer.PushState(E);
end;

procedure TEditorWindow.ApplySnapshot(const AEntry: TEditorUndoEntry);
begin
  if AEntry.HexMode then
    FDoc.RestoreBytes(AEntry.Bytes, True)
  else
    FDoc.RestoreLines(AEntry.Lines, True);
  FCursorRow := AEntry.CursorRow;
  FCursorCol := AEntry.CursorCol;
  ClearSelection;
  ClampCursor;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.UndoEdit;
var
  Cur, Prev: TEditorUndoEntry;
begin
  if not CanEdit or not Assigned(FUndoBuffer) or not FUndoBuffer.CanUndo then
    Exit;
  BreakInsertCoalesce;
  Cur.Lines := FDoc.SnapshotLines;
  Cur.Bytes := FDoc.SnapshotBytes;
  Cur.HexMode := FHexMode;
  Cur.CursorRow := FCursorRow;
  Cur.CursorCol := FCursorCol;
  FUndoBuffer.PushRedo(Cur);
  Prev := FUndoBuffer.PopUndoState;
  ApplySnapshot(Prev);
end;

procedure TEditorWindow.RedoEdit;
var
  Cur, Next: TEditorUndoEntry;
begin
  if not CanEdit or not Assigned(FUndoBuffer) or not FUndoBuffer.CanRedo then
    Exit;
  BreakInsertCoalesce;
  Cur.Lines := FDoc.SnapshotLines;
  Cur.Bytes := FDoc.SnapshotBytes;
  Cur.HexMode := FHexMode;
  Cur.CursorRow := FCursorRow;
  Cur.CursorCol := FCursorCol;
  FUndoBuffer.PushState(Cur);
  Next := FUndoBuffer.PopRedoState;
  ApplySnapshot(Next);
end;

function TEditorWindow.ClipboardGetText: string;
var
  Svc: IFMXClipboardService;
  V: TValue;
begin
  Result := '';
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Exit;
  V := Svc.GetClipboard;
  if not V.IsEmpty and V.IsType<string> then
    Result := V.AsString;
end;

procedure TEditorWindow.ClipboardSetText(const AText: string);
var
  Svc: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Svc.SetClipboard(AText);
end;

procedure TEditorWindow.CopySelectionOrLine;
begin
  if not FDoc.Ready then
    Exit;
  ClampCursor;
  if HasSelection then
  begin
    ClipboardSetText(SelectedText);
    Notice(T('ui.toast.copiedSelection', 'Selected text copied to the clipboard'));
  end
  else
  begin
    ClipboardSetText(FDoc.GetLine(FCursorRow));
    Notice(T('ui.toast.copiedLine', 'Line %s copied to the clipboard'),
      IntToStr(FCursorRow + 1));
  end;
end;

procedure TEditorWindow.CutSelectionOrLine;
begin
  if not CanEdit then
    Exit;
  ClampCursor;
  BreakInsertCoalesce;
  if HasSelection then
  begin
    PushUndo;
    ClipboardSetText(SelectedText);
    DeleteSelection;
    EnsureCursorVisible;
    NotifyHost;
    Exit;
  end;
  PushUndo;
  ClipboardSetText(FDoc.GetLine(FCursorRow));
  RemoveCurrentLine;
end;

procedure TEditorWindow.PasteText;
var
  Text, Line, Left, Right, Piece: string;
  Parts: TArray<string>;
  I: Integer;
begin
  if not CanEdit then
    Exit;
  Text := ClipboardGetText;
  if Text = '' then
    Exit;
  ClampCursor;
  BreakInsertCoalesce;
  PushUndo;
  if HasSelection then
    DeleteSelection;
  Text := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  Text := StringReplace(Text, #13, #10, [rfReplaceAll]);
  Parts := Text.Split([#10]);
  if Length(Parts) = 0 then
    Exit;
  Line := FDoc.GetLine(FCursorRow);
  Left := Copy(Line, 1, FCursorCol);
  Right := Copy(Line, FCursorCol + 1, MaxInt);
  if Length(Parts) = 1 then
  begin
    Piece := Left + Parts[0] + Right;
    FDoc.SetLine(FCursorRow, Piece);
    FCursorCol := Length(Left) + Length(Parts[0]);
  end
  else
  begin
    FDoc.SetLine(FCursorRow, Left + Parts[0]);
    for I := 1 to High(Parts) - 1 do
      FDoc.InsertLine(FCursorRow + I, Parts[I]);
    FDoc.InsertLine(FCursorRow + High(Parts), Parts[High(Parts)] + Right);
    Inc(FCursorRow, High(Parts));
    FCursorCol := Length(Parts[High(Parts)]);
  end;
  ClearSelection;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.InsertChar(ACh: Char);
var
  Line: string;
begin
  if FViewOnly then
    Exit;
  if not CanEdit then
  begin
    TryUnlockEdit;
    Exit;
  end;
  if FHexMode then
  begin
    HexTypeChar(ACh);
    Exit;
  end;
  ClampCursor;
  if HasSelection then
  begin
    BreakInsertCoalesce;
    PushUndo;
    DeleteSelection;
    FCoalesceInsert := True;
  end
  else if not FCoalesceInsert then
  begin
    PushUndo;
    FCoalesceInsert := True;
  end;
  Line := FDoc.GetLine(FCursorRow);
  Insert(ACh, Line, FCursorCol + 1);
  FDoc.SetLine(FCursorRow, Line);
  Inc(FCursorCol);
  ClearSelection;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.DoBackspace;
var
  Line, Prev: string;
begin
  if FViewOnly then
    Exit;
  if not CanEdit then
  begin
    TryUnlockEdit;
    Exit;
  end;
  if FHexMode then
  begin
    HexDeleteAtCursor(True);
    Exit;
  end;
  ClampCursor;
  BreakInsertCoalesce;
  if HasSelection then
  begin
    PushUndo;
    DeleteSelection;
    EnsureCursorVisible;
    NotifyHost;
    Exit;
  end;
  PushUndo;
  if FCursorCol > 0 then
  begin
    Line := FDoc.GetLine(FCursorRow);
    Delete(Line, FCursorCol, 1);
    FDoc.SetLine(FCursorRow, Line);
    Dec(FCursorCol);
  end
  else if FCursorRow > 0 then
  begin
    Prev := FDoc.GetLine(FCursorRow - 1);
    Line := FDoc.GetLine(FCursorRow);
    FCursorCol := Length(Prev);
    FDoc.SetLine(FCursorRow - 1, Prev + Line);
    FDoc.DeleteLine(FCursorRow);
    Dec(FCursorRow);
  end;
  ClearSelection;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.DoDelete;
var
  Line, Next: string;
begin
  if FViewOnly then
    Exit;
  if not CanEdit then
  begin
    TryUnlockEdit;
    Exit;
  end;
  if FHexMode then
  begin
    HexDeleteAtCursor(False);
    Exit;
  end;
  ClampCursor;
  BreakInsertCoalesce;
  if HasSelection then
  begin
    PushUndo;
    DeleteSelection;
    EnsureCursorVisible;
    NotifyHost;
    Exit;
  end;
  PushUndo;
  Line := FDoc.GetLine(FCursorRow);
  if FCursorCol < Length(Line) then
  begin
    Delete(Line, FCursorCol + 1, 1);
    FDoc.SetLine(FCursorRow, Line);
  end
  else if FCursorRow < FDoc.LineCount - 1 then
  begin
    Next := FDoc.GetLine(FCursorRow + 1);
    FDoc.SetLine(FCursorRow, Line + Next);
    FDoc.DeleteLine(FCursorRow + 1);
  end;
  ClearSelection;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.DoEnter;
var
  Line, Left, Right: string;
begin
  // Markdown Viewer: Enter on an external link offers to open it (the Help
  // window follows its own topic links before the key gets here).
  if FMarkdownMode and not FHelpMode and LinkAtCursor(Line) then
  begin
    if IsExternalLink(Line) then
      OpenExternalLink(Line);
    Exit;
  end;
  if FHexMode or (not CanEdit) then
    Exit;
  ClampCursor;
  BreakInsertCoalesce;
  PushUndo;
  if HasSelection then
    DeleteSelection;
  Line := FDoc.GetLine(FCursorRow);
  Left := Copy(Line, 1, FCursorCol);
  Right := Copy(Line, FCursorCol + 1, MaxInt);
  FDoc.SetLine(FCursorRow, Left);
  FDoc.InsertLine(FCursorRow + 1, Right);
  Inc(FCursorRow);
  FCursorCol := 0;
  ClearSelection;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TEditorWindow.OpenFindDialog;
begin
  if not FDoc.Ready then
    Exit;
  FFindStatus := '';
  SeedFindFromHistory;
  FDialogs.OpenFind(FFindText);
  NotifyHost;
end;

function TEditorWindow.WordAtCursor: string;
var
  Line: string;
  WStart, WEnd: Integer;
begin
  Result := '';
  if not FDoc.Ready then
    Exit;
  ClampCursor;
  Line := CursorLineText(FCursorRow);
  TextWordRangeAt(Line, FCursorCol, WStart, WEnd);
  Result := Copy(Line, WStart + 1, WEnd - WStart);
end;

function TEditorWindow.SelectionForSearch: string;
var
  P: Integer;
begin
  if HasSelection then
    Result := SelectedText
  else if FDoc.Ready then
  begin
    ClampCursor;
    Result := CursorLineText(FCursorRow);
  end
  else
    Result := '';
  // A search never spans a line break: the first line of a multi-line
  // selection is what can be found.
  P := Pos(#10, Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
end;

procedure TEditorWindow.BadPatternMessage(const AError: string);
begin
  FFindStatus := 'bad pattern';
  SearchMessage(T('ui.editor.badPatternMsg', 'Invalid regular expression'), AError);
  NotifyHost;
end;

procedure TEditorWindow.SearchMessage(const AMessage, ADetails: string);
var
  Decl: TDialogDeclaration;
begin
  if FChromeless or (FConfirm <> ecNone) or FDialog.Visible then
    Exit;
  Decl := BuildUpdateMessageDialog(AMessage, ADetails, '', False);
  DialogSetTitle(Decl, T('ui.editor.notFoundTitle', 'Search'));
  FConfirm := ecNotFound;
  FDialog.Open(Decl,
    procedure(const AControlId, AValuesJson: string)
    begin
      FDialog.Close;
      FConfirm := ecNone;
      NotifyHost;
    end);
end;

function TEditorWindow.FindMatch(AForward: Boolean): Boolean;
var
  Needle, Err: string;
  I, Row, Col, R2, C2: Integer;
  Lines: TArray<string>;
  Opts: TSearchOptions;
  Hit: TSearchResult;
  Forward: Boolean;
begin
  Result := False;
  Needle := FFindText;
  if (Trim(Needle) = '') or not FDoc.Ready or (FDoc.LineCount = 0) then
  begin
    FFindStatus := 'not found';
    NotifyHost;
    Exit;
  end;
  Opts := GEditorSearchOptions;
  Err := TEditorSearchEngine.QueryError(Needle, Opts);
  if Err <> '' then
  begin
    BadPatternMessage(Err);
    Exit;
  end;

  SetLength(Lines, FDoc.LineCount);
  for I := 0 to FDoc.LineCount - 1 do
    Lines[I] := CursorLineText(I);
  ClampCursor;
  // The key (F3 or Shift+F3) against the Reverse box of the Find dialog.
  Forward := AForward <> Opts.SearchBackwards;
  if Forward then
    // A found match is selected with the cursor at its end, so the next
    // search starts after it.
    Hit := TEditorSearchEngine.FindNextWrapped(Lines, Needle, FCursorRow,
      FCursorCol, Opts, False)
  else
  begin
    Row := FCursorRow;
    Col := FCursorCol;
    if HasSelection then
      GetSelRange(Row, Col, R2, C2);
    Hit := TEditorSearchEngine.FindPrevWrapped(Lines, Needle, Row, Col, Opts,
      False);
  end;

  if Hit.Found then
  begin
    FSelAnchorRow := Hit.LineIndex;
    FSelAnchorCol := Hit.ColIndex;
    FCursorRow := Hit.LineIndex;
    FCursorCol := Hit.ColIndex + Hit.Length;
    EnsureCursorVisible;
    FFindStatus := Format('found %d/%d', [Hit.LineIndex + 1, FDoc.LineCount]);
    Result := True;
    NotifyHost;
    Exit;
  end;

  FFindStatus := 'not found';
  NotFoundMessage(Needle);
  NotifyHost;
end;

procedure TEditorWindow.NotFoundMessage(const ANeedle: string);
begin
  SearchMessage(T('ui.editor.notFoundMsg', 'Could not find the string'),
    '"' + ANeedle + '"');
end;

procedure TEditorWindow.DrawFunctionKeys(AY, AWidth: Integer);
var
  Items, Letters: TArray<string>;
  Colors: TFunctionBarColors;
begin
  FunctionBarGetItems(ChromeContext, KeyModifiers, Items, Letters);
  Colors := FunctionBarDefaultColors;
  Colors.Bg := FThemeColors.BodyBg;
  DrawFunctionBar(Buffer, AY, AWidth, Items, Letters, KeyModifiers, Colors, Theme);
end;

procedure TEditorWindow.DrawAppStatusLine(AY, AWidth: Integer);
var
  Segs: TArray<string>;
  Name, PosText, LinesText, Flag, Mode: string;
  PrefixLen, EditW: Integer;
  Colors: TInputLineColors;
  Prefix: string;
begin
  Mode := ModeTitle;
  Name := ExtractFileName(FDoc.Path);
  if Name = '' then
    Name := FileUriTitle(FURI);
  Name := EditorDirtyName(Name, (not FViewOnly) and FDoc.Dirty);

  EditorPosAndLinesText(FDoc.Ready, FDoc.Loading, FHexMode, FCursorRow, FCursorCol,
    HexBytesPerRow, FDoc.ByteCount, FDoc.LineCount, FDoc.Error, PosText, LinesText);

  Flag := EditorStatusFlag(FHexMode, FViewOnly, FWordWrap, FDoc.ReadOnly,
    FDoc.Saving, FDoc.Status);

  if FConfirm = ecAskSave then
    Segs := TArray<string>.Create(Mode, Name, 'Y=Save', 'N=Discard', 'Esc=Cancel')
  else if FConfirm = ecDiscardEncoding then
    Segs := TArray<string>.Create(Mode, Name, 'Enter=Discard', 'Esc=Cancel')
  else
  begin
    Segs := TArray<string>.Create(Mode);
    if Name <> '' then
      Segs := Segs + [Name];
    if PosText <> '' then
      Segs := Segs + [PosText];
    if HasSelection then
      Segs := Segs + ['Sel']
    else if LinesText <> '' then
      Segs := Segs + [LinesText];
    if Flag <> '' then
      Segs := Segs + [Flag];
    if FDoc.Ready and not FHexMode then
      Segs := Segs + [TextEncodingName(FDoc.Encoding)];
    if FFindStatus <> '' then
      Segs := Segs + [FFindStatus];
  end;

  if Assigned(Theme) then
    Theme.DrawStatusLine(Buffer, TRectI.Make(0, AY, AWidth - 1, AY), Segs, [])
  else
  begin
    FillGridRect(Buffer, 0, AY, AWidth - 1, AY, ' ', FThemeColors.StatusFg, FThemeColors.StatusBg);
    PutGridText(Buffer, 1, AY, Mode + '  ' + Name + '  ' + PosText,
      FThemeColors.StatusFg, FThemeColors.StatusBg);
  end;
end;

procedure TEditorWindow.DrawScrollBar;
var
  W, Bottom, Span, ThumbAt, I, MaxTop, Total: Integer;
begin
  W := Area.Width;
  Bottom := ContentBottomRow;
  Span := Bottom; // rows 1..Bottom
  if Span < 2 then
    Exit;

  if Assigned(Theme) then
  begin
    if FDoc.Ready then
      Total := ContentRowCount
    else
      Total := 0;
    MaxTop := Max(Total - ViewHeight, 0);
    Theme.DrawScrollBar(Buffer, TRectI.Make(W - 2, 1, W - 2, Bottom),
      FTopLine, MaxTop, True, WidgetState);
    Exit;
  end;

  DrawGridChar(Buffer, W - 2, 1, #$25B2, FThemeColors.ScrollFg, FThemeColors.BodyBg); // в-І
  DrawGridChar(Buffer, W - 2, Bottom, #$25BC, FThemeColors.ScrollFg, FThemeColors.BodyBg); // в-ј
  for I := 2 to Bottom - 1 do
    DrawGridChar(Buffer, W - 2, I, chShadeLight, FThemeColors.ScrollFg, FThemeColors.BodyBg);
  if FDoc.Ready then
    Total := ContentRowCount
  else
    Total := 0;
  MaxTop := Max(Total - ViewHeight, 0);
  ThumbAt := 2;
  if (MaxTop > 0) and (Span > 3) then
    Inc(ThumbAt, EnsureRange(Round(FTopLine * (Span - 3) / MaxTop), 0, Span - 3));
  DrawGridChar(Buffer, W - 2, ThumbAt, chBlock, FThemeColors.ScrollThumb, FThemeColors.BodyBg);
end;

procedure TEditorWindow.DrawHexContent;
var
  W, ViewH, TextW, Y, LineIdx, Per, ByteIdx, AscStart: Integer;
  Line: string;
  HexX, AscX: Integer;
begin
  W := Area.Width;
  ViewH := ViewHeight;
  TextW := TextWidth;
  Per := HexBytesPerRow;
  AscStart := TEditorHexFormatter.AsciiColStart(Per);

  for Y := 0 to ViewH - 1 do
  begin
    LineIdx := FTopLine + Y;
    if LineIdx < HexRowCount then
      Line := FormatHexLine(LineIdx)
    else
      Line := '';
    if Length(Line) > TextW then
      Line := Copy(Line, 1, TextW)
    else
      while Length(Line) < TextW do
        Line := Line + ' ';
    FillGridRect(Buffer, 1, 1 + Y, W - 3, 1 + Y, ' ', FThemeColors.BodyFg, FThemeColors.BodyBg);
    if (1 + Y >= 0) and (1 + Y <= High(Buffer)) then
      TEditorPainter.DrawHexLine(Buffer[1 + Y], TextW, Line, FThemeColors.BodyFg, FThemeColors.BodyBg);
    for ByteIdx := 0 to Per - 1 do
      if IsCellSelected(LineIdx, ByteIdx) then
      begin
        HexX := TEditorHexFormatter.HexGlyphCol(ByteIdx);
        if (HexX >= 0) and (HexX + 1 < TextW) then
          PutGridText(Buffer, 1 + HexX, 1 + Y, Copy(Line, 1 + HexX, 2),
            FThemeColors.SelFg, FThemeColors.SelBg);
        AscX := AscStart + ByteIdx;
        if (AscX >= 0) and (AscX < TextW) then
          PutGridText(Buffer, 1 + AscX, 1 + Y, Line[1 + AscX],
            FThemeColors.SelFg, FThemeColors.SelBg);
      end;
    if (LineIdx = FCursorRow) and (FConfirm = ecNone) and FCursorVisible then
    begin
      ByteIdx := FCursorCol;
      if (ByteIdx >= 0) and (ByteIdx < Per) then
      begin
        HexX := TEditorHexFormatter.HexGlyphCol(ByteIdx);
        if (HexX >= 0) and (HexX < TextW) then
          MarkGridInsertCaret(Buffer, 1 + HexX, 1 + Y);
      end;
    end;
  end;
end;

function TEditorWindow.IsMarkdownFile: Boolean;
begin
  Result := SameText(ExtractFileExt(FDoc.Path), '.md');
end;

function TEditorWindow.GetMdLine(ALineIdx: Integer): TMdLine;
var
  State: TMdFenceState;
  EnteredInFence: Boolean;
  Raw: string;
  StartIdx, EndIdx, I: Integer;
  Block: TArray<string>;

  function RowIsPipeTable(AIdx: Integer): Boolean;
  var
    St: TMdFenceState;
  begin
    Result := False;
    if (AIdx < 0) or (AIdx >= FDoc.LineCount) then
      Exit;
    St := FMdFenceIdx.FenceStateBefore(FDoc, AIdx);
    if St.InFence then
      Exit;
    Result := TMarkdownParser.LooksLikePipeTableRow(FDoc.GetLine(AIdx));
  end;

begin
  if TextWidth <> FMdLineCacheWidth then
  begin
    FMdLineCache.Clear;
    FMdTableLayoutStart := -1;
    FMdLineCacheOrder.Clear;
    FMdLineCacheWidth := TextWidth;
  end;
  if FMdLineCache.TryGetValue(ALineIdx, Result) then
    Exit;
  State := FMdFenceIdx.FenceStateBefore(FDoc, ALineIdx);
  EnteredInFence := State.InFence;
  Raw := FDoc.GetLine(ALineIdx);
  Result := TMarkdownParser.ParseLine(Raw, State);
  if (not EnteredInFence) and TMarkdownParser.LooksLikePipeTableRow(Raw) then
  begin
    StartIdx := ALineIdx;
    while (StartIdx > 0) and (ALineIdx - StartIdx < cMdTableMaxRows) and
      RowIsPipeTable(StartIdx - 1) do
      Dec(StartIdx);
    EndIdx := ALineIdx;
    while (EndIdx + 1 < FDoc.LineCount) and (EndIdx - StartIdx < cMdTableMaxRows) and
      RowIsPipeTable(EndIdx + 1) do
      Inc(EndIdx);
    if (EndIdx >= StartIdx + 1) and
       TMarkdownParser.IsPipeTableSeparator(FDoc.GetLine(StartIdx + 1)) and
       (not TMarkdownParser.IsPipeTableSeparator(FDoc.GetLine(StartIdx))) then
    begin
      if (FMdTableLayoutStart <> StartIdx) or (FMdTableLayoutEnd <> EndIdx) or
         (FMdTableLayoutWidth <> TextWidth) then
      begin
        SetLength(Block, EndIdx - StartIdx + 1);
        for I := 0 to High(Block) do
          Block[I] := FDoc.GetLine(StartIdx + I);
        FMdTableLayout := TMarkdownParser.ComputeTableLayout(Block, TextWidth);
        FMdTableLayoutStart := StartIdx;
        FMdTableLayoutEnd := EndIdx;
        FMdTableLayoutWidth := TextWidth;
      end;
      Result := TMarkdownParser.FormatPipeTableRow(Raw, ALineIdx - StartIdx, FMdTableLayout);
    end;
  end;
  CacheMdLine(ALineIdx, Result);
end;

function TEditorWindow.MarkdownWrapStarts(const ALine: TMdLine; ATextW: Integer): TArray<Integer>;
var
  RowW: Integer;
begin
  if ALine.IsTable then
  begin
    // The rows of a table line are cut where they were joined; a table that
    // is wider than the window has no such seam and is cut at the window width.
    RowW := ALine.TableRowWidth;
    if (RowW <= 0) or (RowW > ATextW) then
      RowW := ATextW;
    Result := TMarkdownParser.ComputeHardWrapStarts(ALine.DisplayText, RowW);
  end
  else
    Result := TMarkdownParser.ComputeWrapStarts(ALine.DisplayText, ATextW);
end;

procedure TEditorWindow.CacheMdLine(AIndex: Integer; const AValue: TMdLine);
begin
  if FMdLineCache.ContainsKey(AIndex) then
    Exit;
  while (FMdLineCacheOrder.Count > 0) and (FMdLineCache.Count >= cMdLineCacheCap) do
    FMdLineCache.Remove(FMdLineCacheOrder.Dequeue);
  FMdLineCache.Add(AIndex, AValue);
  FMdLineCacheOrder.Enqueue(AIndex);
end;

// Resolves a Markdown/Obsidian image ref to a local file:// URI.
// HTTP(S) has no VFS here and always falls back to text. Existence is
// probed (same folder as the document, then attachments\<filename>).
function TEditorWindow.ResolveMarkdownImageUri(const AImagePath: string): string;
var
  Combined: string;
begin
  Result := '';
  if Trim(AImagePath) = '' then
    Exit;
  if Pos('://', AImagePath) > 0 then
  begin
    if StartsText('file:', AImagePath) then
      Result := AImagePath;
    Exit;
  end;
  if FMdImageUriCache.TryGetValue(AImagePath, Result) then
    Exit;
  Combined := MarkdownResolveImageFile(FDoc.Path, AImagePath);
  if Combined = '' then
    Exit; // Not found yet -- keep re-probing so a file created later still shows up.
  Result := PathToFileUri(Combined);
  FMdImageUriCache.Add(AImagePath, Result);
end;

function TEditorWindow.MarkdownImageBlock(const AImageUri: string; AReqW, AReqH, ATextW, AViewH: Integer;
  out ACols: Integer; out AScale: Single): Integer;
var
  Sz: TMdImageSize;
  Aspect: Single;
  NatCols, NatRows: Integer;
begin
  ACols := Max(ATextW, 1);
  AScale := 0;
  if not FMdImageSizeCache.TryGetValue(AImageUri, Sz) then
  begin
    if not ReadImagePixelSize(FileUriToPath(AImageUri), Sz.W, Sz.H) then
    begin
      Sz.W := 0;
      Sz.H := 0;
    end;
    FMdImageSizeCache.Add(AImageUri, Sz);
  end;
  if (Sz.W <= 0) or (Sz.H <= 0) then
    Exit(Min(cMdImageRows, Max(AViewH, 1))); // unknown format: a fixed-height block
  Aspect := OverlayCellAspect;
  AScale := 1;
  if (AReqW > 0) and (AReqH > 0) then
    AScale := Min(AReqW / Sz.W, AReqH / Sz.H)
  else if AReqW > 0 then
    AScale := AReqW / Sz.W
  else if AReqH > 0 then
    AScale := AReqH / Sz.H;
  if OverlayNativeCellSize(Ceil(Sz.W * AScale), Ceil(Sz.H * AScale), NatCols, NatRows) and
     (NatCols <= ACols) then
  begin
    // Fits the width: shown at the requested (or its own) pixel size.
    ACols := NatCols;
    Result := NatRows;
  end
  else
    // Wider than the viewer: scaled down proportionally to the full width.
    Result := Max(1, Ceil(ACols * (Sz.H / Sz.W) / Aspect));
  if Result > Max(AViewH, 1) then
  begin
    // Taller than the viewport: fit the height, narrow the block to match so
    // the image still starts at the left edge.
    Result := Max(AViewH, 1);
    ACols := EnsureRange(Ceil(Result * Aspect * Sz.W / Sz.H), 1, ACols);
  end;
end;

procedure TEditorWindow.DrawMarkdownContent;
var
  W, ViewH, TextW, Y, LineIdx, Reserved, ImgCols, ImgRows: Integer;
  ImgScale: Single;
  BodyFg, BodyBg: TAlphaColor;
  TextAttr: TCharCellAttributes;
  MdLine: TMdLine;
  ImgUri: string;
  AbsBounds, AbsClip: TRectI;
  ShowingOverlay: Boolean;
  DisplayLen, RowsForLine, RowInLine, ChunkStart, ChunkEnd, DrawCol, SkipRows: Integer;
  WrapStarts: TArray<Integer>;
  Vis: string;
begin
  W := Area.Width;
  ViewH := ViewHeight;
  TextW := TextWidth;
  ShowingOverlay := False;
  // The Markdown view's body colors are the theme's colors of plain Markdown text.
  BodyFg := FThemeColors.BodyFg;
  BodyBg := FThemeColors.BodyBg;
  if Assigned(Theme) then
    Theme.ResolveMarkdownStyleColors(mskText, BodyFg, BodyBg, TextAttr);

  Y := 0;
  LineIdx := FTopLine;
  SkipRows := MarkdownTopSubRow;
  while Y < ViewH do
  begin
    if LineIdx >= FDoc.LineCount then
    begin
      FillGridRect(Buffer, 1, 1 + Y, W - 3, 1 + Y, ' ', BodyFg, BodyBg);
      Inc(Y);
      Inc(LineIdx);
      Continue;
    end;

    MdLine := GetMdLine(LineIdx);

    if MdLine.IsImage and not FChromeless then
    begin
      ImgUri := ResolveMarkdownImageUri(MdLine.ImagePath);
      if (ImgUri <> '') and IsOverlayImageExtension(ExtractFileExt(MdLine.ImagePath)) then
      begin
        ImgRows := MarkdownImageBlock(ImgUri, MdLine.ImageWidth, MdLine.ImageHeight,
          TextW, ViewH, ImgCols, ImgScale);
        Reserved := Min(ImgRows, ViewH - Y);
        FillGridRect(Buffer, 1, 1 + Y, W - 3, 1 + Y + Reserved - 1, ' ', BodyFg, BodyBg);
        // Area is compositor-absolute (PaintEmbedded sets DualPanel.Area +
        // dest inset; a standalone editor's Area is the MDI window). Overlay
        // FormPaint uses the same absolute cells as Quick View.
        // The image is laid out at its full block size and cut off at the
        // viewport's bottom edge (AbsClip) rather than shrunk to fit.
        AbsBounds := TRectI.Make(1 + Area.Left, 1 + Y + Area.Top,
          ImgCols + Area.Left, 1 + Y + ImgRows - 1 + Area.Top);
        AbsClip := TRectI.Make(1 + Area.Left, 1 + Y + Area.Top,
          ImgCols + Area.Left, 1 + Y + Reserved - 1 + Area.Top);
        if OverlayCurrentURI <> ImgUri then
          RequestOverlayPreview(ImgUri, AbsBounds, AbsClip, ImgScale)
        else
          UpdateOverlayBounds(AbsBounds, AbsClip, ImgScale);
        ShowingOverlay := True;
        Inc(Y, Reserved);
        Inc(LineIdx);
        SkipRows := 0;
        Continue;
      end;
    end;

    // Word wrap: a long line is sliced into word-boundary chunks (breaks
    // after the rightmost space/punctuation that still fits - see
    // TMarkdownParser.ComputeWrapStarts; falls back to a hard cut only for
    // an unbroken run longer than the width, e.g. a URL), one
    // TMarkdownPainter.DrawLine call per chunk. Deliberately computed per
    // line during this same forward walk instead of a global "display row"
    // index over the whole document (as the plain Viewer's
    // MapDisplayRowToLine does): that scans every line on every call, which
    // would reintroduce exactly the "large file blocks the UI" problem
    // the lazy fence index (uMarkdownIndex) exists to avoid.
    DisplayLen := Length(MdLine.DisplayText);
    WrapStarts := MarkdownWrapStarts(MdLine, TextW);
    RowsForLine := Length(WrapStarts);

    for RowInLine := Min(SkipRows, RowsForLine - 1) to RowsForLine - 1 do
    begin
      if Y >= ViewH then
        Break;
      ChunkStart := WrapStarts[RowInLine];
      if RowInLine + 1 < RowsForLine then
        ChunkEnd := WrapStarts[RowInLine + 1] - 1
      else
        ChunkEnd := DisplayLen;
      FillGridRect(Buffer, 1, 1 + Y, W - 3, 1 + Y, ' ', BodyFg, BodyBg);
      if (1 + Y >= 0) and (1 + Y <= High(Buffer)) then
      begin
        TMarkdownPainter.DrawLine(Buffer[1 + Y], 1, TextW, MdLine, Theme, ChunkStart, ChunkEnd);
        Vis := Copy(MdLine.DisplayText, ChunkStart, Max(ChunkEnd - ChunkStart + 1, 0));
        if Length(Vis) < TextW then
          Vis := Vis + StringOfChar(' ', TextW - Length(Vis));
        PaintVisibleSelection(1 + Y, LineIdx, ChunkStart - 1, Vis);
        if (LineIdx = FCursorRow) and (FConfirm = ecNone) and FCursorVisible and
           EditorCaretDrawCol(FCursorCol, ChunkStart, ChunkEnd, DisplayLen, TextW,
             RowInLine = RowsForLine - 1, DrawCol) then
          MarkGridInsertCaret(Buffer, 1 + DrawCol, 1 + Y);
      end;
      Inc(Y);
    end;
    SkipRows := 0;
    Inc(LineIdx);
  end;

  // LeaveMarkdownOverlay reads the previous FMdOverlayShowing to decide
  // whether a ClearOverlayPreview is even needed - set the new flag only
  // in the branch that doesn't call it.
  if ShowingOverlay then
    FMdOverlayShowing := True
  else
    LeaveMarkdownOverlay;
end;

procedure TEditorWindow.DrawContent;
var
  W, H, ViewH, TextW, Y, LineIdx, CharOffset, DrawCol: Integer;
  Line, Vis: string;
begin
  if Assigned(Theme) then
    Theme.ResolveEditorColors(FThemeColors);
  W := Area.Width;
  H := Area.Height;
  if (W < 8) or (H < 6) then
    Exit;

  ViewH := ViewHeight;
  TextW := TextWidth;

  if FDoc.Loading then
    PutGridText(Buffer, 1, 1, 'Loading...', FThemeColors.HintFg, FThemeColors.BodyBg)
  else if (not FDoc.Ready) and (FDoc.Error <> '') then
    PutGridText(Buffer, 1, 1, FDoc.Error, FThemeColors.HintFg, FThemeColors.BodyBg)
  else if FDoc.Ready and FHexMode then
    DrawHexContent
  else if FDoc.Ready and FMarkdownMode then
    DrawMarkdownContent
  else if FDoc.Ready then
  begin
    for Y := 0 to ViewH - 1 do
    begin
      if FWordWrap and FViewOnly and (TextW > 0) then
      begin
        if MapDisplayRowToLine(FTopLine + Y, TextW, LineIdx, CharOffset) then
        begin
          Line := FDoc.GetLine(LineIdx);
          Vis := Copy(Line, CharOffset + 1, TextW);
        end
        else
        begin
          LineIdx := -1;
          CharOffset := 0;
          Vis := '';
        end;
      end
      else
      begin
        LineIdx := FTopLine + Y;
        if LineIdx < FDoc.LineCount then
          Line := FDoc.GetLine(LineIdx)
        else
          Line := '';
        if FLeftCol >= Length(Line) then
          Vis := ''
        else
          Vis := Copy(Line, FLeftCol + 1, TextW);
      end;
      if Length(Vis) < TextW then
        Vis := Vis + StringOfChar(' ', TextW - Length(Vis));
      FillGridRect(Buffer, 1, 1 + Y, W - 3, 1 + Y, ' ', FThemeColors.BodyFg, FThemeColors.BodyBg);
      if (1 + Y >= 0) and (1 + Y <= High(Buffer)) then
        TEditorPainter.DrawTextLine(Buffer[1 + Y], 1, TextW, Vis, 1, FThemeColors.BodyFg, FThemeColors.BodyBg);
      if FWordWrap and FViewOnly and (TextW > 0) then
        PaintVisibleSelection(1 + Y, LineIdx, CharOffset, Vis)
      else
        PaintVisibleSelection(1 + Y, LineIdx, FLeftCol, Vis);

      // Cursor on this line (drawn over selection).
      if (LineIdx = FCursorRow) and (FConfirm = ecNone) and FCursorVisible then
      begin
        if FWordWrap and FViewOnly and (TextW > 0) then
          DrawCol := FCursorCol - CharOffset
        else
          DrawCol := FCursorCol - FLeftCol;

        if (DrawCol >= 0) and (DrawCol < TextW) then
          MarkGridInsertCaret(Buffer, 1 + DrawCol, 1 + Y);
      end;
    end;
  end;

  DrawScrollBar;
  if FChromeless then
    Exit;

  // Frame closes above chrome: bottom border, then F-keys, then status.
  // A hidden status line still shows over the last row while it holds the
  // Find prompt or a Y/N question.
  DrawWindowBottomBorder(H - 1 - ChromeBottomRows, W);
  if GShowKeyBar then
    DrawFunctionKeys(KeyBarRow(H), W);
  if GShowStatusLine then
    DrawAppStatusLine(StatusLineRow(H), W)
  else if FConfirm <> ecNone then
    DrawAppStatusLine(H - 1, W);

  if Assigned(FDialog) and FDialog.Visible then
    FDialog.Draw(Buffer, W, H);
end;

function TEditorWindow.HandleFunctionBarClick(ALocalCol: Integer;
  AShift: TShiftState): Boolean;
var
  Items, Letters: TArray<string>;
  Hit: TFunctionBarHit;
  Key: Word;
  KeyChar: Char;
  Shift: TShiftState;
begin
  Result := False;
  FunctionBarGetItems(ChromeContext, AShift, Items, Letters);
  Hit := FunctionBarHitTest(ALocalCol, Area.Width, Items, Letters, AShift,
    Assigned(Theme));
  if not FunctionBarHitToInput(Hit, AShift, Key, KeyChar, Shift) then
    Exit;
  Result := HandleInput(Key, Shift, KeyChar);
end;

function TEditorWindow.HandleClick(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
begin
  // Kept for call sites; mouse selection uses Down/Move/Up.
  Result := HandleMouseDown(ALocalCol, ALocalRow, AShift);
end;

function TEditorWindow.HandleMouseDown(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
var
  W, Bottom, ViewH, MaxTop, TrackH, Row, Col: Integer;
  Frame: TRectI;
begin
  Result := False;
  FMouseSelecting := False;
  FPressLink := '';
  // Dialog frame first (may overlap F-bar on short windows); F-bar hints next
  // (Y/N/Esc for AskSave); only then treat outside click as Cancel.
  if Assigned(FDialog) and FDialog.Visible and
     FDialog.ContainsLocal(ALocalCol, ALocalRow) then
    Exit(FDialog.HandleClick(ALocalCol, ALocalRow, AShift));
  if ALocalRow = KeyBarRow(Area.Height) then
    Exit(HandleFunctionBarClick(ALocalCol, AShift));
  if Assigned(FDialog) and FDialog.Visible then
    Exit(FDialog.HandleClick(ALocalCol, ALocalRow));
  if FConfirm <> ecNone then
    Exit;
  // Frame [x] (DrawWindowFrame) - embedded Viewer/Editor and standalone.
  Frame := TRectI.Make(0, 0, Area.Width - 1, Area.Height - 1);
  if WindowFrameCloseHit(Frame, ALocalCol, ALocalRow) then
  begin
    RequestClose;
    Exit(True);
  end;
  W := Area.Width;
  Bottom := ContentBottomRow;
  if (W < 8) or (Bottom < 1) then
    Exit;

  // Scrollbar column.
  if ALocalCol = W - 2 then
  begin
    if (ALocalRow < 1) or (ALocalRow > Bottom) then
      Exit;
    ViewH := ViewHeight;
    MaxTop := Max(ContentRowCount - ViewH, 0);
    Result := True;
    if ALocalRow = 1 then
      ScrollBy(-1)
    else if ALocalRow = Bottom then
      ScrollBy(1)
    else if MaxTop > 0 then
    begin
      TrackH := Max(Bottom - 2, 1);
      ScrollTo(Round((ALocalRow - 2) * MaxTop / Max(TrackH - 1, 1)));
    end;
    Exit;
  end;

  if not HitTextCell(ALocalCol, ALocalRow, Row, Col) then
    Exit;

  Result := True;
  if ssShift in AShift then
  begin
    FClicks.Reset;
    SetCursorPos(Row, Col, True);
  end
  else if not FHexMode and (FClicks.Hit(ALocalCol, ALocalRow) > 1) then
  begin
    // Double click = word, the next quick click = whole line. No drag
    // selection afterwards: the range is already final.
    SelectClickRange(Row, Col, FClicks.Count = 3);
    Exit;
  end
  else
  begin
    // Anchor at click; selection appears when the cursor moves on drag.
    BreakInsertCoalesce;
    FSelAnchorRow := Row;
    FSelAnchorCol := Col;
    FCursorRow := Row;
    FCursorCol := Col;
    EnsureCursorVisible;
    NotifyHost;
    // The Help window tracks its own link presses.
    if FMarkdownMode and not FHelpMode and LinkAtCursor(FPressLink) and
       not IsExternalLink(FPressLink) then
      FPressLink := '';
  end;
  FMouseSelecting := True;
end;

function TEditorWindow.HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
var
  Row, Col, Bottom, CharOffset: Integer;
begin
  Result := False;
  if not FMouseSelecting then
    Exit;
  Result := True;

  if HitTextCell(ALocalCol, ALocalRow, Row, Col) then
  begin
    if (Row <> FCursorRow) or (Col <> FCursorCol) then
    begin
      FCursorRow := Row;
      FCursorCol := Col;
      EnsureCursorVisible;
      NotifyHost;
    end;
    Exit;
  end;

  // Drag above/below the text pane -> scroll and keep selecting.
  Bottom := ContentBottomRow;
  if (ALocalRow < 1) and (FTopLine > 0) then
  begin
    ScrollBy(-1);
    if FWordWrap and FViewOnly and (TextWidth > 0) then
    begin
      if MapDisplayRowToLine(FTopLine, TextWidth, Row, CharOffset) then
        Col := CharOffset + Max(ALocalCol - 1, 0)
      else
      begin
        Row := 0;
        Col := 0;
      end;
    end
    else
    begin
      Row := FTopLine;
      Col := FLeftCol + Max(ALocalCol - 1, 0);
    end;
    ClampDocPos(Row, Col);
    FCursorRow := Row;
    FCursorCol := Col;
    NotifyHost;
  end
  else if ALocalRow > Bottom then
  begin
    ScrollBy(1);
    if FWordWrap and FViewOnly and (TextWidth > 0) then
    begin
      if MapDisplayRowToLine(FTopLine + ViewHeight - 1, TextWidth, Row, CharOffset) then
        Col := CharOffset + Max(ALocalCol - 1, 0)
      else
      begin
        Row := Max(FDoc.LineCount - 1, 0);
        Col := 0;
      end;
    end
    else
    begin
      Row := Min(FTopLine + ViewHeight - 1, Max(FDoc.LineCount - 1, 0));
      Col := FLeftCol + Max(ALocalCol - 1, 0);
    end;
    ClampDocPos(Row, Col);
    FCursorRow := Row;
    FCursorCol := Col;
    NotifyHost;
  end;
end;

function TEditorWindow.HandleMouseUp: Boolean;
var
  Link: string;
begin
  Result := FMouseSelecting;
  FMouseSelecting := False;
  // A plain click (no drag selection) on an external link offers to open it.
  if (FPressLink <> '') and not HasSelection and LinkAtCursor(Link) and
     (Link = FPressLink) then
  begin
    FPressLink := '';
    OpenExternalLink(Link);
    Exit(True);
  end;
  FPressLink := '';
end;

procedure TEditorWindow.SetCursorVisible(AVisible: Boolean);
begin
  if FCursorVisible = AVisible then
    Exit;
  FCursorVisible := AVisible;
  Invalidate;
  NotifyHost;
end;

function TEditorWindow.KeymapChain: TArray<TKeymapContext>;
begin
  Result := EditorKeymapChain(EditorIsViewOnly, EditorIsMarkdownMode);
end;

function TEditorWindow.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := True;
  if not FCursorVisible then
  begin
    FCursorVisible := True;
    Invalidate;
  end;
  // Normalize Enter before dialog (FMX may deliver raw 13/10 or KeyChar only).
  if (AKey = 0) and ((AKeyChar = #13) or (AKeyChar = #10)) then
    AKey := vkReturn;
  if (AKey = 10) or (AKey = 13) then
    AKey := vkReturn;
  // AskSave: resolve Yes/No/Cancel here so F-bar letter hints and dialog buttons
  // cannot desync (a dialog-only path would swallow the outcome on Esc/outside).
  if FConfirm = ecAskSave then
    Exit(FDialogs.HandleAskSaveInput(AKey, AShift, AKeyChar));
  if Assigned(FDialog) and FDialog.Visible then
    Exit(FDialog.HandleInput(AKey, AShift, AKeyChar));

  if FHexMode and (AKey = vkInsert) and (AShift = []) then
  begin
    HexInsertZero;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  // Markdown Viewer: Tab / Shift+Tab select the next / previous link.
  if FMarkdownMode and ((AKey = vkTab) or ((AKey = 0) and (AKeyChar = #9))) and
     TKeyChord.Make(AKey, AKeyChar, AShift).HasMods([], [ssShift]) then
  begin
    SelectMarkdownLink(not (ssShift in AShift));
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  Result := DispatchEditorKeys(FKeymapHost, AKey, AShift, AKeyChar, ViewHeight);
end;
end.
