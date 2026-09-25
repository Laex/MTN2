unit uDriveInfo;

{ Enumerate local drive letters for the Alt+F1/F2 Change Drive popup.

  CROSS-PLATFORM (Этап 23): drive letters are a Windows-only concept, not
  just a Windows-only API call -- a POSIX port needs a different UI concept
  here (mounted filesystems under a single '/' tree), not a drop-in
  replacement for EnumLogicalDrives. Callers keying off TDriveInfo.Letter
  (uDualPanelWindow.pas, uDualPanelDrivePopup.pas) will need a parallel path
  for that case, not just a portable data source. }

interface

uses
  System.SysUtils;

type
  TDriveInfo = record
    Letter: Char;
    RootPath: string;    // e.g. 'C:\'
    KindLabel: string;   // Hard disk / Removable / Network / …
    FsName: string;      // NTFS, FAT32, …
    LabelOrPath: string; // volume label or UNC for network
    TotalBytes: Int64;
    FreeBytes: Int64;
    SerialNumber: Cardinal;
    VolumeFlags: Cardinal;
  end;

  TDriveInfoArray = TArray<TDriveInfo>;

/// <summary>Letters + KindLabel only -- GetLogicalDriveStrings/GetDriveType,
/// no GetVolumeInformation/GetDiskFreeSpaceEx. Those two touch the actual
/// filesystem and can block for a long time (even minutes) on an
/// unresponsive network share; GetDriveType does not. Safe to call from a
/// paint routine every frame -- see EnumDriveBarGlyphs.</summary>
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
function DriveKindLabel(ADriveType: Cardinal): string;
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
/// <summary>'C:\Work' → 'C'; UNC / empty / relative → #0.</summary>
function DriveLetterFromPath(const APath: string): Char;
function IndexOfDriveLetter(const ADrives: TDriveInfoArray; ALetter: Char): Integer;
/// <summary>Wrap ACurrentIndex by ADelta. Missing current (ACurrentIndex&lt;0):
/// +delta starts at 0, −delta at last.</summary>
function CycleDriveIndex(ACount, ACurrentIndex, ADelta: Integer): Integer;

const
  /// <summary>Same numbered extras as Change Drive (Alt+F1/F2), after the
  /// physical drives. Glyphs are '1'.. so they never collide with A–Z.</summary>
  ChangeDriveSpecialCount = 4;
  ChangeDriveSpecialLabels: array[0..ChangeDriveSpecialCount - 1] of string =
    ('System folders', 'Recycle bin', 'Temporary', 'Workspace');
  ChangeDriveSpecialUris: array[0..ChangeDriveSpecialCount - 1] of string =
    ('sys://folders', 'recycle:///', 'tmp:///', 'ws:///');

/// <summary>ChangeDriveSpecialLabels[AIndex] as shown on screen (translated).</summary>
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
/// Length(ADrives)+1+special. Unknown URI → 0.</summary>
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
  System.Math, System.Classes,
  Winapi.Windows,
  uTerminalTypes, uVfsTypes, uStrings;

function ChangeDriveSpecialTitle(AIndex: Integer): string;
const
  cKeys: array[0..ChangeDriveSpecialCount - 1] of string =
    ('systemFolders', 'recycleBin', 'temporary', 'workspace');
begin
  if (AIndex < 0) or (AIndex >= ChangeDriveSpecialCount) then
    Exit('');
  Result := T('ui.drivePopup.' + cKeys[AIndex], ChangeDriveSpecialLabels[AIndex]);
end;

function DriveKindTitle(const AKindLabel: string): string;
begin
  if AKindLabel = '' then
    Result := ''
  else
    Result := T('ui.driveKind.' + AKindLabel, AKindLabel);
end;

function DriveKindLabel(ADriveType: Cardinal): string;
begin
  case ADriveType of
    DRIVE_REMOVABLE: Result := 'Removable';
    DRIVE_FIXED:     Result := 'Hard disk';
    DRIVE_REMOTE:    Result := 'Network';
    DRIVE_CDROM:     Result := 'CD-ROM';
    DRIVE_RAMDISK:   Result := 'RAM';
  else
    Result := '';
  end;
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
  // Use chBoxV (#$2502), not a UTF-8 literal — source encoding must not matter.
  Sep := ' ' + chBoxV + ' ';
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

function RemoteConnectionName(const ARoot: string): string;
var
  Buf: array[0..512] of Char;
  Len: DWORD;
begin
  Result := '';
  Len := Length(Buf);
  FillChar(Buf, SizeOf(Buf), 0);
  if WNetGetConnection(PChar(Copy(ARoot, 1, 2)), Buf, Len) = NO_ERROR then
    Result := string(Buf);
