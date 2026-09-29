unit uDualPanelFolderTree;

{ Folder tree of a drive (Alt+F10), drawn over the active panel with
  box-drawing lines. The arrows walk it, Right / Left open and close a
  branch, a letter jumps to the next folder starting with it. The opposite
  panel follows the cursor after a short pause; Enter opens the folder in
  the active panel, Esc or Alt+F10 closes the tree and the panel under it
  shows again as it was. Like a FAR tree panel it stays when the other
  panel takes the focus (Tab, a click there): it then looks inactive, the
  keys go to the other panel, and Tab or a click on the tree's frame
  brings the focus back. The mouse works the tree as an index of the other
  panel: a click on a folder shows it there at once and hands that panel
  the focus, a click on "[+]" / "[-]" opens or closes the branch and leaves
  the focus where it is. It also follows that panel: when the other panel goes to
  another folder by itself, the tree opens the path to it (in the
  background) and puts the cursor there; another drive rebuilds the tree
  for that drive.

  Branches load when opened (one folder listing each), so a large disk
  opens at once: the drive root with the path to the current folder open.
  Every listing runs on a background thread. A result applies only to the
  tree that asked for it (FGen): closing or reopening the tree drops it,
  and so does the panel under the tree going elsewhere (another drive, a
  restored session) - the tree then closes. There is one tree per window,
  so it is never open in both panels. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  System.Generics.Collections, System.Generics.Defaults, System.Threading,
  FMX.Types,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes,
  uDualPanelOverlays, uDualPanelDrawUtils, uDualPanelPanelDraw;

type
  TFolderEntry = record
    Name: string;
    HasSubfolders: Boolean;
  end;
  /// <summary>Subfolders of APath, sorted, each with whether it has its own.</summary>
  TFolderListFunc = reference to function(const APath: string): TArray<TFolderEntry>;

  TFolderTreeNode = record
    /// <summary>Full local path; the root keeps its trailing delimiter.</summary>
    Path: string;
    Name: string;
    Depth: Integer;
    Expanded: Boolean;
    HasChildren: Boolean;
  end;

  /// <summary>The visible rows of the tree, in display order: opening a
  /// branch inserts its children after it, closing one removes them.</summary>
  TFolderTree = class
  private
    FNodes: TList<TFolderTreeNode>;
    FCursor: Integer;
    FList: TFolderListFunc;
    function MakeNode(const APath, AName: string; ADepth: Integer;
      AHasChildren: Boolean): TFolderTreeNode;
    function IndexOfChild(AParent: Integer; const AName: string): Integer;
    procedure SetCursor(AValue: Integer);
  public
    constructor Create(const AList: TFolderListFunc);
    destructor Destroy; override;
    /// <summary>The tree of APath's drive with the path to APath and APath
    /// itself open, the cursor on APath (or on the deepest folder of it that
    /// exists).</summary>
    procedure OpenAt(const APath: string);
    function Count: Integer;
    function Node(AIndex: Integer): TFolderTreeNode;
    function IndexOfPath(const APath: string): Integer;
    function ParentIndex(AIndex: Integer): Integer;
    function IsLastSibling(AIndex: Integer): Boolean;
    /// <summary>Box-drawing lines before the name: one four-cell column per
    /// level ("│   " or blank), then "├" / "└" and a mark ending in a blank:
    /// "── " for a folder without subfolders, "[+]─ " / "[-]─ " for a
    /// closed / open branch. The children's line runs down from the "─"
    /// after the branch mark.</summary>
    function LinePrefix(AIndex: Integer): string;
    /// <summary>Opens a closed branch, listing it; False when it has no
    /// subfolders.</summary>
    function Expand(AIndex: Integer): Boolean;
    /// <summary>Opens the closed branch AIndex with AEntries already listed.</summary>
    function ExpandWith(AIndex: Integer; const AEntries: TArray<TFolderEntry>): Boolean;
    procedure Collapse(AIndex: Integer);
    /// <summary>Left: closes an open branch, else steps to the parent.</summary>
    procedure StepOut;
    /// <summary>Next row after the cursor (wrapping) whose name starts with
    /// ALetter; False when there is none.</summary>
    function JumpToLetter(ALetter: Char): Boolean;
    function CursorPath: string;
    property Cursor: Integer read FCursor write SetCursor;
  end;

  /// <summary>Shared with background listings: False once the controller
  /// is gone, so a late result does not touch it.</summary>
  /// <summary>One listing on the way to a folder the tree syncs to.</summary>
  TFolderListing = record
    Path: string;
    Entries: TArray<TFolderEntry>;
  end;

  TFolderTreeLife = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  /// <summary>What a click on the tree leaves for the host: ftcOutside -
  /// not the tree's, the panels take it; ftcFocusTree / ftcFocusFiles - give
  /// the tree / the other panel the focus; ftcKeep - the focus stays.</summary>
  TFolderTreeClick = (ftcOutside, ftcFocusTree, ftcFocusFiles, ftcKeep);

  TFolderTreePanelEvent = reference to function(ASide: TPanelSide): TRectI;
  TFolderTreeUriEvent = reference to function(ASide: TPanelSide): string;
  TFolderTreeNavigateEvent = reference to procedure(ASide: TPanelSide; const AURI: string);

  TFolderTreeController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FGetPanelBounds: TFolderTreePanelEvent;
    FGetPanelUri: TFolderTreeUriEvent;
    FOnNavigate: TFolderTreeNavigateEvent;
    FList: TFolderListFunc;
    FTree: TFolderTree;
    FVisible: Boolean;
    FSide: TPanelSide;
    FBounds: TRectI;
    FScroll: Integer;
    FFollowTimer: TTimer;
    FFollowed: string;
    /// <summary>Panel folder the tree was opened over.</summary>
    FOwnerUri: string;
    /// <summary>Bumped by Open and Close: a listing finished for an earlier
    /// tree is dropped.</summary>
    FGen: Cardinal;
    FLife: TFolderTreeLife;
    FLifeRef: IInterface;
    FLoading: Boolean;
    /// <summary>Branch being listed in the background, '' when none.</summary>
    FListingPath: string;
    /// <summary>The other panel's folder when last looked at.</summary>
    FOtherSeen: string;
    /// <summary>Draw is running: it paints the change itself, and a repaint
    /// request from inside it would re-enter the compose.</summary>
    FDrawing: Boolean;
    procedure ApplySync(AGen: Cardinal; const ATarget: string;
      const AListings: TArray<TFolderListing>);
    procedure StartBuild(const APath: string);
    procedure FollowTick(Sender: TObject);
    procedure CursorMoved;
    procedure Invalidate;
    function ViewHeight: Integer;
    /// <summary>Keeps the scroll in range; AShowCursor also brings the cursor
    /// row into view (after the cursor moves, not on every paint - the
    /// wheel scrolls away from it).</summary>
    procedure EnsureScroll(AShowCursor: Boolean = True);
    procedure StepIn;
    /// <summary>Opens the closed branch AIndex, listing it in the background.</summary>
    procedure ExpandInBackground(AIndex: Integer);
    procedure ApplyListing(AGen: Cardinal; const APath: string;
      const AEntries: TArray<TFolderEntry>);
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AGetPanelBounds: TFolderTreePanelEvent;
      const AGetPanelUri: TFolderTreeUriEvent;
      const AOnNavigate: TFolderTreeNavigateEvent;
      const AList: TFolderListFunc = nil);
    destructor Destroy; override;
    procedure SetTheme(const ATheme: IThemeRenderer);
    /// <summary>Opens the tree over ASide's panel; nothing happens when the
    /// panel does not show a folder on a local disk.</summary>
    procedure Open(ASide: TPanelSide);
    /// <summary>Closes an open tree (whichever panel it is over), else opens
    /// one over ASide.</summary>
    procedure Toggle(ASide: TPanelSide);
    procedure Close;
    /// <summary>Closes the tree when the panel under it no longer shows the
    /// folder it was opened over.</summary>
    procedure CheckOwner;
    /// <summary>AFocused: the tree's side is the active one.</summary>
    procedure Draw(const AGrid: TTerminalGrid; AFocused: Boolean);
    /// <summary>Drops a pending follow of the opposite panel (the focus
    /// leaves the tree).</summary>
    procedure StopFollow;
    /// <summary>Mouse wheel: scrolls the rows by ADelta, the cursor and the
    /// focus stay.</summary>
    procedure ScrollBy(ADelta: Integer);
    /// <summary>Follows the other panel's folder when it changed by itself
    /// (see the unit comment). Draw calls it.</summary>
    procedure SyncWithOther;
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleClick(ALocalCol, ALocalRow: Integer): TFolderTreeClick;
    property Visible: Boolean read FVisible;
    property Bounds: TRectI read FBounds;
    property Loading: Boolean read FLoading;
    property Side: TPanelSide read FSide;
    property Tree: TFolderTree read FTree;
  end;

