unit uEditorDoc;

{ In-memory text document for Editor (Stage 10). Loads/saves small files via
  async VFS. Dirty flag tracks unsaved edits. Raw bytes kept for F8 re-decode.

  Live reload: a local (non-streaming) file is watched via TDirectoryWatcher
  (uDirWatch) — its containing directory, since Windows has no lightweight
  single-file change notification — and silently re-read whenever the file's
  on-disk size/write-time no longer match what was last loaded or saved
  (FKnownSize/FKnownWriteTime double as the guard against reacting to our
  own SaveAsync writing the file: right after a save they're updated to
  match, so the watcher notification that follows sees no difference and
  is a no-op). Only fires when there are no unsaved edits (FDirty) — an
  edit in progress is never silently discarded. ContentGen (FGen, already
  used to guard stale async completions) doubles as a change counter the
  Viewer/Editor can compare against to know when its own per-line caches
  (markdown fence index, wrapped-row cache) need invalidating. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uVfsTypes, uTextEncoding, uDirWatch;

const
  cEditorMaxBytes = 16 * 1024 * 1024; // 16 MB — F3 View whole-buffer limit
  cEditorEditMaxBytes = 256 * 1024 * 1024; // 256 MB — F4 in-RAM edit cap
  cStreamSampleBytes = 65536;        // sample read for encoding/binary sniff before indexing
  cStreamScanChunk = 1024 * 1024;    // read buffer while scanning for line offsets
  cStreamCacheCap = 4000;            // decoded-line cache size (FIFO eviction)

type
  TFileStatCallback = reference to procedure(AExists: Boolean; ASize: Int64; AWriteTime: TDateTime);

  TEditorDoc = class
  private
    FVfs: IVirtualFileSystem;
    FURI: string;
    FPath: string;
    FLines: TList<string>;
    FRawBytes: TBytes;
    FReady: Boolean;
    FLoading: Boolean;
    FSaving: Boolean;
    FDirty: Boolean;
    FReadOnly: Boolean;
    FCrlf: Boolean;
    FEncoding: TTextFileEncoding;
    FBinary: Boolean;
    FError: string;
    FStatus: string;
    FGen: Cardinal;
    FSaveGen: Cardinal;
    FCancel: IJobCancelToken;
    FOnChanged: TNotifyEvent;
    // Stage 24: streaming Viewer for local text files too big for whole-buffer
    // load (cEditorMaxBytes). View-only — FReadOnly is forced True. FLines
    // stays empty in this mode; lines are seeked/decoded on demand from
    // FStreamPath using FLineOffsets and cached in FLineCache.
    FStreaming: Boolean;
    FStreamPath: string;
    // True when FStreamPath is a temp file extracted from an archive entry
    // for streaming (Stage: archive streaming) — Close must delete it. False
    // for a plain local file, where FStreamPath is the user's own file.
    FStreamPathIsTemp: Boolean;
    FStreamEncoding: TTextFileEncoding;
    FStreamFileSize: Int64;
    FLineOffsets: TArray<Int64>;   // byte offset of each line start; last entry is a file-size sentinel
    FLineCache: TDictionary<Integer, string>;
    FLineCacheOrder: TQueue<Integer>;
    FWantEdit: Boolean;
    // Live reload (see file header comment).
    FWatcher: TDirectoryWatcher;
    FKnownSize: Int64;
    FKnownWriteTime: TDateTime;
    procedure NotifyChanged;
    procedure ApplyLoadedText(const AText: string);
    function BuildSaveText: string;
    procedure RefreshReadOnly;
    procedure ScanFileForStreaming(const APath: string; const ACancel: IJobCancelToken;
      out AErr: string; out AHexMode: Boolean; out AHexBuf: TBytes;
      out AOffsets: TArray<Int64>; out ADetEnc: TTextFileEncoding; out ASize: Int64);
    function BuildStreamingLineOffsets(FS: TFileStream; ASize: Int64;
      ADetEnc: TTextFileEncoding; const ACancel: IJobCancelToken;
      out AErr: string): TArray<Int64>;
    procedure StartStreamingOpen(const APath: string; AGen: Cardinal);
    procedure StartStreamingOpenFromArchive(const AURI: string; AGen: Cardinal);
    function StreamingGetLine(AIndex: Integer): string;
    procedure CacheLine(AIndex: Integer; const AValue: string);
    // Stats APath (Exists/GetSize/GetLastWriteTime) on a background thread
    // and delivers the result back via AOnDone on the main thread — never
    // call TFile.Exists/GetSize/GetLastWriteTime directly here (see
    // RefreshReadOnly's note on why). Silently reports AExists=False on any
    // stat failure (e.g. a momentarily-locked/unreachable path) rather than
    // raising, and drops the result entirely if AGen no longer matches
    // FGen (a newer Open/Close/reload started while the stat was in flight).
    procedure StatFileAsync(const APath: string; AGen: Cardinal; const AOnDone: TFileStatCallback);
    procedure RecordKnownFileStat;
    procedure StartWatchingCurrentFile;
    function CanReloadFromDisk: Boolean;
    procedure CheckExternalChange;
    procedure ReloadFromDisk;
    /// <summary>Shift+F4 / edit of a path that does not exist yet: empty
    /// UTF-8 buffer, not dirty. SaveAsync creates the file; discard leaves
    /// nothing on disk.</summary>
    procedure BeginEmptyNewFile;
  public
    constructor Create;
    destructor Destroy; override;
    procedure OpenAsync(const AURI: string; AWantEdit: Boolean = False);
    procedure Close;
    procedure SaveAsync(ARawBytes: Boolean = False);
    function TryPromoteStreaming: Boolean;
    function TryClearOsReadOnly(out AError: string): Boolean;
    /// <summary>Set encoding; when ARedecode, rebuild lines from FRawBytes.</summary>
    function ApplyEncoding(AEncoding: TTextFileEncoding; ARedecode: Boolean): Boolean;
    function LineCount: Integer;
    function GetLine(AIndex: Integer): string;
    procedure SetLine(AIndex: Integer; const AValue: string);
    procedure EnsureLine(AIndex: Integer);
    procedure InsertLine(AIndex: Integer; const AValue: string);
    procedure DeleteLine(AIndex: Integer);
    procedure MarkDirty;
    function SnapshotLines: TArray<string>;
    procedure RestoreLines(const ALines: TArray<string>; AMarkDirty: Boolean);
    function ByteCount: Integer;
    function GetByte(AIndex: Integer): Byte;
    procedure SetByte(AIndex: Integer; AValue: Byte);
    procedure InsertByte(AIndex: Integer; AValue: Byte);
    procedure DeleteByte(AIndex: Integer);
    function SnapshotBytes: TBytes;
    procedure RestoreBytes(const ABytes: TBytes; AMarkDirty: Boolean);
    property URI: string read FURI;
    property Path: string read FPath;
    property Ready: Boolean read FReady;
    property Loading: Boolean read FLoading;
    property Saving: Boolean read FSaving;
    property Dirty: Boolean read FDirty;
    property ReadOnly: Boolean read FReadOnly;
    property Binary: Boolean read FBinary;
    /// <summary>Stage 24: line-indexed view of a file too big for the
    /// whole-buffer load. Read-only until TryPromoteStreaming.</summary>
    property Streaming: Boolean read FStreaming;
    property StreamFileSize: Int64 read FStreamFileSize;
    property Encoding: TTextFileEncoding read FEncoding;
    property Error: string read FError;
    property Status: string read FStatus;
    /// <summary>Bumps every time the in-memory content is (re)loaded from
    /// disk — a fresh Open, a re-decode, or a live-reload triggered by an
    /// external change. A caller with its own per-line cache derived from
    /// this document's content (e.g. the Markdown Viewer's fence index and
    /// wrapped-row cache) can compare this against what it last saw to know
    /// when to invalidate, without reacting to every unrelated OnChanged
    /// tick (dirty-flag toggling, saving, ...).</summary>
    property ContentGen: Cardinal read FGen;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.IOUtils,
  uVfsRegistry;

constructor TEditorDoc.Create;
begin
  inherited Create;
  FVfs := CreateDefaultVfs;
  FLines := TList<string>.Create;
  FLineCache := TDictionary<Integer, string>.Create;
  FLineCacheOrder := TQueue<Integer>.Create;
  FEncoding := tfeUtf8;
  FBinary := False;
  SetLength(FRawBytes, 0);
  FWatcher := TDirectoryWatcher.Create;
  FWatcher.OnChanged := CheckExternalChange;
end;

destructor TEditorDoc.Destroy;
begin
  Close;
  if Assigned(FWatcher) then
  begin
    FWatcher.OnChanged := nil;
    FreeAndNil(FWatcher);
  end;
  FreeAndNil(FLines);
  FreeAndNil(FLineCache);
  FreeAndNil(FLineCacheOrder);
  FVfs := nil;
  inherited Destroy;
end;

procedure TEditorDoc.NotifyChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TEditorDoc.Close;
begin
  if Assigned(FCancel) then
    FCancel.Cancel;
  FCancel := nil;
  Inc(FGen);
  Inc(FSaveGen);
  FURI := '';
  FPath := '';
  FLines.Clear;
  SetLength(FRawBytes, 0);
  FReady := False;
  FLoading := False;
  FSaving := False;
  FDirty := False;
  FReadOnly := False;
  FWantEdit := False;
  FCrlf := True;
  FEncoding := tfeUtf8;
  FBinary := False;
  FError := '';
  FStatus := '';
  FStreaming := False;
  if FStreamPathIsTemp and (FStreamPath <> '') then
    try
      TFile.Delete(WinApiPath(FStreamPath));
    except
      // best-effort cleanup
    end;
  FStreamPath := '';
  FStreamPathIsTemp := False;
  FStreamFileSize := 0;
  SetLength(FLineOffsets, 0);
  FLineCache.Clear;
  FLineCacheOrder.Clear;
  FWatcher.SetPath('');
  FKnownSize := 0;
  FKnownWriteTime := 0;
end;

function TEditorDoc.LineCount: Integer;
begin
  if FStreaming then
    Result := Length(FLineOffsets) - 1
  else
    Result := FLines.Count;
end;

function TEditorDoc.GetLine(AIndex: Integer): string;
begin
  if FStreaming then
    Result := StreamingGetLine(AIndex)
  else if (AIndex < 0) or (AIndex >= FLines.Count) then
    Result := ''
  else
    Result := FLines[AIndex];
end;

procedure TEditorDoc.CacheLine(AIndex: Integer; const AValue: string);
begin
  if FLineCache.ContainsKey(AIndex) then
    Exit;
  while (FLineCacheOrder.Count > 0) and (FLineCache.Count >= cStreamCacheCap) do
    FLineCache.Remove(FLineCacheOrder.Dequeue);
  FLineCache.Add(AIndex, AValue);
  FLineCacheOrder.Enqueue(AIndex);
end;

function TEditorDoc.StreamingGetLine(AIndex: Integer): string;
var
  StartOff, EndOff: Int64;
  Len: Integer;
  Buf: TBytes;
  FS: TFileStream;
  S: string;
begin
  if (AIndex < 0) or (AIndex >= Length(FLineOffsets) - 1) then
    Exit('');
  if FLineCache.TryGetValue(AIndex, Result) then
    Exit;

  StartOff := FLineOffsets[AIndex];
  EndOff := FLineOffsets[AIndex + 1];
  Len := EndOff - StartOff;
  if Len < 0 then
    Len := 0;
  SetLength(Buf, Len);
  if Len > 0 then
  begin
    // Local single-line seek+read, synchronous by design: bounded (a few KB
    // at most), fmShareDenyNone, and normally page-cache-backed after the
    // background index scan already touched the whole file once. Kept
    // deliberately synchronous (not routed through async VFS/Jobs) so
    // uEditorWindow.pas's paint path — which calls GetLine per visible row —
    // needs no changes; a fully async per-line fetch would require a
    // placeholder/redraw protocol there instead.
    FS := TFileStream.Create(WinApiPath(FStreamPath), fmOpenRead or fmShareDenyNone);
    try
      FS.Position := StartOff;
      FS.Read(Buf[0], Len);
    finally
      FS.Free;
    end;
    // Offsets mark spans including the trailing line terminator; strip it.
    // UTF-16 lines carry a 2-byte code unit per terminator (see
    // Utf16PairIsLF) — a single trailing byte check would only ever see the
    // unit's zero half and strip nothing, leaving a stray CR/LF in the text.
    if FStreamEncoding = tfeUtf16LE then
      while (Length(Buf) >= 2) and
            ((Buf[High(Buf) - 1] = 10) or (Buf[High(Buf) - 1] = 13)) and (Buf[High(Buf)] = 0) do
        SetLength(Buf, Length(Buf) - 2)
    else if FStreamEncoding = tfeUtf16BE then
      while (Length(Buf) >= 2) and (Buf[High(Buf) - 1] = 0) and
            ((Buf[High(Buf)] = 10) or (Buf[High(Buf)] = 13)) do
        SetLength(Buf, Length(Buf) - 2)
    else
      while (Length(Buf) > 0) and ((Buf[High(Buf)] = 10) or (Buf[High(Buf)] = 13)) do
        SetLength(Buf, Length(Buf) - 1);
  end;
  S := DecodeTextWithEncoding(Buf, FStreamEncoding);
  CacheLine(AIndex, S);
  Result := S;
end;

procedure TEditorDoc.SetLine(AIndex: Integer; const AValue: string);
begin
  if FStreaming then
    Exit; // streaming docs are always read-only; caller must not reach here
  EnsureLine(AIndex);
  if FLines[AIndex] <> AValue then
  begin
    FLines[AIndex] := AValue;
    MarkDirty;
  end;
end;

procedure TEditorDoc.EnsureLine(AIndex: Integer);
begin
  while FLines.Count <= AIndex do
    FLines.Add('');
end;

procedure TEditorDoc.InsertLine(AIndex: Integer; const AValue: string);
begin
  if FStreaming then
    Exit;
  if AIndex < 0 then
    AIndex := 0;
  if AIndex > FLines.Count then
    AIndex := FLines.Count;
  FLines.Insert(AIndex, AValue);
  MarkDirty;
end;

procedure TEditorDoc.DeleteLine(AIndex: Integer);
begin
  if FStreaming then
    Exit;
  if (AIndex < 0) or (AIndex >= FLines.Count) then
    Exit;
  FLines.Delete(AIndex);
  if FLines.Count = 0 then
    FLines.Add('');
  MarkDirty;
end;

procedure TEditorDoc.MarkDirty;
begin
  if not FDirty then
  begin
    FDirty := True;
    NotifyChanged;
  end
  else
    NotifyChanged;
end;

function TEditorDoc.SnapshotLines: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FLines.Count);
  for I := 0 to FLines.Count - 1 do
    Result[I] := FLines[I];
