unit uPluginInfo;

{ What a plugin tells the user about itself. Two sources are combined:
  - the plugin's manifest: a description (per language), author, homepage and
    an optional help page (a Markdown file in the plugin's folder);
  - what the host itself saw the plugin register: commands and their keys,
    watched commands, file types it opens, folder kinds, archive types, menu
    items, status text, settings.
  The second part is always right and needs nothing from the plugin author;
  the first explains what it is for. The Plugins dialog shows both. }

interface

uses
  System.SysUtils;

type
  TPluginInfo = record
    Id: string;
    Name: string;
    Version: string;
    Author: string;
    Homepage: string;
    /// <summary>The manifest description in the user's language, '' if none.</summary>
    Description: string;
    /// <summary>Full path of the help page (Markdown) in the user's language, '' if none.</summary>
    HelpFile: string;
    /// <summary>What the host saw the plugin register, one line each.</summary>
    Provides: TArray<string>;
    HasSettings: Boolean;
    /// <summary>What the manifest asks the user to allow, one line each, with the
    /// state ("granted" or "not granted").</summary>
    Permissions: TArray<string>;
  end;

/// <summary>Reads the manifest in APluginDir (may be missing) and asks every
/// registry what APluginId registered.</summary>
function BuildPluginInfo(const APluginId, APluginDir: string): TPluginInfo;

/// <summary>The text of the information dialog, wrapped to AWidth characters,
/// one list row per line.</summary>
function PluginInfoLines(const AInfo: TPluginInfo; AWidth: Integer): TArray<string>;

/// <summary>What a permission lets the plugin do, in the user's language, with the
/// permission's own name in brackets ("... (vfs.read)").</summary>
function PermissionDescription(const AName: string): string;

/// <summary>Splits AText at spaces into lines of at most AWidth characters
/// (a longer word is cut). AIndent is put in front of every line after the first.</summary>
function WrapInfoText(const AText: string; AWidth: Integer;
  const AIndent: string = ''): TArray<string>;

implementation

uses
  System.Generics.Collections,
  uStrings, uPluginManifest, uPluginPermissions, uCommandRegistry, uDocumentProviders, uPanelPluginRegistry,
  uMenuRegistry, uKeymapRegistry, uPluginChrome, uPluginSettings, uVfsRegistry, uPluginHighlight;

procedure AddAll(AInto: TList<string>; const ALines: TArray<string>);
var
  L: string;
begin
  for L in ALines do
    AInto.Add(L);
end;

function BuildPluginInfo(const APluginId, APluginDir: string): TPluginInfo;
var
  M: TPluginManifest;
  Lines, Perms: TList<string>;
  Locale, P: string;
begin
  Result := Default(TPluginInfo);
  Result.Id := APluginId;
  Result.Name := APluginId;
  Locale := CurrentLocale;
  if TryReadPluginManifest(APluginDir, M) then
  begin
    if M.Name <> '' then
      Result.Name := M.Name;
    Result.Version := M.Version;
    Result.Author := M.Author;
    Result.Homepage := M.Homepage;
    Result.Description := ManifestDescription(M, Locale);
    Result.HelpFile := ManifestHelpFile(M, APluginDir, Locale);
  end;
  Lines := TList<string>.Create;
  try
    AddAll(Lines, CommandRegistry.DescribePlugin(APluginId));
    AddAll(Lines, KeymapRegistry.DescribePlugin(APluginId));
    AddAll(Lines, MenuRegistry.DescribePlugin(APluginId));
    AddAll(Lines, DocumentProviders.DescribePlugin(APluginId));
    AddAll(Lines, PanelPluginRegistry.DescribePlugin(APluginId));
    AddAll(Lines, GlobalVfsRegistry.DescribePlugin(APluginId));
    AddAll(Lines, PluginChrome.DescribePlugin(APluginId));
  AddAll(Lines, DescribeHighlighters(APluginId));
    Result.HasSettings := PluginSettings.HasConfigure(APluginId);
    if Result.HasSettings then
      Lines.Add(T('ui.plugininfo.settings', 'Has settings (the Settings button)'));
    Result.Provides := Lines.ToArray;
  finally
    Lines.Free;
  end;
  Perms := TList<string>.Create;
  try
    for P in PluginPermissionsDeclared(APluginId) do
      if PluginPermissionGranted(APluginId, P) then
        Perms.Add(P + ' - ' + T('ui.plugininfo.granted', 'granted'))
      else
        Perms.Add(P + ' - ' + T('ui.plugininfo.notGranted', 'not granted (the Permissions button)'));
    Result.Permissions := Perms.ToArray;
  finally
    Perms.Free;
  end;
end;


function WrapInfoText(const AText: string; AWidth: Integer;
  const AIndent: string): TArray<string>;
var
  Lines: TList<string>;
  Cur, W: string;
  First: Boolean;

  function Limit: Integer;
  begin
    if First then
      Result := AWidth
    else
      Result := AWidth - Length(AIndent);
  end;

  procedure Flush(const AText: string);
  begin
    if First then
      Lines.Add(AText)
    else
      Lines.Add(AIndent + AText);
    First := False;
  end;

begin
  if AWidth < Length(AIndent) + 8 then
    AWidth := Length(AIndent) + 8;
  Lines := TList<string>.Create;
  try
    First := True;
    Cur := '';
    for W in Trim(AText).Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty) do
    begin
      if Cur = '' then
        Cur := W
      else if Length(Cur) + 1 + Length(W) <= Limit then
        Cur := Cur + ' ' + W
      else
      begin
        Flush(Cur);
        Cur := W;
      end;
      // A word longer than a line is cut.
      while Length(Cur) > Limit do
      begin
        Flush(Copy(Cur, 1, Limit));
        Cur := Copy(Cur, Limit + 1, MaxInt);
      end;
    end;
    if Cur <> '' then
      Flush(Cur);
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

