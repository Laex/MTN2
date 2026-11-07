unit uOpenWith;

{ freedesktop application entries for the "Open with" menu: reading a .desktop
  file, finding the entries a MIME type is associated with in a mimeinfo.cache
  file, and turning an Exec line into a shell command for a list of files.
  Pure text handling; the Posix shell unit reads the files. }

interface

type
  TOpenWithEntry = record
    Name: string;
    Exec: string;
    /// <summary>NoDisplay or Hidden: not offered in menus.</summary>
    Hidden: Boolean;
    /// <summary>Wants a terminal window; not launched from here.</summary>
    Terminal: Boolean;
  end;

  TOpenWithApp = record
    Name: string;
    /// <summary>Shell command line that opens the files, paths included.</summary>
    Command: string;
  end;

/// <summary>Reads the [Desktop Entry] group of a .desktop file. False when the
/// text has no application entry with a name and an Exec line.</summary>
function ParseOpenWithEntry(const AText: string; out AEntry: TOpenWithEntry): Boolean;

/// <summary>The desktop file ids a MIME type maps to in the text of a
/// mimeinfo.cache file (lines "type=a.desktop;b.desktop;").</summary>
function MimeCacheApps(const ACacheText, AMime: string): TArray<string>;

/// <summary>Quotes a word for a POSIX shell.</summary>
function ShellQuoteWord(const AText: string): string;

/// <summary>Shell command for an Exec line and the files to open: %f and %u
/// take one file, %F and %U all of them, %c is the app name, other codes drop
/// out. An application that takes one file per run is started once per file;
/// an Exec line without any file code gets the files appended. Empty when the
/// line has no program.</summary>
function OpenWithExecToCommand(const AExec, AName: string; const APaths: TArray<string>): string;

implementation

uses
  System.SysUtils, System.Classes;