end;

procedure TEditorDoc.RestoreLines(const ALines: TArray<string>; AMarkDirty: Boolean);
var
  I: Integer;
begin
  FLines.Clear;
  if Length(ALines) = 0 then
    FLines.Add('')
  else
    for I := 0 to High(ALines) do
      FLines.Add(ALines[I]);
  if AMarkDirty then
    FDirty := True;
  NotifyChanged;
end;

procedure TEditorDoc.RefreshReadOnly;
var
  Path: string;
  Gen: Cardinal;
begin
  // Streaming docs (Stage 24) are always view-only; StartStreamingOpen
  // already forces FReadOnly := True and never calls this method, but keep
  // the guard for any future caller.
  if FStreaming then
  begin
    FReadOnly := True;
    Exit;
  end;
  // Archive entries cannot be written back (Stage 14).
  if HasArchiveChain(FURI) then
  begin
    FReadOnly := True;
    Exit;
  end;
  // Never call sync Exists/GetAttributes on the UI thread.
  Path := FPath;
  Gen := FGen;
  if Path = '' then
  begin
    FReadOnly := False;
    Exit;
  end;
  TThread.CreateAnonymousThread(
    procedure
    var
      Ro: Boolean;
      {$WARN SYMBOL_PLATFORM OFF}
      Attrs: TFileAttributes;
      {$WARN SYMBOL_PLATFORM ON}
    begin
      Ro := False;
      try
        if TFile.Exists(WinApiPath(Path)) then
        begin
          {$WARN SYMBOL_PLATFORM OFF}
          Attrs := TFile.GetAttributes(WinApiPath(Path));
          Ro := TFileAttribute.faReadOnly in Attrs;
          {$WARN SYMBOL_PLATFORM ON}
        end;
      except
        Ro := False;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Gen <> FGen then
            Exit;
          FReadOnly := Ro;
          if FReady then
          begin
            if Ro then
              FStatus := 'Read-only'
            else if FStatus = 'Read-only' then
              FStatus := '';
            NotifyChanged;
          end;
        end);
    end).Start;