function PermissionDescription(const AName: string): string;
begin
  if SameText(AName, cPermVfsRead) then
    Result := T('ui.plugininfo.perm.vfsRead', 'read files and folders on any drive or archive') +
      ' (' + AName + ')'
  else
    Result := AName;
end;

/// <summary>"vfs.read - granted" shown as "read files and folders (vfs.read) - granted".</summary>
function PermissionTitle(const ALine: string): string;
var
  Name, Rest: string;
  P: Integer;
begin
  P := Pos(' - ', ALine);
  if P > 0 then
  begin
    Name := Copy(ALine, 1, P - 1);
    Rest := Copy(ALine, P);
  end
  else
  begin
    Name := ALine;
    Rest := '';
  end;
  Result := PermissionDescription(Name) + Rest;
end;

function PluginInfoLines(const AInfo: TPluginInfo; AWidth: Integer): TArray<string>;
var
  Lines: TList<string>;
  L, Head: string;
begin
  Lines := TList<string>.Create;
  try
    Head := AInfo.Name;
    if AInfo.Version <> '' then
      Head := Head + '  ' + AInfo.Version;
    Lines.Add(Head);
    if AInfo.Name <> AInfo.Id then
      Lines.Add(T('ui.plugininfo.id', 'Id: %s', [AInfo.Id]));
    Lines.Add('');
    if AInfo.Description <> '' then
      for L in WrapInfoText(AInfo.Description, AWidth) do
        Lines.Add(L)
    else
      Lines.Add(T('ui.plugininfo.noDescription', 'The plugin gives no description.'));
    Lines.Add('');
    if AInfo.Author <> '' then
      Lines.Add(T('ui.plugininfo.author', 'Author: %s', [AInfo.Author]));
    if AInfo.Homepage <> '' then
      Lines.Add(T('ui.plugininfo.homepage', 'Homepage: %s', [AInfo.Homepage]));
    if (AInfo.Author <> '') or (AInfo.Homepage <> '') then
      Lines.Add('');
    Lines.Add(T('ui.plugininfo.provides', 'What it adds to MTN2:'));
    if Length(AInfo.Provides) = 0 then
      Lines.Add('  ' + T('ui.plugininfo.nothing', 'nothing yet (it may load on first use)'))
    else
      for L in AInfo.Provides do
        Lines.AddRange(WrapInfoText('- ' + L, AWidth - 2, '    '));
    if Length(AInfo.Permissions) > 0 then
    begin
      Lines.Add('');
      Lines.Add(T('ui.plugininfo.permissions', 'It asks to be allowed to:'));
      for L in AInfo.Permissions do
        Lines.AddRange(WrapInfoText('- ' + PermissionTitle(L), AWidth - 2, '    '));
    end;
    if AInfo.HelpFile <> '' then
    begin
      Lines.Add('');
      Lines.Add(T('ui.plugininfo.help', 'A help page is available (the Help button).'));
    end;
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

end.
