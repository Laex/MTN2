unit uQuickTextView;

{ Ctrl+Q Quick View for everything that is not a picture: the passive panel
  shows the file under the active cursor through one embedded TEditorWindow
  in Viewer mode (Chromeless) -- text in its detected encoding, Markdown
  rendered, binary as a hex dump, big local files streamed. Pictures keep
  going through the image Overlay (TDualPanelWindow.DrawQuickViewContent).

  One viewer for the life of the panel: switching files goes through
  TEditorWindow.CloseDocument / Open, never Free -- TEditorDoc's async load
  callback would otherwise land on a freed object. CloseDocument cancels the
  load and bumps the document generation, so a stale result is dropped.

  ShowFile / Clear are called while the host paints; they do not fire
  OnChanged themselves (no repaint request from inside a paint). The load
  finishing later does, and the host repaints then. }

interface

uses
  System.SysUtils, System.Classes,
  uTerminalTypes, uThemeTypes, uDualPanelTypes, uEditorWindow;

type
  TQuickTextPreview = (qtpNone, qtpText, qtpAskF3);

  TQuickTextView = class
  private
    FViewer: TEditorWindow;
    FUri: string;
    FSilent: Integer;
    FOnChanged: TNotifyEvent;
    procedure ViewerChanged(Sender: TObject);
  public
    constructor Create(const ATheme: IThemeRenderer);
    destructor Destroy; override;
    /// <summary>What Quick View does with ARow when it is not a picture:
    /// qtpText -- open it; qtpAskF3 -- only on F3 (SFTP and other remote
    /// VFS, big files inside archives: reading them on every cursor move
    /// would stall the panel); qtpNone -- folder / "..", nothing to show.</summary>
    class function PreviewKind(AHasRow: Boolean; const ARow: TPanelRow): TQuickTextPreview; static;
    /// <summary>Starts loading AUri unless it is already shown.</summary>
    procedure ShowFile(const AUri: string);
    /// <summary>Forget the file (stops reading / watching it).</summary>
    procedure Clear;
    /// <summary>ABounds: the whole panel rectangle in AGrid (frame included;
    /// the frame is left as the panel drew it). AAbsLeft/Top: AGrid's origin
    /// in compositor cells.</summary>
    procedure Paint(const AGrid: TTerminalGrid; const ABounds: TRectI;
      AAbsLeft, AAbsTop: Integer);
    procedure ScrollBy(ADelta: Integer);
    property Uri: string read FUri;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

const
  /// <summary>Largest archive member Quick View reads on a cursor move.</summary>
  cQuickTextArchiveMaxBytes = 16 * 1024 * 1024;

implementation

uses
  uVfsTypes;

constructor TQuickTextView.Create(const ATheme: IThemeRenderer);
begin
  inherited Create;
  FViewer := TEditorWindow.Create(ATheme, High(Cardinal) - 1);
  FViewer.Embedded := True;
  FViewer.Chromeless := True;
  FViewer.OnContentChanged := ViewerChanged;
end;

destructor TQuickTextView.Destroy;
begin
  FViewer.OnContentChanged := nil;
  FreeAndNil(FViewer);
  inherited;
end;

class function TQuickTextView.PreviewKind(AHasRow: Boolean;
  const ARow: TPanelRow): TQuickTextPreview;
begin
  if not AHasRow or ARow.IsDirectory or ARow.IsParent or (ARow.URI = '') then
    Exit(qtpNone);
  if HasArchiveChain(ARow.URI) then
  begin
    if (ARow.Size >= 0) and (ARow.Size <= cQuickTextArchiveMaxBytes) then
      Exit(qtpText);
    Exit(qtpAskF3);
  end;
  if FileUriToPath(ARow.URI) <> '' then
    Result := qtpText
  else
    Result := qtpAskF3;
end;

procedure TQuickTextView.ViewerChanged(Sender: TObject);
begin
  if (FSilent = 0) and Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TQuickTextView.ShowFile(const AUri: string);
begin
  if SameText(AUri, FUri) then
    Exit;
  Inc(FSilent);
  try
    FUri := AUri;
    FViewer.Open(AUri, True);
  finally
    Dec(FSilent);
  end;
end;

procedure TQuickTextView.Clear;
begin
  if FUri = '' then
    Exit;
  Inc(FSilent);
  try
    FUri := '';
    FViewer.CloseDocument;
  finally
    Dec(FSilent);
  end;
end;

procedure TQuickTextView.Paint(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AAbsLeft, AAbsTop: Integer);
begin
  if FUri = '' then
    Exit;
  FViewer.PaintEmbedded(AGrid, ABounds.Left, ABounds.Top, ABounds.Width,
    ABounds.Height, AAbsLeft + ABounds.Left, AAbsTop + ABounds.Top);
end;

procedure TQuickTextView.ScrollBy(ADelta: Integer);
begin
  if FUri <> '' then
    FViewer.ScrollLines(ADelta);
end;

end.
