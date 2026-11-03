unit uLogFilter;

{ Pure helper of the line filter plugin: keeps the lines of a text that match
  (or, inverted, do not match) a pattern. No host calls, so it is covered by
  tests. }

interface

type
  TLogFilterOptions = record
    Pattern: string;
    MatchCase: Boolean;
    /// <summary>Pattern is a regular expression instead of a plain substring.</summary>
    Regex: Boolean;
    /// <summary>Keep the lines that do NOT match.</summary>
    Invert: Boolean;
    /// <summary>Prefix every kept line with its number in the original text.</summary>
    LineNumbers: Boolean;
  end;

/// <summary>The lines of AText (separated by LF or CRLF) that pass AOptions, joined
/// with CRLF; AMatched / ATotal count the kept and all lines. Empty result with
/// AError set when the pattern is empty or not a valid expression.</summary>
function FilterLines(const AText: string; const AOptions: TLogFilterOptions;
  out AMatched, ATotal: Integer; out AError: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.RegularExpressions;

function FilterLines(const AText: string; const AOptions: TLogFilterOptions;
  out AMatched, ATotal: Integer; out AError: string): string;
var
  Lines: TStringList;
  Output: TStringBuilder;
  Rx: TRegEx;
  Opts: TRegExOptions;
  I, NumW: Integer;
  Line, Needle: string;
  Hit: Boolean;
begin
  Result := '';
  AMatched := 0;
  ATotal := 0;
  AError := '';
  if AOptions.Pattern = '' then
  begin
    AError := 'empty';
    Exit;
  end;
  if AOptions.Regex then
  begin
    Opts := [roCompiled];
    if not AOptions.MatchCase then
      Include(Opts, roIgnoreCase);
    try
      Rx := TRegEx.Create(AOptions.Pattern, Opts);
    except
      on E: Exception do
      begin
        AError := E.Message;
        Exit;
      end;
    end;
  end;
  Needle := AOptions.Pattern;
  if not AOptions.MatchCase then
    Needle := LowerCase(Needle);
  Lines := TStringList.Create;
  Output := TStringBuilder.Create;
  try
    Lines.LineBreak := #10;
    Lines.StrictDelimiter := True;
    Lines.Text := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
    // A trailing line break does not add a line of its own.
    if (Lines.Count > 0) and (Lines[Lines.Count - 1] = '') then
      Lines.Delete(Lines.Count - 1);
    ATotal := Lines.Count;
    NumW := Length(IntToStr(ATotal));
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      if AOptions.Regex then
        Hit := Rx.IsMatch(Line)
      else if AOptions.MatchCase then
        Hit := Pos(Needle, Line) > 0
      else
        Hit := Pos(Needle, LowerCase(Line)) > 0;
      if Hit = AOptions.Invert then
        Continue;
      Inc(AMatched);
      if AOptions.LineNumbers then
        Output.Append(IntToStr(I + 1).PadLeft(NumW)).Append(': ');
      Output.Append(Line).Append(#13#10);
    end;
    Result := Output.ToString;
  finally
    Output.Free;
    Lines.Free;
  end;
end;

end.
