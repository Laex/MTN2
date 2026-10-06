unit uPluginHighlight;

{ Syntax coloring by plugins. A plugin registers a highlighter for file name
  extensions; the viewer and the editor ask it for the colored spans of every line they
  draw and recolor the text cells of those spans. The plugin only names a class of text
  (comment, string, keyword, ...): the colors are the program's and follow the theme.

  Spans of a line are cached by the text of the line, so a line that is drawn again (every
  repaint) does not call the plugin again. Main thread only. }

interface

uses
  System.SysUtils, System.UITypes;

const
  cHighlightPlain = 0;
  cHighlightComment = 1;
  cHighlightString = 2;
  cHighlightNumber = 3;
  cHighlightKeyword = 4;
  cHighlightType = 5;
  cHighlightFunction = 6;
  cHighlightOperator = 7;
  cHighlightPreprocessor = 8;
  cHighlightConstant = 9;
  cHighlightKey = 10;
  cHighlightError = 11;
  cHighlightClassCount = 12;

type
  /// <summary>A colored part of a line: Start (0-based) and Len in characters, Kind one of
  /// the cHighlight* classes.</summary>
  THighlightSpan = record
    Start, Len, Kind: Integer;
  end;
  THighlightSpans = TArray<THighlightSpan>;

  /// <summary>Colors one line; False (or no spans) = leave it plain.</summary>
  THighlightProvider = reference to function(const ALine: string; out ASpans: THighlightSpans): Boolean;

/// <summary>Registers AProvider for the extensions in AExtensions (comma or semicolon
/// separated, ".json;.ini"). A plugin's second registration replaces its first.</summary>
procedure RegisterHighlighter(const APluginId, AExtensions: string; const AProvider: THighlightProvider);
procedure UnregisterHighlighter(const APluginId: string);
/// <summary>The highlighter that serves AExtension (".json"), 0 when none; an id for HighlightLine.</summary>
function HighlighterFor(const AExtension: string): Integer;
/// <summary>The spans of ALine from highlighter AId (cached). False when it colors nothing here.</summary>
function HighlightLine(AId: Integer; const ALine: string; out ASpans: THighlightSpans): Boolean;
/// <summary>Color of a class on a body background of ABodyBg (dark and light themes differ).</summary>
function HighlightColor(AKind: Integer; ABodyBg: TAlphaColor): TAlphaColor;
/// <summary>One line per highlighter of the plugin, for the plugin's information dialog.</summary>
function DescribeHighlighters(const APluginId: string): TArray<string>;

implementation

uses
  System.Classes, System.Generics.Collections, uStrings;

type
  THighlighterEntry = record
    Id: Integer;
    PluginId: string;
    Extensions: TArray<string>;
    Provider: THighlightProvider;
    Cache: TDictionary<string, THighlightSpans>;
  end;

const
  cCacheLimit = 4000;

var
  GEntries: TList<THighlighterEntry>;
  GNextId: Integer = 0;

function SplitExtensions(const AExtensions: string): TArray<string>;
var
  Part, E: string;
begin
  Result := [];
  for Part in AExtensions.Split([',', ';']) do
  begin
    E := LowerCase(Trim(Part));
    if E = '' then
      Continue;
    if E[1] <> '.' then
      E := '.' + E;
    Result := Result + [E];
  end;
end;

procedure DropEntry(AIndex: Integer);
begin
  GEntries[AIndex].Cache.Free;
  GEntries.Delete(AIndex);
end;

procedure RegisterHighlighter(const APluginId, AExtensions: string; const AProvider: THighlightProvider);
var
  E: THighlighterEntry;
  I: Integer;
  Id: string;
