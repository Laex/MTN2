unit uDocumentProviders;

{ Open registration API for the code that opens a file in the viewer (F3) or
  the editor (F4), so a plugin can take over files of the types it knows.
  Mirrors uCommandRegistry.pas / uVfsRegistry.pas.

  A provider names the file name extensions it serves (".md", or "*" for every
  file) and the modes (view, edit). When a file is opened, the providers that
  match run in ascending priority order before the built-in viewer / editor.
  A provider answers one of:
    dokPass     - not mine; the next provider, then the built-in window, runs.
    dokHandled  - the plugin opened the file itself (its own window, an
                  external program); nothing more happens.
    dokRedirect - open ARedirectURI in the built-in window instead (the
                  plugin rendered the file to a text/Markdown file). The
                  redirect target is not offered to providers again.

  A provider that raises counts as dokPass. Everything runs on the main
  thread. Windows (viewer/editor tabs) stay the host's: a plugin never gets a
  canvas, only these three answers. }

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TDocumentOpenKind = (dokPass, dokHandled, dokRedirect);

  TDocumentMode = (dmView, dmEdit);
  TDocumentModes = set of TDocumentMode;

  TDocumentOpenHandler = reference to function(const AURI: string; AViewOnly: Boolean;
    out ARedirectURI: string): TDocumentOpenKind;

  IDocumentProviderRegistry = interface
    ['{2F8C4B71-6D3A-49E5-A1B0-7C5E9D2F4A83}']
    /// <summary>Adds a provider for the extensions in AExtensions (comma or
    /// semicolon separated, ".md,.markdown"; "*" = every file) in the given
    /// modes. A plugin's second registration with the same AProviderId replaces
    /// its first. Empty plugin id, no extensions, no modes or a nil handler are
    /// ignored.</summary>
    procedure RegisterProvider(const APluginId, AProviderId, AExtensions: string;
      AModes: TDocumentModes; AHandler: TDocumentOpenHandler; APriority: Integer = 100);
    /// <summary>Removes the providers of APluginId.</summary>
    procedure UnregisterPlugin(const APluginId: string);
    /// <summary>Asks the matching providers in order; the first answer other
    /// than dokPass wins. dokPass when none matches or none takes the file.</summary>
    function TryOpen(const AURI: string; AViewOnly: Boolean;
      out ARedirectURI: string): TDocumentOpenKind;
  end;

function DocumentProviders: IDocumentProviderRegistry;

/// <summary>Extension of the file a URI names (".md", lower-case), '' when the
/// last path segment has none. Works for file:// and plugin-scheme URIs,
/// including a path inside an archive (a.zip!/inner/f.txt).</summary>
function DocumentUriExtension(const AURI: string): string;

/// <summary>Opens a local file:// URI with the program the system associates
/// with it. False for any other scheme or a missing file. For plugins that run
/// native code; it is not offered to WASM guests, which would otherwise be
/// able to start programs.</summary>
function OpenUriWithSystem(const AURI: string): Boolean;

implementation

uses
  System.IOUtils, Winapi.Windows, Winapi.ShellAPI,
  uVfsTypes;

