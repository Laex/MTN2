unit uDualPanelInfoPanel;

{ FAR/NDN Ctrl+L information panel (host/disk/memory). Extracted from
  TDualPanelWindow.DrawPanelInfoContent — the host only supplies path and
  directory totals. }

interface

uses
  System.SysUtils, System.Math, System.UITypes,
  uTerminalTypes, uThemeTypes, uDriveInfo;

procedure DrawPanelInfoContent(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI;
  AFrame, ABodyBg: TAlphaColor; const APath: string;
  ABytes: Int64; AFiles, AFolders: Integer);

implementation

uses
  Winapi.Windows, uStrings;

const
  cFileFg   = TAlphaColor($FFAAAAAA);
  cHeaderFg = TAlphaColor($FF55FFFF);

procedure DrawPanelInfoContent(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI;
  AFrame, ABodyBg: TAlphaColor; const APath: string;
  ABytes: Int64; AFiles, AFolders: Integer);
var
  Path, Serial, Comp, User, Domain, Profile, Access, Elevated, DiskTitle: string;
  Info: TDriveInfo;
  X, Y, InnerW, MaxY: Integer;
  Fg, ValFg, DiscardBg: TAlphaColor;
  CompBuf, UserBuf: array[0..255] of Char;
  CompLen, UserLen: DWORD;
  Used: Int64;
  Mem: TMemoryStatusEx;
  Token: THandle;
  Elev: TOKEN_ELEVATION;
  ElevSz: DWORD;
  IsElev: Boolean;
  Tick: UInt64;
  Days, Hours, Mins: Integer;

  procedure PutRaw(AX, AY: Integer; const AText: string; AFg: TAlphaColor);
  var
    T: string;
  begin
    if (AY < ABounds.Top + 1) or (AY > MaxY) then
      Exit;
    T := AText;
    if Length(T) > InnerW then
      T := Copy(T, 1, InnerW);
    PutGridText(ABuffer, AX, AY, T, AFg, ABodyBg);
  end;

  procedure PutCentered(const AText: string; AFg: TAlphaColor);
  var
    T: string;
    Pad: Integer;
  begin
    if Y > MaxY then
      Exit;
    T := AText;
    if Length(T) > InnerW then
      T := Copy(T, 1, InnerW);
    Pad := Max((InnerW - Length(T)) div 2, 0);
    PutRaw(X + Pad, Y, T, AFg);
    Inc(Y);
  end;

  procedure PutSection(const ATitle: string);
  var
    Head, Line: string;
    I: Integer;
  begin
    if Y > MaxY then
      Exit;
    Head := '+[-] ' + ATitle + ' ';
    Line := Head;
    for I := Length(Head) + 1 to InnerW do
      Line := Line + chBoxH;
    if Length(Line) > InnerW then
      Line := Copy(Line, 1, InnerW);
    PutRaw(X, Y, Line, AFrame);
    Inc(Y);
  end;

  procedure PutLR(const AKey, AValue: string);
  var
    KeyPart, ValPart: string;
    Gap, I: Integer;
    Line: string;
  begin
    if (AValue = '') or (Y > MaxY) then
      Exit;
    KeyPart := AKey;
    ValPart := AValue;
    if Length(KeyPart) + 1 + Length(ValPart) > InnerW then
    begin
      if Length(ValPart) > InnerW - 8 then
        ValPart := Copy(ValPart, 1, Max(InnerW - 8, 4));
      if Length(KeyPart) + 1 + Length(ValPart) > InnerW then
        KeyPart := Copy(KeyPart, 1, Max(InnerW - Length(ValPart) - 1, 1));
    end;
    Gap := InnerW - Length(KeyPart) - Length(ValPart);
    if Gap < 1 then
      Gap := 1;
    Line := KeyPart;
    for I := 1 to Gap do
      Line := Line + ' ';
    PutRaw(X, Y, Copy(Line, 1, Length(KeyPart) + Gap), Fg);
    PutRaw(X + Length(KeyPart) + Gap, Y, ValPart, ValFg);
    Inc(Y);
  end;

  procedure PutBlank;
  begin
    if Y <= MaxY then
      Inc(Y);
  end;