const
  /// <summary>Pause after the last cursor move before the opposite panel
  /// follows: walking through folders does not read each one.</summary>
  cFolderTreeFollowMs = 350;

/// <summary>Subfolders of a local folder, sorted without regard to case.</summary>
function ListLocalSubfolders(const APath: string): TArray<TFolderEntry>;
function LocalFolderHasSubfolders(const APath: string): Boolean;

implementation

uses
  uVfsTypes, uStrings;

const
  // Without a theme: the NDN panel colours.
  cCursorFg = TAlphaColor($FF000000);
  cCursorBg = TAlphaColor($FF00AAAA);
  cDirFg    = TAlphaColor($FFFFFFFF);
  cPanelBg  = TAlphaColor($FF0000AA);
  cFrameFg  = TAlphaColor($FF55FFFF);
  cVert = #$2502;
  cHorz = #$2500;
  cTee = #$251C;
  cCorner = #$2514;
  cClosed = '[+]' + #$2500 + ' ';
  cOpen = '[-]' + #$2500 + ' ';
  /// <summary>A folder without subfolders: as wide as the branch marks.</summary>
  cLeaf = #$2500#$2500' ';

function IsSubfolderEntry(const ASr: TSearchRec): Boolean;
begin
  Result := ((ASr.Attr and faDirectory) <> 0) and (ASr.Name <> '.') and (ASr.Name <> '..');