end;

procedure TEditorDoc.StatFileAsync(const APath: string; AGen: Cardinal;
  const AOnDone: TFileStatCallback);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Sz: Int64;
      Wt: TDateTime;
      Ex: Boolean;
    begin
      Sz := 0;
      Wt := 0;
      Ex := False;
      try
        Ex := TFile.Exists(WinApiPath(APath));
        if Ex then
        begin
          Sz := TFile.GetSize(WinApiPath(APath));
          Wt := TFile.GetLastWriteTime(WinApiPath(APath));
        end;
      except
        Ex := False;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if AGen <> FGen then
            Exit;
          AOnDone(Ex, Sz, Wt);
        end);
    end).Start;
end;

procedure TEditorDoc.RecordKnownFileStat;
begin
  if FPath = '' then
    Exit;
  StatFileAsync(FPath, FGen,
    procedure(AExists: Boolean; ASize: Int64; AWriteTime: TDateTime)
    begin
      if AExists then
      begin
        FKnownSize := ASize;
        FKnownWriteTime := AWriteTime;
      end;
    end);
end;

// Only a genuine local file backs a real directory to watch — archive
// entries and streamed-from-archive temp copies aren't worth following.
// Streaming docs (Stage 24) are excluded too: reacting to an external
// change there means rescanning the whole file for FLineOffsets, a much
// bigger job than a plain reload — out of scope for now.
procedure TEditorDoc.StartWatchingCurrentFile;
begin
  if FStreaming or FBinary or HasArchiveChain(FURI) or (FPath = '') then
  begin
    FWatcher.SetPath('');
    Exit;
  end;
  FWatcher.SetPath(ExtractFileDir(FPath));
