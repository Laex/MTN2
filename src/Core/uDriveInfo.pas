unit uDriveInfo;

{ Volume list for the Alt+F1/F2 Change Drive popup, with caching and
  formatting. The volumes come from uPlatformDrives: drive letters on
  Windows, mount points (each given a letter) on Posix systems. }

interface

uses
  System.SysUtils, uDriveTypes;

type
  TDriveInfo = uDriveTypes.TDriveInfo;
  TDriveInfoArray = uDriveTypes.TDriveInfoArray;

/// <summary>Letters + KindLabel only -- never touches the volume itself.
/// The detail queries touch the actual filesystem and can block for a long
/// time (even minutes) on an unresponsive network share; the listing does
/// not. Safe to call from a paint routine every frame -- see
/// EnumDriveBarGlyphs.</summary>
function EnumLogicalDrivesFast: TDriveInfoArray;
/// <summary>Full detail (FsName/LabelOrPath/TotalBytes/FreeBytes) for every
/// drive -- see EnumLogicalDrivesFast's warning. Never call this from a UI
/// paint path; use CachedDriveInfo instead.</summary>
function EnumLogicalDrives: TDriveInfoArray;
/// <summary>Non-blocking: returns the best data on hand right now for every
/// currently-known drive letter (real FsName/size once a drive has answered,
/// otherwise EnumLogicalDrivesFast's letters-only placeholder). Ensures every
/// letter either already has real detail or has exactly one background
/// worker in flight for it, one drive at a time -- an unresponsive network
/// share stays stuck at "letters only" forever without blocking any other
/// drive's result. AOnRefreshed (queued to the main thread) fires once per
/// drive that finishes, so callers can repaint incrementally. Cheap and safe
/// to call every frame: a drive that already answered, or is still being
/// asked, is never re-queried.</summary>
function CachedDriveInfo(const AOnRefreshed: TProc = nil): TDriveInfoArray;
/// <summary>Re-asks every drive that isn't currently in flight, even ones
/// that already answered -- e.g. after the user inserts/removes a drive, or
/// to refresh a free-space figure that's gone stale. A drive still being
/// queried from an earlier round is left alone rather than double-spawned.</summary>
procedure ForceRefreshDriveInfo(const AOnRefreshed: TProc = nil);
/// <summary>TryQueryPathVolume's non-blocking counterpart: looks APath's
/// drive letter up in CachedDriveInfo instead of querying it directly.</summary>
function TryCachedPathVolume(const APath: string; out AInfo: TDriveInfo;
  const AOnRefreshed: TProc = nil): Boolean;
function FormatDriveSize(ABytes: Int64): string;
function FormatDrivePopupLine(const AInfo: TDriveInfo; AIsCurrent: Boolean;
  AInnerWidth: Integer): string;
/// <summary>Volume details for any local path (drive root of APath).</summary>
function TryQueryPathVolume(const APath: string; out AInfo: TDriveInfo): Boolean;
function FormatVolumeSerial(ASerial: Cardinal): string;
function FormatByteCount(ABytes: Int64): string;
/// <summary>FAR-style size: 10.0 GB / 63.2 MB / 1 234.</summary>
function FormatSizeFar(ABytes: Int64): string;
function FormatPctSize(APart, ATotal: Int64): string;
/// <summary>APart of ATotal in whole percent, 0..100; -1 when ATotal is not
/// positive. The same rounding as FormatPctSize.</summary>
function PercentOfTotal(APart, ATotal: Int64): Integer;
/// <summary>'C:\Work' -> 'C'; UNC / empty / relative -> #0.</summary>
function DriveLetterFromPath(const APath: string): Char;
function IndexOfDriveLetter(const ADrives: TDriveInfoArray; ALetter: Char): Integer;
/// <summary>'\\srv\share\dir\a' -> '\\srv\share'; anything that is not a UNC
/// path with a server and a share -> ''.</summary>
function UncShareRoot(const APath: string): string;
/// <summary>The drives followed by one network entry (no letter, root
/// '\\srv\share\') for each distinct UNC share in APaths, in order, up to
/// AMax; a share already behind a mapped drive is left out.</summary>
function AppendUncShares(const ADrives: TDriveInfoArray;
  const APaths: TArray<string>; AMax: Integer): TDriveInfoArray;
