unit uColorCoding;

{ Panel row "color coding" — FAR Manager "File highlighting" style, Stage 37:
  named groups (mask + per-state colors), checked top to bottom against a
  row's display name — first matching group wins, mirroring FAR's own
  highlight.hst structure (group name, mask, separate colors for the
  Normal/Selected/Current visual states).

  Layered by the caller (panel row drawing, uDualPanelDrawUtils.DrawPanelList)
  on top of the theme's normal per-filetype color. A group's Normal color
  overrides the theme unconditionally; its Selected/Current colors are
  opt-in — a group that only sets "normal" leaves selection/cursor
  highlighting exactly as the theme draws it (this was Stage 37's original,
  still-default precedence), while a group that *does* set "selected" or
  "current" now wins there too, same as a FAR highlight group would. This
  unit only resolves colors; it draws nothing and knows nothing about
  selection state beyond the enum passed in.

  Effective group list = one merge-by-name pass, embedded THEME_DEFAULT
  ("fileColoring", the baked-in NDN theme) merged with whichever theme file
  is active on disk — colors are theme-owned on purpose: a mask's color has
  to be picked to not clash with that theme's own selection/cursor palette
  (e.g. Archives is magenta, not yellow, because yellow reads as the NDN
  selection color), so there is no separate theme-agnostic user layer that
  could silently clash after a theme switch. The active file defaults to
  NDNtheme.json in the config dir; TMtnSession.ThemeFile can point it at a
  different file (e.g. FARtheme.json) independent of which IThemeRenderer
  Pascal class is instantiated — see SetActiveThemeFileName / uMainForm.

    GGroups := Merge(THEME_DEFAULT.fileColoring, <active theme file>.fileColoring)

  Merge(base, override) is by Name: an override entry whose Name matches a
  base entry replaces it in place (same priority/position); a new Name is
  prepended (override entries get first crack at matching, since first mask
  match wins). See MergeColorCodingGroups. }

interface

uses
  System.UITypes;

type
  /// <summary>Which of a row's three FAR-style visual states color
  /// resolution is being asked for.</summary>
  TColorCodingState = (ccsNormal, ccsSelected, ccsCurrent);

  TColorCodingColor = record
    Fg: TAlphaColor; // 0 = unset (leave to theme / to the state below it)
    Bg: TAlphaColor; // 0 = unset (leave to theme / to the state below it)
  end;

  /// <summary>Which rows a group is even considered for — TC-style row-kind
  /// condition layered on top of the FAR-style mask (uColorCoding's own
  /// addition, not present in FAR's highlight groups). ccaFilesAndDirs is
  /// the default ("both", no restriction), matching every group loaded from
  /// JSON that omits "applyTo".</summary>
  TColorCodingApplyTo = (ccaFilesAndDirs, ccaFilesOnly, ccaDirsOnly);

  TColorCodingGroup = record
    Name: string;
    Masks: TArray<string>;
    /// <summary>Soft-delete flag (FAR-style "disable without deleting").
    /// A disabled group is skipped entirely during matching — as if it
    /// weren't in the list — but stays present so the color-coding editor
    /// dialog can turn a THEME_DEFAULT-supplied group off via an override
    /// entry, since MergeColorCodingGroups has no way to remove a base
    /// entry outright (override-by-name only ever replaces or adds).
    /// Defaults to True (JSON omits "enabled" in the common case).</summary>
    Enabled: Boolean;
    /// <summary>Restricts matching to files, directories, or both (default).</summary>
    ApplyTo: TColorCodingApplyTo;
    /// <summary>Indexed by TColorCodingState. States left fully unset
    /// (Fg=0 and Bg=0) mean "no opinion for this state" — the caller should
    /// fall back to its own (theme) color, matching FAR: a group that
    /// doesn't define a Current color still gets the normal cursor look.</summary>
    Colors: array[TColorCodingState] of TColorCodingColor;
  end;