end;

function LocalFolderHasSubfolders(const APath: string): Boolean;
var
  Sr: TSearchRec;
begin
  Result := False;
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*', faDirectory, Sr) = 0 then
  try
    repeat
      if IsSubfolderEntry(Sr) then
        Exit(True);
    until FindNext(Sr) <> 0;
  finally
    FindClose(Sr);
  end;
end;

function ListLocalSubfolders(const APath: string): TArray<TFolderEntry>;
var
  Sr: TSearchRec;
  L: TList<string>;
  I: Integer;
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(APath);
  L := TList<string>.Create;
  try
    if FindFirst(Base + '*', faDirectory, Sr) = 0 then
    try
      repeat
        if IsSubfolderEntry(Sr) then
          L.Add(Sr.Name);
      until FindNext(Sr) <> 0;
    finally
      FindClose(Sr);
    end;
    L.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareText(A, B);
      end));
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do
    begin
      Result[I].Name := L[I];
      Result[I].HasSubfolders := LocalFolderHasSubfolders(Base + L[I]);
    end;
  finally
    L.Free;
  end;
end;

{ TFolderTree }

constructor TFolderTree.Create(const AList: TFolderListFunc);
begin
  inherited Create;
  FNodes := TList<TFolderTreeNode>.Create;
  FList := AList;
end;

destructor TFolderTree.Destroy;
begin
  FNodes.Free;
  inherited;
end;

function TFolderTree.MakeNode(const APath, AName: string; ADepth: Integer;
  AHasChildren: Boolean): TFolderTreeNode;
begin
  Result.Path := APath;
  Result.Name := AName;
  Result.Depth := ADepth;
  Result.Expanded := False;
  Result.HasChildren := AHasChildren;
end;

function TFolderTree.Count: Integer;
begin
  Result := FNodes.Count;
end;

function TFolderTree.Node(AIndex: Integer): TFolderTreeNode;
begin
  Result := FNodes[AIndex];
end;