/// <summary>Wrap ACurrentIndex by ADelta. Missing current (ACurrentIndex&lt;0):
/// +delta starts at 0, -delta at last.</summary>
function CycleDriveIndex(ACount, ACurrentIndex, ADelta: Integer): Integer;

const
  /// <summary>Same numbered extras as Change Drive (Alt+F1/F2), after the
  /// physical drives. Glyphs are '1'.. so they never collide with A-Z.</summary>
  ChangeDriveSpecialCount = 4;
  ChangeDriveSpecialLabels: array[0..ChangeDriveSpecialCount - 1] of string =
    ('System folders', 'Recycle bin', 'Temporary', 'Workspace');
  ChangeDriveSpecialUris: array[0..ChangeDriveSpecialCount - 1] of string =
    ('sys://folders', 'recycle:///', 'tmp:///', 'ws:///');

/// <summary>Number of numbered items below the drives: the built-in
/// ChangeDriveSpecialCount ones plus the items plugins registered
/// (uDriveItems.pas).</summary>
function ChangeDriveItemCount: Integer;
/// <summary>Target URI of numbered item AIndex (built-in or plugin).</summary>
function ChangeDriveItemUri(AIndex: Integer): string;
/// <summary>ChangeDriveSpecialLabels[AIndex] as shown on screen (translated);
/// the caption a plugin gave for AIndex >= ChangeDriveSpecialCount.</summary>
function ChangeDriveSpecialTitle(AIndex: Integer): string;
/// <summary>TDriveInfo.KindLabel as shown on screen (translated). KindLabel
/// itself stays English: the info panel compares it ('Hard disk').</summary>
function DriveKindTitle(const AKindLabel: string): string;
function ChangeDriveSpecialGlyph(AIndex: Integer): Char;
function IsChangeDriveSpecialGlyph(AGlyph: Char): Boolean;
function TryChangeDriveSpecialUri(AGlyph: Char; out AUri: string): Boolean;
/// <summary>Drive letter, or special glyph '1'.. when AUri is sys/recycle/tmp/ws.</summary>
function DriveBarGlyphFromUri(const AUri: string): Char;
/// <summary>Change Drive list index for AUri: physical drive, or
/// Length(ADrives)+1+special. Unknown URI -> 0.</summary>
function DrivePopupCursorIndex(const ADrives: TDriveInfoArray;
  const AUri: string): Integer;
/// <summary>Logical drives in EnumLogicalDrives order, then specials 1..N.</summary>
function EnumDriveBarGlyphs: TArray<Char>;
function IndexOfDriveBarGlyph(const AGlyphs: TArray<Char>; AGlyph: Char): Integer;
/// <summary>Fit the Change Drive item list into AMaxWidth cells of the NDN
/// `[ C D | 1 2 ]` bar. Prefers keeping every special; drops trailing drives
/// first. ADriveCount is the visible physical-drive prefix; AShowSep is the
/// `|` between drives and specials.</summary>
procedure FitDriveBarGlyphs(AMaxWidth: Integer; out AGlyphs: TArray<Char>;
  out ADriveCount: Integer; out AShowSep: Boolean);

implementation

uses
  System.Math, System.Classes, System.SyncObjs,
  uPlatformDrives, uTerminalTypes, uVfsTypes, uStrings, uDriveItems;

function PluginDriveItemAt(AIndex: Integer): TDriveItem;
var
  Items: TArray<TDriveItem>;
begin
  Items := DriveItems.Items;
  Result := Items[AIndex];
end;

function ChangeDriveSpecialTitle(AIndex: Integer): string;
const
  cKeys: array[0..ChangeDriveSpecialCount - 1] of string =
    ('systemFolders', 'recycleBin', 'temporary', 'workspace');
