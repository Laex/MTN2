unit uGitStatus;

{ Pure part of the git status plugin: turns the output of
  "git status --porcelain=v2 --branch" into counters and the one-line text of
  the status segment, and picks the folder of the active panel out of the
  host's PanelInfo JSON. No process or host calls here. }

interface

type
  TGitStatus = record
    Branch: string;
    Detached: Boolean;
    HasUpstream: Boolean;
    Ahead, Behind: Integer;
    Staged, Changed, Untracked, Conflicts: Integer;
  end;

/// <summary>Reads the porcelain v2 output. False when it holds no branch
/// header (not the output of git status).</summary>
function ParseGitStatus(const AOutput: string; out AStatus: TGitStatus): Boolean;

type
  /// <summary>Words of the segment's colored parts; the plugin fills them from its
  /// language pack, the defaults are English.</summary>
  TGitLabels = record
    Ahead, Behind, Staged, Changed, Untracked, Conflicts, Clean: string;
  end;

  /// <summary>The parts of the segment that have colors of their own.</summary>
  TGitBadge = (gbBranch, gbSync, gbStaged, gbChanged, gbUntracked, gbConflicts, gbClean);

  /// <summary>Colors the user chose for a badge as "#RRGGBB"; '' = the badge's
  /// default role color.</summary>
  TGitColors = record
    Fg, Bg: array[TGitBadge] of string;
  end;

function DefaultGitLabels: TGitLabels;

/// <summary>Plain segment text: "git:main ^1 v2 +3 ~4 ?5 !1" (staged, changed,
/// untracked, conflicts; "clean" when there is nothing to show).</summary>
function FormatGitStatus(const AStatus: TGitStatus): string;

/// <summary>The status as colored parts for SetStatusSegmentStyled: the branch,
/// then one badge per kind of change with its words and count, e.g.
/// "main" "ahead 1" "staged 3" "modified 4".</summary>
function GitStatusSpansJson(const AStatus: TGitStatus; const ALabels: TGitLabels): string; overload;
/// <summary>As above, with the user's colors over the default ones.</summary>
function GitStatusSpansJson(const AStatus: TGitStatus; const ALabels: TGitLabels;
  const AColors: TGitColors): string; overload;

/// <summary>The URI of the folder of the active panel in the JSON of the host's
/// PanelInfo; '' when the JSON has none.</summary>
function ActivePanelUri(const APanelInfoJson: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.JSON;

function ParseGitStatus(const AOutput: string; out AStatus: TGitStatus): Boolean;
var
  Lines: TArray<string>;
  Line, Oid, Rest: string;
  Parts: TArray<string>;
begin
  AStatus := Default(TGitStatus);
  Result := False;
  Oid := '';
  Lines := AOutput.Replace(#13, '').Split([#10]);
  for Line in Lines do
  begin
    if Line = '' then
      Continue;
    if Line.StartsWith('# branch.oid ') then
    begin
      Oid := Copy(Line, Length('# branch.oid ') + 1, MaxInt);
      Result := True;
    end
    else if Line.StartsWith('# branch.head ') then
    begin
      AStatus.Branch := Copy(Line, Length('# branch.head ') + 1, MaxInt);
      Result := True;
    end
    else if Line.StartsWith('# branch.upstream ') then
      AStatus.HasUpstream := True
    else if Line.StartsWith('# branch.ab ') then
    begin
      Parts := Copy(Line, Length('# branch.ab ') + 1, MaxInt).Split([' ']);
      if Length(Parts) = 2 then
      begin
        AStatus.Ahead := StrToIntDef(Parts[0].TrimLeft(['+']), 0);
        AStatus.Behind := StrToIntDef(Parts[1].TrimLeft(['-']), 0);
      end;
    end
    else if Line[1] = '?' then
      Inc(AStatus.Untracked)
    else if Line[1] = 'u' then
      Inc(AStatus.Conflicts)
    else if CharInSet(Line[1], ['1', '2']) and (Length(Line) >= 4) then
    begin
      if Line[3] <> '.' then
        Inc(AStatus.Staged);
      if Line[4] <> '.' then
        Inc(AStatus.Changed);
    end;
  end;
  if not Result then
    Exit;
  if (AStatus.Branch = '(detached)') or (AStatus.Branch = '') then
  begin
    AStatus.Detached := True;
    Rest := Copy(Oid, 1, 7);
    if (Rest = '') or (Oid = '(initial)') then
      Rest := 'HEAD';
    AStatus.Branch := Rest;
  end;
end;

function DefaultGitLabels: TGitLabels;
begin
  Result.Ahead := 'ahead';
  Result.Behind := 'behind';
  Result.Staged := 'staged';
  Result.Changed := 'modified';
  Result.Untracked := 'new';
  Result.Conflicts := 'conflicts';
  Result.Clean := 'clean';
end;

function BranchLabel(const AStatus: TGitStatus): string;
begin
  Result := AStatus.Branch;
  if Length(Result) > 24 then
    Result := Copy(Result, 1, 23) + '...';
  if AStatus.Detached then
    Result := '@' + Result;
end;

function FormatGitStatus(const AStatus: TGitStatus): string;
begin
  Result := 'git:';
  if AStatus.Detached then
    Result := Result + '@';
  Result := Result + AStatus.Branch;
  if AStatus.Ahead > 0 then
    Result := Result + ' ^' + IntToStr(AStatus.Ahead);
  if AStatus.Behind > 0 then
    Result := Result + ' v' + IntToStr(AStatus.Behind);
  if AStatus.Staged > 0 then
    Result := Result + ' +' + IntToStr(AStatus.Staged);
  if AStatus.Changed > 0 then
    Result := Result + ' ~' + IntToStr(AStatus.Changed);
  if AStatus.Untracked > 0 then
    Result := Result + ' ?' + IntToStr(AStatus.Untracked);
  if AStatus.Conflicts > 0 then
    Result := Result + ' !' + IntToStr(AStatus.Conflicts);
  if (AStatus.Staged + AStatus.Changed + AStatus.Untracked + AStatus.Conflicts = 0) then
    Result := Result + ' clean';
end;

procedure AddSpan(AArr: TJSONArray; const AText, ARole: string; ABold: Boolean = False;
  const AFg: string = ''; const ABg: string = '');
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('t', AText);
  if ARole <> '' then
    O.AddPair('role', ARole);
  if AFg <> '' then
    O.AddPair('fg', AFg);
  if ABg <> '' then
    O.AddPair('bg', ABg);
  if ABold then
    O.AddPair('b', TJSONBool.Create(True));
  AArr.AddElement(O);
end;

function GitStatusSpansJson(const AStatus: TGitStatus; const ALabels: TGitLabels): string;
begin
  Result := GitStatusSpansJson(AStatus, ALabels, Default(TGitColors));
end;

function GitStatusSpansJson(const AStatus: TGitStatus; const ALabels: TGitLabels;
  const AColors: TGitColors): string;
var
  Arr: TJSONArray;

  procedure Badge(const ALabel: string; ACount: Integer; const ARole: string;
    AKind: TGitBadge);
  begin
    if ACount <= 0 then
      Exit;
    AddSpan(Arr, ' ', '');
    AddSpan(Arr, ' ' + ALabel + ' ' + IntToStr(ACount) + ' ', ARole, False,
      AColors.Fg[AKind], AColors.Bg[AKind]);
  end;

begin
  Arr := TJSONArray.Create;
  try
    AddSpan(Arr, ' ' + BranchLabel(AStatus) + ' ', 'accent', True,
      AColors.Fg[gbBranch], AColors.Bg[gbBranch]);
    Badge(ALabels.Ahead, AStatus.Ahead, 'info', gbSync);
    Badge(ALabels.Behind, AStatus.Behind, 'info', gbSync);
    Badge(ALabels.Staged, AStatus.Staged, 'ok', gbStaged);
    Badge(ALabels.Changed, AStatus.Changed, 'warn', gbChanged);
    Badge(ALabels.Untracked, AStatus.Untracked, 'neutral', gbUntracked);
    Badge(ALabels.Conflicts, AStatus.Conflicts, 'error', gbConflicts);
    if AStatus.Staged + AStatus.Changed + AStatus.Untracked + AStatus.Conflicts = 0 then
    begin
      AddSpan(Arr, ' ', '');
      AddSpan(Arr, ' ' + ALabels.Clean + ' ', 'ok', False,
        AColors.Fg[gbClean], AColors.Bg[gbClean]);
    end;
    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

function ActivePanelUri(const APanelInfoJson: string): string;
var
  Root, Side: TJSONValue;
  Active: string;
begin
  Result := '';
  if APanelInfoJson = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(APanelInfoJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    if not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := Root.GetValue<TJSONValue>(Active, nil);
    if Side is TJSONObject then
      Side.TryGetValue<string>('uri', Result);
  finally
    Root.Free;
  end;
end;

end.
