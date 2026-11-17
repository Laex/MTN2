unit uRipgrepFormat;

{ Pure helpers of the ripgrep plugin: the argument list of an rg run for a search.files
  request, and the reading of the JSON lines rg prints (rg --json). }

interface

uses
  uSearchRequest, uSearchHitsJson;

/// <summary>The arguments of rg for the request, without the program name. The text and the
/// root are separate arguments, never part of a command line string. One match per file is
/// asked for: a hit stands for a file.</summary>
function BuildRgArguments(const ARequest: TSearchRequest): TArray<string>;

/// <summary>One line of rg --json output. False when the line is not a match event (a begin,
/// end or summary event, an error line, or a path rg could not give as text).</summary>
function TryParseRgMatch(const ALine: string; out AHit: TSearchHit): Boolean;

/// <summary>Reads the whole output of an rg --json run: the files that matched, in order.
/// Lines that are not JSON (messages of the program) are skipped.</summary>
function ParseRgOutput(const AOutput: string): TArray<TSearchHit>;

implementation

uses
  System.SysUtils, System.Classes, System.JSON;

const
  cSnippetMax = 200;

function BuildRgArguments(const ARequest: TSearchRequest): TArray<string>;
var
  List: TArray<string>;
  Mask: string;

  procedure Add(const AArg: string);
  begin
    SetLength(List, Length(List) + 1);
    List[High(List)] := AArg;
  end;

begin
  SetLength(List, 0);
  Add('--json');
  Add('--no-config');
  Add('--no-messages');
  // The built-in walk reads every file the masks allow; ignore files are not honored.
  Add('--no-ignore');
  Add('--max-count=1');
  Add('--glob-case-insensitive');
  if ARequest.Hidden then
    Add('--hidden');
  if ARequest.CaseSensitive then
    Add('--case-sensitive')
  else
    Add('--ignore-case');
  if ARequest.WholeWords then
    Add('--word-regexp');
  if not ARequest.Regex then
    Add('--fixed-strings');
  if ARequest.Encoding <> '' then
    Add('--encoding=' + ARequest.Encoding);
  // A file list was already cut by the mask and the depth; rg reads exactly those files.
  if Length(ARequest.Files) = 0 then
  begin
    if not ARequest.Subdirs then
      Add('--max-depth=1');
    for Mask in SplitSearchMasks(ARequest.Mask) do
    begin
      // *.* and * are every name, as in the built-in walk, and leave no glob at all.
      if (Mask = '*.*') or (Mask = '*') then
        Continue;
      Add('--glob=' + Mask);
    end;
  end;
  Add('--regexp=' + ARequest.Text);
  Add('--');
  if Length(ARequest.Files) = 0 then
    Add(ARequest.Root)
  else
    for Mask in ARequest.Files do
      Add(Mask);
  Result := List;
end;

function ObjText(AValue: TJSONValue; const AName: string; out AText: string): Boolean;
var
  Member: TJSONValue;
begin
  Result := False;
  if not (AValue is TJSONObject) then
    Exit;
  Member := TJSONObject(AValue).GetValue(AName);
  if Member is TJSONObject then
    Result := TJSONObject(Member).TryGetValue<string>('text', AText);
end;

function TryParseRgMatch(const ALine: string; out AHit: TSearchHit): Boolean;
var
  Root, Data: TJSONValue;
  Kind, Path, Lines: string;
  Num: Int64;
  V: TJSONValue;
begin
  Result := False;
  AHit := NewSearchHit('', False);
  if (ALine = '') or (ALine[1] <> '{') then
    Exit;
  Root := TJSONObject.ParseJSONValue(ALine);
  try
    if not (Root is TJSONObject) then
      Exit;
    if not TJSONObject(Root).TryGetValue<string>('type', Kind) or (Kind <> 'match') then
      Exit;
    Data := TJSONObject(Root).GetValue('data');
    if not ObjText(Data, 'path', Path) or (Path = '') then
      Exit;
    AHit.Path := Path;
    V := TJSONObject(Data).GetValue('line_number');
    if (V is TJSONNumber) and TryStrToInt64(TJSONNumber(V).Value, Num) and (Num > 0) then
      AHit.Line := Integer(Num);
    if ObjText(Data, 'lines', Lines) then
    begin
      Lines := Trim(Lines);
      if Length(Lines) > cSnippetMax then
        Lines := Copy(Lines, 1, cSnippetMax);
      AHit.Snippet := Lines;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function ParseRgOutput(const AOutput: string): TArray<TSearchHit>;
var
  Lines: TStringList;
  Hit: TSearchHit;
  I: Integer;
begin
  SetLength(Result, 0);
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for I := 0 to Lines.Count - 1 do
      if TryParseRgMatch(Lines[I], Hit) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Hit;
      end;
  finally
    Lines.Free;
  end;
end;

end.
