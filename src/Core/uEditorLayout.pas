unit uEditorLayout;

{ Pure layout / chrome helpers extracted from TEditorWindow: word-wrap
  mapping, mode title, CanEdit, status-line fragments, word-char class. }

interface

uses
  System.SysUtils, System.Math;

type
  TEditorLineTextFn = reference to function(AIndex: Integer): string;

function EditorIsWordChar(ACh: Char): Boolean;
function EditorModeTitle(AHexMode, AMarkdownMode, AViewOnly: Boolean): string;
function EditorCanEdit(AViewOnly, AHexMode, AMarkdownMode, ABinary, AReady,
  AReadOnly, ASaving, ALoading: Boolean): Boolean;
function EditorCanHexEdit(AViewOnly, AReady, AReadOnly, ASaving,
  ALoading: Boolean): Boolean;
function EditorDirtyName(const AName: string; AShowDirty: Boolean): string;
/// <summary>Rows a line of ALineLen single-cell characters takes at width ATextW.</summary>
function WrappedSegCount(ALineLen, ATextW: Integer): Integer;
/// <summary>Characters of the wrapped chunk that starts at character AStart (0-based):
/// as many as fit ATextW cells, at least one while any are left.</summary>
function WrapChunkLen(const ALine: string; AStart, ATextW: Integer): Integer;
/// <summary>Rows ALine takes at width ATextW cells (wide characters take two).</summary>
function WrappedLineRows(const ALine: string; ATextW: Integer): Integer;
function CountWrappedRows(ALineCount, ATextW: Integer;
  const AGetLine: TEditorLineTextFn): Integer;
function MapWrappedDisplayToLine(ALineCount, ADisplayRow, ATextW: Integer;
  const AGetLine: TEditorLineTextFn; out ALineIdx, ACharOffset: Integer): Boolean;
function MapWrappedLineToDisplay(ALineCount, ALineIdx, ACharOffset,
  ATextW: Integer; const AGetLine: TEditorLineTextFn): Integer;
procedure EditorPosAndLinesText(AReady, ALoading, AHexMode: Boolean;
  ACursorRow, ACursorCol, AHexBytesPerRow, AByteCount, ALineCount: Integer;
  const AError: string; out APosText, ALinesText: string);
/// <summary>0-based draw column of an insert caret in a 1-based wrapped chunk,
/// or False if the caret is not on this chunk.</summary>
function EditorCaretDrawCol(ACursorCol, AChunkStart1, AChunkEnd1, ADisplayLen,
  ATextW: Integer; ALastChunk: Boolean; out ADrawCol: Integer): Boolean;
function EditorStatusFlag(AHexMode, AViewOnly, AWordWrap, AReadOnly,
  ASaving: Boolean; const ADocStatus: string): string;

implementation

uses
  uInputLine, uStrings, uCharWidth;

// Same alphabet as the input lines (Ctrl+arrows, double-click word).
function EditorIsWordChar(ACh: Char): Boolean;
begin
  Result := TextIsWordChar(ACh);
end;

function EditorModeTitle(AHexMode, AMarkdownMode, AViewOnly: Boolean): string;
begin
  if AHexMode then
    Result := T('ui.window.hex', 'Hex')
  else if AMarkdownMode then
    Result := T('ui.window.markdown', 'Markdown')
  else if AViewOnly then
    Result := T('ui.window.viewer', 'Viewer')
  else
    Result := T('ui.window.editor', 'Editor');
end;

function EditorCanEdit(AViewOnly, AHexMode, AMarkdownMode, ABinary, AReady,
  AReadOnly, ASaving, ALoading: Boolean): Boolean;
begin
  Result := (not AViewOnly) and (not AHexMode) and (not AMarkdownMode) and
    (not ABinary) and AReady and (not AReadOnly) and (not ASaving) and
    (not ALoading);
end;

function EditorCanHexEdit(AViewOnly, AReady, AReadOnly, ASaving,
  ALoading: Boolean): Boolean;
begin
  Result := (not AViewOnly) and AReady and (not AReadOnly) and (not ASaving) and
    (not ALoading);
end;

function EditorDirtyName(const AName: string; AShowDirty: Boolean): string;
begin
  if AShowDirty then
    Result := '* ' + AName
  else
    Result := AName;
end;

function WrappedSegCount(ALineLen, ATextW: Integer): Integer;
begin
  if ATextW <= 0 then
    Exit(0);
  if ALineLen = 0 then
    Result := 1
  else
    Result := (ALineLen + ATextW - 1) div ATextW;
end;

function WrapChunkLen(const ALine: string; AStart, ATextW: Integer): Integer;
var
  I, Used, W: Integer;
begin
  Result := 0;
  if (ATextW <= 0) or (AStart < 0) or (AStart >= Length(ALine)) then
    Exit;
  Used := 0;
  for I := AStart + 1 to Length(ALine) do
  begin
    W := CharDisplayWidth(ALine[I]);
    if Used + W > ATextW then
      Break;
    Inc(Used, W);
    Inc(Result);
  end;
  if Result = 0 then
    Result := 1;
end;

function WrappedLineRows(const ALine: string; ATextW: Integer): Integer;
var
  Pos, Len: Integer;
begin
  if ATextW <= 0 then
    Exit(0);
  if not TextHasWide(ALine) then
    Exit(WrappedSegCount(Length(ALine), ATextW));
  Result := 0;
  Pos := 0;
  repeat
    Len := WrapChunkLen(ALine, Pos, ATextW);
    Inc(Pos, Len);
    Inc(Result);
  until Len = 0;
  // The last iteration found no characters left.
  Dec(Result);
