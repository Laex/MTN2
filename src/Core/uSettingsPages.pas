unit uSettingsPages;

{ The settings window: the pages of several dialog declarations in one dialog,
  with a vertical list of sections on the left and a search line above it.
  Pure data in, data out - the window code opens the result and narrows the list
  as the search text changes. }

interface

uses
  System.SysUtils, System.Generics.Collections, uDialogTypes;

const
  cSettingsSidebarWidth = 16;
  cSettingsStripId = 'sections';
  cSettingsQueryId = 'query';
  /// <summary>Row of the first control on a page of a source declaration: the
  /// tab strip and its rule sit above it and are left out of the merge.</summary>
  cSettingsSourceTop = 3;
  /// <summary>Rows of the description under the content.</summary>
  cSettingsHintRows = 2;

type
  TSettingsPages = record
    /// <summary>Caption of each section and the page of the merged dialog it shows.</summary>
    Captions: TArray<string>;
    Pages: TArray<Integer>;
  end;

/// <summary>Merges the pages of ASources into one declaration. A source with a tab
/// strip gives one section per caption; one without gives a single section named
/// ASingleCaptions[its index]. The OK / Cancel buttons and the rules of the sources
/// are dropped and replaced by one pair under the content.</summary>
function MergeSettingsPages(const ASources: TArray<TDialogDeclaration>;
  const ASingleCaptions: TArray<string>; const ATitle: string;
  out APages: TSettingsPages): TDialogDeclaration;

type
  /// <summary>A field of the settings window as the command palette lists it.</summary>
  TSettingField = record
    Id: string;
    /// <summary>Caption of the field without mnemonic marks.</summary>
    Caption: string;
    Hint: string;
    /// <summary>Caption of the section the field is on.</summary>
    Section: string;
  end;

/// <summary>The check boxes, inputs, drop-downs and lists of ADecl that have an
/// id, a caption (own text, the label on the same row, or the title of the frame
/// around it) and a section in APages.</summary>
function SettingsFields(const ADecl: TDialogDeclaration;
  const APages: TSettingsPages): TArray<TSettingField>;

/// <summary>The sections whose caption or whose page's captions contain AQuery
/// (case-insensitive, mnemonic marks ignored). An empty query keeps all of them.</summary>
function SettingsSectionsMatching(const ADecl: TDialogDeclaration;
  const APages: TSettingsPages; const AQuery: string;
  out AMatches: TSettingsPages): Boolean;

implementation

uses
  System.Math, uDialogTabs;

function PlainText(const AText: string): string;
begin
  Result := AnsiLowerCase(StringReplace(AText, '&', '', [rfReplaceAll]));
end;

function IsRule(const C: TDialogControl): Boolean;
begin
  Result := (C.Kind = dckLabel) and IsHRuleText(C.Text);
end;

// A section whose controls were all left out (the font page of a terminal
// build) is not listed.
procedure DropEmptySections(const AControls: TList<TDialogControl>;
  var APages: TSettingsPages);
var
  I, J, N: Integer;
  Used: Boolean;
begin
  N := 0;
  for I := 0 to High(APages.Pages) do
  begin
    Used := False;
    for J := 0 to AControls.Count - 1 do
      if AControls[J].TabPage = APages.Pages[I] then
      begin
        Used := True;
        Break;
      end;
    if Used then
    begin
      APages.Captions[N] := APages.Captions[I];
      APages.Pages[N] := APages.Pages[I];
      Inc(N);
    end;
  end;
  SetLength(APages.Captions, N);
  SetLength(APages.Pages, N);
end;

function MergeSettingsPages(const ASources: TArray<TDialogDeclaration>;
  const ASingleCaptions: TArray<string>; const ATitle: string;
  out APages: TSettingsPages): TDialogDeclaration;
var
  Controls: TList<TDialogControl>;
  Source: TDialogDeclaration;
  Strip, S, I, PageBase, Bottom, Right, BtnW, BtnLeft: Integer;
  C, Own: TDialogControl;
  OkText, CancelText: string;