function TFolderTree.IndexOfPath(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FNodes.Count - 1 do
    if SameText(FNodes[I].Path, APath) then
      Exit(I);
  Result := -1;
end;

procedure TFolderTree.SetCursor(AValue: Integer);
begin
  if FNodes.Count = 0 then
    FCursor := 0
  else
    FCursor := EnsureRange(AValue, 0, FNodes.Count - 1);
end;

function TFolderTree.IndexOfChild(AParent: Integer; const AName: string): Integer;
var
  I, D: Integer;
begin
  D := FNodes[AParent].Depth + 1;
  I := AParent + 1;
  while (I < FNodes.Count) and (FNodes[I].Depth >= D) do
  begin
    if (FNodes[I].Depth = D) and SameText(FNodes[I].Name, AName) then
      Exit(I);
    Inc(I);
  end;
  Result := -1;
end;

procedure TFolderTree.OpenAt(const APath: string);
var
  Root, Rest, Part: string;
  Parts: TArray<string>;
  Cur, Child: Integer;
begin
  FNodes.Clear;
  FCursor := 0;
  Root := ExtractFileDrive(APath);
  if Root = '' then
    Exit;
  Root := IncludeTrailingPathDelimiter(Root);
  FNodes.Add(MakeNode(Root, Root, 0, True));
  Rest := Copy(ExcludeTrailingPathDelimiter(APath), Length(Root) + 1, MaxInt);
  Parts := Rest.Split([PathDelim], TStringSplitOptions.ExcludeEmpty);
  Cur := 0;
  for Part in Parts do
  begin
    if not Expand(Cur) then
      Break;
    Child := IndexOfChild(Cur, Part);
    if Child < 0 then
      Break;
    Cur := Child;
  end;
  // The folder the tree opens at shows its own subfolders too.
  Expand(Cur);
  FCursor := Cur;
end;

function TFolderTree.ParentIndex(AIndex: Integer): Integer;
var
  D: Integer;
begin
  D := FNodes[AIndex].Depth;
  Result := AIndex - 1;
  while (Result >= 0) and (FNodes[Result].Depth >= D) do
    Dec(Result);
end;

function TFolderTree.IsLastSibling(AIndex: Integer): Boolean;
var
  I, D: Integer;
begin
  D := FNodes[AIndex].Depth;
  for I := AIndex + 1 to FNodes.Count - 1 do
  begin
    if FNodes[I].Depth < D then
      Exit(True);
    if FNodes[I].Depth = D then
      Exit(False);
  end;
  Result := True;
end;

function TFolderTree.LinePrefix(AIndex: Integer): string;
var
  D, L, A: Integer;
  Cols: TArray<string>;
begin
  D := FNodes[AIndex].Depth;
  if D = 0 then
    Exit('');
  SetLength(Cols, D - 1);
  // Walk up the ancestors: each one that has siblings below keeps its line.
  A := ParentIndex(AIndex);
  for L := D - 1 downto 1 do
  begin
    if IsLastSibling(A) then
      Cols[L - 1] := '    '
    else
      Cols[L - 1] := cVert + '   ';
    A := ParentIndex(A);
  end;
  Result := string.Join('', Cols);
  if IsLastSibling(AIndex) then
    Result := Result + cCorner
  else
    Result := Result + cTee;
  if not FNodes[AIndex].HasChildren then
    Result := Result + cLeaf
  else if FNodes[AIndex].Expanded then
    Result := Result + cOpen
  else
    Result := Result + cClosed;
end;

function TFolderTree.Expand(AIndex: Integer): Boolean;
begin
  if FNodes[AIndex].Expanded then
    Exit(True);
  if not Assigned(FList) then
    Exit(False);
  Result := ExpandWith(AIndex, FList(FNodes[AIndex].Path));
end;

function TFolderTree.ExpandWith(AIndex: Integer;
  const AEntries: TArray<TFolderEntry>): Boolean;
var
  N: TFolderTreeNode;
  I: Integer;
begin
  N := FNodes[AIndex];
  if N.Expanded then
    Exit(True);
  N.HasChildren := Length(AEntries) > 0;
  if Length(AEntries) = 0 then
  begin
    FNodes[AIndex] := N;
    Exit(False);
  end;
  N.Expanded := True;
  FNodes[AIndex] := N;
  for I := High(AEntries) downto 0 do
    FNodes.Insert(AIndex + 1,
      MakeNode(IncludeTrailingPathDelimiter(N.Path) + AEntries[I].Name,
        AEntries[I].Name, N.Depth + 1, AEntries[I].HasSubfolders));
  // The cursor keeps its folder when rows appear above it.
  if FCursor > AIndex then
    Inc(FCursor, Length(AEntries));
  Result := True;
end;

procedure TFolderTree.Collapse(AIndex: Integer);
var
  N: TFolderTreeNode;
  Last: Integer;
begin
  N := FNodes[AIndex];
  if not N.Expanded then
    Exit;
  Last := AIndex + 1;
  while (Last < FNodes.Count) and (FNodes[Last].Depth > N.Depth) do
    Inc(Last);
  if (FCursor > AIndex) and (FCursor < Last) then
    FCursor := AIndex
  else if FCursor >= Last then
    Dec(FCursor, Last - AIndex - 1);
  FNodes.DeleteRange(AIndex + 1, Last - AIndex - 1);
  N.Expanded := False;
  FNodes[AIndex] := N;
end;

procedure TFolderTree.StepOut;
var
  P: Integer;
begin
  if FNodes.Count = 0 then
    Exit;
  if FNodes[FCursor].Expanded then
  begin
    Collapse(FCursor);
    Exit;
  end;
  P := ParentIndex(FCursor);
  if P >= 0 then
    FCursor := P;
end;

function TFolderTree.JumpToLetter(ALetter: Char): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  for J := 1 to FNodes.Count do
  begin
    I := (FCursor + J) mod FNodes.Count;
    if (FNodes[I].Name <> '') and (UpCase(FNodes[I].Name[1]) = UpCase(ALetter)) then
    begin
      FCursor := I;
      Exit(True);
    end;
  end;
end;

function TFolderTree.CursorPath: string;
begin
  if FNodes.Count = 0 then
    Result := ''
  else
    Result := FNodes[FCursor].Path;
end;

{ TFolderTreeController }

function OtherSide(ASide: TPanelSide): TPanelSide;
begin
  if ASide = psLeft then
    Result := psRight
  else
    Result := psLeft;
end;

function IsAlive(const ALifeRef: IInterface): Boolean;
begin
  Result := (ALifeRef as TFolderTreeLife).Alive;
end;

constructor TFolderTreeController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AGetPanelBounds: TFolderTreePanelEvent;
  const AGetPanelUri: TFolderTreeUriEvent;
  const AOnNavigate: TFolderTreeNavigateEvent; const AList: TFolderListFunc);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FGetPanelBounds := AGetPanelBounds;
  FGetPanelUri := AGetPanelUri;
  FOnNavigate := AOnNavigate;
  FList := AList;
  if not Assigned(FList) then
    FList := ListLocalSubfolders;
  FTree := TFolderTree.Create(FList);
  FFollowTimer := TTimer.Create(nil);
  FFollowTimer.Enabled := False;
  FFollowTimer.Interval := cFolderTreeFollowMs;
  FFollowTimer.OnTimer := FollowTick;
  FLife := TFolderTreeLife.Create;
  FLife.Alive := True;
  FLifeRef := FLife;
