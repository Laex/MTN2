unit uColorCoding;

{ Panel row "color coding" - FAR Manager "File highlighting" style:
  named groups (mask + per-state colors), checked top to bottom against a
  row's display name - first matching group wins, mirroring FAR's own
  highlight.hst structure (group name, mask, separate colors for the
  Normal/Selected/Current visual states).

  Layered by the caller (panel row drawing, uDualPanelDrawUtils.DrawPanelList)
  on top of the theme's normal per-filetype color. A group's Normal color
  overrides the theme unconditionally; its Selected/Current colors are
  opt-in - a group that only sets "normal" leaves selection/cursor
  highlighting exactly as the theme draws it, while a group that *does* set
  "selected" or "current" wins there too, same as a FAR highlight group
  would. This
  unit only resolves colors; it draws nothing and knows nothing about
  selection state beyond the enum passed in.

  The groups are part of the active theme (TThemeSpec.FileColoring in
  uThemeSpec): a mask's color has to be picked to not clash with that theme's
  own selection/cursor palette (e.g. Archives is magenta, not yellow,
  because yellow reads as the NDN selection color), so there is no separate
  theme-agnostic user layer that could silently clash after a theme switch.
  Activating a theme hands its merged groups to SetActiveColorCodingGroups;
  a theme file that extends another lists only the groups it adds or
  changes.

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
    /// <summary>A color written as a reference ("@cursor.bg" - a theme role -
    /// or a palette name) instead of "#RRGGBB". The theme resolves it into
    /// Fg / Bg when it is activated; until then Fg / Bg are 0.</summary>
    FgRef: string;
    BgRef: string;
  end;

  /// <summary>Which rows a group is even considered for - TC-style row-kind
  /// condition layered on top of the FAR-style mask (uColorCoding's own
  /// addition, not present in FAR's highlight groups). ccaFilesAndDirs is
  /// the default ("both", no restriction), matching every group loaded from
  /// JSON that omits "applyTo".</summary>
  TColorCodingApplyTo = (ccaFilesAndDirs, ccaFilesOnly, ccaDirsOnly);

  /// <summary>Row attributes a group condition can require or exclude.</summary>
  TColorCodingAttr = (ccatHidden, ccatReadOnly, ccatSystem, ccatArchive,
    ccatCompressed, ccatEncrypted, ccatLink);
  TColorCodingAttrs = set of TColorCodingAttr;

  /// <summary>Extra conditions of a group, all of which must hold on top of
  /// the mask. Size and age are checked only for rows that carry the data (a
  /// folder has no size; a row without a time has no age); a row lacking the
  /// data never satisfies such a condition. Text form: see
  /// ColorCodingParseCondition.</summary>
  TColorCodingCondition = record
    /// <summary>When HasMinSize, the size must be greater than MinSize.</summary>
    HasMinSize: Boolean;
    MinSize: Int64;
    /// <summary>When HasMaxSize, the size must be less than MaxSize.</summary>
    HasMaxSize: Boolean;
    MaxSize: Int64;
    /// <summary>Modified less than this many seconds ago; 0 = no limit.</summary>
    NewerSecs: Int64;
    /// <summary>Modified more than this many seconds ago; 0 = no limit.</summary>
    OlderSecs: Int64;
    Require: TColorCodingAttrs;
    Exclude: TColorCodingAttrs;
  end;

  /// <summary>What a panel row offers to the color rules besides its name.
  /// Size = -1 and ModTime = 0 mean "not known".</summary>
  TColorCodingItem = record
    Name: string;
    IsDirectory: Boolean;
    Size: Int64;
    ModTime: TDateTime;
    Attrs: TColorCodingAttrs;
  end;

  TColorCodingGroup = record
    Name: string;
    Masks: TArray<string>;
    /// <summary>Soft-delete flag (FAR-style "disable without deleting").
    /// A disabled group is skipped entirely during matching - as if it
    /// weren't in the list - but stays present so the color-coding editor
    /// dialog can turn a base theme's group off via an override entry,
    /// since MergeColorCodingGroups has no way to remove a base entry
    /// outright (override-by-name only ever replaces or adds).
    /// Defaults to True (JSON omits "enabled" in the common case).</summary>
    Enabled: Boolean;
    /// <summary>Restricts matching to files, directories, or both (default).</summary>
    ApplyTo: TColorCodingApplyTo;
    /// <summary>Rank of the group's rows when a panel sorts with priorities:
    /// lower comes first, negative values move rows to the top, positive ones
    /// to the bottom. 0 (default) leaves the rows with the unranked ones.</summary>
    SortPriority: Integer;
    /// <summary>Further conditions on size, age and attributes.</summary>
    Cond: TColorCodingCondition;
    /// <summary>Indexed by TColorCodingState. States left fully unset
    /// (Fg=0 and Bg=0) mean "no opinion for this state" - the caller should
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
/// <summary>As above, with the size, time and attributes of the row for the
/// group conditions.</summary>
function ColorCodingResolveItem(const AItem: TColorCodingItem;
  AState: TColorCodingState; out AFg, ABg: TAlphaColor): Boolean;
/// <summary>SortPriority of the first enabled group that matches the row
/// (same matching as ColorCodingResolve); 0 when no group matches.</summary>
function ColorCodingSortPriority(const AName: string; AIsDirectory: Boolean): Integer;
function ColorCodingSortPriorityItem(const AItem: TColorCodingItem): Integer;
/// <summary>An item that knows only its name and kind.</summary>
function ColorCodingNameItem(const AName: string; AIsDirectory: Boolean): TColorCodingItem;
/// <summary>True when AItem satisfies ACond; ANow is the reference time for
/// the age checks.</summary>
function ColorCodingConditionMet(const ACond: TColorCodingCondition;
  const AItem: TColorCodingItem; ANow: TDateTime): Boolean;
/// <summary>Parses the condition text: blank-separated terms
/// "size>N" / "size<N" (N in bytes, or with K, M, G, T suffix), "age<N" (modified
/// less than N ago) / "age>N" (more than N ago) with N followed by m, h, d or w
/// (minutes, hours, days, weeks), "+H" / "-H" (the attribute must / must not be
/// set; letters H hidden, R read-only, S system, A archive, C compressed,
/// E encrypted, L link; several letters may follow one sign). Blank text is no
/// condition; anything unrecognized fails.</summary>
function ColorCodingParseCondition(const AText: string;
  out ACond: TColorCodingCondition): Boolean;
/// <summary>The canonical text of ACond; ColorCodingParseCondition reads it back.</summary>
function ColorCodingConditionText(const ACond: TColorCodingCondition): string;
/// <summary>Merge-by-Name: an AOverride entry whose Name matches an ABase
/// entry replaces it in place (same position/priority in the result); an
/// AOverride entry with a new Name is prepended (new/overriding entries get
/// first crack at matching, since first mask match wins). Exposed so the
/// active theme's fileColoring loader can reuse the same algorithm.</summary>
function MergeColorCodingGroups(const ABase, AOverride: TArray<TColorCodingGroup>): TArray<TColorCodingGroup>;
/// <summary>Makes AGroups the effective list the panels draw with (the
/// active theme's merged file coloring).</summary>
procedure SetActiveColorCodingGroups(const AGroups: TArray<TColorCodingGroup>);
/// <summary>Parses a {"groups":[...]}-shaped document (or {"<AArrayKey>":[...]}
/// with a different array key - theme files use "fileColoring") into
/// AGroups. Exposed for reuse by the theme loader and for testing.</summary>
function ParseColorCodingJson(const AJsonText: string; out AGroups: TArray<TColorCodingGroup>;
  const AArrayKey: string = 'groups'): Boolean;
/// <summary>"#RRGGBB"/"RRGGBB" -> TAlphaColor. Exposed so the color-coding
/// editor dialog can validate/parse user-typed hex without duplicating this.</summary>
function HexToColor(const AHex: string; out AColor: TAlphaColor): Boolean;
/// <summary>TAlphaColor -> "#RRGGBB", or '' for AColor = 0 (unset) - the
/// editor dialog's prefill/round-trip counterpart to HexToColor.</summary>
function ColorToHex(AColor: TAlphaColor): string;
/// <summary>Serializes AGroups back to a {"fileColoring":[...]} document,
/// the same shape ParseColorCodingJson(..., 'fileColoring') reads.</summary>
function ColorCodingGroupsToJson(const AGroups: TArray<TColorCodingGroup>): string;
/// <summary>The color as written in a file: its reference when it has one,
/// "#RRGGBB" otherwise ('' for an unset color).</summary>
function ColorCodingColorText(AColor: TAlphaColor; const ARef: string): string;
/// <summary>True when two groups are written identically.</summary>
function ColorCodingGroupSame(const A, B: TColorCodingGroup): Boolean;
function ColorCodingNames(const AGroups: TArray<TColorCodingGroup>): TArray<string>;
/// <summary>Reorders AGroups so the groups named in AOrder come first, in that
/// order; the others follow in their own order. An empty AOrder changes nothing.</summary>
procedure ColorCodingApplyOrder(var AGroups: TArray<TColorCodingGroup>;
  const AOrder: TArray<string>);
/// <summary>What a theme has to store so that merging it over ABase gives
/// AEdited: the groups that differ from the base (or are new), a disabled copy
/// of every base group AEdited dropped, and the order when the merge would
/// not already give it.</summary>
procedure ColorCodingDiff(const ABase, AEdited: TArray<TColorCodingGroup>;
  out AChanges: TArray<TColorCodingGroup>; out AOrder: TArray<string>);
/// <summary>Effective (already merged) groups the panels are currently
/// drawing with - a copy, safe for a caller (the editor dialog) to mutate.
/// Until a theme is activated these come from the defaults provider.</summary>
function GetActiveColorCodingGroups: TArray<TColorCodingGroup>;

type
  TColorCodingDefaultsProvider = function: TArray<TColorCodingGroup>;

/// <summary>The source of the groups used until a theme is activated (the
/// default theme's); installed by the theme registry.</summary>
procedure SetColorCodingDefaultsProvider(AProvider: TColorCodingDefaultsProvider);

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  uFileFind;

var
  GLoaded: Boolean = False;
  GGroups: TArray<TColorCodingGroup>;
  GDefaultsProvider: TColorCodingDefaultsProvider;

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
/// its zeroed default (caller pre-zeroes) - "unset", not an error.</summary>
procedure ParseColorField(AObj: TJSONObject; const AKey: string;
  var AColor: TAlphaColor; var ARef: string);
var
  Text: string;
begin
  if not AObj.TryGetValue<string>(AKey, Text) then
    Exit;
  Text := Trim(Text);
  if HexToColor(Text, AColor) then
    ARef := ''
  else if Text <> '' then
    ARef := Text;
end;

procedure ParseStateBlock(AObj: TJSONObject; const AKey: string; var AColor: TColorCodingColor);
var
  StateVal: TJSONValue;
  StateObj: TJSONObject;
begin
  if not Assigned(AObj) then
    Exit;
  StateVal := AObj.Values[AKey];
  if not (StateVal is TJSONObject) then
    Exit;
  StateObj := TJSONObject(StateVal);
  ParseColorField(StateObj, 'fg', AColor.Fg, AColor.FgRef);
  ParseColorField(StateObj, 'bg', AColor.Bg, AColor.BgRef);
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
  MaskVal, ApplyToVal, WhenVal: string;
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
        // Not Obj.TryGetValue<Boolean>('enabled', Group.Enabled) - that
        // generic overload clobbers the out param to False when the key is
        // absent, defeating "defaults to True" (caught by TestColorCodingMerge).
        Group.Enabled := True;
        if Obj.Values['enabled'] is TJSONBool then
          Group.Enabled := TJSONBool(Obj.Values['enabled']).AsBoolean;
        Group.ApplyTo := ccaFilesAndDirs;
        if Obj.TryGetValue<string>('applyTo', ApplyToVal) then
          Group.ApplyTo := ApplyToFromStr(ApplyToVal);
        Group.SortPriority := 0;
        if Obj.Values['sortPriority'] is TJSONNumber then
          Group.SortPriority := TJSONNumber(Obj.Values['sortPriority']).AsInt;
        Group.Cond := Default(TColorCodingCondition);
        if Obj.TryGetValue<string>('when', WhenVal) and
           not ColorCodingParseCondition(WhenVal, Group.Cond) then
          // A condition that cannot be read leaves the group unrestricted.
          Group.Cond := Default(TColorCodingCondition);
        for S := Low(TColorCodingState) to High(TColorCodingState) do
        begin
          Group.Colors[S].Fg := 0;
          Group.Colors[S].Bg := 0;
          Group.Colors[S].FgRef := '';
          Group.Colors[S].BgRef := '';
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
  // New (unmatched) override entries go first - first mask match wins, and
  // an override/addition should get first crack, not be shadowed by a
  // pre-existing base entry that happens to match the same file too.
  Result := NewEntries + Merged;
end;

procedure SetColorCodingDefaultsProvider(AProvider: TColorCodingDefaultsProvider);
begin
  GDefaultsProvider := AProvider;
end;

procedure SetActiveColorCodingGroups(const AGroups: TArray<TColorCodingGroup>);
begin
  GGroups := Copy(AGroups);
  GLoaded := True;
end;

procedure EnsureGroups;
begin
  if GLoaded then
    Exit;
  if Assigned(GDefaultsProvider) then
    GGroups := GDefaultsProvider()
  else
    SetLength(GGroups, 0);
  GLoaded := True;
end;

function ColorCodingNameItem(const AName: string; AIsDirectory: Boolean): TColorCodingItem;
begin
  Result := Default(TColorCodingItem);
  Result.Name := AName;
  Result.IsDirectory := AIsDirectory;
  Result.Size := -1;
end;

function ColorCodingResolve(const AName: string; AIsDirectory: Boolean;
  AState: TColorCodingState; out AFg, ABg: TAlphaColor): Boolean;
begin
  Result := ColorCodingResolveItem(ColorCodingNameItem(AName, AIsDirectory),
    AState, AFg, ABg);
end;

function ColorCodingResolveItem(const AItem: TColorCodingItem;
  AState: TColorCodingState; out AFg, ABg: TAlphaColor): Boolean;
var
  I: Integer;
  Moment: TDateTime;
begin
  AFg := 0;
  ABg := 0;
  Result := False;
  EnsureGroups;
  if AItem.Name = '' then
    Exit;
  Moment := Now;
  // First mask match wins outright -
  // the winning group's color for AState governs even when it's unset
  // (Result = False then, i.e. "this group has no opinion here, defer to
  // the theme"); we don't fall through to a later group just because this
  // one left a state blank. Disabled groups, and groups whose ApplyTo
  // excludes this row's kind, are invisible to matching - skipped, not
  // treated as a match with nothing to say (that would still stop the scan).
  for I := 0 to High(GGroups) do
  begin
    if not GGroups[I].Enabled then
      Continue;
    if (GGroups[I].ApplyTo = ccaFilesOnly) and AItem.IsDirectory then
      Continue;
    if (GGroups[I].ApplyTo = ccaDirsOnly) and not AItem.IsDirectory then
      Continue;
    if NameMatchesAnyMask(AItem.Name, GGroups[I].Masks) and
       ColorCodingConditionMet(GGroups[I].Cond, AItem, Moment) then
    begin
      AFg := GGroups[I].Colors[AState].Fg;
      ABg := GGroups[I].Colors[AState].Bg;
      Exit((AFg <> 0) or (ABg <> 0));
    end;
  end;
end;

function ColorCodingSortPriority(const AName: string; AIsDirectory: Boolean): Integer;
begin
  Result := ColorCodingSortPriorityItem(ColorCodingNameItem(AName, AIsDirectory));
end;

function ColorCodingSortPriorityItem(const AItem: TColorCodingItem): Integer;
var
  I: Integer;
  Moment: TDateTime;
begin
  Result := 0;
  EnsureGroups;
  if AItem.Name = '' then
    Exit;
  Moment := Now;
  for I := 0 to High(GGroups) do
  begin
    if not GGroups[I].Enabled then
      Continue;
    if (GGroups[I].ApplyTo = ccaFilesOnly) and AItem.IsDirectory then
      Continue;
    if (GGroups[I].ApplyTo = ccaDirsOnly) and not AItem.IsDirectory then
      Continue;
    if NameMatchesAnyMask(AItem.Name, GGroups[I].Masks) and
       ColorCodingConditionMet(GGroups[I].Cond, AItem, Moment) then
      Exit(GGroups[I].SortPriority);
  end;
end;

const
  cAttrLetters = 'HRSACEL';
  cSecsPerDay = 86400;

function ColorCodingConditionMet(const ACond: TColorCodingCondition;
  const AItem: TColorCodingItem; ANow: TDateTime): Boolean;
var
  AgeSecs: Double;
begin
  Result := False;
  if ACond.HasMinSize and ((AItem.Size < 0) or (AItem.Size <= ACond.MinSize)) then
    Exit;
  if ACond.HasMaxSize and ((AItem.Size < 0) or (AItem.Size >= ACond.MaxSize)) then
    Exit;
  if (ACond.NewerSecs > 0) or (ACond.OlderSecs > 0) then
  begin
    if AItem.ModTime <= 0 then
      Exit;
    AgeSecs := (ANow - AItem.ModTime) * cSecsPerDay;
    if (ACond.NewerSecs > 0) and (AgeSecs >= ACond.NewerSecs) then
      Exit;
    if (ACond.OlderSecs > 0) and (AgeSecs <= ACond.OlderSecs) then
      Exit;
  end;
  if ACond.Require - AItem.Attrs <> [] then
    Exit;
  if ACond.Exclude * AItem.Attrs <> [] then
    Exit;
  Result := True;
end;

// Number with an optional one-letter suffix found in AUnits; AMults is the
// factor per suffix letter. A bare number is accepted only when ABareOk.
function ParseAmount(const AText, AUnits: string; const AMults: array of Int64;
  ABareOk: Boolean; out AValue: Int64): Boolean;
var
  Digits: string;
  I, P: Integer;
  N: Int64;
begin
  Result := False;
  Digits := AText;
  P := 0;
  if (Digits <> '') and not CharInSet(Digits[Length(Digits)], ['0'..'9']) then
  begin
    P := Pos(UpCase(Digits[Length(Digits)]), AUnits);
    if P = 0 then
      Exit;
    SetLength(Digits, Length(Digits) - 1);
  end
  else if not ABareOk then
    Exit;
  if (Digits = '') or (Length(Digits) > 12) then
    Exit;
  for I := 1 to Length(Digits) do
    if not CharInSet(Digits[I], ['0'..'9']) then
      Exit;
  if not TryStrToInt64(Digits, N) then
    Exit;
  if P = 0 then
    AValue := N
  else
    AValue := N * AMults[P - 1];
  Result := True;
end;

function ParseAttrTerm(const ATerm: string; var ACond: TColorCodingCondition): Boolean;
var
  I, P: Integer;
  Attr: TColorCodingAttr;
begin
  Result := False;
  if Length(ATerm) < 2 then
    Exit;
  for I := 2 to Length(ATerm) do
  begin
    P := Pos(UpCase(ATerm[I]), cAttrLetters);
    if P = 0 then
      Exit;
    Attr := TColorCodingAttr(P - 1);
    if ATerm[1] = '+' then
    begin
      Include(ACond.Require, Attr);
      Exclude(ACond.Exclude, Attr);
    end
    else
    begin
      Include(ACond.Exclude, Attr);
      Exclude(ACond.Require, Attr);
    end;
  end;
  Result := True;
end;

function ColorCodingParseCondition(const AText: string;
  out ACond: TColorCodingCondition): Boolean;
var
  Terms: TArray<string>;
  T, Key, Rest: string;
  V: Int64;
  Greater: Boolean;
  OpPos: Integer;
begin
  Result := False;
  ACond := Default(TColorCodingCondition);
  Terms := Trim(AText).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  for T in Terms do
  begin
    if CharInSet(T[1], ['+', '-']) then
    begin
      if not ParseAttrTerm(T, ACond) then
        Exit;
      Continue;
    end;
    OpPos := Pos('<', T);
    if OpPos = 0 then
      OpPos := Pos('>', T);
    if OpPos < 2 then
      Exit;
    Key := LowerCase(Copy(T, 1, OpPos - 1));
    Greater := T[OpPos] = '>';
    Rest := Copy(T, OpPos + 1, MaxInt);
    if Key = 'size' then
    begin
      if not ParseAmount(Rest, 'KMGT', [Int64(1) shl 10, Int64(1) shl 20,
        Int64(1) shl 30, Int64(1) shl 40], True, V) then
        Exit;
      if Greater then
      begin
        ACond.HasMinSize := True;
        ACond.MinSize := V;
      end
      else
      begin
        ACond.HasMaxSize := True;
        ACond.MaxSize := V;
      end;
    end
    else if Key = 'age' then
    begin
      if not ParseAmount(Rest, 'MHDW', [60, 3600, 86400, 604800], False, V) or
         (V = 0) then
        Exit;
      // "age<7d": modified less than 7 days ago.
      if Greater then
        ACond.OlderSecs := V
      else
        ACond.NewerSecs := V;
    end
    else
      Exit;
  end;
  Result := True;
end;

function FormatAmount(AValue: Int64; const AUnits: string;
  const AMults: array of Int64): string;
var
  I: Integer;
begin
  for I := High(AMults) downto 0 do
    if (AValue >= AMults[I]) and (AValue mod AMults[I] = 0) then
      Exit(IntToStr(AValue div AMults[I]) + LowerCase(AUnits[I + 1]));
  Result := IntToStr(AValue);
end;

function ColorCodingConditionText(const ACond: TColorCodingCondition): string;
const
  cAgeUnits = 'mhdw';
var
  Parts: TArray<string>;
  A: TColorCodingAttr;
  Plus, Minus: string;

  procedure Add(const AText: string);
  begin
    Parts := Parts + [AText];
  end;

begin
  SetLength(Parts, 0);
  if ACond.HasMinSize then
    Add('size>' + FormatAmount(ACond.MinSize, 'KMGT', [Int64(1) shl 10,
      Int64(1) shl 20, Int64(1) shl 30, Int64(1) shl 40]));
  if ACond.HasMaxSize then
    Add('size<' + FormatAmount(ACond.MaxSize, 'KMGT', [Int64(1) shl 10,
      Int64(1) shl 20, Int64(1) shl 30, Int64(1) shl 40]));
  if ACond.NewerSecs > 0 then
    Add('age<' + FormatAmount(ACond.NewerSecs, cAgeUnits, [60, 3600, 86400, 604800]));
  if ACond.OlderSecs > 0 then
    Add('age>' + FormatAmount(ACond.OlderSecs, cAgeUnits, [60, 3600, 86400, 604800]));
  Plus := '';
  Minus := '';
  for A := Low(TColorCodingAttr) to High(TColorCodingAttr) do
  begin
    if A in ACond.Require then
      Plus := Plus + cAttrLetters[Ord(A) + 1];
    if A in ACond.Exclude then
      Minus := Minus + cAttrLetters[Ord(A) + 1];
  end;
  if Plus <> '' then
    Add('+' + Plus);
  if Minus <> '' then
    Add('-' + Minus);
  Result := string.Join(' ', Parts);
end;

function ColorCodingColorText(AColor: TAlphaColor; const ARef: string): string;
begin
  if ARef <> '' then
    Result := ARef
  else
    Result := ColorToHex(AColor);
end;

function ColorCodingGroupSame(const A, B: TColorCodingGroup): Boolean;
begin
  Result := ColorCodingGroupsToJson([A]) = ColorCodingGroupsToJson([B]);
end;

function ColorCodingNames(const AGroups: TArray<TColorCodingGroup>): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(AGroups));
  for I := 0 to High(AGroups) do
    Result[I] := AGroups[I].Name;