begin
  OkText := 'OK';
  CancelText := 'Cancel';
  Controls := TList<TDialogControl>.Create;
  try
    SetLength(APages.Captions, 0);
    SetLength(APages.Pages, 0);
    PageBase := 0;
    Bottom := 0;
    Right := 0;
    for S := 0 to High(ASources) do
    begin
      Source := ASources[S];
      Strip := DialogTabStripIndex(Source.Controls);
      if Strip >= 0 then
        for I := 0 to High(Source.Controls[Strip].Items) do
        begin
          SetLength(APages.Captions, Length(APages.Captions) + 1);
          APages.Captions[High(APages.Captions)] := Source.Controls[Strip].Items[I];
          SetLength(APages.Pages, Length(APages.Pages) + 1);
          APages.Pages[High(APages.Pages)] := PageBase + I + 1;
        end
      else
      begin
        SetLength(APages.Captions, Length(APages.Captions) + 1);
        if S <= High(ASingleCaptions) then
          APages.Captions[High(APages.Captions)] := ASingleCaptions[S]
        else
          APages.Captions[High(APages.Captions)] := Source.Title;
        SetLength(APages.Pages, Length(APages.Pages) + 1);
        APages.Pages[High(APages.Pages)] := PageBase + 1;
      end;
      for I := 0 to High(Source.Controls) do
      begin
        C := Source.Controls[I];
        if (C.Kind = dckButton) and (C.TabPage = 0) then
        begin
          // The sources' own captions are already translated.
          if C.IsCancel then
            CancelText := C.Text
          else if C.IsDefault then
            OkText := C.Text;
          Continue;
        end;
        if (C.Kind = dckTab) or IsRule(C) then
          Continue;
        if (Strip < 0) or (C.TabPage > 0) then
          C.TabPage := PageBase + Max(C.TabPage, 1);
        C.Col := C.Col + cSettingsSidebarWidth;
        C.Row := C.Row - IfThen(Strip >= 0, cSettingsSourceTop, 0);
        Controls.Add(C);
        if C.Kind <> dckButton then
        begin
          Bottom := Max(Bottom, C.Row + Max(C.BoxH, 1));
          Right := Max(Right, C.Col + Max(C.BoxW, 1));
        end
        else
        begin
          Bottom := Max(Bottom, C.Row + 1);
          Right := Max(Right, C.Col + Max(C.BoxW, 1));
        end;
      end;
      if Strip >= 0 then
        Inc(PageBase, Length(Source.Controls[Strip].Items))
      else
        Inc(PageBase);
    end;

    DropEmptySections(Controls, APages);

    Result := Default(TDialogDeclaration);
    Result.Version := cDialogProtocolV2;
    Result.Title := ATitle;
    Result.Width := Max(Right + 3, cSettingsSidebarWidth + 30);
    Result.Height := Bottom + 9;

    Own := WithControlBox(MakeLabel('', 'search_caption'), 1, 0, cSettingsSidebarWidth - 2, 1);
    Controls.Insert(0, Own);
    Own := WithControlBox(MakeLabel('', cSettingsQueryId), 1, 1, cSettingsSidebarWidth - 2, 1);
    Own.Field := True;
    Own.FieldCaretId := cSettingsStripId;
    Controls.Insert(1, Own);
    Own := MakeTabs(cSettingsStripId, APages.Captions, 0);
    Own.Vertical := True;
    Own.TabPages := Copy(APages.Pages);
    Own := WithControlBox(Own, 1, cSettingsSourceTop, cSettingsSidebarWidth - 2,
      Max(Length(APages.Captions), 1));
    Controls.Insert(2, Own);

    Own := WithControlBox(MakeLabel('', 'sidebar_rule'), cSettingsSidebarWidth - 1, 0, 1, Bottom);
    Own.VRule := True;
    Controls.Insert(3, Own);
    Controls.Add(WithControlBox(MakeHRule(Result.Width - 2), 0, Bottom, Result.Width - 2, 1));
    Controls.Add(WithControlBox(MakeHRule(Result.Width - 2), 0, Bottom + 1 + cSettingsHintRows,
      Result.Width - 2, 1));
    Own := WithControlBox(MakeLabel('', 'hint_area'), 1, Bottom + 1, Result.Width - 4,
      cSettingsHintRows);
    Own.HintArea := True;
    Controls.Add(Own);
    BtnW := 12;
    BtnLeft := (Result.Width - 2 - (2 * BtnW + 2)) div 2;
    Controls.Add(WithControlBox(MakeButton(cDlgCmdOk, OkText, True), BtnLeft, Bottom + 3 + cSettingsHintRows, BtnW, 1));
    Controls.Add(WithControlBox(MakeButton(cDlgCmdCancel, CancelText, False, True),
      BtnLeft + BtnW + 2, Bottom + 3 + cSettingsHintRows, BtnW, 1));
    Result.Controls := Controls.ToArray;
  finally
    Controls.Free;
  end;