begin
  Id := LowerCase(Trim(APluginId));
  if (Id = '') or not Assigned(AProvider) then
    Exit;
  E.Extensions := SplitExtensions(AExtensions);
  if Length(E.Extensions) = 0 then
    Exit;
  for I := GEntries.Count - 1 downto 0 do
    if GEntries[I].PluginId = Id then
      DropEntry(I);
  Inc(GNextId);
  E.Id := GNextId;
  E.PluginId := Id;
  E.Provider := AProvider;
  E.Cache := TDictionary<string, THighlightSpans>.Create;
  GEntries.Add(E);
end;

procedure UnregisterHighlighter(const APluginId: string);
var
  I: Integer;
  Id: string;
begin
  Id := LowerCase(Trim(APluginId));
  for I := GEntries.Count - 1 downto 0 do
    if GEntries[I].PluginId = Id then
      DropEntry(I);
end;

function HighlighterFor(const AExtension: string): Integer;
var
  E: THighlighterEntry;
  X, Ext: string;
begin
  Result := 0;
  Ext := LowerCase(AExtension);
  if (Ext = '') or (GEntries.Count = 0) then
    Exit;
  for E in GEntries do
    for X in E.Extensions do
      if X = Ext then
        Exit(E.Id);
end;

function HighlightLine(AId: Integer; const ALine: string; out ASpans: THighlightSpans): Boolean;
var
  I: Integer;
  E: THighlighterEntry;
begin
  ASpans := nil;
  Result := False;
  if (AId = 0) or (ALine = '') then
    Exit;
  for I := 0 to GEntries.Count - 1 do
    if GEntries[I].Id = AId then
    begin
      E := GEntries[I];
      if not E.Cache.TryGetValue(ALine, ASpans) then
      begin
        ASpans := nil;
        try
          if not E.Provider(ALine, ASpans) then
            ASpans := nil;
        except
          // A faulty plugin highlighter leaves the line plain.
          ASpans := nil;
        end;
        if E.Cache.Count >= cCacheLimit then
          E.Cache.Clear;
        E.Cache.Add(ALine, ASpans);
      end;
      Exit(Length(ASpans) > 0);
    end;
end;

function Luminance(AColor: TAlphaColor): Integer;
begin
  Result := (Integer(TAlphaColorRec(AColor).R) * 299 + Integer(TAlphaColorRec(AColor).G) * 587 +
    Integer(TAlphaColorRec(AColor).B) * 114) div 1000;
end;

function HighlightColor(AKind: Integer; ABodyBg: TAlphaColor): TAlphaColor;
const
  cDark: array[0..cHighlightClassCount - 1] of TAlphaColor = (
    $FFD4D4D4, $FF6A9955, $FFCE9178, $FFB5CEA8, $FF569CD6, $FF4EC9B0, $FFDCDCAA, $FFD4D4D4,
    $FFC586C0, $FF4FC1FF, $FF9CDCFE, $FFF44747);
  cLight: array[0..cHighlightClassCount - 1] of TAlphaColor = (
    $FF000000, $FF008000, $FFA31515, $FF098658, $FF0000FF, $FF267F99, $FF795E26, $FF000000,
    $FFAF00DB, $FF0070C1, $FF001080, $FFE51400);
begin
  if (AKind < 0) or (AKind >= cHighlightClassCount) then
    AKind := 0;
  if Luminance(ABodyBg) < 128 then
    Result := cDark[AKind]
  else
    Result := cLight[AKind];
end;

function DescribeHighlighters(const APluginId: string): TArray<string>;
var
  E: THighlighterEntry;
  Id: string;
begin
  Result := [];
  Id := LowerCase(Trim(APluginId));
  for E in GEntries do
    if E.PluginId = Id then
      Result := Result + [Format(T('ui.plugininfo.highlight', 'Colors the text of files: %s'),
        [string.Join(' ', E.Extensions)])];
end;

initialization
  GEntries := TList<THighlighterEntry>.Create;

finalization
  while GEntries.Count > 0 do
    DropEntry(GEntries.Count - 1);
  FreeAndNil(GEntries);

end.