end;

function FormatVolumeSerial(ASerial: Cardinal): string;
begin
  if ASerial = 0 then
    Exit('');
  Result := Format('%.4X-%.4X', [HiWord(ASerial), LoWord(ASerial)]);
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

function FormatPctSize(APart, ATotal: Int64): string;
var
  Pct: Integer;
begin
  if ATotal <= 0 then
    Exit(FormatSizeFar(APart));
  Pct := EnsureRange(Round(100.0 * APart / ATotal), 0, 100);
  Result := Format('%d%%, %s', [Pct, FormatSizeFar(APart)]);
end;

function FillVolumeDetails(var AInfo: TDriveInfo; ADriveType: Cardinal): Boolean;
var
  VolName, FsName: array[0..255] of Char;
  Serial, MaxComp, Flags: DWORD;
  FreeAvail, TotalBytes, TotalFree: Int64;
begin
  Result := True;
  FillChar(VolName, SizeOf(VolName), 0);
  FillChar(FsName, SizeOf(FsName), 0);
  Serial := 0;
  MaxComp := 0;
  Flags := 0;
  AInfo.SerialNumber := 0;
  try
    if GetVolumeInformation(PChar(AInfo.RootPath), VolName, Length(VolName),
      @Serial, MaxComp, Flags, FsName, Length(FsName)) then
    begin
      AInfo.FsName := string(FsName);
      AInfo.LabelOrPath := string(VolName);
      AInfo.SerialNumber := Serial;
      AInfo.VolumeFlags := Flags;
    end
    else
    begin
      AInfo.FsName := '';
      AInfo.LabelOrPath := '';
      AInfo.VolumeFlags := 0;
    end;
  except
    AInfo.FsName := '';
    AInfo.LabelOrPath := '';
  end;

  if ADriveType = DRIVE_REMOTE then
  begin
    AInfo.LabelOrPath := RemoteConnectionName(AInfo.RootPath);
    if AInfo.LabelOrPath = '' then
      AInfo.LabelOrPath := AInfo.RootPath;
  end;

  AInfo.TotalBytes := 0;
  AInfo.FreeBytes := 0;
  try
    FreeAvail := 0;
    TotalBytes := 0;
    TotalFree := 0;
    if GetDiskFreeSpaceEx(PChar(AInfo.RootPath), FreeAvail, TotalBytes, @TotalFree) then
    begin
      AInfo.TotalBytes := TotalBytes;
      AInfo.FreeBytes := FreeAvail;
    end;
  except
    AInfo.TotalBytes := 0;
    AInfo.FreeBytes := 0;
  end;
end;

function TryQueryPathVolume(const APath: string; out AInfo: TDriveInfo): Boolean;
var
  Root: string;
  Dt: Cardinal;
begin
  AInfo.Letter := #0;
  AInfo.RootPath := '';
  AInfo.KindLabel := '';
  AInfo.FsName := '';
  AInfo.LabelOrPath := '';
  AInfo.TotalBytes := 0;
  AInfo.FreeBytes := 0;
  AInfo.SerialNumber := 0;
  AInfo.VolumeFlags := 0;
  Result := False;
  Root := ExtractFileDrive(APath);
  if Root = '' then
    Exit;
  if (Length(Root) >= 2) and (Root[2] = ':') then
    AInfo.Letter := UpCase(Root[1])
  else
    Exit;
  AInfo.RootPath := AInfo.Letter + ':' + PathDelim;
  Dt := GetDriveType(PChar(AInfo.RootPath));
  if Dt = DRIVE_NO_ROOT_DIR then
    Exit;
  AInfo.KindLabel := DriveKindLabel(Dt);
  FillVolumeDetails(AInfo, Dt);
  Result := True;
end;

function EnumLogicalDrivesCore(AFillDetails: Boolean): TDriveInfoArray;
var
  Buf: array[0..512] of Char;
  P: PChar;
  Root: string;
  Info: TDriveInfo;
  List: TDriveInfoArray;
  N: Integer;
  Dt: Cardinal;