end;

destructor TFolderTreeController.Destroy;
begin
  FLife.Alive := False;
  FFollowTimer.Free;
  FTree.Free;
  inherited;
end;

procedure TFolderTreeController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

procedure TFolderTreeController.Invalidate;
begin
  if FDrawing then
    Exit;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TFolderTreeController.Open(ASide: TPanelSide);
var
  Uri, Path: string;
begin
  Uri := FGetPanelUri(ASide);
  if not Uri.StartsWith('file:', True) or HasArchiveChain(Uri) then
    Exit;
  Path := FileUriToPath(Uri);
  if ExtractFileDrive(Path) = '' then
    Exit;
  FSide := ASide;
  FOwnerUri := Uri;
  FVisible := True;
  FScroll := 0;
  FFollowed := Path;
  FOtherSeen := FGetPanelUri(OtherSide(ASide));
  StartBuild(Path);
end;

procedure TFolderTreeController.StartBuild(const APath: string);
var
  Gen: Cardinal;
  List: TFolderListFunc;
  Self_: TFolderTreeController;
  LifeRef: IInterface;
  Path: string;
begin
  Inc(FGen);
  Gen := FGen;
  FLoading := True;
  FListingPath := '';
  FTree.Free;
  FTree := TFolderTree.Create(FList);
  Invalidate;
  // The path to the folder is several listings: build the whole tree off
  // the UI thread and swap it in.
  Path := APath;
  List := FList;
  Self_ := Self;
  LifeRef := FLifeRef;
  TTask.Run(
    procedure
    var
      Built: TFolderTree;
    begin
      Built := TFolderTree.Create(List);
      try
        Built.OpenAt(Path);
      except
        Built.Free;
        Built := nil;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if (Built = nil) or not IsAlive(LifeRef) or (Gen <> Self_.FGen) then
          begin
            Built.Free;
            Exit;
          end;
          Self_.FTree.Free;
          Self_.FTree := Built;
          Self_.FLoading := False;
          Self_.EnsureScroll;
          Self_.Invalidate;
        end);
    end);
end;

procedure TFolderTreeController.SyncWithOther;
var
  Uri, Path, Target: string;
  Parts: TArray<string>;
  Gen: Cardinal;
  List: TFolderListFunc;
  Self_: TFolderTreeController;
  LifeRef: IInterface;
begin
  if not FVisible or FLoading or (FListingPath <> '') then
    Exit;
  Uri := FGetPanelUri(OtherSide(FSide));
  if SameText(Uri, FOtherSeen) then
    Exit;
  FOtherSeen := Uri;
  if not Uri.StartsWith('file:', True) or HasArchiveChain(Uri) then
    Exit;
  Path := FileUriToPath(Uri);
  // The tree sent the panel there itself: nothing to follow.
  if SameText(ExcludeTrailingPathDelimiter(Path),
     ExcludeTrailingPathDelimiter(FFollowed)) then
    Exit;
  FFollowed := Path;
  FFollowTimer.Enabled := False;
  if (FTree.Count = 0) or not SameText(ExtractFileDrive(Path),
     ExtractFileDrive(FTree.Node(0).Path)) then
  begin
    StartBuild(Path);
    Exit;
  end;
  // Same drive: list every folder on the way that is not open yet.
  Gen := FGen;
  List := FList;
  Target := ExcludeTrailingPathDelimiter(Path);
  Parts := Copy(Target, Length(ExtractFileDrive(Target)) + 2, MaxInt)
    .Split([PathDelim], TStringSplitOptions.ExcludeEmpty);
  Self_ := Self;
  LifeRef := FLifeRef;
  FListingPath := Target;
  Invalidate;
  TTask.Run(
    procedure
    var
      Listings: TArray<TFolderListing>;
      Dir: string;
      I: Integer;
    begin
      Dir := IncludeTrailingPathDelimiter(ExtractFileDrive(Target));
      SetLength(Listings, Length(Parts) + 1);
      try
        for I := 0 to Length(Parts) do
        begin
          Listings[I].Path := Dir;
          Listings[I].Entries := List(Dir);
          if I < Length(Parts) then
            Dir := IncludeTrailingPathDelimiter(Dir) + Parts[I];
        end;
      except
        Listings := nil;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if IsAlive(LifeRef) then
            Self_.ApplySync(Gen, Target, Listings);
        end);
    end);