type
  TProviderEntry = record
    PluginId: string;
    ProviderId: string;
    Extensions: TArray<string>;
    Modes: TDocumentModes;
    Handler: TDocumentOpenHandler;
    Priority: Integer;
  end;

  TDocumentProviderRegistry = class(TInterfacedObject, IDocumentProviderRegistry)
  private
    FEntries: TList<TProviderEntry>;
    procedure SortEntries;
    class function Matches(const AEntry: TProviderEntry; const AExt: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterProvider(const APluginId, AProviderId, AExtensions: string;
      AModes: TDocumentModes; AHandler: TDocumentOpenHandler; APriority: Integer = 100);
    procedure UnregisterPlugin(const APluginId: string);
    function TryOpen(const AURI: string; AViewOnly: Boolean;
      out ARedirectURI: string): TDocumentOpenKind;
  end;

var
  GRegistry: IDocumentProviderRegistry;

function DocumentUriExtension(const AURI: string): string;
var
  Seg: string;
  P: Integer;
begin
  Seg := AURI;
  P := Seg.LastDelimiter('/\');
  if P >= 0 then
    Seg := Seg.Substring(P + 1);
  Result := LowerCase(TPath.GetExtension(Seg));
end;

function OpenUriWithSystem(const AURI: string): Boolean;
var
  Path: string;
begin
  Result := False;
  if not AURI.StartsWith('file:', True) then
    Exit;
  Path := FileUriToPath(AURI);
  if (Path = '') or not TFile.Exists(Path) then
    Exit;
  Result := ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL) > 32;
end;

constructor TDocumentProviderRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TProviderEntry>.Create;
end;

destructor TDocumentProviderRegistry.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TDocumentProviderRegistry.SortEntries;
var
  I, J: Integer;
  Tmp: TProviderEntry;
begin
  // Lower Priority number = earlier (stable insertion sort).
  for I := 1 to FEntries.Count - 1 do
  begin
    Tmp := FEntries[I];
    J := I - 1;
    while (J >= 0) and (FEntries[J].Priority > Tmp.Priority) do
    begin
      FEntries[J + 1] := FEntries[J];
      Dec(J);
    end;
    FEntries[J + 1] := Tmp;
  end;
end;

class function TDocumentProviderRegistry.Matches(const AEntry: TProviderEntry;
  const AExt: string): Boolean;
var
  E: string;
begin
  for E in AEntry.Extensions do
    if (E = '*') or ((AExt <> '') and (E = AExt)) then
      Exit(True);
  Result := False;
end;

procedure TDocumentProviderRegistry.RegisterProvider(const APluginId, AProviderId,
  AExtensions: string; AModes: TDocumentModes; AHandler: TDocumentOpenHandler;
  APriority: Integer);
var
  E: TProviderEntry;
  Part, Ext: string;
  I: Integer;
begin
  E.PluginId := Trim(APluginId);
  E.ProviderId := Trim(AProviderId);
  E.Modes := AModes;
  E.Handler := AHandler;
  E.Priority := APriority;
  SetLength(E.Extensions, 0);
  for Part in AExtensions.Split([',', ';']) do
  begin
    Ext := LowerCase(Trim(Part));
    if Ext = '' then
      Continue;
    if (Ext <> '*') and (Ext[1] <> '.') then
      Ext := '.' + Ext;
    SetLength(E.Extensions, Length(E.Extensions) + 1);
    E.Extensions[High(E.Extensions)] := Ext;
  end;
  if (E.PluginId = '') or (Length(E.Extensions) = 0) or (E.Modes = []) or
     not Assigned(AHandler) then
    Exit;
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].PluginId, E.PluginId) and
       SameText(FEntries[I].ProviderId, E.ProviderId) then
    begin
      FEntries[I] := E;
      SortEntries;
      Exit;
    end;
  FEntries.Add(E);
  SortEntries;
end;

procedure TDocumentProviderRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
end;

function TDocumentProviderRegistry.TryOpen(const AURI: string; AViewOnly: Boolean;
  out ARedirectURI: string): TDocumentOpenKind;
var
  Snapshot: TArray<TProviderEntry>;
  E: TProviderEntry;
  Ext, Redirect: string;
  Mode: TDocumentMode;
  Kind: TDocumentOpenKind;
begin
  ARedirectURI := '';
  Result := dokPass;
  if FEntries.Count = 0 then
    Exit;
  Ext := DocumentUriExtension(AURI);
  if AViewOnly then
    Mode := dmView
  else
    Mode := dmEdit;
  // A provider may unregister its plugin while it runs.
  Snapshot := FEntries.ToArray;
  for E in Snapshot do
  begin
    if not (Mode in E.Modes) or not Matches(E, Ext) then
      Continue;
    Redirect := '';
    try
      Kind := E.Handler(AURI, AViewOnly, Redirect);
    except
      Kind := dokPass;
    end;
    if (Kind = dokRedirect) and (Redirect = '') then
      Kind := dokPass;
    if Kind <> dokPass then
    begin
      ARedirectURI := Redirect;
      Exit(Kind);
    end;
  end;
end;

function DocumentProviders: IDocumentProviderRegistry;
begin
  if GRegistry = nil then
    GRegistry := TDocumentProviderRegistry.Create;
  Result := GRegistry;
end;

initialization

finalization
  GRegistry := nil;

end.