end;

function SettingsSectionsMatching(const ADecl: TDialogDeclaration;
  const APages: TSettingsPages; const AQuery: string;
  out AMatches: TSettingsPages): Boolean;
var
  Q: string;
  I, J: Integer;
  Hit: Boolean;
begin
  Q := PlainText(Trim(AQuery));
  SetLength(AMatches.Captions, 0);
  SetLength(AMatches.Pages, 0);
  for I := 0 to High(APages.Captions) do
  begin
    Hit := (Q = '') or (Pos(Q, PlainText(APages.Captions[I])) > 0);
    if not Hit then
      for J := 0 to High(ADecl.Controls) do
        if (ADecl.Controls[J].TabPage = APages.Pages[I]) and
           (ADecl.Controls[J].Kind in [dckLabel, dckCheckbox, dckRadio, dckRadioGroup, dckButton]) and
           (Pos(Q, PlainText(ADecl.Controls[J].Text)) > 0) then
        begin
          Hit := True;
          Break;
        end;
    if Hit then
    begin
      SetLength(AMatches.Captions, Length(AMatches.Captions) + 1);
      AMatches.Captions[High(AMatches.Captions)] := APages.Captions[I];
      SetLength(AMatches.Pages, Length(AMatches.Pages) + 1);
      AMatches.Pages[High(AMatches.Pages)] := APages.Pages[I];
    end;
  end;
  Result := Length(AMatches.Captions) > 0;
end;

function FieldCaption(const ADecl: TDialogDeclaration; AIndex: Integer): string;
var
  C, L: TDialogControl;
  I: Integer;
begin
  C := ADecl.Controls[AIndex];
  if C.Kind = dckCheckbox then
    Exit(StringReplace(C.Text, '&', '', [rfReplaceAll]));
  for I := 0 to High(ADecl.Controls) do
  begin
    L := ADecl.Controls[I];
    if (L.Kind = dckLabel) and not L.GroupFrame and (L.TabPage = C.TabPage) and
       (L.Row = C.Row) and (L.Col < C.Col) and (L.Text <> '') then
      Exit(StringReplace(Trim(L.Text), '&', '', [rfReplaceAll]).TrimRight([':']));
  end;
  for I := 0 to High(ADecl.Controls) do
  begin
    L := ADecl.Controls[I];
    if (L.Kind = dckLabel) and L.GroupFrame and (L.TabPage = C.TabPage) and
       (C.Row > L.Row) and (C.Row < L.Row + L.BoxH) then
      Exit(StringReplace(L.Text, '&', '', [rfReplaceAll]));
  end;
  Result := '';
end;

function SettingsFields(const ADecl: TDialogDeclaration;
  const APages: TSettingsPages): TArray<TSettingField>;
var
  List: TList<TSettingField>;
  F: TSettingField;
  C: TDialogControl;
  I, S: Integer;
begin
  List := TList<TSettingField>.Create;
  try
    for I := 0 to High(ADecl.Controls) do
    begin
      C := ADecl.Controls[I];
      if (C.Id = '') or (C.TabPage = 0) or
         not (C.Kind in [dckCheckbox, dckInput, dckDropDown, dckList]) then
        Continue;
      F.Section := '';
      for S := 0 to High(APages.Pages) do
        if APages.Pages[S] = C.TabPage then
          F.Section := APages.Captions[S];
      F.Id := C.Id;
      F.Caption := FieldCaption(ADecl, I);
      F.Hint := C.Hint;
      if (F.Section <> '') and (F.Caption <> '') then
        List.Add(F);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