end;

function FindGroup(const AGroups: TArray<TColorCodingGroup>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AGroups) do
    if SameText(AGroups[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

procedure ColorCodingApplyOrder(var AGroups: TArray<TColorCodingGroup>;
  const AOrder: TArray<string>);
var
  Sorted: TArray<TColorCodingGroup>;
  Taken: TArray<Boolean>;
  I, J: Integer;
begin
  if Length(AOrder) = 0 then
    Exit;
  SetLength(Taken, Length(AGroups));
  SetLength(Sorted, 0);
  for I := 0 to High(AOrder) do
  begin
    J := FindGroup(AGroups, AOrder[I]);
    if (J >= 0) and not Taken[J] then
    begin
      Taken[J] := True;
      Sorted := Sorted + [AGroups[J]];
    end;
  end;
  for I := 0 to High(AGroups) do
    if not Taken[I] then
      Sorted := Sorted + [AGroups[I]];
  AGroups := Sorted;
end;

procedure ColorCodingDiff(const ABase, AEdited: TArray<TColorCodingGroup>;
  out AChanges: TArray<TColorCodingGroup>; out AOrder: TArray<string>);
var
  I, J: Integer;
  Gone: TColorCodingGroup;
  Natural: TArray<TColorCodingGroup>;
  Same: Boolean;
begin
  SetLength(AChanges, 0);
  SetLength(AOrder, 0);
  for I := 0 to High(AEdited) do
  begin
    J := FindGroup(ABase, AEdited[I].Name);
    if (J < 0) or not ColorCodingGroupSame(ABase[J], AEdited[I]) then
      AChanges := AChanges + [AEdited[I]];
  end;
  // A merge cannot remove a base group: one the editor dropped is kept off.
  for J := 0 to High(ABase) do
    if FindGroup(AEdited, ABase[J].Name) < 0 then
    begin
      Gone := ABase[J];
      Gone.Enabled := False;
      AChanges := AChanges + [Gone];
    end;
  Natural := MergeColorCodingGroups(ABase, AChanges);
  Same := Length(Natural) = Length(AEdited);
  if Same then
    for I := 0 to High(Natural) do
      if not SameText(Natural[I].Name, AEdited[I].Name) then
      begin
        Same := False;
        Break;
      end;
  if not Same then
    AOrder := ColorCodingNames(AEdited);
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
  StateKey, FgHex, BgHex, CondText: string;
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
      if AGroups[I].SortPriority <> 0 then
        Obj.AddPair('sortPriority', TJSONNumber.Create(AGroups[I].SortPriority));
      CondText := ColorCodingConditionText(AGroups[I].Cond);
      if CondText <> '' then
        Obj.AddPair('when', CondText);
      for S := Low(TColorCodingState) to High(TColorCodingState) do
      begin
        if (AGroups[I].Colors[S].Fg = 0) and (AGroups[I].Colors[S].Bg = 0) and
           (AGroups[I].Colors[S].FgRef = '') and (AGroups[I].Colors[S].BgRef = '') then
          Continue;
        case S of
          ccsNormal: StateKey := 'normal';
          ccsSelected: StateKey := 'selected';
        else
          StateKey := 'current';
        end;
        StateObj := TJSONObject.Create;
        FgHex := ColorCodingColorText(AGroups[I].Colors[S].Fg, AGroups[I].Colors[S].FgRef);
        if FgHex <> '' then
          StateObj.AddPair('fg', FgHex);
        BgHex := ColorCodingColorText(AGroups[I].Colors[S].Bg, AGroups[I].Colors[S].BgRef);
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
  EnsureGroups;
  Result := Copy(GGroups);
end;

end.
