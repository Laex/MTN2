unit uDiskMapTree;

{ Disk usage tree of a local folder and the background scan that builds it.

  The scan runs in a worker thread and fills the tree in place, folder by folder
  and level by level; the sizes of a folder and of all its parents grow as its
  contents are found. The reader (the thread that draws) takes Lock around every
  read of the tree, and the worker around every change of it. A folder whose
  contents are not listed yet has no children and is not Done. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults, System.SyncObjs, System.Diagnostics;

type
  TDiskNode = class
  public
    Name: string;
    /// <summary>Bytes found so far; final once the scan has finished.</summary>
    Size: Int64;
    IsDir: Boolean;
    /// <summary>Stands for the small files (and the folders below the kept
    /// depth) of its folder that have no node of their own.</summary>
    IsRest: Boolean;
    /// <summary>The folder's contents are listed (always true for a file).</summary>
    Done: Boolean;
    Parent: TDiskNode;
    /// <summary>Largest first once the folder is Done; nil for a file.</summary>
    Children: TObjectList<TDiskNode>;
    constructor Create(const AName: string; AIsDir: Boolean);
    destructor Destroy; override;
    procedure AddChild(ANode: TDiskNode);
    procedure SortChildren;
    /// <summary>The size to draw: what the scan has found so far.</summary>
    function ShownSize: Int64;
  end;

  TDiskLimits = record
    /// <summary>Seconds after which the scan stops and keeps what it has.</summary>
    MaxSeconds: Integer;
    /// <summary>Files and folders after which the scan stops.</summary>
    MaxEntries: Int64;
    /// <summary>Folder levels that get nodes; deeper folders only add to their parent.</summary>
    KeepDepth: Integer;
    /// <summary>Largest files kept per folder; the rest become one "rest" node.</summary>
    FilesPerDir: Integer;
    class function Standard: TDiskLimits; static;
  end;

  TDiskScan = class;

  /// <summary>A folder waiting to be listed.</summary>
  TScanItem = record
    Node: TDiskNode;
    Path: string;
    Depth: Integer;
  end;

  IDiskScan = interface
    ['{5B1D2C84-7E49-4A0F-9C36-2D8E41B7A0F5}']
    function Scan: TDiskScan;
  end;

  TDiskScan = class(TInterfacedObject, IDiskScan)
  strict private
    FPath: string;
    FLimits: TDiskLimits;
    FRoot: TDiskNode;
    FLock: TCriticalSection;
    FEntries: Int64;
    FCancel: Integer;
    FFinished: Integer;
    FTruncated: Integer;
    FStarted: Boolean;
    FFinishedAt: TDateTime;
    FWatch: TStopwatch;
    function Stopped: Boolean;
    function RestNode(ANode: TDiskNode): TDiskNode;
    procedure AddUp(ANode: TDiskNode; ABytes: Int64);
    procedure AddToRest(ANode: TDiskNode; ABytes: Int64);
    procedure SumTree(const APath: string; ANode: TDiskNode; var APending: Int64;
      var ACount: Integer);
    procedure ProcessDir(const AItem: TScanItem; AQueue: TQueue<TScanItem>);
    procedure FinishTree(ANode: TDiskNode);
  public
    constructor Create(const APath: string; const ALimits: TDiskLimits);
    destructor Destroy; override;
    function Scan: TDiskScan;
    /// <summary>Starts the worker thread; once only.</summary>
    procedure Start;
    /// <summary>Scans in the calling thread.</summary>
    procedure RunSync;
    /// <summary>Worker body; called by the scan thread.</summary>
    procedure Run;
    /// <summary>Asks the worker to stop; it ends on its own soon after.</summary>
    procedure Cancel;
    procedure Lock;
    procedure Unlock;
    function Finished: Boolean;
    /// <summary>A limit stopped the scan, so the sizes are lower bounds.</summary>
    function Truncated: Boolean;
    function Entries: Int64;
    property Path: string read FPath;
    property Root: TDiskNode read FRoot;
    property FinishedAt: TDateTime read FFinishedAt;
  end;

/// <summary>"1.5 GB", "320 KB", "17 B".</summary>
function FormatBytes(ABytes: Int64): string;

implementation

uses
  System.Math;

const
  // Files added up below the kept depth before their total is put into the tree.
  cBatchFiles = 500;

type
  TFoundFile = record
    Name: string;
    Size: Int64;
  end;

  TScanThread = class(TThread)
  strict private
    FScan: TDiskScan;
    FHold: IDiskScan;
  protected
    procedure Execute; override;
  public
    constructor Create(const AScan: IDiskScan);
  end;

{ TDiskNode }

constructor TDiskNode.Create(const AName: string; AIsDir: Boolean);
begin
  inherited Create;
  Name := AName;
  IsDir := AIsDir;
  Done := not AIsDir;
  if AIsDir then
    Children := TObjectList<TDiskNode>.Create(True);
end;

destructor TDiskNode.Destroy;
begin
  Children.Free;
  inherited;
end;

procedure TDiskNode.AddChild(ANode: TDiskNode);
begin
  ANode.Parent := Self;
  Children.Add(ANode);
end;

procedure TDiskNode.SortChildren;
begin
  if Children = nil then
    Exit;
  Children.Sort(TComparer<TDiskNode>.Construct(
    function(const A, B: TDiskNode): Integer
    begin
      Result := Sign(B.Size - A.Size);
      if Result = 0 then
        Result := CompareText(A.Name, B.Name);
    end));
end;

function TDiskNode.ShownSize: Int64;
begin
  Result := Size;
end;

{ TDiskLimits }

class function TDiskLimits.Standard: TDiskLimits;
begin
  Result.MaxSeconds := 30;
  Result.MaxEntries := 3000000;
  Result.KeepDepth := 6;
  Result.FilesPerDir := 40;
end;

{ TScanThread }

constructor TScanThread.Create(const AScan: IDiskScan);
begin
  FHold := AScan;
  FScan := AScan.Scan;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TScanThread.Execute;
begin
  try
    FScan.Run;
  finally
    // The last reference may go here; the tree is freed by the worker.
    FHold := nil;
  end;
end;

{ TDiskScan }

constructor TDiskScan.Create(const APath: string; const ALimits: TDiskLimits);
begin
  inherited Create;
  FPath := ExcludeTrailingPathDelimiter(APath);
  if FPath = '' then
    FPath := APath;
  FLimits := ALimits;
  FLock := TCriticalSection.Create;
  FRoot := TDiskNode.Create('', True);
end;

destructor TDiskScan.Destroy;
begin
  FRoot.Free;
  FLock.Free;
  inherited;
end;

function TDiskScan.Scan: TDiskScan;
begin
  Result := Self;
end;

procedure TDiskScan.Lock;
begin
  FLock.Enter;
end;

procedure TDiskScan.Unlock;
begin
  FLock.Leave;
end;

function TDiskScan.Finished: Boolean;
begin
  Result := TInterlocked.CompareExchange(FFinished, 0, 0) <> 0;
end;

function TDiskScan.Truncated: Boolean;
begin
  Result := TInterlocked.CompareExchange(FTruncated, 0, 0) <> 0;
end;

function TDiskScan.Entries: Int64;
begin
  Result := TInterlocked.Read(FEntries);
end;

procedure TDiskScan.Cancel;
begin
  TInterlocked.Exchange(FCancel, 1);
end;

function TDiskScan.Stopped: Boolean;
begin
  if TInterlocked.CompareExchange(FCancel, 0, 0) <> 0 then
    Exit(True);
  Result := (FWatch.Elapsed.TotalSeconds > FLimits.MaxSeconds) or
    (TInterlocked.Read(FEntries) > FLimits.MaxEntries);
  if Result then
    TInterlocked.Exchange(FTruncated, 1);
end;

function TDiskScan.RestNode(ANode: TDiskNode): TDiskNode;
var
  I: Integer;
begin
  for I := ANode.Children.Count - 1 downto 0 do
    if ANode.Children[I].IsRest then
      Exit(ANode.Children[I]);
  Result := TDiskNode.Create('', False);
  Result.IsRest := True;
  ANode.AddChild(Result);
end;

procedure TDiskScan.AddUp(ANode: TDiskNode; ABytes: Int64);
begin
  while ANode <> nil do
  begin
    Inc(ANode.Size, ABytes);
    ANode := ANode.Parent;
  end;
end;

procedure TDiskScan.AddToRest(ANode: TDiskNode; ABytes: Int64);
begin
  if ABytes <= 0 then
    Exit;
  Lock;
  try
    Inc(RestNode(ANode).Size, ABytes);
    AddUp(ANode, ABytes);
  finally
    Unlock;
  end;
end;

{ Adds up everything below a folder that has no nodes of its own. The total
  reaches the tree in batches, so a large subtree grows on screen while it is
  read. }
procedure TDiskScan.SumTree(const APath: string; ANode: TDiskNode; var APending: Int64;
  var ACount: Integer);
var
  SR: TSearchRec;
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(APath);
  if FindFirst(Base + '*', faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if Stopped then
        Break;
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
{$WARN SYMBOL_PLATFORM OFF}
      if ((SR.Attr and faSymLink) <> 0) and ((SR.Attr and faDirectory) <> 0) then
        Continue;
{$WARN SYMBOL_PLATFORM ON}
      TInterlocked.Increment(FEntries);
      if (SR.Attr and faDirectory) <> 0 then
        SumTree(Base + SR.Name, ANode, APending, ACount)
      else
      begin
        Inc(APending, SR.Size);
        Inc(ACount);
        if ACount >= cBatchFiles then
        begin
          AddToRest(ANode, APending);
          APending := 0;
          ACount := 0;
        end;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ Lists one folder, then puts what it found into the tree under the lock: the
  largest files and the subfolders get nodes (the subfolders are queued to be
  listed in their turn), the other files and the folders below the kept depth
  are folded into one "rest" node. }
procedure TDiskScan.ProcessDir(const AItem: TScanItem; AQueue: TQueue<TScanItem>);
var
  SR: TSearchRec;
  Base: string;
  Files: TList<TFoundFile>;
  Dirs, Deep: TList<string>;
  RestSize, Delta, Pending: Int64;
  F: TFoundFile;
  D: string;
  Sub: TDiskNode;
  Next: TScanItem;
  Count: Integer;

  procedure Prune(AKeep: Integer);
  var
    I: Integer;
  begin
    if Files.Count <= AKeep then
      Exit;
    Files.Sort(TComparer<TFoundFile>.Construct(
      function(const A, B: TFoundFile): Integer
      begin
        Result := Sign(B.Size - A.Size);
      end));
    for I := AKeep to Files.Count - 1 do
      Inc(RestSize, Files[I].Size);
    Files.DeleteRange(AKeep, Files.Count - AKeep);
  end;

begin
  Files := TList<TFoundFile>.Create;
  Dirs := TList<string>.Create;
  Deep := TList<string>.Create;
  try
    RestSize := 0;
    Base := IncludeTrailingPathDelimiter(AItem.Path);
    if FindFirst(Base + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if Stopped then
          Break;
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        // A folder link or junction would count its target twice or loop.
{$WARN SYMBOL_PLATFORM OFF}
        if ((SR.Attr and faSymLink) <> 0) and ((SR.Attr and faDirectory) <> 0) then
          Continue;
{$WARN SYMBOL_PLATFORM ON}
        TInterlocked.Increment(FEntries);
        if (SR.Attr and faDirectory) <> 0 then
          Dirs.Add(SR.Name)
        else
        begin
          F.Name := SR.Name;
          F.Size := SR.Size;
          Files.Add(F);
          if Files.Count > FLimits.FilesPerDir * 4 then
            Prune(FLimits.FilesPerDir);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    Prune(FLimits.FilesPerDir);

    Lock;
    try
      Delta := RestSize;
      for F in Files do
      begin
        Sub := TDiskNode.Create(F.Name, False);
        Sub.Size := F.Size;
        AItem.Node.AddChild(Sub);
        Inc(Delta, F.Size);
      end;
      if RestSize > 0 then
        Inc(RestNode(AItem.Node).Size, RestSize);
      for D in Dirs do
        if AItem.Depth < FLimits.KeepDepth then
        begin
          Sub := TDiskNode.Create(D, True);
          AItem.Node.AddChild(Sub);
          Next.Node := Sub;
          Next.Path := Base + D;
          Next.Depth := AItem.Depth + 1;
          AQueue.Enqueue(Next);
        end
        else
          Deep.Add(Base + D);
      AItem.Node.Done := True;
      AddUp(AItem.Node, Delta);
    finally
      Unlock;
    end;

    Pending := 0;
    Count := 0;
    for D in Deep do
    begin
      if Stopped then
        Break;
      SumTree(D, AItem.Node, Pending, Count);
    end;
    AddToRest(AItem.Node, Pending);
  finally
    Deep.Free;
    Dirs.Free;
    Files.Free;
  end;
end;

procedure TDiskScan.FinishTree(ANode: TDiskNode);
var
  Kid: TDiskNode;
begin
  ANode.Done := True;
  if ANode.Children = nil then
    Exit;
  for Kid in ANode.Children do
    FinishTree(Kid);
  ANode.SortChildren;
end;

{ Folders are listed level by level, so the big blocks show up first and the
  detail fills in below them; the tree is readable (under the lock) at any
  moment. }
procedure TDiskScan.Run;
var
  Queue: TQueue<TScanItem>;
  Item: TScanItem;
begin
  Queue := TQueue<TScanItem>.Create;
  try
    try
      FWatch := TStopwatch.StartNew;
      Item.Node := FRoot;
      Item.Path := FPath;
      Item.Depth := 0;
      Queue.Enqueue(Item);
      while (Queue.Count > 0) and not Stopped do
        ProcessDir(Queue.Dequeue, Queue);
      Lock;
      try
        FinishTree(FRoot);
      finally
        Unlock;
      end;
    finally
      FFinishedAt := Now;
      TInterlocked.Exchange(FFinished, 1);
    end;
  finally
    Queue.Free;
  end;
end;

procedure TDiskScan.RunSync;
begin
  FStarted := True;
  Run;
end;

procedure TDiskScan.Start;
begin
  if FStarted then
    Exit;
  FStarted := True;
  TScanThread.Create(Self);
end;

function FormatBytes(ABytes: Int64): string;
const
  Units: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  V: Double;
  U: Integer;
begin
  if ABytes < 1024 then
    Exit(IntToStr(ABytes) + ' B');
  V := ABytes;
  U := 0;
  while (V >= 1024) and (U < High(Units)) do
  begin
    V := V / 1024;
    Inc(U);
  end;
  if V >= 100 then
    Result := Format('%.0f %s', [V, Units[U]], TFormatSettings.Invariant)
  else
    Result := Format('%.1f %s', [V, Units[U]], TFormatSettings.Invariant);
end;

end.
