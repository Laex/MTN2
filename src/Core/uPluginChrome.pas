unit uPluginChrome;

{ Text a plugin shows in the host's status line. A plugin sets a named segment
  (a short string: a counter, a mode, a connection state); the status line of
  the file panels appends the segments of all loaded plugins after its own,
  in the order they were first set. An empty text removes the segment.

  A plugin never draws: the host puts the text into the status line through
  the theme, so colors and layout stay the theme's. When a segment changes the
  host is told through SetPluginChromeChanged and repaints. Main thread only. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections;

type
  IPluginChrome = interface
    ['{9B4E6C21-8D5F-4A37-B1C2-3E7A5F9D0B64}']
    /// <summary>Sets (or, with an empty text, removes) the segment ASegmentId
    /// of APluginId. The text is shortened to a status-line sized string.</summary>
    procedure SetStatusSegment(const APluginId, ASegmentId, AText: string);
    /// <summary>The texts to append to the status line, in first-set order.</summary>
    function StatusSegments: TArray<string>;
    /// <summary>Sets the function-bar labels a plugin wants while a panel shows a
    /// folder of AScheme. AJson: {"root": {"F7": "NewCn"}, "inside": {...}}, where
    /// "root" applies to the scheme's own root (scheme:///) and "inside" to every
    /// other folder; keys are F1..F10 with optional Shift+/Ctrl+/Alt+ prefixes,
    /// values the label shown in the slot ('' = an empty slot). Empty AJson removes
    /// the labels of that scheme.</summary>
    procedure SetSchemeFBar(const APluginId, AScheme, AJson: string);
    /// <summary>The label for the F-key AKey (vkF1..vkF10) with AShift held while
    /// the panel is at AUri; False when no plugin labels it.</summary>
    function TryGetSchemeFBarLabel(const AUri: string; AKey: Word; AShift: TShiftState;
      out ALabel: string): Boolean;
    /// <summary>Removes every segment of APluginId.</summary>
    /// <summary>One line per thing the plugin registered, for the plugin's information
    /// dialog (already in the user's language).</summary>
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
  end;

function PluginChrome: IPluginChrome;

/// <summary>Called (on the main thread) after a segment was set, changed or
/// removed. nil clears the handler.</summary>
procedure SetPluginChromeChanged(const AHandler: TProc);

/// <summary>Tells the host that something plugins contribute to the panel
/// chrome (status segments, Change Drive items) changed. Main thread only.</summary>
procedure NotifyPluginChromeChanged;

implementation

uses
  System.JSON, uStrings, uVfsTypes;

const
  cMaxSegmentChars = 40;

type
  TSegment = record
    PluginId: string;
    SegmentId: string;
    Text: string;
  end;

  TFBarLabel = record
    PluginId: string;
    Scheme: string;
    Root: Boolean;
    Key: Word;
    Mods: TShiftState;
    Text: string;
  end;

  TPluginChrome = class(TInterfacedObject, IPluginChrome)
  private
    FSegments: TList<TSegment>;
    FFBar: TList<TFBarLabel>;
    function IndexOf(const APluginId, ASegmentId: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetStatusSegment(const APluginId, ASegmentId, AText: string);
    function StatusSegments: TArray<string>;
    procedure SetSchemeFBar(const APluginId, AScheme, AJson: string);
    function TryGetSchemeFBarLabel(const AUri: string; AKey: Word; AShift: TShiftState;
      out ALabel: string): Boolean;
    function DescribePlugin(const APluginId: string): TArray<string>;
    procedure UnregisterPlugin(const APluginId: string);
  end;

var
  GChrome: IPluginChrome;
  GChanged: TProc;

procedure NotifyChanged;
begin
  if Assigned(GChanged) then
    GChanged();
end;

constructor TPluginChrome.Create;
begin
  inherited Create;
  FSegments := TList<TSegment>.Create;
  FFBar := TList<TFBarLabel>.Create;
end;

destructor TPluginChrome.Destroy;
begin
  FFBar.Free;
  FSegments.Free;
  inherited Destroy;
end;

function TPluginChrome.IndexOf(const APluginId, ASegmentId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FSegments.Count - 1 do
    if SameText(FSegments[I].PluginId, APluginId) and
       SameText(FSegments[I].SegmentId, ASegmentId) then
      Exit(I);
  Result := -1;
end;

procedure TPluginChrome.SetStatusSegment(const APluginId, ASegmentId, AText: string);
var
  S: TSegment;
  I: Integer;
  Text: string;
begin
  S.PluginId := Trim(APluginId);
  S.SegmentId := Trim(ASegmentId);
  if (S.PluginId = '') or (S.SegmentId = '') then
    Exit;
  // One line: control characters would break the status row.
  Text := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]),
    #10, ' ', [rfReplaceAll]));
  if Length(Text) > cMaxSegmentChars then
    Text := Copy(Text, 1, cMaxSegmentChars);
  S.Text := Text;
  I := IndexOf(S.PluginId, S.SegmentId);
  if Text = '' then
  begin
    if I < 0 then
      Exit;
    FSegments.Delete(I);
  end
  else if I < 0 then
    FSegments.Add(S)
  else if FSegments[I].Text <> Text then
    FSegments[I] := S
  else
    Exit;
  NotifyChanged;
end;

function TPluginChrome.StatusSegments: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FSegments.Count);
  for I := 0 to FSegments.Count - 1 do
    Result[I] := FSegments[I].Text;