/// <summary>Resolves AName (file/dir display name, no path, trailing '/'
/// stripped by the caller) against the loaded groups in order for the given
/// AState; returns True and that state's AFg/ABg (either may be 0 = "unset,
/// don't touch that channel") on the first matching group whose AState
/// entry isn't fully unset. False if no group matches, or the matching
/// group(s) have nothing set for this particular state. Disabled groups,
/// and groups whose ApplyTo excludes AIsDirectory, are skipped as if absent
/// (matching continues to the next group, it isn't treated as a non-match
/// that stops the scan).</summary>
function ColorCodingResolve(const AName: string; AIsDirectory: Boolean;
  AState: TColorCodingState; out AFg, ABg: TAlphaColor): Boolean;
/// <summary>Merge-by-Name: an AOverride entry whose Name matches an ABase
/// entry replaces it in place (same position/priority in the result); an
/// AOverride entry with a new Name is prepended (new/overriding entries get
/// first crack at matching, since first mask match wins). Exposed so the
/// active theme's fileColoring loader can reuse the same algorithm.</summary>
function MergeColorCodingGroups(const ABase, AOverride: TArray<TColorCodingGroup>): TArray<TColorCodingGroup>;
/// <summary>Reloads the effective group list: THEME_DEFAULT's "fileColoring"
/// merged with the active theme file's "fileColoring" (AFileName, or the
/// active theme file set via SetActiveThemeFileName — NDNtheme.json by
/// default — when AFileName is blank), read from the config dir. Result =
/// True when that file was found and applied.</summary>
function ReloadColorCoding(const AFileName: string = ''): Boolean;
/// <summary>Cached groups — loaded lazily on first use via ReloadColorCoding.</summary>
function ActiveColorCodingLoaded: Boolean;
/// <summary>Sets the theme file name (in the config dir) ReloadColorCoding
/// reads when called with a blank AFileName — the file a running theme's
/// on-disk override lives in (e.g. 'FARtheme.json'). Empty AFileName resets
/// to the default, 'NDNtheme.json'. Does not itself trigger a reload.</summary>
procedure SetActiveThemeFileName(const AFileName: string);
/// <summary>Parses a {"groups":[...]}-shaped document (or {"<AArrayKey>":[...]}
/// with a different array key — theme files use "fileColoring") into
/// AGroups. Exposed for reuse by the theme loader and for testing.</summary>
function ParseColorCodingJson(const AJsonText: string; out AGroups: TArray<TColorCodingGroup>;
  const AArrayKey: string = 'groups'): Boolean;
/// <summary>"#RRGGBB"/"RRGGBB" -> TAlphaColor. Exposed so the color-coding
/// editor dialog can validate/parse user-typed hex without duplicating this.</summary>
function HexToColor(const AHex: string; out AColor: TAlphaColor): Boolean;
/// <summary>TAlphaColor -> "#RRGGBB", or '' for AColor = 0 (unset) — the
/// editor dialog's prefill/round-trip counterpart to HexToColor.</summary>
function ColorToHex(AColor: TAlphaColor): string;
/// <summary>Serializes AGroups back to a {"fileColoring":[...]} document,
/// the same shape ParseColorCodingJson(..., 'fileColoring') reads — the
/// write-side counterpart that never existed before the color-coding editor
/// dialog needed to persist edits.</summary>
function ColorCodingGroupsToJson(const AGroups: TArray<TColorCodingGroup>): string;
/// <summary>Effective (already merged) groups the panels are currently
/// drawing with — a copy, safe for a caller (the editor dialog) to mutate.
/// Forces a load via ReloadColorCoding if nothing has loaded yet.</summary>
function GetActiveColorCodingGroups: TArray<TColorCodingGroup>;
/// <summary>The theme file name ReloadColorCoding('') currently resolves to
/// (see SetActiveThemeFileName) — where the editor dialog's Save writes.</summary>
function GetActiveThemeFileName: string;
/// <summary>Writes AGroups as the active theme file's "fileColoring"
/// (GetConfigFilePath(GetActiveThemeFileName)), then reloads so panel
/// drawing picks the change up immediately. Best-effort: False on any I/O
/// error, nothing partially written (TFile.WriteAllText is whole-file).</summary>
function SaveActiveThemeFileColoring(const AGroups: TArray<TColorCodingGroup>): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Generics.Collections,
  Winapi.Windows, uConfigLocation, uFileFind;

var
  GLoaded: Boolean = False;
  GGroups: TArray<TColorCodingGroup>;

