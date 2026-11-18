unit uDiskMapView;

{ What the treemap shows and how the keyboard and mouse move through it: the
  folder in view, the selected tile, the drawing of one frame. The tree comes
  from a TDiskScan; every read of it happens under the scan's lock. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uTreemap, uDiskMapTree, uDiskMapRaster;

/// <summary>The folder above APath; '' for a root (a drive, a share, "/").</summary>
function DiskParentFolder(const APath: string): string;

type
  TDiskTile = record
    Node: TDiskNode;
    Rect: TTileRect;
    Depth: Integer;
  end;

  /// <summary>What a key asks of the host besides redrawing. dkParent: the map
  /// is at the top of its scan and the folder above it should be mapped.
  /// dkRefresh: the folder in APath should be scanned again.</summary>
  TDiskKeyResult = (dkNone, dkHandled, dkGoto, dkParent, dkRefresh);

  TDiskMapView = class
  strict private
    FScan: IDiskScan;
    FViewRoot: TDiskNode;
    FSelected: TDiskNode;
    FTiles: TList<TDiskTile>;
    FTextScanning: string;
    FTextIncomplete: string;
    FTextRest: string;
    FTextEmpty: string;
    FTextTotal: string;
    FTextNotReady: string;
    FTextNotFolder: string;
    FTextHint: string;
    // Shown in the status bar instead of the usual text until the next key or click.
    FNotice: string;
    // Name of a top-level tile to select once the scan has produced it.
    FPendingSelect: string;
    procedure LayoutLevel(ARaster: TRaster; ANode: TDiskNode; const ARect: TTileRect;
      ADepth, AHue: Integer);
    procedure DrawBar(ARaster: TRaster; AY: Integer);
    procedure DrawNote(ARaster: TRaster; const AArea: TTileRect);
    function TileLabel(ANode: TDiskNode): string;
    function TotalOf(ANode: TDiskNode): Int64;
    function PathOfLocked(ANode: TDiskNode): string;
    function FirstTile: Integer;
    procedure MoveSelection(ADX, ADY: Integer);
    procedure Drill(ANotify: Boolean);
    procedure ApplyPendingSelect;
    function LastTile: Integer;
    procedure ZoomOutLocked;
    function SelectAtLocked(AX, AY: Integer): Boolean;
    function GotoSelectedLocked(out APath: string; out AIsFile: Boolean): TDiskKeyResult;
    function ZoomOutOrParentLocked(out APath: string): TDiskKeyResult;
  public
    constructor Create(const AScan: IDiskScan);
    destructor Destroy; override;
    procedure Render(ARaster: TRaster);
    /// <summary>A key by its host name ("Left", "Enter", "Backspace", "g").
    /// For dkGoto, APath is the folder (or the file) to show in the file panel.</summary>
    function HandleKey(const AKey: string; out APath: string; out AIsFile: Boolean): TDiskKeyResult;
    /// <summary>Selects the tile under the point; a double click enters a folder.</summary>
    function Click(AX, AY: Integer; ADouble: Boolean): Boolean;
    /// <summary>Selects the tile under the point and names it for the file panel:
    /// dkGoto with APath and AIsFile as for HandleKey, dkNone when no tile is there.</summary>
    function ClickGoto(AX, AY: Integer; out APath: string; out AIsFile: Boolean): TDiskKeyResult;
    /// <summary>One level out; at the top of the scan dkParent with the folder
    /// above in APath (none above a root: dkHandled).</summary>
    function ZoomOutOrParent(out APath: string): TDiskKeyResult;
    /// <summary>The wheel: forward (AClicks > 0) enters the folder under the point,
    /// back leaves the folder in view without leaving the scan. True when used.</summary>
    function Wheel(AX, AY, AClicks: Integer): Boolean;
    /// <summary>Selects the top-level tile of that name as soon as it is there.</summary>
    procedure SelectWhenShown(const AName: string);
    function Title: string;
    function StatusText: string;
    function SelectedName: string;
    function ViewRootPath: string;
    property TextScanning: string read FTextScanning write FTextScanning;
    property TextIncomplete: string read FTextIncomplete write FTextIncomplete;
    property TextRest: string read FTextRest write FTextRest;
    property TextEmpty: string read FTextEmpty write FTextEmpty;
    property TextTotal: string read FTextTotal write FTextTotal;
    property TextNotReady: string read FTextNotReady write FTextNotReady;
    property TextNotFolder: string read FTextNotFolder write FTextNotFolder;
    /// <summary>The key reminder drawn at the right of the status bar when it fits.</summary>
    property TextHint: string read FTextHint write FTextHint;
  end;

/// <summary>$RRGGBB from hue 0..359, saturation and lightness 0..1.</summary>
function HslColor(AHue: Integer; ASat, ALight: Double): Cardinal;

implementation

uses
  System.Math, System.Generics.Defaults;

const
  cBackground = $1E1E1E;
  cBarColor = $2B2B2B;
  cBarText = $D8D8D8;
  cSelectColor = $FFFFFF;
  cBarHeight = 20;
  cHeaderHeight = 16;
  cMaxNest = 3;
  cMinNestW = 70;
  cMinNestH = 48;
  cMinLabelW = 36;

type
  TKid = record
    Node: TDiskNode;
    Size: Int64;
  end;

function HslColor(AHue: Integer; ASat, ALight: Double): Cardinal;

  function Channel(AOffset: Double): Integer;
  var
    K, A, V: Double;
  begin
    K := AOffset - 12 * Floor(AOffset / 12);
    A := ASat * Min(ALight, 1 - ALight);
    V := ALight - A * Max(-1, Min(Min(K - 3, 9 - K), 1));
    Result := Max(0, Min(255, Round(V * 255)));
  end;

var
  H: Double;
begin
  H := ((AHue mod 360) + 360) mod 360 / 30;
  Result := (Cardinal(Channel(H)) shl 16) or (Cardinal(Channel(H + 8)) shl 8) or
    Cardinal(Channel(H + 4));
end;

function NameHash(const AName: string): Cardinal;
var
  C: Char;
begin
  Result := 2166136261;
  for C in LowerCase(AName) do
    Result := (Result xor Ord(C)) * 16777619;
end;

function IsLight(AColor: Cardinal): Boolean;
begin
  Result := 0.299 * ((AColor shr 16) and $FF) + 0.587 * ((AColor shr 8) and $FF) +
    0.114 * (AColor and $FF) > 150;
end;

{ TDiskMapView }

constructor TDiskMapView.Create(const AScan: IDiskScan);
begin
  inherited Create;
  FScan := AScan;
  FTiles := TList<TDiskTile>.Create;
  FViewRoot := AScan.Scan.Root;
  FTextScanning := 'scanning...';
  FTextIncomplete := 'incomplete';
  FTextRest := 'other files';
  FTextEmpty := 'empty';
  FTextTotal := 'total';
  FTextNotReady := 'the folder is still being scanned';
  FTextNotFolder := 'not a folder (G shows it in the panel)';
  FTextHint := 'Tab: keys  G: show in panel  Backspace: up  F5: rescan';
end;

destructor TDiskMapView.Destroy;
begin
  FTiles.Free;
  inherited;
end;

function TDiskMapView.TotalOf(ANode: TDiskNode): Int64;
begin
  Result := ANode.ShownSize;
end;

function DiskParentFolder(const APath: string): string;
var
  Trimmed: string;
begin
  Trimmed := ExcludeTrailingPathDelimiter(APath);
  Result := ExtractFilePath(Trimmed);
  // ExtractFilePath keeps "C:" whole: a drive has nothing above it.
  if SameText(Result, Trimmed) then
    Exit('');
  if (Length(Result) > 1) and (Result[Length(Result)] = PathDelim) and
     (ExtractFileDrive(Result) + PathDelim <> Result) then
    SetLength(Result, Length(Result) - 1);
end;

function TDiskMapView.PathOfLocked(ANode: TDiskNode): string;
var
  N: TDiskNode;
begin
  Result := '';
  N := ANode;
  if (N <> nil) and N.IsRest then
    N := N.Parent;
  while (N <> nil) and (N.Parent <> nil) do
  begin
    Result := PathDelim + N.Name + Result;
    N := N.Parent;
  end;
  Result := FScan.Scan.Path + Result;
end;

function TDiskMapView.TileLabel(ANode: TDiskNode): string;
begin
  if ANode.IsRest then
    Result := FTextRest
  else
    Result := ANode.Name;
end;

procedure TDiskMapView.LayoutLevel(ARaster: TRaster; ANode: TDiskNode; const ARect: TTileRect;
  ADepth, AHue: Integer);
var
  Kids: TArray<TKid>;
  Sizes: TArray<Int64>;
  Rects: TArray<TTileRect>;
  Kid: TDiskNode;
  I, N, Hue, ExtHash: Integer;
  R, Body: TTileRect;
  Fill, HeaderFill, TextColor: Cardinal;
  Tile: TDiskTile;
  Nested: Boolean;
  Caption: string;
begin
  if (ANode.Children = nil) or ARect.IsEmpty then
    Exit;
  N := 0;
  SetLength(Kids, ANode.Children.Count);
  for Kid in ANode.Children do
    if Kid.ShownSize > 0 then
    begin
      Kids[N].Node := Kid;
      Kids[N].Size := Kid.ShownSize;
      Inc(N);
    end;
  SetLength(Kids, N);
  TArray.Sort<TKid>(Kids, TComparer<TKid>.Construct(
    function(const A, B: TKid): Integer
    begin
      Result := Sign(B.Size - A.Size);
    end));
  SetLength(Sizes, N);
  for I := 0 to N - 1 do
    Sizes[I] := Kids[I].Size;
  Rects := SquarifyLayout(Sizes, ARect.X1, ARect.Y1, ARect.Width, ARect.Height);

  for I := 0 to N - 1 do
  begin
    R := Rects[I];
    if R.IsEmpty then
      Continue;
    Kid := Kids[I].Node;
    // One pixel between tiles, taken from the tile's right and bottom edge.
    if R.Width > 2 then
      Dec(R.X2);
    if R.Height > 2 then
      Dec(R.Y2);

    if ADepth = 0 then
      Hue := Integer(NameHash(Kid.Name) mod 360)
    else
      Hue := AHue;
    if Kid.IsRest then
      Fill := $505050
    else if Kid.IsDir then
      Fill := HslColor(Hue, 0.42, 0.24 + 0.04 * ADepth)
    else
    begin
      ExtHash := Integer(NameHash(ExtractFileExt(Kid.Name)) mod 20);
      Fill := HslColor(Hue + 30 + (ExtHash mod 5) * 14, 0.5, 0.38 + (ExtHash mod 4) * 0.05);
    end;
    ARaster.FillRect(R.X1, R.Y1, R.X2, R.Y2, Fill);
    Tile.Node := Kid;
    Tile.Rect := R;
    Tile.Depth := ADepth;
    FTiles.Add(Tile);

    if IsLight(Fill) then
      TextColor := $101010
    else
      TextColor := $F5F5F5;
    Caption := TileLabel(Kid);

    Nested := Kid.IsDir and Kid.Done and (Kid.Children <> nil) and (Kid.Children.Count > 0) and
      (ADepth < cMaxNest) and (R.Width >= cMinNestW) and (R.Height >= cMinNestH);
    if Nested then
    begin
      HeaderFill := HslColor(Hue, 0.45, 0.33 + 0.04 * ADepth);
      ARaster.FillRect(R.X1, R.Y1, R.X2, R.Y1 + cHeaderHeight, HeaderFill);
      if IsLight(HeaderFill) then
        TextColor := $101010
      else
        TextColor := $F5F5F5;
      ARaster.DrawText(R.X1 + 3, R.Y1 + 1,
        ARaster.FitText(Caption + '  ' + FormatBytes(Kids[I].Size), R.Width - 6), TextColor,
        R.X2 - 2);
      Body.X1 := R.X1 + 2;
      Body.Y1 := R.Y1 + cHeaderHeight;
      Body.X2 := R.X2 - 2;
      Body.Y2 := R.Y2 - 2;
      LayoutLevel(ARaster, Kid, Body, ADepth + 1, Hue);
    end
    else if R.Width >= cMinLabelW then
    begin
      if R.Height >= cTextHeight + 2 then
        ARaster.DrawText(R.X1 + 3, R.Y1 + 1, ARaster.FitText(Caption, R.Width - 6), TextColor,
          R.X2 - 2);
      if R.Height >= 2 * cTextHeight + 2 then
        ARaster.DrawText(R.X1 + 3, R.Y1 + cTextHeight + 1,
          ARaster.FitText(FormatBytes(Kids[I].Size), R.Width - 6), TextColor, R.X2 - 2);
    end;

    if Kid = FSelected then
      ARaster.FrameRect(R.X1, R.Y1, R.X2, R.Y2, cSelectColor, 2);
  end;
end;

procedure TDiskMapView.DrawBar(ARaster: TRaster; AY: Integer);
var
  Info: string;
  Avail, HintW: Integer;
begin
  ARaster.FillRect(0, AY, ARaster.Width, ARaster.Height, cBarColor);
  Info := StatusText;
  Avail := ARaster.Width - 12;
  HintW := ARaster.TextWidth(FTextHint);
  // The reminder is drawn only when it fits beside the whole status text.
  if (FNotice = '') and (FTextHint <> '') and (ARaster.TextWidth(Info) + 24 + HintW <= Avail) then
    ARaster.DrawText(ARaster.Width - 6 - HintW, AY + 3, FTextHint, cBarText, ARaster.Width - 4);
  ARaster.DrawText(6, AY + 3, ARaster.FitText(Info, Avail), cBarText, ARaster.Width - 4);
end;

{ Says what is going on while there is nothing to draw yet. }
procedure TDiskMapView.DrawNote(ARaster: TRaster; const AArea: TTileRect);
var
  Text: string;
begin
  if FScan.Scan.Finished then
    Text := FTextEmpty
  else
    Text := FTextScanning;
  Text := ARaster.FitText(Text, AArea.Width - 12);
  ARaster.DrawText((AArea.Width - ARaster.TextWidth(Text)) div 2,
    (AArea.Height - cTextHeight) div 2, Text, cBarText, AArea.X2);
end;

procedure TDiskMapView.Render(ARaster: TRaster);
var
  Area: TTileRect;
begin
  ARaster.Clear(cBackground);
  FScan.Scan.Lock;
  try
    FTiles.Clear;
    ApplyPendingSelect;
    Area.X1 := 0;
    Area.Y1 := 0;
    Area.X2 := ARaster.Width;
    Area.Y2 := Max(ARaster.Height - cBarHeight, 0);
    LayoutLevel(ARaster, FViewRoot, Area, 0, 0);
    if FTiles.Count = 0 then
      DrawNote(ARaster, Area);
    DrawBar(ARaster, Area.Y2);
  finally
    FScan.Scan.Unlock;
  end;
end;

function TDiskMapView.StatusText: string;
var
  Scan: TDiskScan;
  Total: Int64;
begin
  Scan := FScan.Scan;
  Scan.Lock;
  try
    if FNotice <> '' then
      Exit(FNotice);
    Total := TotalOf(FViewRoot);
    if FSelected <> nil then
    begin
      Result := TileLabel(FSelected) + '  -  ' + FormatBytes(FSelected.ShownSize);
      if Total > 0 then
        Result := Result + Format('  -  %.1f%%', [FSelected.ShownSize * 100 / Total],
          TFormatSettings.Invariant);
      // The path comes last: a narrow bar cuts it first.
      Result := Result + '  -  ' + PathOfLocked(FSelected);
    end
    else
      Result := PathOfLocked(FViewRoot) + '  -  ' + FTextTotal + ' ' + FormatBytes(Total);
    if not Scan.Finished then
      Result := Result + '  -  ' + FTextScanning
    else if Scan.Truncated then
      Result := Result + '  -  ' + FTextIncomplete
    else if Total = 0 then
      Result := Result + '  -  ' + FTextEmpty;
  finally
    Scan.Unlock;
  end;
end;

function TDiskMapView.Title: string;
begin
  Result := ExtractFileName(FScan.Scan.Path);
  if Result = '' then
    Result := FScan.Scan.Path;
end;

function TDiskMapView.SelectedName: string;
begin
  FScan.Scan.Lock;
  try
    if FSelected = nil then
      Result := ''
    else
      Result := TileLabel(FSelected);
  finally
    FScan.Scan.Unlock;
  end;
end;

function TDiskMapView.ViewRootPath: string;
begin
  FScan.Scan.Lock;
  try
    Result := PathOfLocked(FViewRoot);
  finally
    FScan.Scan.Unlock;
  end;
end;

{ The largest tile of the level in view, which is the first one laid out. }
function TDiskMapView.FirstTile: Integer;
var
  I: Integer;
begin
  for I := 0 to FTiles.Count - 1 do
    if FTiles[I].Depth = 0 then
      Exit(I);
  Result := -1;
end;

procedure TDiskMapView.MoveSelection(ADX, ADY: Integer);
var
  I, Cur, Best: Integer;
  CX, CY, OX, OY, Primary, Secondary, Score, BestScore: Integer;
  T: TDiskTile;
begin
  Cur := -1;
  for I := 0 to FTiles.Count - 1 do
    if FTiles[I].Node = FSelected then
    begin
      Cur := I;
      Break;
    end;
  if Cur < 0 then
  begin
    I := FirstTile;
    if I >= 0 then
      FSelected := FTiles[I].Node;
    Exit;
  end;
  CX := (FTiles[Cur].Rect.X1 + FTiles[Cur].Rect.X2) div 2;
  CY := (FTiles[Cur].Rect.Y1 + FTiles[Cur].Rect.Y2) div 2;
  Best := -1;
  BestScore := MaxInt;
  for I := 0 to FTiles.Count - 1 do
  begin
    T := FTiles[I];
    if (I = Cur) or (T.Node.Parent <> FSelected.Parent) then
      Continue;
    OX := (T.Rect.X1 + T.Rect.X2) div 2;
    OY := (T.Rect.Y1 + T.Rect.Y2) div 2;
    Primary := (OX - CX) * ADX + (OY - CY) * ADY;
    if Primary <= 0 then
      Continue;
    Secondary := Abs((OX - CX) * ADY) + Abs((OY - CY) * ADX);
    Score := Primary + 2 * Secondary;
    if Score < BestScore then
    begin
      BestScore := Score;
      Best := I;
    end;
  end;
  if Best >= 0 then
    FSelected := FTiles[Best].Node;
end;

procedure TDiskMapView.Drill(ANotify: Boolean);
begin
  if FSelected = nil then
    Exit;
  if not FSelected.IsDir then
  begin
    if ANotify then
      FNotice := FTextNotFolder;
  end
  else if not FSelected.Done then
  begin
    if ANotify then
    begin
      if FScan.Scan.Finished then
        FNotice := FTextIncomplete
      else
        FNotice := FTextNotReady;
    end;
  end
  else if (FSelected.Children = nil) or (FSelected.Children.Count = 0) then
  begin
    if ANotify then
      FNotice := FTextEmpty;
  end
  else
  begin
    FViewRoot := FSelected;
    FSelected := nil;
  end;
end;

procedure TDiskMapView.ApplyPendingSelect;
var
  Kid: TDiskNode;
begin
  if (FPendingSelect = '') or (FSelected <> nil) then
    Exit;
  if FViewRoot.Children <> nil then
    for Kid in FViewRoot.Children do
      if Kid.IsDir and SameText(Kid.Name, FPendingSelect) then
      begin
        FSelected := Kid;
        FPendingSelect := '';
        Exit;
      end;
  // Nothing more will turn up: stop waiting.
  if FScan.Scan.Finished then
    FPendingSelect := '';
end;

{ The smallest tile of the level in view, which is the last one laid out. }
function TDiskMapView.LastTile: Integer;
var
  I: Integer;
begin
  for I := FTiles.Count - 1 downto 0 do
    if FTiles[I].Depth = 0 then
      Exit(I);
  Result := -1;
end;

procedure TDiskMapView.SelectWhenShown(const AName: string);
begin
  FScan.Scan.Lock;
  try
    FPendingSelect := AName;
  finally
    FScan.Scan.Unlock;
  end;
end;

procedure TDiskMapView.ZoomOutLocked;
begin
  if FViewRoot.Parent <> nil then
  begin
    FSelected := FViewRoot;
    FViewRoot := FViewRoot.Parent;
  end;
end;

function TDiskMapView.ZoomOutOrParentLocked(out APath: string): TDiskKeyResult;
begin
  APath := '';
  Result := dkHandled;
  if FViewRoot.Parent <> nil then
    ZoomOutLocked
  else
  begin
    APath := DiskParentFolder(FScan.Scan.Path);
    if APath <> '' then
      Result := dkParent;
  end;
end;

function TDiskMapView.ZoomOutOrParent(out APath: string): TDiskKeyResult;
begin
  FScan.Scan.Lock;
  try
    Result := ZoomOutOrParentLocked(APath);
  finally
    FScan.Scan.Unlock;
  end;
end;

function TDiskMapView.HandleKey(const AKey: string; out APath: string;
  out AIsFile: Boolean): TDiskKeyResult;
begin
  APath := '';
  AIsFile := False;
  Result := dkHandled;
  FScan.Scan.Lock;
  try
    FNotice := '';
    FPendingSelect := '';
    if (AKey = 'Enter') or (AKey = 'Return') then
      Drill(True)
    else if AKey = 'Backspace' then
      Result := ZoomOutOrParentLocked(APath)
    else if AKey = 'Left' then
      MoveSelection(-1, 0)
    else if AKey = 'Right' then
      MoveSelection(1, 0)
    else if AKey = 'Up' then
      MoveSelection(0, -1)
    else if AKey = 'Down' then
      MoveSelection(0, 1)
    else if AKey = 'Home' then
    begin
      if FirstTile >= 0 then
        FSelected := FTiles[FirstTile].Node;
    end
    else if AKey = 'End' then
    begin
      if LastTile >= 0 then
        FSelected := FTiles[LastTile].Node;
    end
    // The Cyrillic letters are G on a Russian layout.
    else if (AKey = 'Ctrl+Enter') or (AKey = 'Shift+Enter') or (AKey = 'g') or (AKey = 'G') or
            (AKey = #$043F) or (AKey = #$041F) then
      Result := GotoSelectedLocked(APath, AIsFile)
    else if (AKey = 'F5') or (AKey = 'Ctrl+R') then
    begin
      APath := FScan.Scan.Path;
      Result := dkRefresh;
    end
    else
      Result := dkNone;
  finally
    FScan.Scan.Unlock;
  end;
end;

function TDiskMapView.GotoSelectedLocked(out APath: string; out AIsFile: Boolean): TDiskKeyResult;
begin
  AIsFile := False;
  if FSelected <> nil then
  begin
    APath := PathOfLocked(FSelected);
    AIsFile := not (FSelected.IsDir or FSelected.IsRest);
  end
  else
    APath := PathOfLocked(FViewRoot);
  Result := dkGoto;
end;

function TDiskMapView.SelectAtLocked(AX, AY: Integer): Boolean;
var
  I: Integer;
begin
  for I := FTiles.Count - 1 downto 0 do
    if FTiles[I].Rect.Contains(AX, AY) then
    begin
      FSelected := FTiles[I].Node;
      Exit(True);
    end;
  Result := False;
end;

function TDiskMapView.Click(AX, AY: Integer; ADouble: Boolean): Boolean;
begin
  FScan.Scan.Lock;
  try
    FNotice := '';
    FPendingSelect := '';
    Result := SelectAtLocked(AX, AY);
    if Result and ADouble then
      Drill(True);
  finally
    FScan.Scan.Unlock;
  end;
end;

function TDiskMapView.Wheel(AX, AY, AClicks: Integer): Boolean;
var
  Before: TDiskNode;
begin
  Result := False;
  FScan.Scan.Lock;
  try
    FNotice := '';
    FPendingSelect := '';
    if AClicks > 0 then
    begin
      Result := SelectAtLocked(AX, AY);
      Before := FViewRoot;
      if Result then
        Drill(False);
      Result := Result or (Before <> FViewRoot);
    end
    else if (AClicks < 0) and (FViewRoot.Parent <> nil) then
    begin
      ZoomOutLocked;
      Result := True;
    end;
  finally
    FScan.Scan.Unlock;
  end;
end;

function TDiskMapView.ClickGoto(AX, AY: Integer; out APath: string;
  out AIsFile: Boolean): TDiskKeyResult;
begin
  APath := '';
  AIsFile := False;
  Result := dkNone;
  FScan.Scan.Lock;
  try
    FNotice := '';
    FPendingSelect := '';
    if SelectAtLocked(AX, AY) then
      Result := GotoSelectedLocked(APath, AIsFile);
  finally
    FScan.Scan.Unlock;
  end;
end;

end.