end;

procedure TFolderTreeController.ApplySync(AGen: Cardinal; const ATarget: string;
  const AListings: TArray<TFolderListing>);
var
  L: TFolderListing;
  Idx, Deepest: Integer;
  P: string;
begin
  if AGen <> FGen then
    Exit;
  FListingPath := '';
  Deepest := -1;
  for L in AListings do
  begin
    // The root keeps its trailing delimiter; other rows do not have one.
    if Length(L.Path) <= 3 then
      P := L.Path
    else
      P := ExcludeTrailingPathDelimiter(L.Path);
    Idx := FTree.IndexOfPath(P);
    if Idx < 0 then
      Break;
    Deepest := Idx;
    FTree.ExpandWith(Idx, L.Entries);
  end;
  Idx := FTree.IndexOfPath(ATarget);
  if Idx >= 0 then
    FTree.Cursor := Idx
  else if Deepest >= 0 then
    FTree.Cursor := Deepest;
  EnsureScroll;
  Invalidate;
end;

procedure TFolderTreeController.Toggle(ASide: TPanelSide);
begin
  if FVisible then
    Close
  else
    Open(ASide);
end;

procedure TFolderTreeController.Close;
begin
  if not FVisible then
    Exit;
  Inc(FGen);
  FFollowTimer.Enabled := False;
  FVisible := False;
  FLoading := False;
  FListingPath := '';
  Invalidate;
end;

procedure TFolderTreeController.CheckOwner;
begin
  if FVisible and not SameText(FGetPanelUri(FSide), FOwnerUri) then
    Close;
end;

procedure TFolderTreeController.FollowTick(Sender: TObject);
var
  Path: string;
begin
  FFollowTimer.Enabled := False;
  if not FVisible or FLoading then
    Exit;
  Path := FTree.CursorPath;
  if (Path = '') or SameText(Path, FFollowed) then
    Exit;
  FFollowed := Path;
  if Assigned(FOnNavigate) then
    FOnNavigate(OtherSide(FSide), PathToFileUri(Path));
end;

procedure TFolderTreeController.StopFollow;
begin
  FFollowTimer.Enabled := False;
end;

procedure TFolderTreeController.CursorMoved;
begin
  EnsureScroll;
  // Restart the pause: the opposite panel reads only where the cursor stops.
  FFollowTimer.Enabled := False;
  FFollowTimer.Enabled := True;
  Invalidate;
end;

procedure TFolderTreeController.StepIn;
var
  N: TFolderTreeNode;
begin
  if (FTree.Count = 0) or (FListingPath <> '') then
    Exit;
  N := FTree.Node(FTree.Cursor);
  if N.Expanded then
  begin
    if (FTree.Cursor + 1 < FTree.Count) and
       (FTree.Node(FTree.Cursor + 1).Depth > N.Depth) then
    begin
      FTree.Cursor := FTree.Cursor + 1;
      CursorMoved;
    end;
    Exit;
  end;
  ExpandInBackground(FTree.Cursor);
end;

procedure TFolderTreeController.ExpandInBackground(AIndex: Integer);
var
  N: TFolderTreeNode;
  Gen: Cardinal;
  List: TFolderListFunc;
  Path: string;
  Self_: TFolderTreeController;
  LifeRef: IInterface;
begin
  if (AIndex < 0) or (AIndex >= FTree.Count) or (FListingPath <> '') then
    Exit;
  N := FTree.Node(AIndex);
  if N.Expanded or not N.HasChildren then
    Exit;
  // List the branch in the background (ApplyListing).
  Gen := FGen;
  List := FList;
  Path := N.Path;
  FListingPath := Path;
  Self_ := Self;
  LifeRef := FLifeRef;
  Invalidate;
  TTask.Run(
    procedure
    var
      Entries: TArray<TFolderEntry>;
    begin
      try
        Entries := List(Path);
      except
        Entries := nil;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if IsAlive(LifeRef) then
            Self_.ApplyListing(Gen, Path, Entries);
        end);
    end);
end;

procedure TFolderTreeController.ApplyListing(AGen: Cardinal; const APath: string;
  const AEntries: TArray<TFolderEntry>);
