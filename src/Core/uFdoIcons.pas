unit uFdoIcons;

{ File type icons from the freedesktop.org data of the machine: the MIME type
  of a file name comes from the shared-mime-info glob list, the icon names for
  a MIME type from its generic-icons list, and the icon file from the icon
  themes installed under the XDG data directories. Everything is looked up
  lazily and cached; a missing file or theme only means "no icon". Used from
  the main thread only. }

interface

uses
  System.SysUtils;

/// <summary>MIME type of a file name by its glob (extension or whole name);
/// '' when the name matches nothing.</summary>
function FdoMimeForFileName(const AName: string): string;

/// <summary>Icon names to try for a MIME type, most specific first: the type
/// itself with '/' written as '-', its generic icon, the media-type icon.</summary>
function FdoIconNamesForMime(const AMime: string): TArray<string>;

/// <summary>Path of the icon file for a name in a context ("mimetypes" or
/// "places"), taken from the first theme that has it; '' when none does.</summary>
function FdoFindIcon(const AContext, AName: string): string;

/// <summary>Replaces the places the data is read from, for tests: the glob list,
/// the generic-icons list, the icon base directories and the theme names to
/// try in order. Clears every cache.</summary>
procedure FdoSetSources(const AGlobsFile, AGenericIconsFile: string;
  const AIconDirs, AThemes: TArray<string>);

/// <summary>Back to the data of the machine.</summary>
procedure FdoUseSystemSources;

implementation

uses
  System.Classes, System.IOUtils, System.Generics.Collections;

const
  cGlobsFile = '/usr/share/mime/globs2';
  cGenericIconsFile = '/usr/share/mime/generic-icons';
  // Sizes are tried in this order: large enough to shrink cleanly into a row.
  cIconSizes: array[0..8] of Integer = (32, 24, 22, 48, 16, 64, 96, 128, 256);
  cFallbackThemes: array[0..4] of string = ('Adwaita', 'Yaru', 'breeze', 'Papirus', 'hicolor');

var
  GGlobsFile, GGenericFile: string;
  GIconDirs, GThemes: TArray<string>;
  GCustom: Boolean;
  GSuffixes, GLiterals, GGeneric: TDictionary<string, string>;
  GGlobsLoaded, GGenericLoaded: Boolean;
  GIconCache: TDictionary<string, string>;
  GDirs, GThemeList: TArray<string>;
  GSourcesReady: Boolean;

procedure ResetCaches;
begin
  FreeAndNil(GSuffixes);
  FreeAndNil(GLiterals);
  FreeAndNil(GGeneric);
  FreeAndNil(GIconCache);
  GGlobsLoaded := False;
  GGenericLoaded := False;
  GSourcesReady := False;
  GDirs := nil;
  GThemeList := nil;
end;

procedure FdoSetSources(const AGlobsFile, AGenericIconsFile: string;
  const AIconDirs, AThemes: TArray<string>);
begin
  ResetCaches;
  GCustom := True;
  GGlobsFile := AGlobsFile;
  GGenericFile := AGenericIconsFile;
  GIconDirs := AIconDirs;
  GThemes := AThemes;
end;

procedure FdoUseSystemSources;
begin
  ResetCaches;
  GCustom := False;
end;

procedure LoadGlobs;
var
  Lines: TStringList;
  Line, Mime, Glob: string;
  Parts: TArray<string>;
  Key: string;
begin
  if GGlobsLoaded then
    Exit;
  GGlobsLoaded := True;
  GSuffixes := TDictionary<string, string>.Create;
  GLiterals := TDictionary<string, string>.Create;
  if GCustom then
    Key := GGlobsFile
  else
    Key := cGlobsFile;
  if not TFile.Exists(Key) then
    Exit;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(Key, TEncoding.UTF8);
    except
      Exit;
    end;
    // The list is sorted by weight, so the first entry of a glob wins.
    for Line in Lines do
    begin
      if (Line = '') or (Line[1] = '#') then
        Continue;
      Parts := Line.Split([':']);
      if Length(Parts) < 3 then
        Continue;
      Mime := Parts[1];
      Glob := LowerCase(Parts[2]);
      if Glob = '' then
        Continue;
      if (Glob[1] = '*') and (Glob.IndexOfAny(['*', '?', '['], 1) < 0) then
        GSuffixes.TryAdd(Copy(Glob, 2, MaxInt), Mime)
      else if Glob.IndexOfAny(['*', '?', '[']) < 0 then
        GLiterals.TryAdd(Glob, Mime);
    end;
  finally
    Lines.Free;
  end;
end;

procedure LoadGeneric;
var
  Lines: TStringList;
  Line, Key: string;
  P: Integer;
begin
  if GGenericLoaded then
    Exit;
  GGenericLoaded := True;
  GGeneric := TDictionary<string, string>.Create;
  if GCustom then
    Key := GGenericFile
  else
    Key := cGenericIconsFile;
  if not TFile.Exists(Key) then
    Exit;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(Key, TEncoding.UTF8);
    except
      Exit;
    end;
    for Line in Lines do
    begin
      P := Pos(':', Line);
      if (P > 1) and (Line[1] <> '#') then
        GGeneric.TryAdd(Copy(Line, 1, P - 1), Copy(Line, P + 1, MaxInt));
    end;
  finally
    Lines.Free;
  end;
