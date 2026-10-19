unit uPluginHighlight;

{ Syntax coloring by plugins. A plugin registers a highlighter for file name
  extensions; the viewer and the editor ask it for the colored spans of every line they
  draw and recolor the text cells of those spans. The plugin only names a class of text
  (comment, string, keyword, ...): the colors are the program's and follow the theme.

  Spans of a line are cached by the text of the line, so a line that is drawn again (every
  repaint) does not call the plugin again. Main thread only.

  A stateful highlighter also gets the state the previous line ended in (0 at the start of
  the file) and returns the state its own line ends in, so a block comment or a multi-line
  string colors the lines that follow. A state is an opaque integer of the plugin.
  THighlightTracker keeps the state at the start of every line of one document. }

interface

uses
  System.SysUtils, System.UITypes, System.Generics.Collections;

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
  /// <summary>Colors one line that starts in state AStateIn and returns the state the line ends
  /// in. AStateOut = -1 with False: the plugin does not know AStateIn any more.</summary>
  THighlightStep = reference to function(const ALine: string; AStateIn: Integer;
    out ASpans: THighlightSpans; out AStateOut: Integer): Boolean;

  /// <summary>The state at the start of each line of a document, filled on demand from the
  /// top. A line edit drops the states after it (InvalidateFrom); Reach continues from the last
  /// known state within a time budget, so a jump to the end of a big file is spread over
  /// several repaints.</summary>
  THighlightTracker = class
  strict private
    FId: Integer;
    FStates: TList<Integer>;
  public
    constructor Create(AId: Integer);
    destructor Destroy; override;
    property Id: Integer read FId;
    /// <summary>The line ALine and the lines after it changed.</summary>
    procedure InvalidateFrom(ALine: Integer);
    /// <summary>True when the state at the start of ATarget is known; works for at most
    /// ABudgetMs milliseconds getting there.</summary>
    function Reach(ATarget: Integer; const AGetLine: TFunc<Integer, string>; ABudgetMs: Integer): Boolean;
    function StateAt(ALine: Integer): Integer;
  end;

/// <summary>Registers a highlighter that carries a state from line to line. A plugin may register
/// several (one per language); a second one for the same extensions replaces the first.</summary>
procedure RegisterStatefulHighlighter(const APluginId, AExtensions: string; const AStep: THighlightStep);
/// <summary>The highlighter that serves the file name AFileName (its extension, or its whole name
/// such as "Makefile"), 0 when none.</summary>
function HighlighterForFile(const AFileName: string): Integer;
function HighlighterIsStateful(AId: Integer): Boolean;
/// <summary>The spans of ALine, which starts in state AStateIn, and the state it ends in (cached).
/// False when the line stays plain; AStateOut is still the state to go on with, or -1 when
/// AStateIn is not known to the plugin.</summary>
function HighlightLineState(AId: Integer; const ALine: string; AStateIn: Integer;
  out ASpans: THighlightSpans; out AStateOut: Integer): Boolean;
/// <summary>Forgets the cached answers of a highlighter.</summary>
procedure ResetHighlighterCache(AId: Integer);

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
  System.Classes, System.Diagnostics, uStrings;

type
  TStepResult = record
    Spans: THighlightSpans;
    StateOut: Integer;
    Ok: Boolean;
  end;

  THighlighterEntry = record
    Id: Integer;
    PluginId: string;
    Extensions: TArray<string>;
    Provider: THighlightProvider;
    Step: THighlightStep;
    Cache: TDictionary<string, THighlightSpans>;
    StepCache: TDictionary<string, TStepResult>;
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
  GEntries[AIndex].StepCache.Free;
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
    if (GEntries[I].PluginId = Id) and not Assigned(GEntries[I].Step) then
      DropEntry(I);
  Inc(GNextId);
  E.Id := GNextId;
  E.PluginId := Id;
  E.Provider := AProvider;
  E.Step := nil;
  E.Cache := TDictionary<string, THighlightSpans>.Create;
  E.StepCache := TDictionary<string, TStepResult>.Create;
  GEntries.Add(E);
end;

procedure RegisterStatefulHighlighter(const APluginId, AExtensions: string; const AStep: THighlightStep);
var
  E: THighlighterEntry;
  I: Integer;
  Id, Key: string;
begin
  Id := LowerCase(Trim(APluginId));
  if (Id = '') or not Assigned(AStep) then
    Exit;
  E.Extensions := SplitExtensions(AExtensions);
  if Length(E.Extensions) = 0 then
    Exit;
  Key := string.Join(' ', E.Extensions);
  for I := GEntries.Count - 1 downto 0 do
    if (GEntries[I].PluginId = Id) and Assigned(GEntries[I].Step) and
       (string.Join(' ', GEntries[I].Extensions) = Key) then
      DropEntry(I);
  Inc(GNextId);
  E.Id := GNextId;
  E.PluginId := Id;
  E.Provider := nil;
  E.Step := AStep;
  E.Cache := TDictionary<string, THighlightSpans>.Create;
  E.StepCache := TDictionary<string, TStepResult>.Create;
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

function HighlighterForFile(const AFileName: string): Integer;
var
  E: THighlighterEntry;
  X, Ext, Name: string;