begin
  if (AIndex < 0) or (AIndex >= ChangeDriveItemCount) then
    Exit('');
  if AIndex >= ChangeDriveSpecialCount then
    Exit(PluginDriveItemAt(AIndex - ChangeDriveSpecialCount).Caption);
  Result := T('ui.drivePopup.' + cKeys[AIndex], ChangeDriveSpecialLabels[AIndex]);
end;

function ChangeDriveItemCount: Integer;
begin
  Result := ChangeDriveSpecialCount + Length(DriveItems.Items);
end;

function ChangeDriveItemUri(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= ChangeDriveItemCount) then
    Exit('');
  if AIndex < ChangeDriveSpecialCount then
    Result := ChangeDriveSpecialUris[AIndex]
  else
    Result := PluginDriveItemAt(AIndex - ChangeDriveSpecialCount).Uri;
end;

function DriveKindTitle(const AKindLabel: string): string;
begin
  if AKindLabel = '' then
    Result := ''
  else
    Result := T('ui.driveKind.' + AKindLabel, AKindLabel);
end;

function FormatDriveSize(ABytes: Int64): string;
var
  G: Int64;
  S: string;
  I: Integer;
begin
  if ABytes <= 0 then
    Exit('');
  // Round to whole GiB like FAR's "930G" / "1 908G".
  G := (ABytes + (Int64(1) shl 30) - 1) div (Int64(1) shl 30);
  if G <= 0 then
    G := 1;
  S := IntToStr(G);
  Result := '';
  for I := 1 to Length(S) do
  begin
    if (I > 1) and (((Length(S) - I + 1) mod 3) = 0) then
      Result := Result + ' ';
    Result := Result + S[I];
  end;
  Result := Result + 'G';
end;

function PadTrunc(const AText: string; AWidth: Integer): string;
begin
  if AWidth <= 0 then
    Exit('');
  if Length(AText) >= AWidth then
    Result := Copy(AText, 1, AWidth)
  else
    Result := AText + StringOfChar(' ', AWidth - Length(AText));
end;

function FormatDrivePopupLine(const AInfo: TDriveInfo; AIsCurrent: Boolean;
  AInnerWidth: Integer): string;
var
  Mark: Char;
  Kind, Fs, Lab, Sz, FreeSz, LeftPart: string;
  LabW: Integer;
  Sep: string;
begin
  if AIsCurrent then
    Mark := '*'
  else
    Mark := ' ';
  Kind := PadTrunc(DriveKindTitle(AInfo.KindLabel), 12);
  Fs := PadTrunc(AInfo.FsName, 5);
  Sz := FormatDriveSize(AInfo.TotalBytes);
  if Length(Sz) < 7 then
    Sz := StringOfChar(' ', 7 - Length(Sz)) + Sz
  else
    Sz := Copy(Sz, 1, 7);
  // Free space column, same width/format as the total-size column.
  FreeSz := FormatDriveSize(AInfo.FreeBytes);
  if Length(FreeSz) < 7 then
    FreeSz := StringOfChar(' ', 7 - Length(FreeSz)) + FreeSz
  else
    FreeSz := Copy(FreeSz, 1, 7);
  // Use chBoxV (#$2502), not a UTF-8 literal - source encoding must not matter.
  Sep := ' ' + chBoxV + ' ';
  if AInfo.Letter = #0 then
    LeftPart := Mark + '   ' + Kind + Sep + Fs + Sep
  else
    LeftPart := Mark + AInfo.Letter + ': ' + Kind + Sep + Fs + Sep;
  // AInnerWidth - 1 reserve empty column before right border / scrollbar
  LabW := (AInnerWidth - 1) - Length(LeftPart) - Length(Sz) - Length(FreeSz) -
    2 * Length(Sep);
  if LabW < 4 then
    LabW := 4;
  Lab := PadTrunc(AInfo.LabelOrPath, LabW);
  Result := LeftPart + Lab + Sep + Sz + Sep + FreeSz;
  if Length(Result) > AInnerWidth - 1 then
    Result := Copy(Result, 1, AInnerWidth - 1);
  while Length(Result) < AInnerWidth do
    Result := Result + ' ';