function HexToColor(const AHex: string; out AColor: TAlphaColor): Boolean;
var
  S: string;
  R, G, B: Integer;
begin
  Result := False;
  S := Trim(AHex);
  if (Length(S) > 0) and (S[1] = '#') then
    Delete(S, 1, 1);
  if Length(S) <> 6 then
    Exit;
  try
    R := StrToInt('$' + Copy(S, 1, 2));
    G := StrToInt('$' + Copy(S, 3, 2));
    B := StrToInt('$' + Copy(S, 5, 2));
  except
    Exit;
  end;
  AColor := TAlphaColor($FF000000 or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B));
  Result := True;
end;

/// <summary>Parses one optional {"fg":"#..","bg":"#.."} state block. Missing
/// entirely, or present with unparsable colors, both just leave AColor at
/// its zeroed default (caller pre-zeroes) — "unset", not an error.</summary>
procedure ParseStateBlock(AObj: TJSONObject; const AKey: string; var AColor: TColorCodingColor);
var
  StateVal: TJSONValue;
  StateObj: TJSONObject;
  HexVal: string;
begin
  if not Assigned(AObj) then
    Exit;
  StateVal := AObj.Values[AKey];
  if not (StateVal is TJSONObject) then
    Exit;
  StateObj := TJSONObject(StateVal);
  if StateObj.TryGetValue<string>('fg', HexVal) then
    HexToColor(HexVal, AColor.Fg);
  if StateObj.TryGetValue<string>('bg', HexVal) then
    HexToColor(HexVal, AColor.Bg);
end;

function ApplyToFromStr(const AStr: string): TColorCodingApplyTo;
begin
  if SameText(AStr, 'files') then
    Result := ccaFilesOnly
  else if SameText(AStr, 'dirs') then
    Result := ccaDirsOnly
  else
    Result := ccaFilesAndDirs;
end;

function ApplyToToStr(AApplyTo: TColorCodingApplyTo): string;
begin
  case AApplyTo of
    ccaFilesOnly: Result := 'files';
    ccaDirsOnly: Result := 'dirs';
  else
    Result := 'both';
  end;
end;

function ParseColorCodingJson(const AJsonText: string; out AGroups: TArray<TColorCodingGroup>;
  const AArrayKey: string = 'groups'): Boolean;
var
  RootVal: TJSONValue;
  RootObj: TJSONObject;
  Arr: TJSONArray;
  I, N: Integer;
  S: TColorCodingState;
  Item: TJSONValue;
  Obj: TJSONObject;
  MaskVal, ApplyToVal: string;
  Group: TColorCodingGroup;
begin
  Result := False;
  SetLength(AGroups, 0);
  if Trim(AJsonText) = '' then
    Exit;
  try
    RootVal := TJSONObject.ParseJSONValue(AJsonText);
    if not (RootVal is TJSONObject) then
    begin
      RootVal.Free;
      Exit;
    end;
    RootObj := TJSONObject(RootVal);
    try
      if not (RootObj.Values[AArrayKey] is TJSONArray) then
        Exit;
      Arr := TJSONArray(RootObj.Values[AArrayKey]);
      N := 0;
      SetLength(AGroups, Arr.Count);
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I];
        if not (Item is TJSONObject) then
          Continue;
        Obj := TJSONObject(Item);
        if not Obj.TryGetValue<string>('mask', MaskVal) then
          Continue;
        if Trim(MaskVal) = '' then
          Continue;
        if not Obj.TryGetValue<string>('name', Group.Name) then
          Group.Name := MaskVal;
        Group.Masks := SplitMasks(MaskVal);
        // Not Obj.TryGetValue<Boolean>('enabled', Group.Enabled) — that
        // generic overload clobbers the out param to False when the key is
        // absent, defeating "defaults to True" (caught by TestColorCodingMerge).
        Group.Enabled := True;
        if Obj.Values['enabled'] is TJSONBool then
          Group.Enabled := TJSONBool(Obj.Values['enabled']).AsBoolean;
        Group.ApplyTo := ccaFilesAndDirs;
        if Obj.TryGetValue<string>('applyTo', ApplyToVal) then
          Group.ApplyTo := ApplyToFromStr(ApplyToVal);
        for S := Low(TColorCodingState) to High(TColorCodingState) do
        begin
          Group.Colors[S].Fg := 0;
          Group.Colors[S].Bg := 0;
        end;
        ParseStateBlock(Obj, 'normal', Group.Colors[ccsNormal]);
        ParseStateBlock(Obj, 'selected', Group.Colors[ccsSelected]);
        ParseStateBlock(Obj, 'current', Group.Colors[ccsCurrent]);
        AGroups[N] := Group;
        Inc(N);
      end;
      SetLength(AGroups, N);
      Result := True;
    finally
      RootObj.Free;
    end;
  except
    SetLength(AGroups, 0);
    Result := False;
  end;
