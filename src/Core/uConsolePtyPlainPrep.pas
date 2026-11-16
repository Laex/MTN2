unit uConsolePtyPlainPrep;

{ Pure PTY plain-buffer heuristics used before AppendOutputEx parses a chunk:
  drive/PS/shell prompt recognition, glued-prompt newline rewrite, and when
  a new plain line must start before the chunk is applied. }

interface

uses
  System.SysUtils, System.Classes, System.Math;

type
  TPlainChunkBreak = (pcbGluedPrompt, pcbOutputAfterInput);
  TPlainChunkBreaks = set of TPlainChunkBreak;

function LooksLikeDrivePrompt(const S: string): Boolean;
function FindPromptEndIndex(const ALine: string): Integer;
function FindPromptProtectedEnd(const ALine: string): Integer;
function LineHasInputAfterPrompt(const ALine: string): Boolean;
/// <summary>True if S has at least one char that is not part of a
/// backspace/erase idiom (BS, DEL, or a plain space used to blank a cell).</summary>
function HasPrintableChunkContent(const S: string): Boolean;
function FixPromptNewlines(const AText: string; APendingRedraw: Boolean): string;
/// <summary>Which StartNewLine calls BreakLineBeforeChunk should make for a
/// non-empty current plain line. Empty set when grid/local/CRLF lead/empty.</summary>
function ClassifyPlainChunkLineBreaks(const ACurrentLineTrimmed, AChunk: string;
  AGridEnabled, AIsLocalInput: Boolean): TPlainChunkBreaks;

implementation

function LooksLikeDrivePrompt(const S: string): Boolean;
var
  Trimmed: string;