begin
  SetLength(List, 0);
  FillChar(Buf, SizeOf(Buf), 0);
  if GetLogicalDriveStrings(Length(Buf) - 1, Buf) = 0 then
    Exit(List);

  P := Buf;
  while P^ <> #0 do
  begin
    Root := string(P);
    if (Length(Root) >= 2) and (Root[2] = ':') then
    begin
      Dt := GetDriveType(PChar(Root));
      if Dt <> DRIVE_NO_ROOT_DIR then
      begin
        Info.Letter := UpCase(Root[1]);
        Info.RootPath := Info.Letter + ':' + PathDelim;
        Info.KindLabel := DriveKindLabel(Dt);
        Info.FsName := '';
        Info.LabelOrPath := '';
        Info.TotalBytes := 0;
        Info.FreeBytes := 0;
        Info.SerialNumber := 0;
        Info.VolumeFlags := 0;
        if AFillDetails then
          FillVolumeDetails(Info, Dt);
        N := Length(List);
        SetLength(List, N + 1);
        List[N] := Info;
      end;
    end;
    Inc(P, StrLen(P) + 1);
  end;
  Result := List;
end;

function EnumLogicalDrivesFast: TDriveInfoArray;
begin
  Result := EnumLogicalDrivesCore(False);
end;

function EnumLogicalDrives: TDriveInfoArray;
begin
  Result := EnumLogicalDrivesCore(True);
end;

var
  /// <summary>A plain record in the data segment, not a heap object: a
  /// worker stuck on an unresponsive drive can wake up after the RTL has
  /// shut the memory manager down, and must still be able to take the lock
  /// to see GDriveInfoShuttingDown.</summary>
  GDriveInfoLock: TRTLCriticalSection;
  GDriveInfoCache: TDriveInfoArray;
  GDriveInfoCacheReady: Boolean;
  /// <summary>Drive letters with a worker thread currently running
  /// FillVolumeDetails for them -- the per-drive dedup key. A drive stuck
  /// here forever (an unresponsive network share) simply never gets
  /// re-queried; it does NOT block any other drive's worker or result.</summary>
  GDriveInfoInFlight: TArray<Char>;
  /// <summary>Set by finalization under GDriveInfoLock. A worker still stuck
  /// on an unresponsive drive can return after the program's main block
  /// ends -- by then globals and the heap are being torn down, so it must
  /// leave without touching either (see StartDriveWorker).</summary>
  GDriveInfoShuttingDown: Boolean;

procedure LockDriveInfo; inline;
begin
  EnterCriticalSection(GDriveInfoLock);
end;

procedure UnlockDriveInfo; inline;
begin
  LeaveCriticalSection(GDriveInfoLock);
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
/// forever in FillVolumeDetails must not stop C:/D:/... from getting their
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
      Dt: Cardinal;
      Idx: Integer;
    begin
      Info.Letter := ALetter;
      Info.RootPath := ALetter + ':' + PathDelim;
      Dt := GetDriveType(PChar(Info.RootPath));
      Info.KindLabel := DriveKindLabel(Dt);
      Info.FsName := '';
      Info.LabelOrPath := '';
      Info.TotalBytes := 0;
      Info.FreeBytes := 0;
      Info.SerialNumber := 0;
      Info.VolumeFlags := 0;
      FillVolumeDetails(Info, Dt); // the slow part -- may block for a long time
      LockDriveInfo;
      if GDriveInfoShuttingDown then
      begin
        // Woke up after finalization: the heap may already be gone, so even
        // releasing this frame's strings or the TThread object would fault.
        // The process is ending anyway -- leave without any RTL cleanup.
        UnlockDriveInfo;
        ExitThread(0);
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
  if (Length(APath) >= 2) and (APath[2] = ':') then
    Result := UpCase(APath[1])
  else
    Result := #0;
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
  if (AIndex < 0) or (AIndex >= ChangeDriveSpecialCount) then
    Exit(#0);
  Result := Char(Ord('1') + AIndex);
end;

function IsChangeDriveSpecialGlyph(AGlyph: Char): Boolean;
begin
  Result := (AGlyph >= '1') and
    (AGlyph <= Char(Ord('0') + ChangeDriveSpecialCount));
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
  AUri := ChangeDriveSpecialUris[Idx];
  Result := True;
end;

function DriveBarGlyphFromUri(const AUri: string): Char;
begin
  if IsSystemFoldersUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(0));
  if IsRecycleBinUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(1));
  if IsTmpPanelUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(2));
  if IsWorkspaceUri(AUri) then
    Exit(ChangeDriveSpecialGlyph(3));
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
  SetLength(Result, N + ChangeDriveSpecialCount);
  for I := 0 to N - 1 do
    Result[I] := Drives[I].Letter;
  for I := 0 to ChangeDriveSpecialCount - 1 do
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
  InitializeCriticalSection(GDriveInfoLock);

finalization
  // Workers blocked on an unresponsive drive outlive the main block; stop
  // them touching GDriveInfoCache (or the heap) once they wake. The lock is
  // deliberately never deleted: those late workers still enter it.
  LockDriveInfo;
  GDriveInfoShuttingDown := True;
  UnlockDriveInfo;

end.
