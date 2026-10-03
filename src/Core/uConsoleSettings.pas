unit uConsoleSettings;

{ Console and terminal options: scrollback size, confirmation of a multi-line
  paste, trimming of trailing spaces on copy and paste. Kept in session.json
  (uSession), edited in Options > Console... and read by TBaseConsoleWindow. }

interface

uses
  System.SysUtils;

const
  /// <summary>Scrollback sizes offered by the dialog, in lines.</summary>
  cScrollbackChoices: array[0..4] of Integer = (1000, 5000, 10000, 25000, 50000);
  cDefaultScrollbackLines = 10000;

type
  TConsoleSettings = record
    /// <summary>Lines kept above the screen (one of cScrollbackChoices).</summary>
    ScrollbackLines: Integer;
    /// <summary>Ask before pasting text of more than one line.</summary>
    ConfirmMultiLinePaste: Boolean;
    /// <summary>Copied text loses the spaces at the end of every line.</summary>
    TrimCopiedSpaces: Boolean;
    /// <summary>Pasted text loses the spaces at the end of every line.</summary>
    TrimPastedSpaces: Boolean;
  end;

var
  /// <summary>Live values; TBaseConsoleWindow reads them on every output,
  /// copy and paste, so a change applies to the open consoles at once.</summary>
  GConsoleSettings: TConsoleSettings;

function DefaultConsoleSettings: TConsoleSettings;
/// <summary>Nearest offered scrollback size.</summary>
function ClampScrollbackLines(ALines: Integer): Integer;
function ScrollbackIndexOf(ALines: Integer): Integer;
function ScrollbackAt(AIndex: Integer): Integer;
/// <summary>Dialog dropdown items ("10000 lines").</summary>
function ScrollbackItems: TArray<string>;
/// <summary>More than one line once trailing line breaks are ignored.</summary>
function IsMultiLineText(const AText: string): Boolean;
/// <summary>Lines in AText, ignoring trailing line breaks (0 for empty).</summary>
function CountTextLines(const AText: string): Integer;
/// <summary>Removes spaces and tabs before every line break and at the end;
/// the line breaks themselves are kept as they are.</summary>
function TrimTrailingSpaces(const AText: string): string;

implementation

uses
  System.Math, uStrings;

function DefaultConsoleSettings: TConsoleSettings;
begin
  Result.ScrollbackLines := cDefaultScrollbackLines;
  Result.ConfirmMultiLinePaste := False;
  Result.TrimCopiedSpaces := False;
  Result.TrimPastedSpaces := False;
end;

function ScrollbackIndexOf(ALines: Integer): Integer;
var
  I, Best: Integer;
begin
  Best := 0;
  for I := 1 to High(cScrollbackChoices) do
    if Abs(cScrollbackChoices[I] - ALines) < Abs(cScrollbackChoices[Best] - ALines) then
      Best := I;
  Result := Best;
end;

function ScrollbackAt(AIndex: Integer): Integer;
begin
  Result := cScrollbackChoices[EnsureRange(AIndex, 0, High(cScrollbackChoices))];
end;

function ClampScrollbackLines(ALines: Integer): Integer;
begin
  Result := ScrollbackAt(ScrollbackIndexOf(ALines));
end;

function ScrollbackItems: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(cScrollbackChoices));
  for I := 0 to High(cScrollbackChoices) do
    Result[I] := Format('%d %s', [cScrollbackChoices[I], T('ui.console.lines', 'lines')]);
end;

function CountTextLines(const AText: string): Integer;
var
  I, Last: Integer;
begin
  Last := Length(AText);
  while (Last > 0) and ((AText[Last] = #10) or (AText[Last] = #13)) do
    Dec(Last);
  if Last = 0 then
    Exit(0);
  Result := 1;
  I := 1;
  while I <= Last do
  begin
    if AText[I] = #10 then
      Inc(Result)
    else if (AText[I] = #13) and ((I = Last) or (AText[I + 1] <> #10)) then
      Inc(Result);
    Inc(I);
  end;
end;

function IsMultiLineText(const AText: string): Boolean;
begin
  Result := CountTextLines(AText) > 1;
end;

function TrimTrailingSpaces(const AText: string): string;
var
  I, N, Keep: Integer;
  Buf: TStringBuilder;
  Ch: Char;
begin
  Buf := TStringBuilder.Create;
  try
    Keep := 0; // length of Buf up to the last character that is not a space
    N := Length(AText);
    for I := 1 to N do
    begin
      Ch := AText[I];
      if (Ch = #10) or (Ch = #13) then
      begin
        Buf.Length := Keep;
        Buf.Append(Ch);
        Keep := Buf.Length;
      end
      else
      begin
        Buf.Append(Ch);
        if (Ch <> ' ') and (Ch <> #9) then
          Keep := Buf.Length;
      end;
    end;
    Buf.Length := Keep;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

initialization
  GConsoleSettings := DefaultConsoleSettings;

end.