end;

// True when it's safe to (re-)read the current file from disk in place:
// fully loaded, no load/save in flight, no unsaved edits, not a
// streaming/binary doc, and there's actually a local path to read.
function TEditorDoc.CanReloadFromDisk: Boolean;
begin
  Result := FReady and not FLoading and not FSaving and not FDirty and
    not FStreaming and not FBinary and (FPath <> '');
end;

// TDirectoryWatcher.OnChanged — already marshaled to the main thread (see
// uDirWatch). Fires on ANY change in the file's directory, not just this
// file, so this always re-stats before deciding anything.
procedure TEditorDoc.CheckExternalChange;
begin
  if not CanReloadFromDisk then
    Exit;
  StatFileAsync(FPath, FGen,
    procedure(AExists: Boolean; ASize: Int64; AWriteTime: TDateTime)
    begin
      // FKnownSize/FKnownWriteTime were set to match what we last loaded OR
      // saved — if the file on disk is still exactly that, there's nothing
      // to do (this is what makes SaveAsync's own write a no-op here too,
      // not just a genuinely external one).
      if AExists and ((ASize <> FKnownSize) or (AWriteTime <> FKnownWriteTime)) then
        ReloadFromDisk;
    end);
end;

// Silently re-reads the current file and replaces the in-memory content —
// only ever called with no unsaved edits (FDirty), so there's nothing to
// lose. Deliberately does NOT go through Close/the FReady:=False "Loading"
// state OpenAsync uses for a fresh open: staying FReady=True throughout
// means TEditorWindow.DocChanged's cursor-clamp never sees a not-ready
// document and never resets the cursor to (0,0) — the existing
// ClampCursor/EnsureCursorVisible calls it already makes on every
// OnChanged tick are exactly what re-clamps the view to content that may
// now be shorter/longer, so no separate scroll-position bookkeeping is
// needed here.
procedure TEditorDoc.ReloadFromDisk;
var
  Gen: Cardinal;
  URI: string;
  Cancel: IJobCancelToken;
  MaxBytes: Int64;
begin
  if not CanReloadFromDisk then
    Exit;
  Inc(FGen);
  Gen := FGen;
  URI := FURI;
  Cancel := TJobCancelToken.Create;
  FCancel := Cancel;
  if FWantEdit then
    MaxBytes := cEditorEditMaxBytes
  else
    MaxBytes := cEditorMaxBytes;
  FVfs.ReadBytesAsync(URI, MaxBytes, Cancel,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    var
      Text: string;
      Enc: TTextFileEncoding;
      IsBin: Boolean;
    begin
      if Gen <> FGen then
        Exit;
      FCancel := nil;
      // A failed read, a decode failure, or content that now looks binary
      // is left alone rather than surfaced as an error or flipped into Hex
      // mid-view — most likely a transient race with the writer still
      // mid-save; the next change notification gets another try.
      if (AError.Code <> vecOk) or (not DetectAndDecodeText(ABytes, Text, Enc, IsBin)) or IsBin then
        Exit;
      FRawBytes := Copy(ABytes);
      FEncoding := Enc;
      ApplyLoadedText(Text);
      RefreshReadOnly;
      RecordKnownFileStat;
      NotifyChanged;
    end);
end;

procedure TEditorDoc.ApplyLoadedText(const AText: string);
var
  S, Line: string;
  I, Start: Integer;
  Ch: Char;