var
  Idx: Integer;
begin
  // The result finds its row by path: other branches may have opened or
  // closed meanwhile.
  if AGen <> FGen then
    Exit;
  FListingPath := '';
  Idx := FTree.IndexOfPath(APath);
  if Idx >= 0 then
    FTree.ExpandWith(Idx, AEntries);
  // Opening a branch keeps the view: the rows under the mouse stay put.
  EnsureScroll(False);
  Invalidate;
end;

function TFolderTreeController.ViewHeight: Integer;
begin
  // Frame top and bottom, and the path line above the bottom frame.
  Result := Max(FBounds.Height - 3, 1);
end;

procedure TFolderTreeController.EnsureScroll(AShowCursor: Boolean);
var
  ViewH: Integer;
begin
  FBounds := FGetPanelBounds(FSide);
  ViewH := ViewHeight;
  if AShowCursor then
  begin
    if FTree.Cursor < FScroll then
      FScroll := FTree.Cursor;
    if FTree.Cursor >= FScroll + ViewH then
      FScroll := FTree.Cursor - ViewH + 1;
  end;
  FScroll := EnsureRange(FScroll, 0, Max(FTree.Count - ViewH, 0));
end;

procedure TFolderTreeController.ScrollBy(ADelta: Integer);
begin
  if not FVisible or FLoading then
    Exit;
  Inc(FScroll, ADelta);
  EnsureScroll(False);
  Invalidate;
end;

procedure TFolderTreeController.Draw(const AGrid: TTerminalGrid; AFocused: Boolean);
var
  R: TRectI;
  I, Y, Idx, InnerW, ListTop, ListBottom, ViewH, StatusY, ScrollX: Integer;
  Line, Status: string;
  Fg, Bg, TabFg, TabBg: TAlphaColor;
  TL, TR, BL, BR, HC, VC: Char;

  // Folder rows look like directories in the panel, in the theme's colours.
  procedure RowColors(ACursor: Boolean);
  begin
    if Assigned(FTheme) then
      FTheme.ResolveFileRowColors(True, False, False, '', False, ACursor, AFocused, Fg, Bg)
    else if ACursor and AFocused then
    begin
      Fg := cCursorFg;
      Bg := cCursorBg;
    end
    else
    begin
      Fg := cDirFg;
      Bg := cPanelBg;
    end;
  end;

begin
  FDrawing := True;
  try
    CheckOwner;
    if FVisible then
      SyncWithOther;
  finally
    FDrawing := False;
  end;
  if not FVisible then
    Exit;
  EnsureScroll(False);
  R := FBounds;
  if (R.Width < 12) or (R.Height < 5) then
    Exit;
  // Drawn as the panel it covers: its frame, its title bar colours.
  if Assigned(FTheme) then
  begin
    FTheme.DrawPanelFrame(AGrid, R, AFocused, []);
    FTheme.ResolvePanelChromeColors(pcpPanelTabActive, AFocused, TabFg, TabBg);
  end
  else
  begin
    PanelFrameGlyphs(AFocused, TL, TR, BL, BR, HC, VC);
    DrawPanelFrameGlyphs(AGrid, R, TL, TR, BL, BR, HC, VC, cFrameFg, cDirFg, cPanelBg);
    TabFg := cCursorFg;
    TabBg := cCursorBg;
  end;
  DrawCenteredPanelTitle(AGrid, R, ' ' + T('ui.folderTree.title', 'Tree') + ' ',
    TabFg, TabBg);
  ListTop := R.Top + 1;
  StatusY := R.Bottom - 1;
  ListBottom := StatusY - 1;
  ViewH := Max(ListBottom - ListTop + 1, 1);
  ScrollX := R.Right - 1;
  InnerW := Max(ScrollX - (R.Left + 1), 4);
  for I := 0 to ViewH - 1 do
  begin
    Y := ListTop + I;
    Idx := FScroll + I;
    if (not FLoading) and (Idx < FTree.Count) then
    begin
      Line := FTree.LinePrefix(Idx) + FTree.Node(Idx).Name;
      if Length(Line) > InnerW then
        Line := Copy(Line, 1, InnerW);
      Line := Line + StringOfChar(' ', InnerW - Length(Line));
      RowColors(Idx = FTree.Cursor);
    end
    else
    begin
      Line := StringOfChar(' ', InnerW);
      RowColors(False);
    end;
    PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);
  end;
  if (ScrollX > R.Left) and not FLoading then
    DrawPanelScrollBar(AGrid, ScrollX, ListTop, ListBottom, FScroll,
      FTree.Count, ViewH, FTheme, False);
  // The cursor folder's full path, its end kept when it does not fit.
  if FLoading or (FListingPath <> '') then
    Status := T('ui.folderTree.reading', 'Reading...')
  else
    Status := FTree.CursorPath;
  if Length(Status) > InnerW then
    Status := '...' + Copy(Status, Length(Status) - InnerW + 4, MaxInt);
  Status := Status + StringOfChar(' ', InnerW - Length(Status));
  // The panel's own bottom line (the cursor file strip) colours.
  if Assigned(FTheme) then
    FTheme.ResolvePanelChromeColors(pcpInfoStrip, AFocused, Fg, Bg)
  else
    RowColors(False);
  PutGridText(AGrid, R.Left + 1, StatusY, Status, Fg, Bg);
  if ScrollX > R.Left then
    DrawGridChar(AGrid, ScrollX, StatusY, ' ', Fg, Bg);