end;

const
  cResThemeDefault = 'THEME_DEFAULT';
  cDefaultThemeFileName = 'NDNtheme.json';

var
  GActiveThemeFileName: string = cDefaultThemeFileName;

function TryLoadRCDataJson(const AResName: string; out AJson: string): Boolean;
var
  RS: TResourceStream;
  Bytes: TBytes;
begin
  AJson := '';
  Result := False;
  if FindResource(HInstance, PChar(AResName), RT_RCDATA) = 0 then
    Exit;
  try
    RS := TResourceStream.Create(HInstance, AResName, RT_RCDATA);
    try
      SetLength(Bytes, RS.Size);
      if RS.Size > 0 then
        RS.ReadBuffer(Bytes[0], RS.Size);
      AJson := TEncoding.UTF8.GetString(Bytes);
      if (Length(AJson) > 0) and (Ord(AJson[1]) = $FEFF) then
        Delete(AJson, 1, 1);
      Result := Trim(AJson) <> '';
    finally
      RS.Free;
    end;
  except
    AJson := '';
    Result := False;
  end;
end;

procedure SetActiveThemeFileName(const AFileName: string);
begin
  if Trim(AFileName) = '' then
    GActiveThemeFileName := cDefaultThemeFileName
  else
    GActiveThemeFileName := AFileName;
end;

function MergeColorCodingGroups(const ABase, AOverride: TArray<TColorCodingGroup>): TArray<TColorCodingGroup>;
var
  Merged: TArray<TColorCodingGroup>;
  NewEntries: TArray<TColorCodingGroup>;
  NewCount: Integer;
  I, J: Integer;
  MatchIdx: Integer;
begin
  Merged := Copy(ABase);
  SetLength(NewEntries, Length(AOverride));
  NewCount := 0;
  for I := 0 to High(AOverride) do
  begin
    MatchIdx := -1;
    for J := 0 to High(Merged) do
      if SameText(Merged[J].Name, AOverride[I].Name) then
      begin
        MatchIdx := J;
        Break;
      end;
    if MatchIdx >= 0 then
      Merged[MatchIdx] := AOverride[I]
    else
    begin
      NewEntries[NewCount] := AOverride[I];
      Inc(NewCount);
    end;
  end;
  SetLength(NewEntries, NewCount);
  // New (unmatched) override entries go first — first mask match wins, and
  // an override/addition should get first crack, not be shadowed by a
  // pre-existing base entry that happens to match the same file too.
  Result := NewEntries + Merged;
end;

function ReloadColorCoding(const AFileName: string): Boolean;
var
  Json: string;
  ActualFileName, ActualPath: string;
  BaseGroups, OverrideGroups: TArray<TColorCodingGroup>;
begin
  Result := False;
  SetLength(BaseGroups, 0);
  if TryLoadRCDataJson(cResThemeDefault, Json) then
    ParseColorCodingJson(Json, BaseGroups, 'fileColoring');

  ActualFileName := AFileName;
  if ActualFileName = '' then
    ActualFileName := GActiveThemeFileName;
  ActualPath := GetConfigFilePath(ActualFileName);
  if TFile.Exists(ActualPath) then
  begin
    try
      Json := TFile.ReadAllText(ActualPath, TEncoding.UTF8);
      if ParseColorCodingJson(Json, OverrideGroups, 'fileColoring') then
      begin
        BaseGroups := MergeColorCodingGroups(BaseGroups, OverrideGroups);
        Result := True;
      end;
    except
      // Corrupt/unreadable theme file — keep the embedded THEME_DEFAULT groups.
    end;
  end;

  GGroups := BaseGroups;
  GLoaded := True;