end;

function ParseFBarKey(const AText: string; out AKey: Word; out AMods: TShiftState): Boolean;
var
  Parts: TArray<string>;
  I, N: Integer;
begin
  AKey := 0;
  AMods := [];
  Parts := AText.Split(['+']);
  if Length(Parts) = 0 then
    Exit(False);
  for I := 0 to High(Parts) - 1 do
    if SameText(Trim(Parts[I]), 'Shift') then
      Include(AMods, ssShift)
    else if SameText(Trim(Parts[I]), 'Ctrl') then
      Include(AMods, ssCtrl)
    else if SameText(Trim(Parts[I]), 'Alt') then
      Include(AMods, ssAlt)
    else
      Exit(False);
  Result := False;
  Parts[High(Parts)] := Trim(Parts[High(Parts)]);
  if (Length(Parts[High(Parts)]) < 2) or not CharInSet(Parts[High(Parts)][1], ['F', 'f']) then
    Exit;
  N := StrToIntDef(Copy(Parts[High(Parts)], 2, MaxInt), 0);
  if (N < 1) or (N > 10) then
    Exit;
  AKey := $70 + N - 1; // vkF1..vkF10
  Result := True;
end;

procedure TPluginChrome.SetSchemeFBar(const APluginId, AScheme, AJson: string);
var
  I, S: Integer;
  Scheme: string;
  Root: TJSONValue;
  Section: TJSONValue;
  Pair: TJSONPair;
  Item: TFBarLabel;
  Names: array[0..1] of string;
begin
  Scheme := LowerCase(Trim(AScheme));
  if (Trim(APluginId) = '') or (Scheme = '') then
    Exit;
  for I := FFBar.Count - 1 downto 0 do
    if SameText(FFBar[I].PluginId, APluginId) and (FFBar[I].Scheme = Scheme) then
      FFBar.Delete(I);
  Root := nil;
  if Trim(AJson) <> '' then
    Root := TJSONObject.ParseJSONValue(AJson);
  try
    if Root is TJSONObject then
    begin
      Names[0] := 'root';
      Names[1] := 'inside';
      for S := 0 to 1 do
      begin
        Section := TJSONObject(Root).GetValue(Names[S]);
        if not (Section is TJSONObject) then
          Continue;
        for Pair in TJSONObject(Section) do
        begin
          Item := Default(TFBarLabel);
          Item.PluginId := Trim(APluginId);
          Item.Scheme := Scheme;
          Item.Root := S = 0;
          if not ParseFBarKey(Pair.JsonString.Value, Item.Key, Item.Mods) then
            Continue;
          Item.Text := Pair.JsonValue.Value;
          FFBar.Add(Item);
        end;
      end;
    end;
  finally
    Root.Free;
  end;
  NotifyChanged;
end;

function TPluginChrome.TryGetSchemeFBarLabel(const AUri: string; AKey: Word;
  AShift: TShiftState; out ALabel: string): Boolean;
var
  I: Integer;
  Scheme: string;
  IsRoot: Boolean;
begin
  ALabel := '';
  Result := False;
  if FFBar.Count = 0 then
    Exit;
  Scheme := GenericVfsSchemeOf(AUri);
  if Scheme = '' then
    Exit;
  IsRoot := (GenericVfsAuthorityOf(AUri) = '') and (GenericVfsPathOf(AUri) = '/');
  for I := 0 to FFBar.Count - 1 do
    if (FFBar[I].Scheme = Scheme) and (FFBar[I].Root = IsRoot) and
       (FFBar[I].Key = AKey) and (FFBar[I].Mods = AShift) then
    begin
      ALabel := FFBar[I].Text;
      Exit(True);
    end;
end;

function TPluginChrome.DescribePlugin(const APluginId: string): TArray<string>;
var
  S: TSegment;
  Lines: TList<string>;
  Count: Integer;
begin
  Lines := TList<string>.Create;
  try
    Count := 0;
    for S in FSegments do
      if SameText(S.PluginId, APluginId) then
        Inc(Count);
    if Count > 0 then
      Lines.Add(T('ui.plugininfo.status', 'Shows text in the status line'));
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

procedure TPluginChrome.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
  Removed: Boolean;
begin
  Removed := False;
  for I := FFBar.Count - 1 downto 0 do
    if SameText(FFBar[I].PluginId, APluginId) then
    begin
      FFBar.Delete(I);
      Removed := True;
    end;
  for I := FSegments.Count - 1 downto 0 do
    if SameText(FSegments[I].PluginId, APluginId) then
    begin
      FSegments.Delete(I);
      Removed := True;
    end;
  if Removed then
    NotifyChanged;
end;

function PluginChrome: IPluginChrome;
begin
  if GChrome = nil then
    GChrome := TPluginChrome.Create;
  Result := GChrome;
end;

procedure SetPluginChromeChanged(const AHandler: TProc);
begin
  GChanged := AHandler;
end;

procedure NotifyPluginChromeChanged;
begin
  NotifyChanged;
end;

initialization

finalization
  GChanged := nil;
  GChrome := nil;

end.