end;

function FdoMimeForFileName(const AName: string): string;
var
  Lower: string;
  I: Integer;
begin
  LoadGlobs;
  Lower := LowerCase(AName);
  if GLiterals.TryGetValue(Lower, Result) then
    Exit;
  // The longest suffix first, so "x.tar.gz" is an archive and not a gzip stream alone.
  for I := 1 to Length(Lower) do
    if (Lower[I] = '.') and GSuffixes.TryGetValue(Copy(Lower, I, MaxInt), Result) then
      Exit;
  Result := '';
end;

function FdoIconNamesForMime(const AMime: string): TArray<string>;
var
  Names: TList<string>;
  Generic: string;
  P: Integer;
begin
  Names := TList<string>.Create;
  try
    if AMime <> '' then
    begin
      LoadGeneric;
      Names.Add(StringReplace(AMime, '/', '-', [rfReplaceAll]));
      if GGeneric.TryGetValue(AMime, Generic) then
        Names.Add(Generic);
      P := Pos('/', AMime);
      if P > 1 then
        Names.Add(Copy(AMime, 1, P - 1) + '-x-generic');
    end;
    Names.Add('text-x-generic');
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

function GtkThemeName: string;
var
  Home, Candidate, Line: string;
  Lines: TStringList;
begin
  Result := '';
  Home := GetEnvironmentVariable('HOME');
  for Candidate in [TPath.Combine(Home, '.config/gtk-3.0/settings.ini'),
                    TPath.Combine(Home, '.config/gtk-4.0/settings.ini')] do
  begin
    if not TFile.Exists(Candidate) then
      Continue;
    Lines := TStringList.Create;
    try
      try
        Lines.LoadFromFile(Candidate, TEncoding.UTF8);
      except
        Continue;
      end;
      for Line in Lines do
        if Line.StartsWith('gtk-icon-theme-name', True) and (Pos('=', Line) > 0) then
          Exit(Trim(Copy(Line, Pos('=', Line) + 1, MaxInt)));
    finally
      Lines.Free;
    end;
  end;
end;

procedure PrepareSources;
var
  Dirs, Themes: TList<string>;
  Home, DataHome, DataDirs, D, T, Chosen: string;
begin
  if GSourcesReady then
    Exit;
  GSourcesReady := True;
  GIconCache := TDictionary<string, string>.Create;
  if GCustom then
  begin
    GDirs := GIconDirs;
    GThemeList := GThemes;
    Exit;
  end;
  Home := GetEnvironmentVariable('HOME');
  DataHome := GetEnvironmentVariable('XDG_DATA_HOME');
  if DataHome = '' then
    DataHome := TPath.Combine(Home, '.local/share');
  DataDirs := GetEnvironmentVariable('XDG_DATA_DIRS');
  if DataDirs = '' then
    DataDirs := '/usr/local/share:/usr/share';
  Dirs := TList<string>.Create;
  Themes := TList<string>.Create;
  try
    Dirs.Add(TPath.Combine(DataHome, 'icons'));
    Dirs.Add(TPath.Combine(Home, '.icons'));
    for D in DataDirs.Split([':']) do
      if D <> '' then
        Dirs.Add(TPath.Combine(D, 'icons'));
    Chosen := GtkThemeName;
    if Chosen <> '' then
      Themes.Add(Chosen);
    for T in cFallbackThemes do
      if not Themes.Contains(T) then
        Themes.Add(T);
    GDirs := Dirs.ToArray;
    GThemeList := Themes.ToArray;
  finally
    Dirs.Free;
    Themes.Free;
  end;
end;

function ProbeTheme(const AThemeDir, AContext, AName: string): string;
var
  Size: Integer;
  S: string;

  function Try_(const ARelative: string): Boolean;
  var
    Ext: string;
  begin
    for Ext in ['.png', '.svg'] do
      if TFile.Exists(TPath.Combine(AThemeDir, ARelative + Ext)) then
      begin
        Result := True;
        S := TPath.Combine(AThemeDir, ARelative + Ext);
        Exit;
      end;
    Result := False;
  end;

begin
  Result := '';
  for Size in cIconSizes do
    if Try_(Format('%dx%d/%s/%s', [Size, Size, AContext, AName])) or
       Try_(Format('%d/%s/%s', [Size, AContext, AName])) or
       Try_(Format('%s/%d/%s', [AContext, Size, AName])) then
      Exit(S);
  if Try_(Format('scalable/%s/%s', [AContext, AName])) or
     Try_(Format('%s/scalable/%s', [AContext, AName])) then
    Result := S;
end;

function FdoFindIcon(const AContext, AName: string): string;
var
  Key, Theme, Dir, ThemeDir: string;
begin
  PrepareSources;
  Key := AContext + '/' + AName;
  if GIconCache.TryGetValue(Key, Result) then
    Exit;
  Result := '';
  for Theme in GThemeList do
  begin
    for Dir in GDirs do
    begin
      ThemeDir := TPath.Combine(Dir, Theme);
      if not TDirectory.Exists(ThemeDir) then
        Continue;
      Result := ProbeTheme(ThemeDir, AContext, AName);
      if Result <> '' then
        Break;
    end;
    if Result <> '' then
      Break;
  end;
  GIconCache.AddOrSetValue(Key, Result);
end;

initialization

finalization
  ResetCaches;

end.
