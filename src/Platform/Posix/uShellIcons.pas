unit uShellIcons;

{ Shell icons for the panel icon column (POSIX build). A text terminal draws
  no bitmaps, so without a decoder no icon is ever available and the file-kind
  glyph stays. A host that can show pictures (the SDL window) installs a
  decoder; the icon of a row is then the freedesktop theme icon of its MIME
  type (folders: the "folder" icon), decoded once and kept. The Windows build
  lives in Platform\Windows; each project puts exactly one of the two
  directories on its unit search path. }

interface

uses
  System.SysUtils, uDualPanelTypes;

const
  /// <summary>How many grid cells a shell icon occupies horizontally.</summary>
  cShellIconCells = 2;

type
  /// <summary>Fired on the main thread after icons land in the cache.</summary>
  TShellIconsReadyProc = reference to procedure;

  /// <summary>Decodes a picture file into 32-bit pixels (blue, green, red,
  /// alpha in memory order); False when it cannot be read.</summary>
  TShellIconDecoder = reference to function(const APath: string;
    out AWidth, AHeight: Integer; out APixels: TBytes): Boolean;

/// <summary>0: there is no icon.</summary>
function ShellIconIdForRow(const ARow: TPanelRow): Integer;
function ShellIconIdForRowWait(const ARow: TPanelRow): Integer;
procedure ShellIconsSetOnReady(const AProc: TShellIconsReadyProc);

/// <summary>Turns icons on; nil turns them off again.</summary>
procedure ShellIconsSetDecoder(const ADecoder: TShellIconDecoder);

/// <summary>The pixels of an icon id returned by ShellIconIdForRow.</summary>
function ShellIconPixels(AId: Integer; out AWidth, AHeight: Integer;
  out APixels: TBytes): Boolean;

implementation

uses
  System.Generics.Collections, uFdoIcons;

type
  TIconEntry = record
    Path: string;
    Width, Height: Integer;
    Pixels: TBytes;
    Loaded: Boolean;
    Usable: Boolean;
  end;

var
  GDecoder: TShellIconDecoder;
  GEntries: TList<TIconEntry>;
  GByPath: TDictionary<string, Integer>;
  // Row kind -> icon id (0 = none), so a kind is resolved against the themes once.
  GByKind: TDictionary<string, Integer>;

procedure ResetState;
begin
  FreeAndNil(GEntries);
  FreeAndNil(GByPath);
  FreeAndNil(GByKind);
end;

function IdForPath(const APath: string): Integer;
var
  Entry: TIconEntry;
begin
  if APath = '' then
    Exit(0);
  if GByPath.TryGetValue(APath, Result) then
    Exit;
  Entry := Default(TIconEntry);
  Entry.Path := APath;
  GEntries.Add(Entry);
  Result := GEntries.Count;
  GByPath.Add(APath, Result);
end;

function ResolveRowIcon(const ARow: TPanelRow): Integer;
var
  Name, Mime, Path: string;
begin
  if ARow.IsDirectory then
    Exit(IdForPath(FdoFindIcon('places', 'folder')));
  Name := ARow.Text;
  Mime := FdoMimeForFileName(Name);
  for Name in FdoIconNamesForMime(Mime) do
  begin
    Path := FdoFindIcon('mimetypes', Name);
    if Path <> '' then
      Exit(IdForPath(Path));
  end;
  Result := 0;
end;

function RowKind(const ARow: TPanelRow): string;
begin
  if ARow.IsDirectory then
    Exit('/');
  if ARow.Extension <> '' then
    Exit(LowerCase(ARow.Extension));
  Result := 'name:' + LowerCase(ARow.Text);
end;

function ShellIconIdForRow(const ARow: TPanelRow): Integer;
var
  Kind: string;
begin
  Result := 0;
  if not Assigned(GDecoder) or ARow.IsParent then
    Exit;
  Kind := RowKind(ARow);
  if GByKind.TryGetValue(Kind, Result) then
    Exit;
  Result := ResolveRowIcon(ARow);
  GByKind.Add(Kind, Result);
end;

function ShellIconIdForRowWait(const ARow: TPanelRow): Integer;
begin
  Result := ShellIconIdForRow(ARow);
end;

procedure ShellIconsSetOnReady(const AProc: TShellIconsReadyProc);
begin
end;

procedure ShellIconsSetDecoder(const ADecoder: TShellIconDecoder);
begin
  ResetState;
  GDecoder := ADecoder;
  if Assigned(ADecoder) then
  begin
    GEntries := TList<TIconEntry>.Create;
    GByPath := TDictionary<string, Integer>.Create;
    GByKind := TDictionary<string, Integer>.Create;
  end;
end;

function ShellIconPixels(AId: Integer; out AWidth, AHeight: Integer;
  out APixels: TBytes): Boolean;
var
  Entry: TIconEntry;
begin
  AWidth := 0;
  AHeight := 0;
  APixels := nil;
  Result := False;
  if not Assigned(GDecoder) or (AId < 1) or (AId > GEntries.Count) then
    Exit;
  Entry := GEntries[AId - 1];
  if not Entry.Loaded then
  begin
    Entry.Loaded := True;
    try
      Entry.Usable := GDecoder(Entry.Path, Entry.Width, Entry.Height, Entry.Pixels) and
        (Entry.Width > 0) and (Entry.Height > 0) and
        (Length(Entry.Pixels) >= Entry.Width * Entry.Height * 4);
    except
      Entry.Usable := False;
    end;
    GEntries[AId - 1] := Entry;
  end;
  if not Entry.Usable then
    Exit;
  AWidth := Entry.Width;
  AHeight := Entry.Height;
  APixels := Entry.Pixels;
  Result := True;
end;

initialization

finalization
  ResetState;

end.