end;

function ActiveColorCodingLoaded: Boolean;
begin
  Result := GLoaded;
end;

function ColorCodingResolve(const AName: string; AIsDirectory: Boolean;
  AState: TColorCodingState; out AFg, ABg: TAlphaColor): Boolean;
var
  I: Integer;
begin
  AFg := 0;
  ABg := 0;
  Result := False;
  if not GLoaded then
    ReloadColorCoding('');
  if AName = '' then
    Exit;
  // First mask match wins outright (Stage 37's original resolution rule) —
  // the winning group's color for AState governs even when it's unset
  // (Result = False then, i.e. "this group has no opinion here, defer to
  // the theme"); we don't fall through to a later group just because this
  // one left a state blank. Disabled groups, and groups whose ApplyTo
  // excludes this row's kind, are invisible to matching — skipped, not
  // treated as a match with nothing to say (that would still stop the scan).
  for I := 0 to High(GGroups) do
  begin
    if not GGroups[I].Enabled then
      Continue;
    if (GGroups[I].ApplyTo = ccaFilesOnly) and AIsDirectory then
      Continue;
    if (GGroups[I].ApplyTo = ccaDirsOnly) and not AIsDirectory then
      Continue;
    if NameMatchesAnyMask(AName, GGroups[I].Masks) then
    begin
      AFg := GGroups[I].Colors[AState].Fg;
      ABg := GGroups[I].Colors[AState].Bg;
      Exit((AFg <> 0) or (ABg <> 0));
    end;
  end;
end;

function ColorToHex(AColor: TAlphaColor): string;
begin
  if AColor = 0 then
    Result := ''
  else
    Result := Format('#%.2x%.2x%.2x', [TAlphaColorRec(AColor).R,
      TAlphaColorRec(AColor).G, TAlphaColorRec(AColor).B]);
end;

function ColorCodingGroupsToJson(const AGroups: TArray<TColorCodingGroup>): string;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Obj, StateObj: TJSONObject;
  I: Integer;
  S: TColorCodingState;
  StateKey, FgHex, BgHex: string;
begin
  Root := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    Root.AddPair('fileColoring', Arr);
    for I := 0 to High(AGroups) do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('name', AGroups[I].Name);
      Obj.AddPair('mask', string.Join(';', AGroups[I].Masks));
      if not AGroups[I].Enabled then
        Obj.AddPair('enabled', TJSONBool.Create(False));
      if AGroups[I].ApplyTo <> ccaFilesAndDirs then
        Obj.AddPair('applyTo', ApplyToToStr(AGroups[I].ApplyTo));
      for S := Low(TColorCodingState) to High(TColorCodingState) do
      begin
        if (AGroups[I].Colors[S].Fg = 0) and (AGroups[I].Colors[S].Bg = 0) then
          Continue;
        case S of
          ccsNormal: StateKey := 'normal';
          ccsSelected: StateKey := 'selected';
        else
          StateKey := 'current';
        end;
        StateObj := TJSONObject.Create;
        FgHex := ColorToHex(AGroups[I].Colors[S].Fg);
        if FgHex <> '' then
          StateObj.AddPair('fg', FgHex);
        BgHex := ColorToHex(AGroups[I].Colors[S].Bg);
        if BgHex <> '' then
          StateObj.AddPair('bg', BgHex);
        Obj.AddPair(StateKey, StateObj);
      end;
      Arr.AddElement(Obj);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function GetActiveColorCodingGroups: TArray<TColorCodingGroup>;
begin
  if not GLoaded then
    ReloadColorCoding('');
  Result := Copy(GGroups);
end;

function GetActiveThemeFileName: string;
begin
  Result := GActiveThemeFileName;
end;

function SaveActiveThemeFileColoring(const AGroups: TArray<TColorCodingGroup>): Boolean;
begin
  try
    TFile.WriteAllText(GetConfigFilePath(GActiveThemeFileName),
      ColorCodingGroupsToJson(AGroups), TEncoding.UTF8);
    Result := True;
  except
    Result := False;
  end;
end;

end.