begin
  FLines.Clear;
  FCrlf := Pos(#13#10, AText) > 0;
  S := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  S := StringReplace(S, #13, #10, [rfReplaceAll]);
  Start := 1;
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if Ch = #10 then
    begin
      Line := Copy(S, Start, I - Start);
      FLines.Add(Line);
      Start := I + 1;
    end;
  end;
  if Start <= Length(S) then
    FLines.Add(Copy(S, Start, MaxInt))
  else if (S = '') or ((Length(S) > 0) and (S[Length(S)] = #10)) then
    FLines.Add('');
  if FLines.Count = 0 then
    FLines.Add('');
end;

function TEditorDoc.ApplyEncoding(AEncoding: TTextFileEncoding; ARedecode: Boolean): Boolean;
var
  Text: string;
begin
  Result := False;
  if not FReady then
    Exit;
  if FStreaming then
  begin
    // The line index built by StartStreamingOpen is aligned to whatever
    // code-unit width it was scanned with — 1 byte for UTF-8/ANSI/OEM, 2
    // bytes for UTF-16 (see Utf16PairIsLF). Redecoding within the same
    // width only changes how each line's bytes are decoded, not where
    // lines start, so the index stays valid (this is also how UTF-16
    // LE <-> BE re-decoding is allowed here — same 2-byte width, index
    // unaffected). Crossing widths would silently reinterpret the index at
    // the wrong granularity, so refuse instead of corrupting line
    // boundaries.
    if ((FStreamEncoding = tfeUtf16LE) or (FStreamEncoding = tfeUtf16BE)) <>
       ((AEncoding = tfeUtf16LE) or (AEncoding = tfeUtf16BE)) then
      Exit;
    FEncoding := AEncoding;
    if ARedecode then
    begin
      FStreamEncoding := AEncoding;
      FLineCache.Clear;
      FLineCacheOrder.Clear;
    end;
    NotifyChanged;
    Result := True;
    Exit;
  end;
  if Length(FRawBytes) = 0 then
    Exit;
  FEncoding := AEncoding;
  if ARedecode then
  begin
    Text := DecodeTextWithEncoding(FRawBytes, AEncoding);
    ApplyLoadedText(Text);
    FBinary := False;
    FDirty := False;
    FError := '';
    if FReadOnly then
      FStatus := 'Read-only'
    else
      FStatus := '';
  end;
  NotifyChanged;
  Result := True;
end;

function TEditorDoc.ByteCount: Integer;
begin
  Result := Length(FRawBytes);
end;

function TEditorDoc.GetByte(AIndex: Integer): Byte;
begin
  if (AIndex < 0) or (AIndex >= Length(FRawBytes)) then
    Result := 0
  else
    Result := FRawBytes[AIndex];
end;

procedure TEditorDoc.SetByte(AIndex: Integer; AValue: Byte);
begin
  if FStreaming or FReadOnly or (not FReady) then
    Exit;
  if (AIndex < 0) or (AIndex >= Length(FRawBytes)) then
    Exit;
  FRawBytes[AIndex] := AValue;
  FDirty := True;
  NotifyChanged;
end;

procedure TEditorDoc.InsertByte(AIndex: Integer; AValue: Byte);
var
  N: Integer;
  Tmp: TBytes;
begin
  if FStreaming or FReadOnly or (not FReady) then
    Exit;
  N := Length(FRawBytes);
  if AIndex < 0 then
    AIndex := 0;
  if AIndex > N then
    AIndex := N;
  SetLength(Tmp, N + 1);
  if AIndex > 0 then
    Move(FRawBytes[0], Tmp[0], AIndex);
  Tmp[AIndex] := AValue;
  if AIndex < N then
    Move(FRawBytes[AIndex], Tmp[AIndex + 1], N - AIndex);
  FRawBytes := Tmp;
  FDirty := True;
  NotifyChanged;
end;

procedure TEditorDoc.DeleteByte(AIndex: Integer);
var
  N: Integer;
  Tmp: TBytes;
begin
  if FStreaming or FReadOnly or (not FReady) then
    Exit;
  N := Length(FRawBytes);
  if (AIndex < 0) or (AIndex >= N) then
    Exit;
  if N = 1 then
    SetLength(FRawBytes, 0)
  else
  begin
    SetLength(Tmp, N - 1);
    if AIndex > 0 then
      Move(FRawBytes[0], Tmp[0], AIndex);
    if AIndex < N - 1 then
      Move(FRawBytes[AIndex + 1], Tmp[AIndex], N - AIndex - 1);
    FRawBytes := Tmp;
  end;
  FDirty := True;
  NotifyChanged;
end;

function TEditorDoc.SnapshotBytes: TBytes;
begin
  Result := Copy(FRawBytes);
end;

procedure TEditorDoc.RestoreBytes(const ABytes: TBytes; AMarkDirty: Boolean);
begin
  FRawBytes := Copy(ABytes);
  if AMarkDirty then
    FDirty := True;
  NotifyChanged;
end;

function TEditorDoc.BuildSaveText: string;
var
  I: Integer;
  EOL: string;
begin
  if FCrlf then
    EOL := #13#10
  else
    EOL := #10;
  Result := '';
  for I := 0 to FLines.Count - 1 do
  begin
    Result := Result + FLines[I];
    if I < FLines.Count - 1 then
      Result := Result + EOL;
  end;
end;

procedure TEditorDoc.OpenAsync(const AURI: string; AWantEdit: Boolean);
var
  Gen: Cardinal;
  URI: string;
  MaxBytes: Int64;
begin
  Close;
  URI := AURI;
  FURI := URI;
  FWantEdit := AWantEdit;
  if HasArchiveChain(URI) then
    FPath := VfsUriTitle(URI)
  else
    FPath := FileUriToPath(URI);
  Inc(FGen);
  Gen := FGen;
  FLoading := True;
  FReady := False;
  FError := '';
  FStatus := 'Loading...';
  FCancel := TJobCancelToken.Create;
  NotifyChanged;

  if AWantEdit then
    MaxBytes := cEditorEditMaxBytes
  else
    MaxBytes := cEditorMaxBytes;
  FVfs.ReadBytesAsync(URI, MaxBytes, FCancel,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    var
      Text: string;
      Enc: TTextFileEncoding;
      IsBin: Boolean;
    begin
      if Gen <> FGen then
        Exit;
      // Stage 24: a plain local file that's too big for the whole-buffer
      // read gets a second chance as a streaming (line-indexed) doc instead
      // of surfacing "File too large". vecNotSupported from
      // TFileVirtualFileSystem.ReadBytesAsync means exactly "too large for
      // MaxBytes" (see uFileVfs.pas); it isn't reused there for any other
      // reason.
      if (AError.Code = vecNotSupported) and (not HasArchiveChain(URI)) and (FPath <> '') then
      begin
        StartStreamingOpen(FPath, Gen);
        Exit;
      end;
      // An oversized archive entry gets the same second chance, but there's
      // no local file to seek/line-index directly — extract it to a temp
      // file first (reusing the same CopyAsync path F5/Copy uses to pull a
      // file out of a ZIP), then stream from that temp copy.
      if (AError.Code = vecNotSupported) and HasArchiveChain(URI) then
      begin
        StartStreamingOpenFromArchive(URI, Gen);
        Exit;
      end;
      FLoading := False;
      FCancel := nil;
      if AError.Code <> vecOk then
      begin
        if AWantEdit and (AError.Code = vecNotFound) and (FPath <> '') and
          (not HasArchiveChain(URI)) then
        begin
          BeginEmptyNewFile;
          Exit;
        end;
        SetLength(FRawBytes, 0);
        FError := AError.Message;
        FStatus := '';
        FReady := False;
      end
      else if not DetectAndDecodeText(ABytes, Text, Enc, IsBin) then
      begin
        // Binary (NUL bytes, etc.): keep raw dump for Hex Viewer.
        if IsBin then
        begin
          FRawBytes := Copy(ABytes);
          FBinary := True;
          FEncoding := tfeUtf8;
          FLines.Clear;
          FLines.Add('');
          RefreshReadOnly;
          FDirty := False;
          FError := '';
          FReady := True;
          FStatus := Format('Hex  %d bytes', [Length(FRawBytes)]);
          StartWatchingCurrentFile; // no-op for binary (see StartWatchingCurrentFile)
        end
        else
        begin
          SetLength(FRawBytes, 0);
          FBinary := False;
          FError := 'Cannot decode text';
          FStatus := '';
          FReady := False;
        end;
      end
      else
      begin
        FRawBytes := Copy(ABytes);
        FBinary := False;
        FEncoding := Enc;
        ApplyLoadedText(Text);
        RefreshReadOnly;
        FDirty := False;
        FError := '';
        FReady := True;
        if Length(FRawBytes) > cEditorMaxBytes then
          FStatus := Format('Loaded  %d MB', [Length(FRawBytes) div (1024 * 1024)])
        else if FReadOnly then
          FStatus := 'Read-only'
        else
          FStatus := '';
        StartWatchingCurrentFile;
        RecordKnownFileStat;
      end;
      NotifyChanged;
    end);
end;

procedure TEditorDoc.BeginEmptyNewFile;
begin
  SetLength(FRawBytes, 0);
  FBinary := False;
  FEncoding := tfeUtf8;
  ApplyLoadedText('');
  FCrlf := True;
  RefreshReadOnly;
  FDirty := False;
  FError := '';
  FReady := True;
  FStatus := '';
  StartWatchingCurrentFile;
  NotifyChanged;
end;

{ Stage 24: line-indexed streaming open for a local file that ReadBytesAsync
  refused as too large. Two phases, both off the UI thread:
    1. Sample the first cStreamSampleBytes to detect encoding/binary — reuses
       the exact same DetectAndDecodeText used for the whole-buffer path, so
       detection behavior matches for the part of the file that overlaps.
    2. Scan the whole file once (cStreamScanChunk-sized reads) to build
       FLineOffsets. Byte-level LF scanning (one byte at a time) is safe for
       UTF-8/ANSI/OEM — a raw 0x0A byte is never part of a multi-byte UTF-8
       sequence, and single-byte code pages have no multi-byte sequences at
       all — but NOT safe for UTF-16, where a lone 0x0A byte can be the
       non-LF half of an unrelated code unit, so UTF-16 gets its own 2-byte-
       code-unit-aligned scan instead (see Utf16PairIsLF below); this is
       possible only because UTF-16 is BOM-only detected in this codebase
       (DetectAndDecodeText), which guarantees content starts 2-byte-aligned
       right after the 2-byte BOM. Binary samples open in Hex (up to
       cEditorEditMaxBytes) instead of the old "File too large" error. }

/// <summary>True when (AByte0, AByte1), read in AIsLE's byte order, is the
/// UTF-16 code unit 0x000A (LF). LE stores it as [0x0A, 0x00]; BE as
/// [0x00, 0x0A].</summary>
function Utf16PairIsLF(AByte0, AByte1: Byte; AIsLE: Boolean): Boolean;
begin
  if AIsLE then
    Result := (AByte0 = 10) and (AByte1 = 0)
  else
    Result := (AByte0 = 0) and (AByte1 = 10);
end;

// Off the UI thread: sniffs APath's first chunk to tell text from binary,
// then either loads it whole as hex (binary) or walks the file once via
// BuildStreamingLineOffsets to build a line-start offset table (text) for
// random-access streaming later. AErr is set on any failure; the other out
// params are meaningful only when AErr = ''.
procedure TEditorDoc.ScanFileForStreaming(const APath: string;
  const ACancel: IJobCancelToken; out AErr: string; out AHexMode: Boolean;
  out AHexBuf: TBytes; out AOffsets: TArray<Int64>;
  out ADetEnc: TTextFileEncoding; out ASize: Int64);
var
  FS: TFileStream;
  Sample: TBytes;
  SampleLen: Int64;
  DetIsBin: Boolean;
  DetText: string;
  HexLen: Int64;
begin
  AErr := '';
  AHexMode := False;
  ADetEnc := tfeUtf8;
  ASize := 0;
  SetLength(AOffsets, 0);
  SetLength(AHexBuf, 0);
  try
    if not TFile.Exists(WinApiPath(APath)) then
    begin
      AErr := 'File not found';
      Exit;
    end;
    ASize := TFile.GetSize(WinApiPath(APath));
    FS := TFileStream.Create(WinApiPath(APath), fmOpenRead or fmShareDenyNone);
    try
      if ASize < cStreamSampleBytes then
        SampleLen := ASize
      else
        SampleLen := cStreamSampleBytes;
      SetLength(Sample, SampleLen);
      if SampleLen > 0 then
        FS.Read(Sample[0], SampleLen);
      // The cut at SampleLen is arbitrary, not an encoding boundary, unless
      // the sample is the whole file (real EOF) — drop a trailing incomplete
      // UTF-8 sequence so it doesn't make a genuinely UTF-8 file look invalid
      // (see TrimUtf8SampleTail).
      if SampleLen < ASize then
        TrimUtf8SampleTail(Sample);
      if not DetectAndDecodeText(Sample, DetText, ADetEnc, DetIsBin) then
        DetIsBin := True;

      if DetIsBin then
      begin
        AHexMode := True;
        if ASize > cEditorEditMaxBytes then
          HexLen := cEditorEditMaxBytes
        else
          HexLen := ASize;
        SetLength(AHexBuf, HexLen);
        if HexLen > 0 then
        begin
          FS.Position := 0;
          if FS.Read(AHexBuf[0], Integer(HexLen)) <> HexLen then
            AErr := 'Cannot read file';
        end;
      end
      else
        AOffsets := BuildStreamingLineOffsets(FS, ASize, ADetEnc, ACancel, AErr);
    finally
      FS.Free;
    end;
  except
    on E: Exception do
      AErr := E.Message;
  end;
end;

// Walks FS from its current position building a table of line-start byte
// offsets (LF for 8-bit encodings, matching UTF-16 code-unit pairs for
// UTF-16). Result[0] is the first line's start (already positioned past any
// BOM by the caller); a trailing sentinel equal to ASize is appended so the
// last line's length can always be computed as Result[i+1] - Result[i].
function TEditorDoc.BuildStreamingLineOffsets(FS: TFileStream; ASize: Int64;
  ADetEnc: TTextFileEncoding; const ACancel: IJobCancelToken;
  out AErr: string): TArray<Int64>;
var
  ChunkBuf: TBytes;
  OffCount: Integer;
  Pos, Read: Int64;
  I: Integer;
  IsUtf16, IsLE, HasPending: Boolean;
  PendingByte: Byte;
begin
  AErr := '';
  IsUtf16 := (ADetEnc = tfeUtf16LE) or (ADetEnc = tfeUtf16BE);
  IsLE := ADetEnc = tfeUtf16LE;
  SetLength(Result, 1024);
  OffCount := 0;
  if IsUtf16 then
    Result[0] := 2 // skip the 2-byte BOM; first line starts right after it
  else
    Result[0] := 0;
  Inc(OffCount);
  FS.Position := Result[0];
  SetLength(ChunkBuf, cStreamScanChunk);
  Pos := Result[0];
  HasPending := False;
  PendingByte := 0;
  while True do
  begin
    if JobCancelRequested(ACancel) then
    begin
      AErr := 'Cancelled';
      Break;
    end;
    Read := FS.Read(ChunkBuf[0], Length(ChunkBuf));
    if Read <= 0 then
      Break;
    if not IsUtf16 then
    begin
      for I := 0 to Read - 1 do
        if ChunkBuf[I] = 10 then // LF; offsets mark line starts
        begin
          if OffCount >= Length(Result) then
            SetLength(Result, Length(Result) * 2);
          Result[OffCount] := Pos + I + 1;
          Inc(OffCount);
        end;
    end
    else
    begin
      I := 0;
      // A leftover byte from the previous chunk pairs with this chunk's
      // first byte — keeps pairs aligned to the code-unit grid even if a
      // read ever returns an odd byte count.
      if HasPending then
      begin
        if Utf16PairIsLF(PendingByte, ChunkBuf[0], IsLE) then
        begin
          if OffCount >= Length(Result) then
            SetLength(Result, Length(Result) * 2);
          Result[OffCount] := Pos + 1;
          Inc(OffCount);
        end;
        HasPending := False;
        I := 1;
      end;
      while I + 1 < Read do
      begin
        if Utf16PairIsLF(ChunkBuf[I], ChunkBuf[I + 1], IsLE) then
        begin
          if OffCount >= Length(Result) then
            SetLength(Result, Length(Result) * 2);
          Result[OffCount] := Pos + I + 2;
          Inc(OffCount);
        end;
        Inc(I, 2);
      end;
      if I < Read then
      begin
        PendingByte := ChunkBuf[Read - 1];
        HasPending := True;
      end;
    end;
    Inc(Pos, Read);
  end;
  if AErr = '' then
  begin
    // Trailing sentinel for the last line's length; if the file doesn't end
    // with LF, the last line runs to EOF.
    if (OffCount = 0) or (Result[OffCount - 1] < ASize) then
    begin
      if OffCount >= Length(Result) then
        SetLength(Result, OffCount + 1);
      Result[OffCount] := ASize;
      Inc(OffCount);
    end;
    SetLength(Result, OffCount);
  end;
end;

procedure TEditorDoc.StartStreamingOpen(const APath: string; AGen: Cardinal);
var
  Cancel: IJobCancelToken;
begin
  FStatus := 'Indexing...';
  NotifyChanged;
  FCancel := TJobCancelToken.Create;
  Cancel := FCancel;
  TThread.CreateAnonymousThread(
    procedure
    var
      Offsets: TArray<Int64>;
      DetEnc: TTextFileEncoding;
      Size: Int64;
      HexBuf: TBytes;
      HexMode: Boolean;
      Err: string;
    begin
      ScanFileForStreaming(APath, Cancel, Err, HexMode, HexBuf, Offsets, DetEnc, Size);

      TThread.Queue(nil,
        procedure
        begin
          if AGen <> FGen then
            Exit;
          FLoading := False;
          FCancel := nil;
          if Err <> '' then
          begin
            FError := Err;
            FStatus := '';
            FReady := False;
          end
          else if HexMode then
          begin
            FStreaming := False;
            FStreamPath := '';
            FBinary := True;
            FEncoding := tfeUtf8;
            FRawBytes := HexBuf;
            FLines.Clear;
            FLines.Add('');
            FReadOnly := True;
            FDirty := False;
            FError := '';
            FReady := True;
            if Size > Length(FRawBytes) then
              FStatus := Format('Hex  first %d of %d bytes',
                [Length(FRawBytes), Size])
            else
              FStatus := Format('Hex  %d bytes', [Length(FRawBytes)]);
          end
          else
          begin
            FStreaming := True;
            FStreamPath := APath;
            FStreamEncoding := DetEnc;
            FEncoding := DetEnc;
            FStreamFileSize := Size;
            FLineOffsets := Offsets;
            FLineCache.Clear;
            FLineCacheOrder.Clear;
            FBinary := False;
            FReadOnly := True; // streaming docs start view-only until promote
            FDirty := False;
            FError := '';
            FReady := True;
            if FWantEdit then
              FStatus := Format('Too large to edit  %d MB',
                [Size div (1024 * 1024)])
            else
              FStatus := Format('Streaming  %d lines', [Length(FLineOffsets) - 1]);
          end;
          NotifyChanged;
        end);
    end).Start;
end;

{ An oversized archive entry has no local file to seek/line-index directly.
  Extract it to a temp file first — reusing the same CopyAsync path F5/Copy
  already uses to pull a single file out of a ZIP
  (TZipVirtualFileSystem.CopyAsync, "archive -> disk" branch) — then hand
  that temp path to StartStreamingOpen unchanged. }
procedure TEditorDoc.StartStreamingOpenFromArchive(const AURI: string; AGen: Cardinal);
var
  TempPath: string;
  Cancel: IJobCancelToken;
begin
  FStatus := 'Extracting...';
  NotifyChanged;
  TempPath := TPath.GetTempFileName;
  FCancel := TJobCancelToken.Create;
  Cancel := FCancel;
  FVfs.CopyAsync(AURI, PathToFileUri(TempPath), Cancel,
    procedure(const ADone, ATotal: Int64; const AName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string) begin end,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if AGen <> FGen then
        Exit;
      if not ASuccess then
      begin
        try
          if TFile.Exists(WinApiPath(TempPath)) then
            TFile.Delete(WinApiPath(TempPath));
        except
          // best-effort cleanup
        end;
        FLoading := False;
        FCancel := nil;
        FError := 'File too large to preview as text.';
        FStatus := '';
        FReady := False;
        NotifyChanged;
        Exit;
      end;
      // StartStreamingOpen takes over FCancel/FLoading/FGen bookkeeping from
      // here — same contract as the plain-local-file call site.
      FStreamPathIsTemp := True;
      StartStreamingOpen(TempPath, AGen);
    end, True, False);
end;

function TEditorDoc.TryPromoteStreaming: Boolean;
var
  Bytes: TBytes;
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
  Path: string;
begin
  Result := False;
  if (not FStreaming) or (not FReady) or FLoading or FSaving then
    Exit;
  if FStreamFileSize > cEditorEditMaxBytes then
  begin
    FError := 'Too large to edit';
    FStatus := FError;
    NotifyChanged;
    Exit;
  end;
  Path := FStreamPath;
  if Path = '' then
    Exit;
  try
    Bytes := TFile.ReadAllBytes(WinApiPath(Path));
  except
    on E: Exception do
    begin
      FError := E.Message;
      FStatus := FError;
      NotifyChanged;
      Exit;
    end;
  end;
  FStreaming := False;
  SetLength(FLineOffsets, 0);
  FLineCache.Clear;
  FLineCacheOrder.Clear;
  FRawBytes := Bytes;
  if not DetectAndDecodeText(Bytes, Text, Enc, IsBin) then
  begin
    FBinary := True;
    FEncoding := tfeUtf8;
    FLines.Clear;
    FLines.Add('');
    FStatus := Format('Hex  %d bytes', [Length(FRawBytes)]);
  end
  else
  begin
    FBinary := False;
    FEncoding := Enc;
    ApplyLoadedText(Text);
    FStatus := Format('Loaded  %d MB', [Length(FRawBytes) div (1024 * 1024)]);
  end;
  FReadOnly := False;
  FDirty := False;
  FError := '';
  RefreshReadOnly;
  NotifyChanged;
  Result := True;
end;

function TEditorDoc.TryClearOsReadOnly(out AError: string): Boolean;
var
  Path: string;
  {$WARN SYMBOL_PLATFORM OFF}
  Attrs: TFileAttributes;
  {$WARN SYMBOL_PLATFORM ON}
begin
  Result := False;
  AError := '';
  Path := FPath;
  if (Path = '') or HasArchiveChain(FURI) then
  begin
    AError := 'Cannot clear read-only here';
    Exit;
  end;
  try
    {$WARN SYMBOL_PLATFORM OFF}
    Attrs := TFile.GetAttributes(WinApiPath(Path));
    Exclude(Attrs, TFileAttribute.faReadOnly);
    TFile.SetAttributes(WinApiPath(Path), Attrs);
    {$WARN SYMBOL_PLATFORM ON}
  except
    on E: Exception do
    begin
      AError := E.Message;
      Exit;
    end;
  end;
  FReadOnly := False;
  FError := '';
  FStatus := '';
  RefreshReadOnly;
  NotifyChanged;
  Result := True;
end;

procedure TEditorDoc.SaveAsync(ARawBytes: Boolean);
var
  SaveGen: Cardinal;
  URI, Text, Path: string;
  Enc: TTextFileEncoding;
  Raw: TBytes;
begin
  if (not FReady) or FSaving or FLoading then
    Exit;
  if FStreaming then
  begin
    FError := 'Streaming view is read-only';
    FStatus := FError;
    NotifyChanged;
    Exit;
  end;
  if FReadOnly then
  begin
    FError := 'File is read-only';
    FStatus := FError;
    NotifyChanged;
    Exit;
  end;
  if ARawBytes or FBinary then
  begin
    if HasArchiveChain(FURI) then
    begin
      FError := 'Cannot save binary into an archive';
      FStatus := FError;
      NotifyChanged;
      Exit;
    end;
    Path := FPath;
    if Path = '' then
    begin
      FError := 'Cannot save';
      FStatus := FError;
      NotifyChanged;
      Exit;
    end;
    Raw := Copy(FRawBytes);
    Inc(FSaveGen);
    SaveGen := FSaveGen;
    FSaving := True;
    FError := '';
    FStatus := 'Saving...';
    NotifyChanged;
    TThread.CreateAnonymousThread(
      procedure
      var
        Ok: Boolean;
        Err: string;
      begin
        Ok := False;
        Err := '';
        try
          TFile.WriteAllBytes(WinApiPath(Path), Raw);
          Ok := True;
        except
          on E: Exception do
            Err := E.Message;
        end;
        TThread.Queue(nil,
          procedure
          begin
            if SaveGen <> FSaveGen then
              Exit;
            FSaving := False;
            if not Ok then
            begin
              FError := Err;
              FStatus := FError;
            end
            else
            begin
              FDirty := False;
              FError := '';
              FStatus := 'Saved';
              RefreshReadOnly;
              StartWatchingCurrentFile;
              RecordKnownFileStat; // so the watcher notification our own write triggers is a no-op
            end;
            NotifyChanged;
          end);
      end).Start;
    Exit;
  end;

  URI := FURI;
  Text := BuildSaveText;
  Enc := FEncoding;
  Inc(FSaveGen);
  SaveGen := FSaveGen;
  FSaving := True;
  FError := '';
  FStatus := 'Saving...';
  FCancel := TJobCancelToken.Create;
  NotifyChanged;

  FVfs.WriteTextAsync(URI, Text, Enc, FCancel,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if SaveGen <> FSaveGen then
        Exit;
      FSaving := False;
      FCancel := nil;
      if not ASuccess then
      begin
        FError := AError.Message;
        FStatus := FError;
        if AError.Code = vecAccessDenied then
          FReadOnly := True;
      end
      else
      begin
        FRawBytes := EncodeTextBytes(Text, Enc);
        FDirty := False;
        FError := '';
        FStatus := 'Saved';
        RefreshReadOnly;
        StartWatchingCurrentFile;
        RecordKnownFileStat; // so the watcher notification our own write triggers is a no-op
      end;
      NotifyChanged;
    end);
end;

end.
