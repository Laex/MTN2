unit uCommandPalette;

{ Search over the commands of the top menu. The entries are the live menu
  (built-in items and plugin items alike); the search text is matched against
  the caption, the category title and the aliases that the string tables give
  to an item as 'menu.alias.<action name>' (comma separated words in any
  language, so a command is found by the name another program or another
  language gives it). Only the commands that can run now are listed. }

interface

uses
  System.SysUtils, System.Generics.Collections, uTopMenuBar;

type
  TPaletteEntry = record
    Title: string;
    Category: string;
    Shortcut: string;
    Aliases: string;
    /// <summary>Stable id of the command, the same in every locale; the list
    /// of recent commands is keyed by it.</summary>
    Key: string;
    Item: TSubmenuItem;
  end;

const
  cPaletteRecentMax = 8;

/// <summary>The commands of AMenu that can run now, in menu order.</summary>
function BuildPaletteEntries(AMenu: TTopMenuController): TArray<TPaletteEntry>;

/// <summary>Quality of the match of AQuery with the entry, lower is better;
/// -1 when it does not match. Every word of the query must match: the start
/// of a word of the caption is best, then the inside of the caption, the
/// initials of the caption's words, an alias, the category.</summary>
function PaletteMatchScore(const AQuery: string; const AEntry: TPaletteEntry): Integer;

/// <summary>Indexes into AEntries that match AQuery, best first. Ties go to
/// the commands run recently, then to the menu order. With an empty query:
/// the recent commands, then all the others in menu order.</summary>
function PaletteRank(const AEntries: TArray<TPaletteEntry>;
  const AQuery: string): TArray<Integer>;

/// <summary>One list row: caption, category and keys in columns that fill
/// AWidth cells.</summary>
function PaletteRowText(const AEntry: TPaletteEntry; AWidth: Integer): string;

/// <summary>Remembers that the command was run from the palette.</summary>
procedure PaletteNoteRun(const AKey: string);
procedure PaletteForgetRecent;

implementation

uses
  System.Classes, System.JSON, System.Generics.Defaults, System.TypInfo,
  uStrings, uCharWidth, uResourceAccess;

const
  cResMenuAliases = 'MENU_ALIASES';

var
  GRecent: TArray<string>; // newest first
  GAliases: TDictionary<string, string>;

// The search words of the commands, from the embedded config\menualiases.json:
// action name -> comma separated words.
function AliasTable: TDictionary<string, string>;
var
  RS: TStream;
  Bytes: TBytes;
  Root: TJSONValue;
  Pair: TJSONPair;
begin
  if GAliases <> nil then
    Exit(GAliases);
  GAliases := TDictionary<string, string>.Create;
  Result := GAliases;
  RS := OpenRcData(cResMenuAliases);
  if RS = nil then
    Exit;
  try
    SetLength(Bytes, RS.Size);
    if RS.Size > 0 then
      RS.ReadBuffer(Bytes[0], RS.Size);
  finally
    RS.Free;
  end;
  Root := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Bytes));
  try
    if Root is TJSONObject then
      for Pair in TJSONObject(Root) do
        if (Pair.JsonValue is TJSONString) and not Pair.JsonString.Value.StartsWith('//') then
          GAliases.AddOrSetValue(Pair.JsonString.Value, Pair.JsonValue.Value);
  finally
    Root.Free;
  end;
end;

function AliasesOf(const AKey: string): string;
var
  Own: string;
begin
  if not AliasTable.TryGetValue(AKey, Result) then
    Result := '';
  // a locale file can add words of its own
  Own := T('menu.alias.' + AKey, '');
  if Own <> '' then
    Result := Result + ', ' + Own;
end;

function CleanTitle(const ACaption: string): string;
begin
  Result := StringReplace(ACaption, '&', '', [rfReplaceAll]);
end;

function ItemKey(const AItem: TSubmenuItem): string;
begin
  if AItem.IsPluginItem then
    Result := 'plugin:' + AItem.PluginId + ':' + AItem.Caption
  else
    Result := GetEnumName(TypeInfo(TTopMenuAction), Ord(AItem.Action));
end;

function BuildPaletteEntries(AMenu: TTopMenuController): TArray<TPaletteEntry>;
var
  List: TList<TPaletteEntry>;
begin
  List := TList<TPaletteEntry>.Create;
  try
    AMenu.ListItems(
      procedure(ACategory: string; AItem: TSubmenuItem)
      var
        E: TPaletteEntry;
      begin
        if (AItem.Action = tmaNone) and not Assigned(AItem.PluginOnClick) then
          Exit;
        if not AMenu.CanRunItem(AItem) then
          Exit;
        E.Item := AItem;
        E.Title := CleanTitle(AItem.Caption);
        if ACategory = #$2261 then // the system menu has no name worth showing
          E.Category := ''
        else
          E.Category := ACategory;
        E.Shortcut := TopMenuItemShortcut(AItem);
        E.Key := ItemKey(AItem);
        if AItem.IsPluginItem then
          E.Aliases := ''
        else
          E.Aliases := AliasesOf(E.Key);
        List.Add(E);
      end);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function Fold(const S: string): string;
