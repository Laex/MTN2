unit uFeatureTips;

{ Tips about features the user has not tried yet. From the third run on, each
  run offers at most one tip, for a feature the user has neither used nor been
  told about; a feature used by any of its keys counts as known. The keys in a
  tip are read from the live keymap. The state (runs, used features, shown
  tips) is kept in the session file. }

interface

uses
  uKeymap;

const
  /// <summary>The run on which the first tip is offered; earlier runs are left
  /// alone so a new user is not buried in hints.</summary>
  cFirstTipRun = 3;

type
  // The state stores tips as a bit set of their ordinals: new ones are
  // appended, never inserted.
  TFeatureTip = (ftNone, ftCommandPalette, ftRetired, ftFolderHotlist,
    ftPairedFolders, ftCompareFolders, ftQuickView, ftNewTerminal, ftFolderTree,
    ftGroupBy, ftNewWorkspace);

  TFeatureTipState = record
    Launches: Integer;
    /// <summary>Bit set of the features the user has used.</summary>
    Used: Integer;
    /// <summary>Bit set of the tips already shown.</summary>
    Shown: Integer;
  end;

  TFeatureTipTracker = class
  private
    FEnabled: Boolean;
    FState: TFeatureTipState;
    FOfferedThisRun: Boolean;
  public
    constructor Create(AEnabled: Boolean);
    /// <summary>Counts a run; call once when the program starts.</summary>
    procedure BeginSession;
    /// <summary>Records that the user ran AAction (a no-op for actions that
    /// have no tip).</summary>
    procedure NoteAction(AAction: TKeymapAction);
    /// <summary>The next tip text, '' when none is due: before the first tip
    /// run, after one was offered in this run, while the tips are off, or when
    /// every tip was used or shown.</summary>
    function NextTip(const AProfile: TKeymapProfile): string;
    /// <summary>Makes every tip due again; the run count is kept.</summary>
    procedure ResetShown;
    property Enabled: Boolean read FEnabled write FEnabled;
    property State: TFeatureTipState read FState write FState;
  end;

/// <summary>The tip of the feature AAction belongs to (ftNone for any other
/// action).</summary>
function FeatureTipOfAction(AAction: TKeymapAction): TFeatureTip;

/// <summary>Bit set of every tip: a session from a version without tips
/// starts with all of them shown, since its user already knows the program.</summary>
function AllFeatureTipsMask: Integer;

/// <summary>The tip in the current language, keys filled in.</summary>
function FeatureTipText(ATip: TFeatureTip; const AProfile: TKeymapProfile): string;

implementation

uses
  uKeyHints, uStrings;

const
  cTipKey: array[TFeatureTip] of string = (
    '', 'palette', 'retired', 'hotlist', 'paired', 'compare', 'quickview',
    'terminal', 'tree', 'groupby', 'workspace');

function FeatureTipTemplate(ATip: TFeatureTip): string;
begin
  case ATip of
    ftCommandPalette:
      Result := 'Tip: {CommandPalette} finds any command by name and shows its keys';
    ftFolderHotlist:
      Result := 'Tip: {FolderHotlist} opens the folder hotlist, {FolderFrecent} the folders you visit most';
    ftPairedFolders:
      Result := 'Tip: {PairedFolders} pairs the panels: entering a folder opens the same one on the other side';
    ftCompareFolders:
      Result := 'Tip: {CompareFolders} compares the folders of both panels, {CompareFiles} two files';
    ftQuickView:
      Result := 'Tip: {QuickView} shows the file under the cursor on the other panel';
    ftNewTerminal:
      Result := 'Tip: {NewTerminal} opens a terminal tab: PowerShell, WSL, SSH';
    ftFolderTree:
      Result := 'Tip: {FolderTree} shows the folder tree over the panel';
    ftGroupBy:
      Result := 'Tip: {GroupBy} groups the rows by type or date';
    ftNewWorkspace:
      Result := 'Tip: {NewWorkspace} opens a separate workspace with its own panels and terminals';
  else
    Result := '';
  end;
end;

function FeatureTipOfAction(AAction: TKeymapAction): TFeatureTip;
begin
  case AAction of
    kaCommandPalette: Result := ftCommandPalette;
    kaFolderHotlist, kaFolderFrecent: Result := ftFolderHotlist;
    kaPairedFolders: Result := ftPairedFolders;
    kaCompareFolders, kaCompareFiles: Result := ftCompareFolders;
    kaQuickView: Result := ftQuickView;
    kaNewTerminal: Result := ftNewTerminal;
    kaFolderTree: Result := ftFolderTree;
    kaGroupBy: Result := ftGroupBy;
    kaNewWorkspace: Result := ftNewWorkspace;
  else
    Result := ftNone;
  end;
end;

function AllFeatureTipsMask: Integer;
var
  Tip: TFeatureTip;
begin
  Result := 0;
  for Tip := Succ(ftNone) to High(TFeatureTip) do
    Result := Result or (1 shl Ord(Tip));
end;

function FeatureTipText(ATip: TFeatureTip; const AProfile: TKeymapProfile): string;
var
  Template: string;
begin
  Template := FeatureTipTemplate(ATip);
  if Template = '' then
    Exit('');
  Result := ExpandKeyHint(T('ui.tip.' + cTipKey[ATip], Template), AProfile);
end;

constructor TFeatureTipTracker.Create(AEnabled: Boolean);
begin
  inherited Create;
  FEnabled := AEnabled;
  FState.Launches := 0;
  FState.Used := 0;
  FState.Shown := 0;
end;

procedure TFeatureTipTracker.BeginSession;
begin
  Inc(FState.Launches);
  FOfferedThisRun := False;
end;

procedure TFeatureTipTracker.NoteAction(AAction: TKeymapAction);
var
  Tip: TFeatureTip;
begin
  Tip := FeatureTipOfAction(AAction);
  if Tip <> ftNone then
    FState.Used := FState.Used or (1 shl Ord(Tip));
end;

function TFeatureTipTracker.NextTip(const AProfile: TKeymapProfile): string;
var
  Tip: TFeatureTip;
  Bit: Integer;
begin
  Result := '';
  if (not FEnabled) or FOfferedThisRun or (FState.Launches < cFirstTipRun) then
    Exit;
  for Tip := Succ(ftNone) to High(TFeatureTip) do
  begin
    Bit := 1 shl Ord(Tip);
    if (FState.Used and Bit <> 0) or (FState.Shown and Bit <> 0) then
      Continue;
    Result := FeatureTipText(Tip, AProfile);
    if Result = '' then
      Continue;
    FState.Shown := FState.Shown or Bit;
    FOfferedThisRun := True;
    Exit;
  end;
end;

procedure TFeatureTipTracker.ResetShown;
begin
  FState.Shown := 0;
end;

end.