function Unescape(const AValue: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AValue) do
  begin
    if (AValue[I] = '\') and (I < Length(AValue)) then
    begin
      Inc(I);
      case AValue[I] of
        's': Result := Result + ' ';
        'n': Result := Result + #10;
        't': Result := Result + #9;
        'r': Result := Result + #13;
      else
        Result := Result + AValue[I];
      end;
    end
    else
      Result := Result + AValue[I];
    Inc(I);
  end;
end;

function ParseOpenWithEntry(const AText: string; out AEntry: TOpenWithEntry): Boolean;
var
  Lines: TArray<string>;
  Line, Key, Value, EntryType: string;
  InEntry: Boolean;
  P: Integer;
begin
  AEntry := Default(TOpenWithEntry);
  EntryType := 'Application';
  InEntry := False;
  Lines := AText.Replace(#13, '').Split([#10]);
  for Line in Lines do
  begin
    if (Line = '') or (Line[1] = '#') then
      Continue;
    if Line[1] = '[' then
    begin
      // Only the main group counts; actions and other groups follow it.
      if InEntry then
        Break;
      InEntry := Line = '[Desktop Entry]';
      Continue;
    end;
    if not InEntry then
      Continue;
    P := Pos('=', Line);
    if P < 2 then
      Continue;
    Key := Trim(Copy(Line, 1, P - 1));
    Value := Trim(Copy(Line, P + 1, MaxInt));
    if Key = 'Name' then
      AEntry.Name := Unescape(Value)
    else if Key = 'Exec' then
      AEntry.Exec := Value
    else if Key = 'Type' then
      EntryType := Value
    else if (Key = 'NoDisplay') or (Key = 'Hidden') then
      AEntry.Hidden := AEntry.Hidden or SameText(Value, 'true')
    else if Key = 'Terminal' then
      AEntry.Terminal := SameText(Value, 'true');
  end;
  Result := (EntryType = 'Application') and (AEntry.Name <> '') and (AEntry.Exec <> '');
end;

function MimeCacheApps(const ACacheText, AMime: string): TArray<string>;
var
  Line, Ids, Id: string;
  Prefix: string;
  N: Integer;
begin
  SetLength(Result, 0);
  Prefix := AMime + '=';
  for Line in ACacheText.Replace(#13, '').Split([#10]) do
    if Line.StartsWith(Prefix) then
    begin
      Ids := Copy(Line, Length(Prefix) + 1, MaxInt);
      for Id in Ids.Split([';'], TStringSplitOptions.ExcludeEmpty) do
      begin
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := Id;
      end;
      Exit;
    end;
end;

function ShellQuoteWord(const AText: string): string;
begin
  Result := '''' + StringReplace(AText, '''', '''\''''', [rfReplaceAll]) + '''';
end;

// Splits an Exec value into words: double quotes group, a backslash inside
// them escapes the next character.
function SplitExec(const AExec: string): TArray<string>;
var
  I, N: Integer;
  Cur: string;
  InQuote, Have: Boolean;
  C: Char;
begin
  SetLength(Result, 0);
  Cur := '';
  InQuote := False;
  Have := False;
  I := 1;
  while I <= Length(AExec) do
  begin
    C := AExec[I];
    if InQuote then
    begin
      if (C = '\') and (I < Length(AExec)) then
      begin
        Inc(I);
        Cur := Cur + AExec[I];
      end
      else if C = '"' then
        InQuote := False
      else
        Cur := Cur + C;
    end
    else if C = '"' then
    begin
      InQuote := True;
      Have := True;
    end
    else if (C = ' ') or (C = #9) then
    begin
      if Have or (Cur <> '') then
      begin
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := Cur;
      end;
      Cur := '';
      Have := False;
    end
    else
      Cur := Cur + C;
    Inc(I);
  end;
  if Have or (Cur <> '') then
  begin
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := Cur;
  end;
end;

type
  TExecCodes = record
    OneFile: Boolean;
    AllFiles: Boolean;
  end;

// Expands one Exec word for the files at AIndex (single-file codes) or for all
// of them (list codes). A word that is only a list code becomes several words.
function ExpandWord(const AWord, AName: string; const APaths: TArray<string>;
  AIndex: Integer; var ACodes: TExecCodes): TArray<string>;
var
  I: Integer;
  Cur, One: string;
  First: string;
begin
  SetLength(Result, 0);
  if (AWord = '%F') or (AWord = '%U') then
  begin
    ACodes.AllFiles := True;
    Result := Copy(APaths);
    Exit;
  end;
  if Length(APaths) > 0 then
    First := APaths[AIndex]
  else
    First := '';
  Cur := '';
  I := 1;
  while I <= Length(AWord) do
  begin
    if (AWord[I] = '%') and (I < Length(AWord)) then
    begin
      Inc(I);
      case AWord[I] of
        '%': Cur := Cur + '%';
        'f', 'u':
          begin
            ACodes.OneFile := True;
            Cur := Cur + First;
          end;
        'F', 'U':
          begin
            ACodes.AllFiles := True;
            Cur := Cur + First;
          end;
        'c': Cur := Cur + AName;
      end;
    end
    else
      Cur := Cur + AWord[I];
    Inc(I);
  end;
  One := Cur;
  // A word that held only a dropped code (%i, %k ...) vanishes.
  if (One = '') and (AWord <> '') and (AWord[1] = '%') then
    Exit;
  SetLength(Result, 1);
  Result[0] := One;
end;

function JoinQuoted(const AWords: TArray<string>): string;
var
  W: string;
begin
  Result := '';
  for W in AWords do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + ShellQuoteWord(W);
  end;
end;

function OpenWithExecToCommand(const AExec, AName: string; const APaths: TArray<string>): string;
var
  Words, Expanded, All: TArray<string>;
  Codes, Probe: TExecCodes;
  Run: string;
  W: string;
  I, N: Integer;
  Idx: Integer;
begin
  Result := '';
  Words := SplitExec(AExec);
  if (Length(Words) = 0) or (Words[0] = '') then
    Exit;
  // First pass: which file codes the line has.
  Probe := Default(TExecCodes);
  for W in Words do
    ExpandWord(W, AName, APaths, 0, Probe);
  if Probe.OneFile and not Probe.AllFiles then
  begin
    // One file per run: one command per file.
    for Idx := 0 to Length(APaths) - 1 do
    begin
      Codes := Default(TExecCodes);
      All := nil;
      for W in Words do
      begin
        Expanded := ExpandWord(W, AName, APaths, Idx, Codes);
        N := Length(All);
        SetLength(All, N + Length(Expanded));
        for I := 0 to High(Expanded) do
          All[N + I] := Expanded[I];
      end;
      Run := JoinQuoted(All);
      if Result <> '' then
        Result := Result + ' ; ';
      Result := Result + Run;
    end;
    if Length(APaths) > 1 then
      Result := '( ' + Result + ' )';
    Exit;
  end;
  Codes := Default(TExecCodes);
  All := nil;
  for W in Words do
  begin
    Expanded := ExpandWord(W, AName, APaths, 0, Codes);
    N := Length(All);
    SetLength(All, N + Length(Expanded));
    for I := 0 to High(Expanded) do
      All[N + I] := Expanded[I];
  end;
  if not (Codes.OneFile or Codes.AllFiles) then
  begin
    N := Length(All);
    SetLength(All, N + Length(APaths));
    for I := 0 to High(APaths) do
      All[N + I] := APaths[I];
  end;
  Result := JoinQuoted(All);
end;

end.