end;

function TFolderTreeController.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Path: string;
begin
  Result := True;
  if (AKey = vkEscape) or ((AKey = vkF10) and (ssAlt in AShift)) then
    Close
  else if FLoading then
    // Nothing to walk yet: only Esc / Alt+F10 act while the tree builds.
  else if AKey = vkReturn then
  begin
    Path := FTree.CursorPath;
    Close;
    if (Path <> '') and Assigned(FOnNavigate) then
      FOnNavigate(FSide, PathToFileUri(Path));
  end
  else if AKey = vkUp then
  begin
    FTree.Cursor := FTree.Cursor - 1;
    CursorMoved;
  end
  else if AKey = vkDown then
  begin
    FTree.Cursor := FTree.Cursor + 1;
    CursorMoved;
  end
  else if AKey = vkPrior then
  begin
    FTree.Cursor := FTree.Cursor - ViewHeight;
    CursorMoved;
  end
  else if AKey = vkNext then
  begin
    FTree.Cursor := FTree.Cursor + ViewHeight;
    CursorMoved;
  end
  else if AKey = vkHome then
  begin
    FTree.Cursor := 0;
    CursorMoved;
  end
  else if AKey = vkEnd then
  begin
    FTree.Cursor := FTree.Count - 1;
    CursorMoved;
  end
  else if (AKey = vkRight) or (AKey = vkAdd) or (AKeyChar = '+') then
    StepIn
  else if (AKey = vkLeft) or (AKey = vkSubtract) or (AKeyChar = '-') then
  begin
    FTree.StepOut;
    CursorMoved;
  end
  else if (AKeyChar > ' ') and (AShift * [ssCtrl, ssAlt] = []) and
     FTree.JumpToLetter(AKeyChar) then
    CursorMoved;
  // The tree owns the keyboard while it is open.
  AKey := 0;
  AKeyChar := #0;
end;

function TFolderTreeController.HandleClick(ALocalCol, ALocalRow: Integer): TFolderTreeClick;
var
  Idx, ListTop, ListBottom, MarkStart: Integer;
  N: TFolderTreeNode;
begin
  if not FVisible or not FBounds.Contains(ALocalCol, ALocalRow) then
    Exit(ftcOutside);
  if WindowFrameCloseHit(FBounds, ALocalCol, ALocalRow) then
  begin
    Close;
    Exit(ftcKeep);
  end;
  ListTop := FBounds.Top + 1;
  ListBottom := FBounds.Bottom - 2;
  // The frame, the title, the path line: the tree takes the focus.
  if FLoading or (ALocalRow < ListTop) or (ALocalRow > ListBottom) or
     (ALocalCol <= FBounds.Left) or (ALocalCol >= FBounds.Right - 1) then
    Exit(ftcFocusTree);
  Idx := FScroll + ALocalRow - ListTop;
  if Idx >= FTree.Count then
    Exit(ftcKeep);
  N := FTree.Node(Idx);
  // "[+]" / "[-]" sit right after the connector: four cells per level
  // before it, the row text starting one cell right of the frame.
  MarkStart := FBounds.Left + 1 + (N.Depth - 1) * 4 + 1;
  if (N.Depth > 0) and N.HasChildren and (ALocalCol >= MarkStart) and
     (ALocalCol <= MarkStart + 2) then
  begin
    if N.Expanded then
      FTree.Collapse(Idx)
    else
      ExpandInBackground(Idx);
    EnsureScroll(False);
    Invalidate;
    Exit(ftcKeep);
  end;
  // A folder: the other panel shows it now, no pause.
  FTree.Cursor := Idx;
  FFollowTimer.Enabled := False;
  FFollowed := N.Path;
  if Assigned(FOnNavigate) then
    FOnNavigate(OtherSide(FSide), PathToFileUri(N.Path));
  EnsureScroll;
  Invalidate;
  Result := ftcFocusFiles;
end;

end.