begin
  Path := APath;

  InnerW := Max(ABounds.Width - 2, 10);
  X := ABounds.Left + 1;
  Y := ABounds.Top + 1;
  MaxY := ABounds.Bottom - 1;
  if Assigned(ATheme) then
  begin
    ATheme.ResolvePanelChromeColors(pcpListBody, True, Fg, DiscardBg);
    ATheme.ResolvePanelChromeColors(pcpColumnHeader, True, ValFg, DiscardBg);
  end
  else
  begin
    Fg := cFileFg;
    ValFg := cHeaderFg;
  end;
  FillGridRect(ABuffer, X, Y, ABounds.Right - 1, MaxY, ' ', Fg, ABodyBg);

  CompLen := Length(CompBuf);
  UserLen := Length(UserBuf);
  FillChar(CompBuf, SizeOf(CompBuf), 0);
  FillChar(UserBuf, SizeOf(UserBuf), 0);
  Comp := '';
  User := '';
  if GetComputerName(CompBuf, CompLen) then
    Comp := string(CompBuf);
  if GetUserName(UserBuf, UserLen) then
    User := string(UserBuf);
  Domain := GetEnvironmentVariable('USERDOMAIN');
  Profile := GetEnvironmentVariable('USERPROFILE');

  IsElev := False;
  if OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
  try
    ElevSz := SizeOf(Elev);
    if GetTokenInformation(Token, TokenElevation, @Elev, SizeOf(Elev), ElevSz) then
      IsElev := Elev.TokenIsElevated <> 0;
  finally
    CloseHandle(Token);
  end;
  if IsElev then
    Access := T('ui.info.administrator', 'Administrator')
  else
    Access := T('ui.info.user', 'User');
  if IsElev then
    Elevated := T('ui.info.yes', 'Yes')
  else
    Elevated := T('ui.info.noLimited', 'No (Limited)');

  PutLR(T('ui.info.computerName', 'Computer name:'), Comp);
  PutLR(T('ui.info.userName', 'User name:'), User);
  PutLR(T('ui.info.accessLevel', 'Access level:'), Access);
  PutLR(T('ui.info.elevated', 'Elevated:'), Elevated);
  PutBlank;

  PutSection(T('ui.info.currentDirectory', 'Current directory'));
  PutCentered(Path, ValFg);
  PutCentered(T('ui.info.files', '%d files with %s bytes',
    [AFiles, FormatByteCount(ABytes)]), Fg);
  PutCentered(T('ui.info.subdirs', '%d subdirs', [AFolders]), Fg);
  PutBlank;

  // Cached (non-blocking): this draws every repaint while Ctrl+L is active,
  // so it must not risk a GetVolumeInformation/GetDiskFreeSpaceEx hang.
  if TryCachedPathVolume(Path, Info) then
  begin
    // KindLabel is an English identifier ('Hard disk'); only the shown
    // text is translated.
    if Info.KindLabel = 'Hard disk' then
      DiskTitle := T('ui.info.fixedDisk', 'Fixed disk')
    else
      DiskTitle := DriveKindTitle(Info.KindLabel);
    DiskTitle := Format('%s %s', [DiskTitle, Info.RootPath]);
    if Info.FsName <> '' then
      DiskTitle := DiskTitle + ' (' + Info.FsName + ')';
    PutSection(DiskTitle);
    Used := Info.TotalBytes - Info.FreeBytes;
    if Used < 0 then
      Used := 0;
    PutLR(T('ui.info.spaceTotal', 'Space, total:'), FormatSizeFar(Info.TotalBytes));
    PutLR(T('ui.info.spaceAvailable', 'Space, available:'), FormatPctSize(Info.FreeBytes, Info.TotalBytes));
    PutLR(T('ui.info.spaceUsed', 'Space, used:'), FormatPctSize(Used, Info.TotalBytes));
    if Info.LabelOrPath <> '' then
      PutLR(T('ui.info.volumeLabel', 'Volume label:'), Info.LabelOrPath);
    Serial := FormatVolumeSerial(Info.SerialNumber);
    if Serial <> '' then
      PutLR(T('ui.info.serialNumber', 'Serial number:'), Serial);
    if Info.VolumeFlags <> 0 then
      PutLR(T('ui.info.volumeFlags', 'Volume flags:'), IntToStr(Info.VolumeFlags));
  end
  else
  begin
    PutSection(T('ui.info.disk', 'Disk'));
    PutCentered(T('ui.info.diskUnavailable', 'Disk information unavailable'), Fg);
  end;
  PutBlank;

  FillChar(Mem, SizeOf(Mem), 0);
  Mem.dwLength := SizeOf(Mem);
  if GlobalMemoryStatusEx(Mem) then
  begin
    PutSection(T('ui.info.memory', 'Memory'));
    PutLR(T('ui.info.memoryLoad', 'Memory load:'), Format('%d%%', [Mem.dwMemoryLoad]));
    PutLR(T('ui.info.totalPhysical', 'Total Physical:'), FormatByteCount(Int64(Mem.ullTotalPhys)));
    PutLR(T('ui.info.availPhysical', 'Avail Physical:'), FormatByteCount(Int64(Mem.ullAvailPhys)));
    PutLR(T('ui.info.totalPageFile', 'Total PageFile:'), FormatByteCount(Int64(Mem.ullTotalPageFile)));
    PutLR(T('ui.info.availPageFile', 'Avail PageFile:'), FormatByteCount(Int64(Mem.ullAvailPageFile)));
    PutLR(T('ui.info.totalVirtual', 'Total Virtual:'), FormatByteCount(Int64(Mem.ullTotalVirtual)));
    PutLR(T('ui.info.availVirtual', 'Avail Virtual:'), FormatByteCount(Int64(Mem.ullAvailVirtual)));
  end;
  PutBlank;

  PutSection(T('ui.info.hostInfo', 'Host Info'));
  PutLR(T('ui.info.processId', 'Process ID:'), IntToStr(GetCurrentProcessId));
  if Profile <> '' then
    PutLR(T('ui.info.userProfile', 'User profile:'), Profile);
  if Domain <> '' then
    PutLR(T('ui.info.userDomain', 'Userdomain:'), Domain);
  PutLR(T('ui.info.os', 'OS:'), Format('[v%d.%d.%d] %s',
    [TOSVersion.Major, TOSVersion.Minor, TOSVersion.Build, TOSVersion.Name]));
  Tick := GetTickCount64;
  Days := Tick div (UInt64(24) * 60 * 60 * 1000);
  Hours := (Tick div (UInt64(60) * 60 * 1000)) mod 24;
  Mins := (Tick div (UInt64(60) * 1000)) mod 60;
  PutLR(T('ui.info.uptime', 'Uptime:'), T('ui.info.uptimeValue', '%dd %2.2d:%2.2d', [Days, Hours, Mins]));
  PutBlank;

  PutSection(T('ui.info.description', 'Description'));
  PutCentered(T('ui.info.noDescription', 'Folder description file is absent'), Fg);
end;

end.
