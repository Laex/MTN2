unit uInputLine;

{ Shared single-line text editor (SDS Input Line): caret, selection, clipboard.
  Used by Dual Panel cmdline, dialog stubs, Viewer find, etc. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes;

type
  TInputLine = record
    Text: string;
    Cursor: Integer;     // 0..Length(Text)
    SelAnchor: Integer;  // -1 = no selection
    ViewLeft: Integer;   // horizontal scroll
  end;

  TInputLineResult = (
    ilrHandled,      // key consumed; state may have changed
    ilrSubmit,       // Enter
    ilrCancel,       // Escape on empty field (caller: unfocus / close)
    ilrPassThrough   // not consumed (e.g. scroll keys when allowed)
  );

  TInputLineColors = record
    Fg, Bg: TAlphaColor;
    SelFg, SelBg: TAlphaColor;
    CaretFg, CaretBg: TAlphaColor;
  end;

function InputLineEmpty: TInputLine;
procedure InputLineReset(var A: TInputLine);
procedure InputLineSetText(var A: TInputLine; const AText: string;
  ACursorAtEnd: Boolean = True);
procedure InputLineInsert(var A: TInputLine; const AText: string);
procedure InputLineSelectAll(var A: TInputLine);
procedure InputLineClearSelection(var A: TInputLine);
function InputLineHasSelection(const A: TInputLine): Boolean;
function InputLineSelectedText(const A: TInputLine): string;
procedure InputLineCopy(const A: TInputLine);
procedure InputLineCut(var A: TInputLine);
procedure InputLinePaste(var A: TInputLine);

function InputLineHandleInput(var A: TInputLine; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char;
  APassScrollKeys: Boolean = False): TInputLineResult;

procedure InputLineDraw(const AGrid: TTerminalGrid; AX, AY, AWidth: Integer;
  var A: TInputLine; AFocused: Boolean; const AColors: TInputLineColors;
  ACursorVisible: Boolean = True; APasswordMask: Boolean = False);

function InputLineDefaultColors(AFocused: Boolean): TInputLineColors;
function InputLineDialogColors(AFocused: Boolean): TInputLineColors;

procedure ClipboardSet(const AText: string);
function ClipboardGet: string;

/// <summary>Word-navigation alphabet shared by input lines and the
/// Viewer/Editor: letters (any script), digits and '_'. Everything else —
/// spaces, punctuation, path separators — is a delimiter.</summary>
function TextIsWordChar(ACh: Char): Boolean;
/// <summary>Ctrl+Right step within one line: skip delimiters, then the word,
/// stopping at the next delimiter. APos/Result are 0-based caret positions
/// (0..Length(S)).</summary>
function TextWordStepRight(const S: string; APos: Integer): Integer;
/// <summary>Ctrl+Left step: skip delimiters leftwards, then the word, stopping
/// right after the previous delimiter.</summary>
function TextWordStepLeft(const S: string; APos: Integer): Integer;
/// <summary>Double-click range around the char at 0-based AIndex: the whole
/// word for a word char, otherwise the run of the same delimiter char.
/// [AStart, AEnd) in 0-based caret positions; empty when S is empty.</summary>
procedure TextWordRangeAt(const S: string; AIndex: Integer; out AStart, AEnd: Integer);
/// <summary>Upper-cased char the same physical key produces on the other
/// keyboard layout (US QWERTY <-> Russian JCUKEN), or #0 when the key is on
/// neither table -- lets a menu hotkey fire whichever layout is active.</summary>
function TextKeyLayoutAlternate(AChar: Char): Char;

type
  /// <summary>Counts consecutive left clicks on the same cell within the
  /// system double-click time: 1 = click, 2 = double, 3 = triple; a fourth
  /// quick click starts over at 1.</summary>
  TMouseClickCounter = record
    LastTick: Cardinal;
    LastX, LastY: Integer;
    Count: Integer;
    function Hit(AX, AY: Integer): Integer;
    procedure Reset;
  end;

/// <summary>Mouse click inside a drawn input line. ARelCol is the cell offset
/// from the field's left edge (the AX passed to InputLineDraw). AClickCount:
/// 1 = place caret (extend selection with AExtendSel), 2 = select the word
/// under the cell, 3 = select the whole line.</summary>
procedure InputLineMouseClick(var A: TInputLine; ARelCol, AClickCount: Integer;
  AExtendSel: Boolean = False);

implementation

uses
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  System.Rtti, System.Character, FMX.Platform;

procedure Clamp(var A: TInputLine);
begin
  if A.Cursor < 0 then
    A.Cursor := 0;
  if A.Cursor > Length(A.Text) then
    A.Cursor := Length(A.Text);
  if A.ViewLeft < 0 then
    A.ViewLeft := 0;
  if A.ViewLeft > Length(A.Text) then
    A.ViewLeft := Length(A.Text);
end;

function SelLo(const A: TInputLine): Integer;
begin
  if not InputLineHasSelection(A) then
    Exit(A.Cursor);
  Result := Min(A.SelAnchor, A.Cursor);
end;

function SelHi(const A: TInputLine): Integer;
begin
  if not InputLineHasSelection(A) then
    Exit(A.Cursor);
  Result := Max(A.SelAnchor, A.Cursor);
end;

procedure DeleteSelection(var A: TInputLine);
var
  Lo, Hi: Integer;
begin
  if not InputLineHasSelection(A) then
    Exit;
  Lo := SelLo(A);
  Hi := SelHi(A);
  Delete(A.Text, Lo + 1, Hi - Lo);
  A.Cursor := Lo;
  InputLineClearSelection(A);
  Clamp(A);
end;

procedure InsertText(var A: TInputLine; const AText: string);
var
  S: string;
begin
  if AText = '' then
    Exit;
  S := StringReplace(AText, #13#10, ' ', [rfReplaceAll]);
  S := StringReplace(S, #13, ' ', [rfReplaceAll]);
  S := StringReplace(S, #10, ' ', [rfReplaceAll]);
  if InputLineHasSelection(A) then
    DeleteSelection(A);
  Insert(S, A.Text, A.Cursor + 1);
  Inc(A.Cursor, Length(S));
  InputLineClearSelection(A);
  Clamp(A);
end;

procedure EnsureVisible(var A: TInputLine; AEditWidth: Integer);
begin
  if AEditWidth < 1 then
    AEditWidth := 1;
  Clamp(A);
  if A.Cursor < A.ViewLeft then
    A.ViewLeft := A.Cursor;
  if A.Cursor > A.ViewLeft + AEditWidth - 1 then
    A.ViewLeft := A.Cursor - AEditWidth + 1;
  if A.ViewLeft < 0 then
    A.ViewLeft := 0;
end;

procedure MoveCursor(var A: TInputLine; ADelta: Integer; AExtendSel: Boolean);
begin
  if AExtendSel then
  begin
    if A.SelAnchor < 0 then
      A.SelAnchor := A.Cursor;
  end
  else
    InputLineClearSelection(A);
  Inc(A.Cursor, ADelta);
  Clamp(A);
end;

function TextIsWordChar(ACh: Char): Boolean;
begin
  Result := ACh.IsLetterOrDigit or (ACh = '_');
end;

function TextWordStepRight(const S: string; APos: Integer): Integer;
begin
  Result := EnsureRange(APos, 0, Length(S));
  while (Result < Length(S)) and not TextIsWordChar(S[Result + 1]) do
    Inc(Result);
  while (Result < Length(S)) and TextIsWordChar(S[Result + 1]) do
    Inc(Result);
end;

function TextWordStepLeft(const S: string; APos: Integer): Integer;
begin
  Result := EnsureRange(APos, 0, Length(S));
  while (Result > 0) and not TextIsWordChar(S[Result]) do
    Dec(Result);
  while (Result > 0) and TextIsWordChar(S[Result]) do
    Dec(Result);
end;

procedure TextWordRangeAt(const S: string; AIndex: Integer; out AStart, AEnd: Integer);
var
  Ch: Char;
begin
  if S = '' then
  begin
    AStart := 0;
    AEnd := 0;
    Exit;
  end;
  // A click past the end of the text picks the last char's word.
  AIndex := EnsureRange(AIndex, 0, Length(S) - 1);
  AStart := AIndex;
  AEnd := AIndex + 1;
  Ch := S[AIndex + 1];
  if TextIsWordChar(Ch) then
  begin
    while (AStart > 0) and TextIsWordChar(S[AStart]) do
      Dec(AStart);
    while (AEnd < Length(S)) and TextIsWordChar(S[AEnd + 1]) do
      Inc(AEnd);
  end
  else
  begin
    while (AStart > 0) and (S[AStart] = Ch) do
      Dec(AStart);
    while (AEnd < Length(S)) and (S[AEnd + 1] = Ch) do
      Inc(AEnd);
  end;
end;

const
  // Same physical keys, index for index. Char codes: this unit has no BOM.
  cLatinKeys = 'QWERTYUIOP[]ASDFGHJKL;''ZXCVBNM,.`';
  cCyrillicKeys =
    #$0419#$0426#$0423#$041A#$0415#$041D#$0413#$0428#$0429#$0417#$0425#$042A +
    #$0424#$042B#$0412#$0410#$041F#$0420#$041E#$041B#$0414#$0416#$042D +
    #$042F#$0427#$0421#$041C#$0418#$0422#$042C#$0411#$042E +
    #$0401;

function TextKeyLayoutAlternate(AChar: Char): Char;
var
  P: Integer;
begin
  Result := #0;
  AChar := AChar.ToUpper;
  P := Pos(AChar, cLatinKeys);
  if P > 0 then
    Exit(cCyrillicKeys[P]);
  P := Pos(AChar, cCyrillicKeys);
  if P > 0 then
    Result := cLatinKeys[P];
end;

function TMouseClickCounter.Hit(AX, AY: Integer): Integer;
var
  NowTick, Limit: Cardinal;
begin
  NowTick := TThread.GetTickCount;
  {$IFDEF MSWINDOWS}
  Limit := GetDoubleClickTime;
  {$ELSE}
  Limit := 500;
  {$ENDIF}
  if (Count > 0) and (Count < 3) and (AX = LastX) and (AY = LastY) and
     (NowTick - LastTick <= Limit) then
    Inc(Count)
  else
    Count := 1;
  LastTick := NowTick;
  LastX := AX;
  LastY := AY;
  Result := Count;
end;

procedure TMouseClickCounter.Reset;
begin
  Count := 0;
end;

procedure InputLineMouseClick(var A: TInputLine; ARelCol, AClickCount: Integer;
  AExtendSel: Boolean);
var
  P, WStart, WEnd: Integer;
begin
  Clamp(A);
  P := EnsureRange(A.ViewLeft + Max(ARelCol, 0), 0, Length(A.Text));
  case AClickCount of
    2:
      begin
        TextWordRangeAt(A.Text, P, WStart, WEnd);
        A.SelAnchor := WStart;
        A.Cursor := WEnd;
      end;
    3:
      InputLineSelectAll(A);
  else
    if AExtendSel then
    begin
      if A.SelAnchor < 0 then
        A.SelAnchor := A.Cursor;
    end
    else
      InputLineClearSelection(A);
    A.Cursor := P;
  end;
  Clamp(A);
end;

// Ctrl+Left/Right; with Shift it grows or shrinks the selection (the anchor
// stays put, so stepping back over the selected part releases it).
procedure MoveWord(var A: TInputLine; AForward, AExtendSel: Boolean);
begin
  if AExtendSel then
  begin
    if A.SelAnchor < 0 then
      A.SelAnchor := A.Cursor;
  end
  else
    InputLineClearSelection(A);

  if AForward then
    A.Cursor := TextWordStepRight(A.Text, A.Cursor)
  else
    A.Cursor := TextWordStepLeft(A.Text, A.Cursor);
  Clamp(A);
end;

function ClipboardGet: string;
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

procedure ClipboardSet(const AText: string);
var
  Svc: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Svc.SetClipboard(AText);
end;

function InputLineEmpty: TInputLine;
begin
  Result.Text := '';
  Result.Cursor := 0;
  Result.SelAnchor := -1;
  Result.ViewLeft := 0;
end;

procedure InputLineReset(var A: TInputLine);
begin
  A := InputLineEmpty;
end;

procedure InputLineSetText(var A: TInputLine; const AText: string;
  ACursorAtEnd: Boolean);
begin
  A.Text := AText;
  if ACursorAtEnd then
    A.Cursor := Length(A.Text)
  else
    A.Cursor := 0;
  A.SelAnchor := -1;
  A.ViewLeft := 0;
  Clamp(A);
end;

procedure InputLineInsert(var A: TInputLine; const AText: string);
begin
  InsertText(A, AText);
end;

procedure InputLineSelectAll(var A: TInputLine);
begin
  A.SelAnchor := 0;
  A.Cursor := Length(A.Text);
  Clamp(A);
end;

procedure InputLineClearSelection(var A: TInputLine);
begin
  A.SelAnchor := -1;
end;

function InputLineHasSelection(const A: TInputLine): Boolean;
begin
  Result := (A.SelAnchor >= 0) and (A.SelAnchor <> A.Cursor);
end;

function InputLineSelectedText(const A: TInputLine): string;
begin
  if not InputLineHasSelection(A) then
    Exit('');
  Result := Copy(A.Text, SelLo(A) + 1, SelHi(A) - SelLo(A));
end;

procedure InputLineCopy(const A: TInputLine);
begin
  if InputLineHasSelection(A) then
    ClipboardSet(InputLineSelectedText(A))
  else if A.Text <> '' then
    ClipboardSet(A.Text);
end;

procedure InputLineCut(var A: TInputLine);
begin
  if InputLineHasSelection(A) then
  begin
    ClipboardSet(InputLineSelectedText(A));
    DeleteSelection(A);
  end
  else if A.Text <> '' then
  begin
    ClipboardSet(A.Text);
    InputLineReset(A);
  end;
end;

procedure InputLinePaste(var A: TInputLine);
begin
  InsertText(A, ClipboardGet);
end;

function InputLineHandleInput(var A: TInputLine; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char;
  APassScrollKeys: Boolean): TInputLineResult;
var
  Ch: Char;
begin
  Result := ilrHandled;

  if (AKey = vkInsert) and (ssShift in AShift) and not (ssAlt in AShift) then
  begin
    InputLinePaste(A);
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  if (AKey = vkInsert) and (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    InputLineCopy(A);
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  // Shift+Delete / Ctrl+Delete — cut (extra-keyboard equivalents of Ctrl+X).
  if (AKey = vkDelete) and not (ssAlt in AShift) and
     (((ssShift in AShift) and not (ssCtrl in AShift)) or
      ((ssCtrl in AShift) and not (ssShift in AShift))) then
  begin
    InputLineCut(A);
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  if (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    Ch := #0;
    if (AKey = Ord('A')) or (AKey = Ord('a')) or (AKeyChar = 'a') or (AKeyChar = 'A') then
      Ch := 'a'
    else if (AKey = Ord('C')) or (AKey = Ord('c')) or (AKeyChar = 'c') or (AKeyChar = 'C') then
      Ch := 'c'
    else if (AKey = Ord('X')) or (AKey = Ord('x')) or (AKeyChar = 'x') or (AKeyChar = 'X') then
      Ch := 'x'
    else if (AKey = Ord('V')) or (AKey = Ord('v')) or (AKeyChar = 'v') or (AKeyChar = 'V') then
      Ch := 'v';

    if Ch = 'a' then
    begin
      InputLineSelectAll(A);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if Ch = 'c' then
    begin
      InputLineCopy(A);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if Ch = 'x' then
    begin
      InputLineCut(A);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
    if Ch = 'v' then
    begin
      InputLinePaste(A);
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
  end;

  case AKey of
    vkEscape:
      begin
        if InputLineHasSelection(A) then
          InputLineClearSelection(A)
        else if A.Text <> '' then
          InputLineReset(A)
        else
        begin
          Result := ilrCancel;
          AKey := 0;
          Exit;
        end;
        AKey := 0;
      end;
    vkReturn:
      begin
        Result := ilrSubmit;
        AKey := 0;
      end;
    vkLeft:
      begin
        if ssCtrl in AShift then
          MoveWord(A, False, ssShift in AShift)
        else
          MoveCursor(A, -1, ssShift in AShift);
        AKey := 0;
      end;
    vkRight:
      begin
        if ssCtrl in AShift then
          MoveWord(A, True, ssShift in AShift)
        else
          MoveCursor(A, 1, ssShift in AShift);
        AKey := 0;
      end;
    vkHome:
      begin
        MoveCursor(A, -A.Cursor, ssShift in AShift);
        AKey := 0;
      end;
    vkEnd:
      begin
        MoveCursor(A, Length(A.Text) - A.Cursor, ssShift in AShift);
        AKey := 0;
      end;
    vkBack:
      begin
        if InputLineHasSelection(A) then
          DeleteSelection(A)
        else if A.Cursor > 0 then
        begin
          Delete(A.Text, A.Cursor, 1);
          Dec(A.Cursor);
        end;
        AKey := 0;
      end;
    vkDelete:
      begin
        if InputLineHasSelection(A) then
          DeleteSelection(A)
        else if A.Cursor < Length(A.Text) then
          Delete(A.Text, A.Cursor + 1, 1);
        AKey := 0;
      end;
  else
    if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
       not (ssCtrl in AShift) and not (ssAlt in AShift) then
    begin
      InsertText(A, AKeyChar);
      AKey := 0;
      AKeyChar := #0;
    end
    else if APassScrollKeys and
      ((AKey = vkUp) or (AKey = vkDown) or (AKey = vkPrior) or (AKey = vkNext)) then
      Result := ilrPassThrough
    else
    begin
      AKey := 0;
      AKeyChar := #0;
    end;
  end;
end;

function InputLineDefaultColors(AFocused: Boolean): TInputLineColors;
begin
  Result.Fg := TAlphaColor($FFE0E0E0);
  Result.Bg := TAlphaColor($FF000000);
  if AFocused then
  begin
    Result.SelFg := TAlphaColor($FF000000);
    Result.SelBg := TAlphaColor($FF3CE0E0);
    Result.CaretFg := TAlphaColor($FF000000);
    Result.CaretBg := TAlphaColor($FF3CE0E0);
  end
  else
  begin
    Result.SelFg := Result.Fg;
    Result.SelBg := Result.Bg;
    Result.CaretFg := Result.Fg;
    Result.CaretBg := Result.Bg;
  end;
end;

function InputLineDialogColors(AFocused: Boolean): TInputLineColors;
begin
  // FAR dialog edit: cyan field on white body (same cursor colors as overlay menus).
  Result.Fg := TAlphaColor($FF000000);
  Result.Bg := TAlphaColor($FF00AAAA);
  if AFocused then
  begin
    // Selection / caret = inverse of field (cyan on black), matching menu contrast.
    Result.SelFg := TAlphaColor($FF00AAAA);
    Result.SelBg := TAlphaColor($FF000000);
    Result.CaretFg := TAlphaColor($FF00AAAA);
    Result.CaretBg := TAlphaColor($FF000000);
  end
  else
  begin
    Result.SelFg := Result.Fg;
    Result.SelBg := Result.Bg;
    Result.CaretFg := Result.Fg;
    Result.CaretBg := Result.Bg;
  end;
end;

procedure InputLineDraw(const AGrid: TTerminalGrid; AX, AY, AWidth: Integer;
  var A: TInputLine; AFocused: Boolean; const AColors: TInputLineColors;
  ACursorVisible: Boolean; APasswordMask: Boolean);
var
  X, I, AbsIdx, MaxVis: Integer;
  Vis: string;
  Ch: Char;
  Fg, Bg: TAlphaColor;
begin
  if AWidth < 1 then
    Exit;
  FillGridRect(AGrid, AX, AY, AX + AWidth - 1, AY, ' ', AColors.Fg, AColors.Bg);
  EnsureVisible(A, AWidth);
  MaxVis := Min(AWidth, Max(Length(A.Text) - A.ViewLeft, 0));
  Vis := Copy(A.Text, A.ViewLeft + 1, MaxVis);

  X := AX;
  for I := 1 to Length(Vis) do
  begin
    if X >= AX + AWidth then
      Break;
    AbsIdx := A.ViewLeft + I - 1;
    if APasswordMask then
      Ch := '*'
    else
      Ch := Vis[I];
    if AFocused and InputLineHasSelection(A) and
       (AbsIdx >= SelLo(A)) and (AbsIdx < SelHi(A)) then
    begin
      Fg := AColors.SelFg;
      Bg := AColors.SelBg;
    end
    else
    begin
      Fg := AColors.Fg;
      Bg := AColors.Bg;
    end;
    PutGridText(AGrid, X, AY, Ch, Fg, Bg);
    Inc(X);
  end;

  if AFocused and ACursorVisible then
  begin
    X := AX + (A.Cursor - A.ViewLeft);
    if (X >= AX) and (X < AX + AWidth) then
      MarkGridInsertCaret(AGrid, X, AY);
  end;
end;

end.