end;

function FormatVolumeSerial(ASerial: Cardinal): string;
begin
  if ASerial = 0 then
    Exit('');
  Result := Format('%.4X-%.4X', [ASerial shr 16, ASerial and $FFFF]);
end;

function FormatByteCount(ABytes: Int64): string;
var
  S: string;
  I, Digits: Integer;
begin
  if ABytes < 0 then
    ABytes := 0;
  S := IntToStr(ABytes);
  Result := '';
  Digits := 0;
  for I := Length(S) downto 1 do
  begin
    if (Digits > 0) and ((Digits mod 3) = 0) then
      Result := ' ' + Result;
    Result := S[I] + Result;
    Inc(Digits);
  end;
end;

function FormatSizeFar(ABytes: Int64): string;
const
  KB = Int64(1024);
  MB = KB * 1024;
  GB = MB * 1024;
  TB = GB * 1024;
begin
  if ABytes < 0 then
    ABytes := 0;
  if ABytes < KB then
    Result := FormatByteCount(ABytes)
  else if ABytes < MB then
    Result := Format('%.1f KB', [ABytes / KB])
  else if ABytes < GB then
    Result := Format('%.1f MB', [ABytes / MB])
  else if ABytes < TB then
    Result := Format('%.2f GB', [ABytes / GB])
  else
    Result := Format('%.2f TB', [ABytes / TB]);
end;

function PercentOfTotal(APart, ATotal: Int64): Integer;
begin
  if ATotal <= 0 then
    Exit(-1);
  Result := EnsureRange(Round(100.0 * APart / ATotal), 0, 100);
end;

function FormatPctSize(APart, ATotal: Int64): string;
begin
  if ATotal <= 0 then
    Exit(FormatSizeFar(APart));
  Result := Format('%d%%, %s', [PercentOfTotal(APart, ATotal), FormatSizeFar(APart)]);
end;