begin
  Result := 0;
  if (AFileName = '') or (GEntries.Count = 0) then
    Exit;
  Ext := LowerCase(ExtractFileExt(AFileName));
  Name := LowerCase(ExtractFileName(AFileName));
  for E in GEntries do
    for X in E.Extensions do
      if ((Ext <> '') and (X = Ext)) or (Name = Copy(X, 2, MaxInt)) then
        Exit(E.Id);
end;

function HighlighterIsStateful(AId: Integer): Boolean;
var
  E: THighlighterEntry;
begin
  Result := False;
  if AId = 0 then
    Exit;
  for E in GEntries do
    if E.Id = AId then
      Exit(Assigned(E.Step));
end;

procedure ResetHighlighterCache(AId: Integer);
var
  E: THighlighterEntry;
begin
  for E in GEntries do
    if E.Id = AId then
    begin
      E.Cache.Clear;
      E.StepCache.Clear;
      Exit;
    end;
end;

function HighlightLineState(AId: Integer; const ALine: string; AStateIn: Integer;
  out ASpans: THighlightSpans; out AStateOut: Integer): Boolean;
var
  I: Integer;
  E: THighlighterEntry;
  R: TStepResult;
  Key: string;
begin
  ASpans := nil;
  AStateOut := AStateIn;
  Result := False;
  if AId = 0 then
    Exit;
  for I := 0 to GEntries.Count - 1 do
    if GEntries[I].Id = AId then
    begin
      E := GEntries[I];
      if not Assigned(E.Step) then
        Exit;
      Key := IntToStr(AStateIn) + #1 + ALine;
      if not E.StepCache.TryGetValue(Key, R) then
      begin
        R := Default(TStepResult);
        R.StateOut := AStateIn;
        try
          R.Ok := E.Step(ALine, AStateIn, R.Spans, R.StateOut);
        except
          // A faulty plugin highlighter leaves the line plain.
          R.Ok := False;
          R.Spans := nil;
          R.StateOut := AStateIn;
        end;
        if R.StateOut < 0 then
        begin
          // The plugin lost the state: nothing cached under it is worth keeping.
          E.StepCache.Clear;
          AStateOut := -1;
          Exit;
        end;
        if E.StepCache.Count >= cCacheLimit then
          E.StepCache.Clear;
        E.StepCache.Add(Key, R);
      end;
      AStateOut := R.StateOut;
      ASpans := R.Spans;
      Exit(R.Ok and (Length(R.Spans) > 0));
    end;
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
      if Assigned(E.Step) then
        Exit;
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

{ THighlightTracker }

constructor THighlightTracker.Create(AId: Integer);
begin
  inherited Create;
  FId := AId;
  FStates := TList<Integer>.Create;
  FStates.Add(0);
end;

destructor THighlightTracker.Destroy;
begin
  FStates.Free;
  inherited;
end;

procedure THighlightTracker.InvalidateFrom(ALine: Integer);
begin
  if ALine < 0 then
    ALine := 0;
  if ALine + 1 < FStates.Count then
    FStates.DeleteRange(ALine + 1, FStates.Count - ALine - 1);
end;

function THighlightTracker.StateAt(ALine: Integer): Integer;
begin
  if (ALine >= 0) and (ALine < FStates.Count) then
    Result := FStates[ALine]
  else
    Result := 0;
end;

function THighlightTracker.Reach(ATarget: Integer; const AGetLine: TFunc<Integer, string>;
  ABudgetMs: Integer): Boolean;
var
  Watch: TStopwatch;
  Spans: THighlightSpans;
  Cur, Next, N: Integer;
begin
  if ATarget < 0 then
    Exit(False);
  if ATarget < FStates.Count then
    Exit(True);
  Watch := TStopwatch.StartNew;
  N := 0;
  while FStates.Count <= ATarget do
  begin
    Cur := FStates.Count - 1;
    HighlightLineState(FId, AGetLine(Cur), FStates[Cur], Spans, Next);
    if Next < 0 then
    begin
      // The plugin forgot its states; start over from the top of the file.
      FStates.Clear;
      FStates.Add(0);
      Exit(ATarget = 0);
    end;
    FStates.Add(Next);
    Inc(N);
    if ((N and 15) = 0) and (Watch.ElapsedMilliseconds >= ABudgetMs) then
      Break;
  end;
  Result := ATarget < FStates.Count;
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
  Stateful: TArray<string>;
begin
  Result := [];
  Id := LowerCase(Trim(APluginId));
  Stateful := [];
  for E in GEntries do
    if E.PluginId <> Id then
      Continue
    else if Assigned(E.Step) then
      Stateful := Stateful + E.Extensions
    else
      Result := Result + [Format(T('ui.plugininfo.highlight', 'Colors the text of files: %s'),
        [string.Join(' ', E.Extensions)])];
  // The languages of one plugin are listed together.
  if Length(Stateful) > 0 then
    Result := Result + [Format(T('ui.plugininfo.highlight', 'Colors the text of files: %s'),
      [string.Join(' ', Stateful)])];
end;

initialization
  GEntries := TList<THighlighterEntry>.Create;

finalization
  while GEntries.Count > 0 do
    DropEntry(GEntries.Count - 1);
  FreeAndNil(GEntries);

end.