begin
  Result := False;
  if Length(S) >= 3 then
  begin
    if CharInSet(S[1], ['A'..'Z', 'a'..'z']) and (S[2] = ':') and (S[3] = '\') then
      Exit(True);
    if (Length(S) >= 6) and (S[1] = 'P') and (S[2] = 'S') and (S[3] = ' ') and
       CharInSet(S[4], ['A'..'Z', 'a'..'z']) and (S[5] = ':') and (S[6] = '\') then
      Exit(True);
    Trimmed := TrimRight(S);
    if (Trimmed <> '') and CharInSet(Trimmed[Length(Trimmed)], ['$', '#']) then
      Exit(True);
  end;
end;

function FindPromptEndIndex(const ALine: string): Integer;
var
  I, Start: Integer;
begin
  Result := 0;
  if ALine = '' then
    Exit;

  Start := 1;
  if (Length(ALine) >= 3) and (ALine[1] = 'P') and (ALine[2] = 'S') and (ALine[3] = ' ') then
  begin
    for I := 4 to Length(ALine) do
      if ALine[I] = '>' then
        Exit(I);
    Exit;
  end;

  if (Length(ALine) >= Start + 1) and CharInSet(ALine[Start], ['A'..'Z', 'a'..'z']) and
     (ALine[Start + 1] = ':') then
  begin
    for I := Start + 2 to Length(ALine) do
      if ALine[I] = '>' then
        Exit(I);
    Exit;
  end;

  if (Length(ALine) >= Start + 1) and (ALine[Start] = '\') and (ALine[Start + 1] = '\') then
  begin
    for I := Start + 2 to Length(ALine) do
      if ALine[I] = '>' then
        Exit(I);
    Exit;
  end;

  for I := 1 to Length(ALine) do
    if CharInSet(ALine[I], ['$', '#']) then
      Exit(I);
end;

function FindPromptProtectedEnd(const ALine: string): Integer;
var
  PromptEnd, I: Integer;
begin
  PromptEnd := FindPromptEndIndex(ALine);
  Result := PromptEnd;
  if PromptEnd = 0 then
    Exit;
  I := PromptEnd + 1;
  while (I <= Length(ALine)) and (ALine[I] = ' ') do
    Inc(I);
  Result := I - 1;
end;

function HasPrintableChunkContent(const S: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
    if (S[I] >= ' ') and (Ord(S[I]) <> 127) and (S[I] <> ' ') then
      Exit(True);
end;

function LineHasInputAfterPrompt(const ALine: string): Boolean;
var
  PromptEnd: Integer;
begin
  PromptEnd := FindPromptProtectedEnd(ALine);
  Result := (PromptEnd > 0) and (Trim(Copy(ALine, PromptEnd + 1, MaxInt)) <> '');
end;

function FixPromptNewlines(const AText: string; APendingRedraw: Boolean): string;
var
  I, Len, PromptStart: Integer;
  Sb: TStringBuilder;
begin
  Len := Length(AText);
  if Len < 4 then
    Exit(AText);
  // A chunk led by CR is a full-line redraw (readline/cmd rewriting the
  // current line from column 0), not two PTY events glued together. Same for
  // a chunk arriving while an erase-to-EOL is still pending (deferred until
  // the redraw's replacement content shows up, possibly in a later chunk
  // with no CR of its own - see PutCellAtCursorLocked). Any "drive:\...>"
  // pattern found in either case is that same redraw's own content
  // re-echoing the prompt, not a new prompt arriving - splitting it here
  // fractures a single redraw into a phantom extra line and drops the prompt
  // prefix (see TestCmdCrPromptRedraw / TestCrElWipesPrompt).
  if (AText[1] = #13) or APendingRedraw then
    Exit(AText);

  Sb := TStringBuilder.Create(Len + 32);
  try
    I := 1;
    while I <= Len do
    begin
      if (I <= Len - 3) and CharInSet(AText[I], ['A'..'Z', 'a'..'z']) and
         (AText[I + 1] = ':') and (AText[I + 2] = '\') then
      begin
        PromptStart := I;
        Inc(I, 3);
        while (I <= Len) and (AText[I] <> '>') and (AText[I] <> #10) and
              (AText[I] <> #13) do
          Inc(I);

        if (I <= Len) and (AText[I] = '>') then
        begin
          Sb.Append(Copy(AText, PromptStart, I - PromptStart + 1));
          Inc(I);
          // Only split when real (non-whitespace) content is glued directly
          // onto the prompt - e.g. a second prompt or command text arriving
          // in the same PTY chunk with no newline between them. A prompt's
          // own trailing padding ("PS D:\path> ") has nothing but whitespace
          // after '>' and must stay on the same line: inserting a break here
          // corrupted it (the synthetic CR then reset the write cursor to
          // column 0, so the very next character - that trailing space -
          // overwrote the prompt's first letter instead of being appended).
          if (I <= Len) and not CharInSet(AText[I], [#10, #13]) and
             (Trim(Copy(AText, I, MaxInt)) <> '') then
            Sb.Append(#13#10);
          Continue;
        end
        else
          I := PromptStart;
      end;

      Sb.Append(AText[I]);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function ClassifyPlainChunkLineBreaks(const ACurrentLineTrimmed, AChunk: string;
  AGridEnabled, AIsLocalInput: Boolean): TPlainChunkBreaks;
begin
  Result := [];
  if AGridEnabled or AIsLocalInput or (AChunk = '') or
     CharInSet(AChunk[1], [#10, #13]) or (ACurrentLineTrimmed = '') then
    Exit;
  // The shell may emit "D:\path>next" with no newline after a line that
  // already ends with '>'.
  if (ACurrentLineTrimmed[Length(ACurrentLineTrimmed)] = '>') and
     LooksLikeDrivePrompt(AChunk) then
    Include(Result, pcbGluedPrompt);
  // Output after a submitted "D:\path>cmd" goes to its own row. A burst of
  // control chars only ("\b\b" from two quick backspaces) edits the line in
  // place instead.
  if LineHasInputAfterPrompt(ACurrentLineTrimmed) and
     ((Length(AChunk) > 1) or (AChunk[1] = ' ')) and
     HasPrintableChunkContent(AChunk) then
    Include(Result, pcbOutputAfterInput);
end;

end.