begin
  Result := AnsiLowerCase(S);
  Result := StringReplace(Result, #$0451, #$0435, [rfReplaceAll]); // yo -> ye
end;

function SplitWords(const S: string): TArray<string>;
var
  I, Start: Integer;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    Start := 0;
    for I := 1 to Length(S) + 1 do
      if (I > Length(S)) or CharInSet(S[I], [' ', ',', ';', '/', '-', '.', #9]) then
      begin
        if Start > 0 then
          List.Add(Copy(S, Start, I - Start));
        Start := 0;
      end
      else if Start = 0 then
        Start := I;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function WordScore(const AWord: string; const AEntry: TPaletteEntry): Integer;
var
  TitleF, Initials: string;
  TitleWords, AliasWords: TArray<string>;
  W: string;
  Best: Integer;
begin
  Best := -1;
  TitleF := Fold(AEntry.Title);
  TitleWords := SplitWords(TitleF);
  if Pos(AWord, TitleF) = 1 then
    Exit(0);
  for W in TitleWords do
    if Pos(AWord, W) = 1 then
      Exit(1);
  if Pos(AWord, TitleF) > 0 then
    Best := 2;
  if (Best < 0) and (Length(AWord) >= 2) then
  begin
    Initials := '';
    for W in TitleWords do
      Initials := Initials + W[1];
    if Pos(AWord, Initials) = 1 then
      Best := 2;
  end;
  if Best >= 0 then
    Exit(Best);
  AliasWords := SplitWords(Fold(AEntry.Aliases));
  for W in AliasWords do
    if Pos(AWord, W) = 1 then
      Exit(3);
  if Pos(AWord, Fold(AEntry.Aliases)) > 0 then
    Exit(4);
  if Pos(AWord, Fold(AEntry.Category)) > 0 then
    Exit(5);
  Result := -1;
end;

function PaletteMatchScore(const AQuery: string; const AEntry: TPaletteEntry): Integer;
var
  Words: TArray<string>;
  W: string;
  S: Integer;
begin
  Words := SplitWords(Fold(AQuery));
  if Length(Words) = 0 then
    Exit(0);
  Result := 0;
  for W in Words do
  begin
    S := WordScore(W, AEntry);
    if S < 0 then
      Exit(-1);
    Inc(Result, S);
  end;
end;

function RecentRank(const AKey: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(GRecent) do
    if GRecent[I] = AKey then
      Exit(I);
  Result := MaxInt;
end;

function PaletteRank(const AEntries: TArray<TPaletteEntry>;
  const AQuery: string): TArray<Integer>;
var
  Scores, Recents: TArray<Integer>;
  List: TList<Integer>;
  I, S: Integer;
  Empty: Boolean;
begin
  Empty := Length(SplitWords(AQuery)) = 0;
  SetLength(Scores, Length(AEntries));
  SetLength(Recents, Length(AEntries));
  List := TList<Integer>.Create;
  try
    for I := 0 to High(AEntries) do
    begin
      S := PaletteMatchScore(AQuery, AEntries[I]);
      if S < 0 then
        Continue;
      Scores[I] := S;
      Recents[I] := RecentRank(AEntries[I].Key);
      List.Add(I);
    end;
    List.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        if Empty then
          Result := Recents[A] - Recents[B]
        else
        begin
          Result := Scores[A] - Scores[B];
          if Result = 0 then
            Result := Recents[A] - Recents[B];
        end;
        if Result = 0 then
          Result := A - B;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function FitCells(const S: string; AWidth: Integer): string;
var
  I, W, CW: Integer;
begin
  Result := '';
  W := 0;
  for I := 1 to Length(S) do
  begin
    CW := CharDisplayWidth(S[I]);
    if W + CW > AWidth then
      Break;
    Result := Result + S[I];
    Inc(W, CW);
  end;
  Result := Result + StringOfChar(' ', AWidth - W);
end;

function PaletteRowText(const AEntry: TPaletteEntry; AWidth: Integer): string;
const
  cShortcutW = 14;
  cCategoryW = 12;
var
  TitleW: Integer;
begin
  TitleW := AWidth - cShortcutW - cCategoryW - 2;
  if TitleW < 8 then
    TitleW := 8;
  Result := FitCells(AEntry.Title, TitleW) + ' ' +
    FitCells(AEntry.Category, cCategoryW) + ' ' +
    FitCells(AEntry.Shortcut, cShortcutW);
end;

procedure PaletteNoteRun(const AKey: string);
var
  List: TList<string>;
  I: Integer;
begin
  if AKey = '' then
    Exit;
  List := TList<string>.Create;
  try
    List.Add(AKey);
    for I := 0 to High(GRecent) do
      if (GRecent[I] <> AKey) and (List.Count < cPaletteRecentMax) then
        List.Add(GRecent[I]);
    GRecent := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure PaletteForgetRecent;
begin
  GRecent := nil;
end;

initialization

finalization
  FreeAndNil(GAliases);

end.