end;

// Character offset (0-based) where chunk AChunk of ALine starts.
function WrappedChunkStart(const ALine: string; AChunk, ATextW: Integer): Integer;
var
  I: Integer;
begin
  if not TextHasWide(ALine) then
    Exit(AChunk * ATextW);
  Result := 0;
  for I := 1 to AChunk do
    Inc(Result, WrapChunkLen(ALine, Result, ATextW));
end;

// Chunk of ALine that holds character offset AOffset.
function WrappedChunkOf(const ALine: string; AOffset, ATextW: Integer): Integer;
var
  Pos, Len: Integer;
begin
  if not TextHasWide(ALine) then
    Exit(AOffset div ATextW);
  Result := 0;
  Pos := 0;
  repeat
    Len := WrapChunkLen(ALine, Pos, ATextW);
    if (Len = 0) or (Pos + Len > AOffset) then
      Exit;
    Inc(Pos, Len);
    Inc(Result);
  until False;
end;

function CountWrappedRows(ALineCount, ATextW: Integer;
  const AGetLine: TEditorLineTextFn): Integer;
var
  I: Integer;
begin
  Result := 0;
  if (ATextW <= 0) or (ALineCount <= 0) or not Assigned(AGetLine) then
    Exit;
  for I := 0 to ALineCount - 1 do
    Inc(Result, WrappedLineRows(AGetLine(I), ATextW));
end;

function MapWrappedDisplayToLine(ALineCount, ADisplayRow, ATextW: Integer;
  const AGetLine: TEditorLineTextFn; out ALineIdx, ACharOffset: Integer): Boolean;
var
  I, Segs, Accum: Integer;
  Line: string;
begin
  Result := False;
  ALineIdx := -1;
  ACharOffset := 0;
  if (ATextW <= 0) or (ADisplayRow < 0) or (ALineCount <= 0) or
     not Assigned(AGetLine) then
    Exit;
  Accum := 0;
  for I := 0 to ALineCount - 1 do
  begin
    Line := AGetLine(I);
    Segs := WrappedLineRows(Line, ATextW);
    if ADisplayRow < Accum + Segs then
    begin
      ALineIdx := I;
      ACharOffset := WrappedChunkStart(Line, ADisplayRow - Accum, ATextW);
      Exit(True);
    end;
    Inc(Accum, Segs);
  end;
end;

function MapWrappedLineToDisplay(ALineCount, ALineIdx, ACharOffset,
  ATextW: Integer; const AGetLine: TEditorLineTextFn): Integer;
var
  I: Integer;
begin
  Result := 0;
  if (ATextW <= 0) or (ALineCount <= 0) or not Assigned(AGetLine) then
    Exit;
  for I := 0 to Min(ALineIdx - 1, ALineCount - 1) do
    Inc(Result, WrappedLineRows(AGetLine(I), ATextW));
  if ALineIdx < ALineCount then
    Inc(Result, WrappedChunkOf(AGetLine(ALineIdx), ACharOffset, ATextW));
end;

procedure EditorPosAndLinesText(AReady, ALoading, AHexMode: Boolean;
  ACursorRow, ACursorCol, AHexBytesPerRow, AByteCount, ALineCount: Integer;
  const AError: string; out APosText, ALinesText: string);
begin
  APosText := '';
  ALinesText := '';
  if AReady then
  begin
    if AHexMode then
    begin
      APosText := Format('%.8x', [ACursorRow * AHexBytesPerRow + ACursorCol]);
      ALinesText := Format('%d bytes', [AByteCount]);
    end
    else
    begin
      APosText := Format('%d:%d', [ACursorRow + 1, ACursorCol + 1]);
      ALinesText := Format('%d lines', [ALineCount]);
    end;
  end
  else if ALoading then
    APosText := 'loading...'
  else if AError <> '' then
  begin
    APosText := 'error';
    ALinesText := AError;
  end;
end;

function EditorCaretDrawCol(ACursorCol, AChunkStart1, AChunkEnd1, ADisplayLen,
  ATextW: Integer; ALastChunk: Boolean; out ADrawCol: Integer): Boolean;
var
  Caret1: Integer;
begin
  Result := False;
  ADrawCol := 0;
  if (ATextW < 1) or (AChunkStart1 < 1) then
    Exit;
  if ACursorCol < 0 then
    ACursorCol := 0;
  if ACursorCol > ADisplayLen then
    ACursorCol := ADisplayLen;
  if ACursorCol >= ADisplayLen then
  begin
    if not ALastChunk then
      Exit;
    ADrawCol := ADisplayLen - (AChunkStart1 - 1);
  end
  else
  begin
    Caret1 := ACursorCol + 1;
    if (Caret1 < AChunkStart1) or (Caret1 > AChunkEnd1) then
      Exit;
    ADrawCol := Caret1 - AChunkStart1;
  end;
  if (ADrawCol < 0) or (ADrawCol >= ATextW) then
    Exit;
  Result := True;
end;

function EditorStatusFlag(AHexMode, AViewOnly, AWordWrap, AReadOnly,
  ASaving: Boolean; const ADocStatus: string): string;
begin
  if AHexMode then
    Result := 'Hex'
  else if AViewOnly then
  begin
    if AWordWrap then
      Result := 'View [Wrap]'
    else
      Result := 'View';
  end
  else if AReadOnly then
    Result := 'RO'
  else if ASaving then
    Result := 'Saving...'
  else
    Result := ADocStatus;
end;

end.
