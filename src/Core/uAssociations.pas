unit uAssociations;

{ Internal file associations for Enter on a file (Stage 8).
  Directories always navigate; files map to view / edit / shell.
  Shell-preferred media/docs always use the platform open (uShellAssoc);
  unknown extensions still probe HasShellOpen before Viewer fallback. }

interface

type
  TAssocAction = (
    aaNavigate,
    aaView,
    aaEdit,
    aaShell,
    /// <summary>A user-defined association resolved to a custom command
    /// line (see uUserAssociations.ResolveAssociationWithUserRules) rather
    /// than one of the built-in view/edit/shell actions above.</summary>
    aaCommand,
    aaNone
  );

function ResolveAssociation(const AName: string; AIsDirectory: Boolean): TAssocAction;
function AssociationLabel(AAction: TAssocAction): string;
/// <summary>True for extensions that always launch directly (.exe/.bat/...)
/// — exported so uUserAssociations.pas can keep this one priority-1 rule
/// ahead of user-defined overrides, mirroring Far/TC/NDN where executables
/// always win over internal associations.</summary>
function IsLaunchableExt(const AExt: string): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils,
  uShellAssoc;

function IsLaunchableExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.exe') or (AExt = '.bat') or (AExt = '.cmd') or
    (AExt = '.com') or (AExt = '.msi') or (AExt = '.ps1') or
    (AExt = '.vbs') or (AExt = '.lnk');
end;

function IsEditorExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.pas') or (AExt = '.dpr') or (AExt = '.dpk') or
    (AExt = '.inc') or (AExt = '.dfm') or (AExt = '.fmx') or
    (AExt = '.dproj') or (AExt = '.groupproj') or (AExt = '.c') or
    (AExt = '.cpp') or (AExt = '.cc') or (AExt = '.cxx') or
    (AExt = '.h') or (AExt = '.hpp') or (AExt = '.cs') or
    (AExt = '.java') or (AExt = '.js') or (AExt = '.ts') or
    (AExt = '.tsx') or (AExt = '.jsx') or (AExt = '.py') or
    (AExt = '.rb') or (AExt = '.go') or (AExt = '.rs') or
    (AExt = '.php') or (AExt = '.sql') or (AExt = '.sh') or
    (AExt = '.psm1') or (AExt = '.json') or (AExt = '.xml') or
    (AExt = '.yml') or (AExt = '.yaml') or (AExt = '.toml') or
    (AExt = '.html') or (AExt = '.htm') or (AExt = '.css') or
    (AExt = '.scss') or (AExt = '.gitignore') or (AExt = '.editorconfig');
end;

function IsPlainTextExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.txt') or (AExt = '.md') or (AExt = '.markdown') or
    (AExt = '.log') or (AExt = '.ini') or (AExt = '.cfg') or
    (AExt = '.conf') or (AExt = '.csv') or (AExt = '.tsv') or
    (AExt = '.nfo') or (AExt = '');
end;

/// <summary>Types that prefer an OS app when one is registered; else Viewer.</summary>
function IsShellPreferredExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.png') or (AExt = '.jpg') or (AExt = '.jpeg') or
    (AExt = '.gif') or (AExt = '.bmp') or (AExt = '.ico') or
    (AExt = '.webp') or (AExt = '.svg') or (AExt = '.mp3') or
    (AExt = '.mp4') or (AExt = '.avi') or (AExt = '.mkv') or
    (AExt = '.wav') or (AExt = '.flac') or (AExt = '.pdf') or
    (AExt = '.doc') or (AExt = '.docx') or (AExt = '.xls') or
    (AExt = '.xlsx') or (AExt = '.ppt') or (AExt = '.pptx');
end;

/// <summary>Known non-openable binaries: no useful OS "open", stay in Viewer.</summary>
function IsNonOpenableBinaryExt(const AExt: string): Boolean;
begin
  Result := (AExt = '.dll') or (AExt = '.so') or (AExt = '.o') or (AExt = '.obj') or
    (AExt = '.lib') or (AExt = '.a') or (AExt = '.pdb') or (AExt = '.exe~');
end;

function ResolveAssociation(const AName: string; AIsDirectory: Boolean): TAssocAction;
var
  Ext: string;
begin
  if AIsDirectory then
    Exit(aaNavigate);

  Ext := NormalizeFileExtension(AName);

  // Launchables → always platform shell.
  if IsLaunchableExt(Ext) then
    Exit(aaShell);

  // Source / structured text → Editor (F4 / Enter).
  if IsEditorExt(Ext) then
    Exit(aaEdit);

  // Plain notes / logs → Viewer on Enter (F4 still edits).
  if IsPlainTextExt(Ext) then
    Exit(aaView);

  // Archives → Nested VFS navigate (Enter handled in ActivateCurrent too).
  if (Ext = '.zip') or (Ext = '.jar') or (Ext = '.apk') then
    Exit(aaNavigate);

  // Documents / media: always prefer the OS open handler (ShellExecute).
  // Do not gate on HasShellOpen — AssocQueryString often returns empty for
  // UWP defaults (Movies & TV, Photos) even though ShellExecute still works.
  if IsShellPreferredExt(Ext) then
    Exit(aaShell);

  // Known non-openable binaries stay in Viewer (no useful shell open).
  if IsNonOpenableBinaryExt(Ext) then
    Exit(aaView);

  // Unknown extension: OS open if registered, otherwise safe Viewer.
  if HasShellOpen(Ext) then
    Exit(aaShell);
  Result := aaView;
end;

function AssociationLabel(AAction: TAssocAction): string;
begin
  case AAction of
    aaNavigate: Result := 'Open';
    aaView: Result := 'View';
    aaEdit: Result := 'Edit';
    aaShell: Result := 'Shell';
    aaCommand: Result := 'Run';
    aaNone: Result := '';
  else
    Result := '';
  end;
end;

end.
