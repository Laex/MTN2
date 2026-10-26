unit uKeyHints;

{ One-line key hints for the state the program is in: search results, an
  archive, a temporary panel, a workspace, an SFTP folder, a command typed
  under the panels. A hint names the keys that are useful there; the keys are
  read from the live keymap, so a rebound key shows its new chord. Each hint is
  offered once per run, and not at all when the hints are switched off. }

interface

uses
  uKeymap;

type
  THintSituation = (hsNone, hsFindResults, hsArchive, hsTempPanel, hsWorkspace,
    hsSftp, hsCommandLine, hsConsoleProgram);

  TKeyHintTracker = class
  private
    FEnabled: Boolean;
    FShown: set of THintSituation;
  public
    constructor Create(AEnabled: Boolean);
    /// <summary>The hint text for ASituation the first time it is asked for,
    /// '' afterwards, for hsNone and while the hints are off.</summary>
    function Take(ASituation: THintSituation; const AProfile: TKeymapProfile): string;
    property Enabled: Boolean read FEnabled write FEnabled;
  end;

/// <summary>The situation of a panel showing AURI (hsNone for a plain folder).</summary>
function HintSituationOfUri(const AURI: string): THintSituation;

/// <summary>The English template of a hint. {Name} stands for the keys of the
/// keymap action called Name (the keymap.json name).</summary>
function KeyHintTemplate(ASituation: THintSituation): string;

/// <summary>ATemplate with every {Name} replaced by the first keys of that
/// action in AProfile; an unknown or unbound name becomes '?'.</summary>
function ExpandKeyHint(const ATemplate: string; const AProfile: TKeymapProfile): string;

/// <summary>The hint of ASituation in the current language, keys filled in.</summary>
function KeyHintText(ASituation: THintSituation; const AProfile: TKeymapProfile): string;

implementation

uses
  System.SysUtils, uVfsTypes, uStrings;

const
  cSituationKey: array[THintSituation] of string = (
    '', 'find', 'archive', 'temp', 'workspace', 'sftp', 'cmdline', 'program');

constructor TKeyHintTracker.Create(AEnabled: Boolean);
begin
  inherited Create;
  FEnabled := AEnabled;
  FShown := [];
end;

function TKeyHintTracker.Take(ASituation: THintSituation;
  const AProfile: TKeymapProfile): string;
begin
  Result := '';
  if (not FEnabled) or (ASituation = hsNone) or (ASituation in FShown) then
    Exit;
  Include(FShown, ASituation);
  Result := KeyHintText(ASituation, AProfile);
end;

function HintSituationOfUri(const AURI: string): THintSituation;
begin
  if IsFindUri(AURI) then
    Result := hsFindResults
  else if HasArchiveChain(AURI) then
    Result := hsArchive
  else if IsTmpPanelUri(AURI) then
    Result := hsTempPanel
  else if IsWorkspaceUri(AURI) then
    Result := hsWorkspace
  else if IsSftpUri(AURI) then
    Result := hsSftp
  else
    Result := hsNone;
end;

function KeyHintTemplate(ASituation: THintSituation): string;
begin
  case ASituation of
    hsFindResults:
      Result := 'Found: Enter goes to file, {View} view, {Edit} edit, ' +
        'Alt+Shift+F3 other panel';
    hsArchive:
      Result := 'Archive: {Copy} unpacks to the other panel, {View} views a file';
    hsTempPanel:
      Result := 'Temp panel: F7 remove, Alt+Shift+F2 save list, ' +
        'Alt+Shift+F3 go to file';
    hsWorkspace:
      Result := 'Workspace: F8 unlink, F7 virtual folder, Alt+Shift+F3 show original';
    hsSftp:
      Result := 'SFTP: {Copy} downloads to the other panel, ' +
        '{SshConnections} connections';
    hsCommandLine:
      Result := 'Enter: run, {RunInBackground}: background, {RunInNewTab}: new tab';
    hsConsoleProgram:
      Result := 'Also: {RunInBackground} runs in background, ' +
        '{RunInNewTab} in a terminal tab';
  else
    Result := '';
  end;
end;

function ExpandKeyHint(const ATemplate: string; const AProfile: TKeymapProfile): string;
var
  P, Q: Integer;
  Name, Keys: string;
  Action: TKeymapAction;
begin
  Result := '';
  P := 1;
  while P <= Length(ATemplate) do
  begin
    if ATemplate[P] = '{' then
    begin
      Q := Pos('}', ATemplate, P);
      if Q > P then
      begin
        Name := Copy(ATemplate, P + 1, Q - P - 1);
        Keys := '';
        if TryKeymapActionByName(Name, Action) then
          Keys := KeymapShortcutText(AProfile, Action, 1);
        if Keys = '' then
          Keys := '?';
        Result := Result + Keys;
        P := Q + 1;
        Continue;
      end;
    end;
    Result := Result + ATemplate[P];
    Inc(P);
  end;
end;

function KeyHintText(ASituation: THintSituation; const AProfile: TKeymapProfile): string;
var
  Template: string;
begin
  Template := KeyHintTemplate(ASituation);
  if Template = '' then
    Exit('');
  Result := ExpandKeyHint(T('ui.hint.' + cSituationKey[ASituation], Template), AProfile);
end;

end.
