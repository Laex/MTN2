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
  System.SysUtils, System.Generics.Collections;

type
  IPluginChrome = interface
    ['{9B4E6C21-8D5F-4A37-B1C2-3E7A5F9D0B64}']
    /// <summary>Sets (or, with an empty text, removes) the segment ASegmentId
    /// of APluginId. The text is shortened to a status-line sized string.</summary>
    procedure SetStatusSegment(const APluginId, ASegmentId, AText: string);
    /// <summary>The texts to append to the status line, in first-set order.</summary>
    function StatusSegments: TArray<string>;
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

implementation

uses
  uStrings;

const
  cMaxSegmentChars = 40;

type
  TSegment = record
    PluginId: string;
    SegmentId: string;
    Text: string;
  end;

  TPluginChrome = class(TInterfacedObject, IPluginChrome)
  private
    FSegments: TList<TSegment>;
    function IndexOf(const APluginId, ASegmentId: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetStatusSegment(const APluginId, ASegmentId, AText: string);
    function StatusSegments: TArray<string>;
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
end;

destructor TPluginChrome.Destroy;
begin
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

initialization

finalization
  GChanged := nil;
  GChrome := nil;

end.