function TryQueryPathVolume(const APath: string; out AInfo: TDriveInfo): Boolean;
var
  Letter: Char;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  Letter := PlatformDriveLetterOfPath(APath);
  if (Letter = #0) or not PlatformDriveByLetter(Letter, AInfo) then
    Exit(False);
  PlatformFillDriveDetails(AInfo);
  Result := True;
end;

function EnumLogicalDrivesFast: TDriveInfoArray;
begin
  Result := PlatformListDrives;
end;

function EnumLogicalDrives: TDriveInfoArray;
var
  I: Integer;
begin
  Result := PlatformListDrives;
  for I := 0 to High(Result) do
    PlatformFillDriveDetails(Result[I]);
end;

var
  /// <summary>A plain record in the data segment, not a heap object: a
  /// worker stuck on an unresponsive drive can wake up after the RTL has
  /// shut the memory manager down, and must still be able to take the lock
  /// to see GDriveInfoShuttingDown.</summary>
  GDriveInfoLock: Integer; // 0 free, 1 held; see LockDriveInfo
  GDriveInfoCache: TDriveInfoArray;
  GDriveInfoCacheReady: Boolean;
  /// <summary>Drive letters with a worker thread currently running
  /// PlatformFillDriveDetails for them -- the per-drive dedup key. A drive stuck
  /// here forever (an unresponsive network share) simply never gets
  /// re-queried; it does NOT block any other drive's worker or result.</summary>
  GDriveInfoInFlight: TArray<Char>;
  /// <summary>Set by finalization under GDriveInfoLock. A worker still stuck
  /// on an unresponsive drive can return after the program's main block
  /// ends -- by then globals and the heap are being torn down, so it must
  /// leave without touching either (see StartDriveWorker).</summary>
  GDriveInfoShuttingDown: Boolean;

// A spin lock on a global integer: critical sections and monitors live on
// the heap, which a late-waking worker must not touch (see GDriveInfoLock).
// The guarded sections only copy small arrays.
procedure LockDriveInfo;
begin
  while TInterlocked.CompareExchange(GDriveInfoLock, 1, 0) <> 0 do
    Sleep(1);
end;

procedure UnlockDriveInfo;
begin
  TInterlocked.Exchange(GDriveInfoLock, 0);
end;

/// <summary>True once a drive's cache entry carries real detail (as opposed
/// to the letters-only placeholder EnumLogicalDrivesFast/a not-yet-answered
/// worker leaves behind) -- the signal to not bother re-querying it.</summary>
function DriveInfoIsFilled(const AInfo: TDriveInfo): Boolean;
begin
  Result := (AInfo.FsName <> '') or (AInfo.TotalBytes <> 0) or (AInfo.FreeBytes <> 0);
end;

function IsLetterInFlight(ALetter: Char): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(GDriveInfoInFlight) do
    if GDriveInfoInFlight[I] = ALetter then
      Exit(True);
  Result := False;
end;

procedure AddInFlight(ALetter: Char);
var
  N: Integer;
begin
  N := Length(GDriveInfoInFlight);
  SetLength(GDriveInfoInFlight, N + 1);
  GDriveInfoInFlight[N] := ALetter;
end;

procedure RemoveInFlight(ALetter: Char);
var
  I, J: Integer;
begin
  for I := 0 to High(GDriveInfoInFlight) do
    if GDriveInfoInFlight[I] = ALetter then
    begin
      for J := I to High(GDriveInfoInFlight) - 1 do
        GDriveInfoInFlight[J] := GDriveInfoInFlight[J + 1];
      SetLength(GDriveInfoInFlight, Length(GDriveInfoInFlight) - 1);
      Exit;
    end;
end;

/// <summary>One worker per drive letter -- an unresponsive P: hanging
/// forever in PlatformFillDriveDetails must not stop C:/D:/... from getting their
/// real (size/label) data; a single shared background pass over all drives
/// would have blocked on P: and left every other drive's result stuck at
/// "letters only" too.</summary>
procedure StartDriveWorker(ALetter: Char; const AOnRefreshed: TProc);
var
  Callback: TProc;
begin
  Callback := AOnRefreshed;
  TThread.CreateAnonymousThread(
    procedure
    var
      Info: TDriveInfo;
      Idx: Integer;
    begin
      PlatformDriveByLetter(ALetter, Info);
      PlatformFillDriveDetails(Info); // the slow part -- may block for a long time
      LockDriveInfo;
      if GDriveInfoShuttingDown then
      begin
        // Woke up after finalization: the heap may already be gone, so even
        // releasing this frame's strings or the TThread object would fault.
        // The process is ending anyway -- leave without any RTL cleanup.
        UnlockDriveInfo;
        PlatformAbandonThread;
      end;
      try
        RemoveInFlight(ALetter);
        Idx := IndexOfDriveLetter(GDriveInfoCache, ALetter);
        if Idx >= 0 then
          GDriveInfoCache[Idx] := Info
        else
        begin
          Idx := Length(GDriveInfoCache);
          SetLength(GDriveInfoCache, Idx + 1);
          GDriveInfoCache[Idx] := Info;
        end;
        // Queued under the lock so finalization cannot slip in between the
        // shutdown check and the queue (TThread.Queue does not block).
        if Assigned(Callback) then
          TThread.Queue(nil,
            procedure
            begin
              Callback();
            end);
      finally
        UnlockDriveInfo;
      end;
    end).Start;
end;

/// <summary>Ensures every currently-known drive letter either already has
/// real detail cached or has exactly one worker in flight for it. Idempotent
/// and cheap to call repeatedly (e.g. once per CachedDriveInfo call): a
/// drive that already answered is never re-queried, and a drive whose
/// worker is still running (or will never return) is never double-spawned
/// -- see StartDriveWorker / DriveInfoIsFilled.</summary>
procedure StartDriveInfoRefresh(const AOnRefreshed: TProc);
var
  Letters: TDriveInfoArray;
  I, Idx: Integer;
  ToSpawn: TArray<Char>;
begin
  Letters := EnumLogicalDrivesFast; // cheap -- no GetVolumeInformation/GetDiskFreeSpaceEx
  SetLength(ToSpawn, 0);
  LockDriveInfo;
  try
    if not GDriveInfoCacheReady then
    begin
      GDriveInfoCache := Letters;
      GDriveInfoCacheReady := True;
    end;
    for I := 0 to High(Letters) do
    begin
      if IsLetterInFlight(Letters[I].Letter) then
        Continue;
      Idx := IndexOfDriveLetter(GDriveInfoCache, Letters[I].Letter);
      if (Idx >= 0) and DriveInfoIsFilled(GDriveInfoCache[Idx]) then
        Continue; // already answered -- no need to ask again
      if Idx < 0 then
      begin
        // A drive that appeared after the cache was first seeded (inserted
        // mid-session) -- add its letters-only placeholder now.
        Idx := Length(GDriveInfoCache);
        SetLength(GDriveInfoCache, Idx + 1);
        GDriveInfoCache[Idx] := Letters[I];
      end;
      AddInFlight(Letters[I].Letter);
      SetLength(ToSpawn, Length(ToSpawn) + 1);
      ToSpawn[High(ToSpawn)] := Letters[I].Letter;
    end;
  finally
    UnlockDriveInfo;
  end;

  for I := 0 to High(ToSpawn) do
    StartDriveWorker(ToSpawn[I], AOnRefreshed);
end;

function CachedDriveInfo(const AOnRefreshed: TProc): TDriveInfoArray;
begin
  StartDriveInfoRefresh(AOnRefreshed);
  LockDriveInfo;
  try
    if GDriveInfoCacheReady then
      Result := Copy(GDriveInfoCache)
    else
      Result := EnumLogicalDrivesFast;
  finally
    UnlockDriveInfo;
  end;
end;

/// <summary>Forces every currently-known drive letter to be re-queried, even
/// ones that already answered -- e.g. after the user inserts/removes a
/// drive, or to refresh a free-space figure that's gone stale. A drive still
/// in flight from a previous round is left alone rather than double-spawned.</summary>
procedure ForceRefreshDriveInfo(const AOnRefreshed: TProc = nil);
var
  I: Integer;
begin
  LockDriveInfo;
  try
    for I := 0 to High(GDriveInfoCache) do
      if not IsLetterInFlight(GDriveInfoCache[I].Letter) then
      begin
        GDriveInfoCache[I].FsName := '';
        GDriveInfoCache[I].TotalBytes := 0;
        GDriveInfoCache[I].FreeBytes := 0;
      end;
  finally
    UnlockDriveInfo;
  end;
  StartDriveInfoRefresh(AOnRefreshed);
end;

function TryCachedPathVolume(const APath: string; out AInfo: TDriveInfo;
  const AOnRefreshed: TProc): Boolean;
var
  Drives: TDriveInfoArray;
  Letter: Char;
  Idx: Integer;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  Letter := DriveLetterFromPath(APath);
  Drives := CachedDriveInfo(AOnRefreshed);
  if Letter = #0 then
    Exit(False);
  Idx := IndexOfDriveLetter(Drives, Letter);
  if Idx < 0 then
    Exit(False);
  AInfo := Drives[Idx];
  Result := True;
end;

function DriveLetterFromPath(const APath: string): Char;
begin
  Result := PlatformDriveLetterOfPath(APath);
end;

function UncShareRoot(const APath: string): string;
var
  P, ServerEnd, ShareEnd: Integer;
begin
  Result := '';
  if (Length(APath) < 5) or (APath[1] <> '\') or (APath[2] <> '\') then
    Exit;
  // The long-path form (\\?\UNC\srv\share) names the same share.
  if SameText(Copy(APath, 1, 8), '\\?\UNC\') then
    P := 9
  else if (APath[3] = '?') or (APath[3] = '.') then
    Exit
  else
    P := 3;
  ServerEnd := P;
  while (ServerEnd <= Length(APath)) and (APath[ServerEnd] <> '\') do
    Inc(ServerEnd);
  if (ServerEnd = P) or (ServerEnd > Length(APath)) then
    Exit;
  ShareEnd := ServerEnd + 1;
  while (ShareEnd <= Length(APath)) and (APath[ShareEnd] <> '\') do
    Inc(ShareEnd);
  if ShareEnd = ServerEnd + 1 then
    Exit;
  Result := '\\' + Copy(APath, P, ShareEnd - P);
end;

function AppendUncShares(const ADrives: TDriveInfoArray;
  const APaths: TArray<string>; AMax: Integer): TDriveInfoArray;
var
  Shares: TArray<string>;
  Share: string;
  I, J: Integer;
  Known: Boolean;
  Entry: TDriveInfo;
begin
  Result := Copy(ADrives);
  SetLength(Shares, 0);
  for I := 0 to High(APaths) do
  begin
    if Length(Shares) >= AMax then
      Break;
    Share := UncShareRoot(APaths[I]);
    if Share = '' then
      Continue;
    Known := False;
    for J := 0 to High(Shares) do
      if SameText(Shares[J], Share) then
        Known := True;
    for J := 0 to High(ADrives) do
      if SameText(ExcludeTrailingPathDelimiter(ADrives[J].LabelOrPath), Share) then
        Known := True;
    if not Known then
      Shares := Shares + [Share];
  end;
  for Share in Shares do
  begin
    Entry := Default(TDriveInfo);
    Entry.Letter := #0;
    Entry.RootPath := Share + '\';
    Entry.KindLabel := 'Network';
    Entry.LabelOrPath := Share;
    Result := Result + [Entry];
  end;
end;

function IndexOfDriveLetter(const ADrives: TDriveInfoArray; ALetter: Char): Integer;
var
  I: Integer;
begin
  Result := -1;
  ALetter := UpCase(ALetter);
  if (ALetter < 'A') or (ALetter > 'Z') then
    Exit;
  for I := 0 to High(ADrives) do
    if ADrives[I].Letter = ALetter then
      Exit(I);
end;

function CycleDriveIndex(ACount, ACurrentIndex, ADelta: Integer): Integer;
begin
  if (ACount <= 0) or (ADelta = 0) then
    Exit(ACurrentIndex);
  if ACurrentIndex < 0 then
  begin
    if ADelta > 0 then
      Result := 0
    else
      Result := ACount - 1;
  end
  else
    Result := ((ACurrentIndex + ADelta) mod ACount + ACount) mod ACount;
end;

function ChangeDriveSpecialGlyph(AIndex: Integer): Char;
begin
  if (AIndex < 0) or (AIndex >= ChangeDriveItemCount) then
    Exit(#0);
  Result := Char(Ord('1') + AIndex);
end;

function IsChangeDriveSpecialGlyph(AGlyph: Char): Boolean;
begin
  Result := (AGlyph >= '1') and
    (AGlyph <= Char(Ord('0') + ChangeDriveItemCount));
end;

function TryChangeDriveSpecialUri(AGlyph: Char; out AUri: string): Boolean;
var
  Idx: Integer;
begin
  AUri := '';
  Result := False;
  if not IsChangeDriveSpecialGlyph(AGlyph) then
    Exit;
  Idx := Ord(AGlyph) - Ord('1');
  AUri := ChangeDriveItemUri(Idx);
  Result := True;
end;

function UriSchemeOfItem(const AUri: string): string;
var
  P: Integer;
begin
  P := Pos('://', AUri);
  if P > 1 then
    Result := LowerCase(Copy(AUri, 1, P - 1))
  else
    Result := '';
end;

function DriveBarGlyphFromUri(const AUri: string): Char;
var
  Items: TArray<TDriveItem>;
  Scheme: string;
  I: Integer;
begin
  if IsSystemFoldersUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(0));
  if IsRecycleBinUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(1));
  if IsTmpPanelUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(2));
  if IsWorkspaceUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(3));
  // A plugin item owns every URI of its scheme (net:///, net://work/dir).
  Scheme := UriSchemeOfItem(AUri);
  if Scheme <> '' then
  begin
    Items := DriveItems.Items;
    for I := 0 to High(Items) do
      if SameText(UriSchemeOfItem(Items[I].Uri), Scheme) then
        Exit(ChangeDriveSpecialGlyph(ChangeDriveSpecialCount + I));
  end;
  Result := DriveLetterFromPath(FileUriToPath(AUri));
end;

function DrivePopupCursorIndex(const ADrives: TDriveInfoArray;
  const AUri: string): Integer;
var
  Glyph: Char;
  DriveIdx: Integer;
begin
  Glyph := DriveBarGlyphFromUri(AUri);
  if IsChangeDriveSpecialGlyph(Glyph) then
    Exit(Length(ADrives) + 1 + (Ord(Glyph) - Ord('1')));
  DriveIdx := IndexOfDriveLetter(ADrives, Glyph);
  if DriveIdx >= 0 then
    Exit(DriveIdx);
  Result := 0;
end;

function EnumDriveBarGlyphs: TArray<Char>;
var
  Drives: TDriveInfoArray;
  I, N: Integer;
begin
  // Fast (letters only) -- this runs on every drive-bar repaint, so it must
  // never touch GetVolumeInformation/GetDiskFreeSpaceEx (see EnumLogicalDrivesFast).
  Drives := EnumLogicalDrivesFast;
  N := Length(Drives);
  SetLength(Result, N + ChangeDriveItemCount);
  for I := 0 to N - 1 do
    Result[I] := Drives[I].Letter;
  for I := 0 to ChangeDriveItemCount - 1 do
    Result[N + I] := ChangeDriveSpecialGlyph(I);
end;

function IndexOfDriveBarGlyph(const AGlyphs: TArray<Char>; AGlyph: Char): Integer;
var
  I: Integer;
  Want: Char;
begin
  Result := -1;
  if AGlyph = #0 then
    Exit;
  if IsChangeDriveSpecialGlyph(AGlyph) then
    Want := AGlyph
  else
    Want := UpCase(AGlyph);
  for I := 0 to High(AGlyphs) do
    if AGlyphs[I] = Want then
      Exit(I);
end;

function DriveBarCellWidth(ADriveCount, ASpecialCount: Integer): Integer;
begin
  Result := 2 * (ADriveCount + ASpecialCount) + 3;
  if (ADriveCount > 0) and (ASpecialCount > 0) then
    Inc(Result, 2);
end;

procedure FitDriveBarGlyphs(AMaxWidth: Integer; out AGlyphs: TArray<Char>;
  out ADriveCount: Integer; out AShowSep: Boolean);
var
  All: TArray<Char>;
  I, DriveN, SpecialN, OrigDriveN: Integer;
begin
  SetLength(AGlyphs, 0);
  ADriveCount := 0;
  AShowSep := False;
  All := EnumDriveBarGlyphs;
  OrigDriveN := 0;
  while (OrigDriveN < Length(All)) and
        not IsChangeDriveSpecialGlyph(All[OrigDriveN]) do
    Inc(OrigDriveN);
  DriveN := OrigDriveN;
  SpecialN := Length(All) - OrigDriveN;
  while (DriveN > 0) and (DriveBarCellWidth(DriveN, SpecialN) > AMaxWidth) do
    Dec(DriveN);
  while (SpecialN > 0) and (DriveBarCellWidth(DriveN, SpecialN) > AMaxWidth) do
    Dec(SpecialN);
  if (DriveN = 0) and (SpecialN = 0) then
    Exit;
  SetLength(AGlyphs, DriveN + SpecialN);
  for I := 0 to DriveN - 1 do
    AGlyphs[I] := All[I];
  for I := 0 to SpecialN - 1 do
    AGlyphs[DriveN + I] := All[OrigDriveN + I];
  ADriveCount := DriveN;
  AShowSep := (DriveN > 0) and (SpecialN > 0);
end;

initialization

finalization
  // Workers blocked on an unresponsive drive outlive the main block; stop
  // them touching GDriveInfoCache (or the heap) once they wake. The lock is
  // deliberately never deleted: those late workers still enter it.
  LockDriveInfo;
  GDriveInfoShuttingDown := True;
  UnlockDriveInfo;

end.
