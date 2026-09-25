unit uFunctionBar;

{ Shared F-key / letter hint bar. Labels follow held modifiers and only list
  actions that the active view actually handles. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uKeymap, uStrings;

type
  TFunctionBarContext = (
    fbcPanels,
    fbcConsole,
    fbcTerminal,
    fbcViewer,
    fbcViewerHex,
    fbcViewerMarkdown,
    fbcViewerFind,
    fbcEditor,
    fbcEditorAskSave,
    fbcDrive,
    fbcUserMenu,
    fbcUserMenuEdit, // F2 user menu: also Ins/F4/Del editing keys
    fbcStub,
    fbcStubEdit,
    fbcDialogList,
    fbcJob,
    fbcJobRunning,
    fbcSearchDialog,
    fbcSearchRunning,
    fbcSearchResults,
    fbcSysFolders,
    fbcRecycleBin,
    fbcTmpPanel,
    fbcWorkspace,
    fbcWorkspaceLibrary,
    fbcFolderHotlist,
    fbcFileHistory, // Alt+F11 list: F3/F4/Ctrl+Enter/Del
    fbcColorCoding,
    fbcColorCodingEdit,
    fbcHelp, // F1 Help window (Markdown viewer with link navigation)
    fbcHelpSearch // fbcHelp after an F7 search: also next/previous match
  );

  TFunctionBarColors = record
    Fg, Bg, HotFg, RuleFg: TAlphaColor;
  end;

  TFunctionBarHitKind = (fbhNone, fbhFKey, fbhHint);

  TFunctionBarHit = record
    Kind: TFunctionBarHitKind;
    FKeyNum: Integer; // 1..10 when Kind=fbhFKey
    HintKey: string;  // "A", "Esc", "Enter", ... when Kind=fbhHint
  end;

procedure FunctionBarGetItems(ACtx: TFunctionBarContext; AMods: TShiftState;
  out AItems, ALetters: TArray<string>);

function FunctionBarDefaultColors: TFunctionBarColors;

procedure DrawFunctionBar(const AGrid: TTerminalGrid; AY, AWidth: Integer;
  const AItems, ALetters: TArray<string>; AMods: TShiftState;
  const AColors: TFunctionBarColors; ATheme: IThemeRenderer = nil);

/// <summary>Hit-test a column on the F-bar. Layout must match DrawFunctionBar.</summary>
function FunctionBarHitTest(ACol, AWidth: Integer;
  const AItems, ALetters: TArray<string>; AMods: TShiftState;
  AThemeLayout: Boolean): TFunctionBarHit;

/// <summary>Map a bar hit to the key event that the label represents.</summary>
function FunctionBarHitToInput(const AHit: TFunctionBarHit; AMods: TShiftState;
  out AKey: Word; out AKeyChar: Char; out AShift: TShiftState): Boolean;

implementation

function EmptyItems: TArray<string>;
begin
  SetLength(Result, 10);
  Result[0] := '1';
  Result[1] := '2';
  Result[2] := '3';
  Result[3] := '4';
  Result[4] := '5';
  Result[5] := '6';
  Result[6] := '7';
  Result[7] := '8';
  Result[8] := '9';
  Result[9] := '10';
end;

procedure FunctionBarItemsForPanels(ACtx: TFunctionBarContext; Mods: TShiftState;
  var AItems, ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) and not (ssShift in Mods) then
  begin
    AItems[0] := '1Left';
    AItems[1] := '2Right';
    AItems[2] := '3Name';
    AItems[3] := '4Ext';
    AItems[4] := '5Time';
    AItems[5] := '6Size';
    AItems[6] := '7Unsrt';
    AItems[7] := '8Creat';
    AItems[8] := '9Acces';
    ApplyKeymapToFBarItems(ActiveKeymap, Mods, AItems);
    // Letter hints: actions not on F1–F10 (F12 / digit / letters).
    SetLength(ALetters, 10);
    ALetters[0] := '3:Modes';
    ALetters[1] := 'U:Swap';
    ALetters[2] := 'L:Info';
    ALetters[3] := 'F12:Sort';
    ALetters[4] := 'O:Cons';
    ALetters[5] := 'R:Refr';
    ALetters[6] := 'A:All';
    ALetters[7] := 'T:PTab';
    ALetters[8] := 'Ent:Name';
    ALetters[9] := 'SEnt:Path';
  end
  else if (ssAlt in Mods) and not (ssCtrl in Mods) and not (ssShift in Mods) then
  begin
    AItems[0] := '1Left';
    AItems[1] := '2Right';
    AItems[6] := '7Find';
    ApplyKeymapToFBarItems(ActiveKeymap, Mods, AItems);
  end
  else if (ssShift in Mods) and not (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    AItems[0] := '1Pack';
    AItems[1] := '2Unpk';
    AItems[3] := '4Edit';
    AItems[4] := '5CopyH';
    AItems[5] := '6Renam';
    AItems[7] := '8Wipe';
    ApplyKeymapToFBarItems(ActiveKeymap, Mods, AItems);
  end
  else if (ssAlt in Mods) and (ssShift in Mods) and not (ssCtrl in Mods)
    and (ACtx = fbcTmpPanel) then
  begin
    // Far TmpPanel: Alt+Shift+F2 save list, Alt+Shift+F3 goto opposite.
    AItems[1] := '2SavLst';
    AItems[2] := '3GoTo';
    SetLength(ALetters, 1);
    ALetters[0] := 'CPgUp:GoTo';
  end
  else if (ssCtrl in Mods) and (ssAlt in Mods) and not (ssShift in Mods)
    and (ACtx = fbcWorkspace) then
  begin
    SetLength(ALetters, 1);
    ALetters[0] := 'Ent:GoTo';
  end
  else if Mods = [] then
  begin
    AItems[0] := '1Help';
    AItems[1] := '2Menu';
    AItems[2] := '3View';
    AItems[3] := '4Edit';
    AItems[4] := '5Copy';
    AItems[5] := '6Move';
    AItems[6] := '7MkDir';
    AItems[7] := '8Del';
    AItems[9] := '10Quit';
    ApplyKeymapToFBarItems(ActiveKeymap, Mods, AItems);
    if ACtx = fbcTmpPanel then
    begin
      AItems[6] := '7Remove';
      SetLength(ALetters, 1);
      ALetters[0] := 'CPgUp:GoTo';
    end
    else if ACtx = fbcWorkspace then
    begin
      AItems[7] := '8Unlink';
      SetLength(ALetters, 1);
      ALetters[0] := 'CtAlt+Ent:GoTo';
    end;
  end;
end;

procedure FunctionBarItemsForConsole(Mods: TShiftState; var ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    SetLength(ALetters, 3);
    ALetters[0] := 'A:All';
    ALetters[1] := 'C:Copy';
    ALetters[2] := 'O:Panels';
  end
  else if Mods = [] then
  begin
    SetLength(ALetters, 1);
    ALetters[0] := 'Esc:Panels';
  end;
end;

// Raw passthrough: almost every key goes straight to the shell, so only the
// host-level shortcuts get a hint here.
procedure FunctionBarItemsForTerminal(Mods: TShiftState; var ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    SetLength(ALetters, 3);
    ALetters[0] := 'A:All';
    ALetters[1] := 'C:Copy/Brk';
    ALetters[2] := 'V:Paste';
  end
  else if Mods = [] then
  begin
    SetLength(ALetters, 1);
    ALetters[0] := 'Esc:Close';
  end;
end;

procedure FunctionBarItemsForViewer(Mods: TShiftState; var AItems, ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    SetLength(ALetters, 3);
    ALetters[0] := 'A:All';
    ALetters[1] := 'C:Copy';
    ALetters[2] := 'H:Hex';
  end
  else if (ssShift in Mods) and not (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    AItems[2] := '3Prev';
    AItems[6] := '7Next';
    AItems[7] := '8Code';
  end
  else if (ssAlt in Mods) and not (ssCtrl in Mods) then
  begin
    AItems[6] := '7Prev';
    AItems[7] := '8Goto';
  end
  else if Mods = [] then
  begin
    AItems[1] := '2Wrap';
    AItems[2] := '3Next';
    AItems[3] := '4Hex';
    AItems[5] := '6Edit';
    AItems[6] := '7Find';
    AItems[7] := '8Code';
    AItems[9] := '10Quit';
  end;
end;

procedure FunctionBarItemsForViewerHex(Mods: TShiftState; var AItems, ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    SetLength(ALetters, 2);
    ALetters[0] := 'C:Copy';
    ALetters[1] := 'H:Text';
  end
  else if (ssAlt in Mods) and not (ssCtrl in Mods) then
  begin
    AItems[7] := '8Goto';
  end
  else if Mods = [] then
  begin
    AItems[3] := '4Text';
    AItems[5] := '6Edit';
    AItems[7] := '8Code';
    AItems[9] := '10Quit';
  end;
end;

// Markdown render: F4 is Raw (same as Ctrl+M). Ctrl+H stays Hex. No Wrap on
// F2 — Markdown wraps via the parser, not Viewer word-wrap.
procedure FunctionBarItemsForViewerMarkdown(Mods: TShiftState; var AItems, ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    SetLength(ALetters, 3);
    ALetters[0] := 'C:Copy';
    ALetters[1] := 'H:Hex';
    ALetters[2] := 'M:Raw';
  end
  else if (ssShift in Mods) and not (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    AItems[2] := '3Prev';
    AItems[6] := '7Next';
  end
  else if (ssAlt in Mods) and not (ssCtrl in Mods) then
  begin
    AItems[6] := '7Prev';
    AItems[7] := '8Goto';
  end
  else if Mods = [] then
  begin
    AItems[2] := '3Next';
    AItems[3] := '4Raw';
    AItems[5] := '6Edit';
    AItems[6] := '7Find';
    AItems[9] := '10Quit';
  end;
end;

// F1 Help: read-only Markdown with links; F6/F4/F8 of the Viewer do not apply.
// Next/previous match (F3, Shift+F3, Shift/Alt+F7) only once something has
// been searched for (AHasSearch) -- Help does not open the prompt for them.
procedure FunctionBarItemsForHelp(Mods: TShiftState; AHasSearch: Boolean;
  var AItems, ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    SetLength(ALetters, 2);
    ALetters[0] := 'A:All';
    ALetters[1] := 'C:Copy';
  end
  else if (ssShift in Mods) and not (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    if AHasSearch then
    begin
      AItems[2] := '3Prev';
      AItems[6] := '7Next';
    end;
    SetLength(ALetters, 1);
    ALetters[0] := 'Shift+Tab:Link';
  end
  else if (ssAlt in Mods) and not (ssCtrl in Mods) then
  begin
    if AHasSearch then
      AItems[6] := '7Prev';
  end
  else if Mods = [] then
  begin
    AItems[0] := '1Contents';
    if AHasSearch then
      AItems[2] := '3Next';
    AItems[6] := '7Find';
    AItems[9] := '10Quit';
    SetLength(ALetters, 3);
    ALetters[0] := 'Tab:Link';
    ALetters[1] := 'Enter:Go';
    ALetters[2] := 'BkSp:Back';
  end;
end;

procedure FunctionBarItemsForEditor(Mods: TShiftState; var AItems, ALetters: TArray<string>);
begin
  if (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    if ssShift in Mods then
    begin
      SetLength(ALetters, 1);
      ALetters[0] := 'Z:Redo';
    end
    else
    begin
      SetLength(ALetters, 7);
      ALetters[0] := 'A:All';
      ALetters[1] := 'C:Copy';
      ALetters[2] := 'X:Cut';
      ALetters[3] := 'V:Paste';
      ALetters[4] := 'Z:Undo';
      ALetters[5] := 'Y:DelLn';
      ALetters[6] := 'F7:Repl';
    end;
  end
  else if (ssShift in Mods) and not (ssCtrl in Mods) and not (ssAlt in Mods) then
  begin
    AItems[2] := '3Prev';
    AItems[6] := '7Next';
    AItems[7] := '8Code';
  end
  else if (ssAlt in Mods) and not (ssCtrl in Mods) then
  begin
    AItems[6] := '7Prev';
    AItems[7] := '8Goto';
  end
  else if Mods = [] then
  begin
    AItems[1] := '2Save';
    AItems[2] := '3Next';
    AItems[5] := '6View';
    AItems[6] := '7Find';
    AItems[7] := '8Code';
    AItems[9] := '10Quit';
  end;
end;

// Labels are built in English everywhere above (and by the keymap) and
// translated here in one pass: "5Copy" -> number + T('fbar.Copy'),
// "Esc:Cancel" -> key + ':' + T('fbar.Cancel'). The number and the key part
// stay as they are -- hit-testing maps them back to keys. F-key slots are
// about 6 cells wide at 80 columns, so fbar.* are short forms of their own,
// not the menu's full captions.
function TranslateFBarLabel(const AText: string): string;
begin
  if AText = '' then
    Result := ''
  else
    Result := T('fbar.' + AText, AText);
end;

procedure TranslateFBarItems(var AItems, ALetters: TArray<string>);
var
  I, P: Integer;
begin
  if SameText(CurrentLocale, 'en') then
    Exit;
  for I := 0 to High(AItems) do
  begin
    P := 1;
    while (P <= Length(AItems[I])) and CharInSet(AItems[I][P], ['0'..'9']) do
      Inc(P);
    AItems[I] := Copy(AItems[I], 1, P - 1) + TranslateFBarLabel(Copy(AItems[I], P, MaxInt));
  end;
  for I := 0 to High(ALetters) do
  begin
    P := Pos(':', ALetters[I]);
    if P > 0 then
      ALetters[I] := Copy(ALetters[I], 1, P) +
        TranslateFBarLabel(Copy(ALetters[I], P + 1, MaxInt));
  end;
end;

procedure FunctionBarGetItems(ACtx: TFunctionBarContext; AMods: TShiftState;
  out AItems, ALetters: TArray<string>);
var
  Mods: TShiftState;
begin
  Mods := AMods * [ssShift, ssAlt, ssCtrl];
  SetLength(ALetters, 0);
  AItems := EmptyItems;

  case ACtx of
    fbcPanels, fbcTmpPanel, fbcWorkspace:
      FunctionBarItemsForPanels(ACtx, Mods, AItems, ALetters);

    fbcConsole:
      FunctionBarItemsForConsole(Mods, ALetters);

    fbcTerminal:
      FunctionBarItemsForTerminal(Mods, ALetters);

    fbcViewer:
      FunctionBarItemsForViewer(Mods, AItems, ALetters);

    fbcViewerHex:
      FunctionBarItemsForViewerHex(Mods, AItems, ALetters);

    fbcViewerMarkdown:
      FunctionBarItemsForViewerMarkdown(Mods, AItems, ALetters);

    fbcHelp, fbcHelpSearch:
      FunctionBarItemsForHelp(Mods, ACtx = fbcHelpSearch, AItems, ALetters);

    fbcViewerFind:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:Next';
        ALetters[1] := 'Esc:Cancel';
      end;

    fbcEditor:
      FunctionBarItemsForEditor(Mods, AItems, ALetters);

    fbcEditorAskSave:
      begin
        SetLength(ALetters, 3);
        ALetters[0] := 'Y:Save';
        ALetters[1] := 'N:Discard';
        ALetters[2] := 'Esc:Cancel';
      end;

    fbcDrive:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:Go';
        ALetters[1] := 'Esc:Cancel';
      end;

    fbcUserMenu:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:Run';
        ALetters[1] := 'Esc:Close';
      end;

    fbcUserMenuEdit:
      begin
        SetLength(ALetters, 6);
        ALetters[0] := 'Enter:Run';
        ALetters[1] := 'Ins:Add';
        ALetters[2] := 'F4:Edit';
        ALetters[3] := 'Del:Delete';
        ALetters[4] := 'Shift+F2:Main/Folder';
        ALetters[5] := 'Esc:Close';
      end;

    fbcStub:
      begin
        SetLength(ALetters, 1);
        ALetters[0] := 'Esc:Close';
      end;

    fbcStubEdit:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:OK';
        ALetters[1] := 'Esc:Cancel';
      end;

    fbcDialogList:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:OK';
        ALetters[1] := 'Esc:Cancel';
      end;

    fbcWorkspaceLibrary:
      begin
        AItems[1] := '2Ren';
        SetLength(ALetters, 4);
        ALetters[0] := 'Enter:Go';
        ALetters[1] := 'Ins:Save';
        ALetters[2] := 'Del:Del';
        ALetters[3] := 'Esc:Cancel';
      end;

    fbcFileHistory:
      begin
        AItems[2] := '3View';
        AItems[3] := '4Edit';
        SetLength(ALetters, 4);
        ALetters[0] := 'Enter:Open';
        ALetters[1] := 'CtEnt:GoTo';
        ALetters[2] := 'Del:Del';
        ALetters[3] := 'Esc:Cancel';
      end;

    fbcFolderHotlist:
      begin
        AItems[1] := '2Ren';
        SetLength(ALetters, 4);
        ALetters[0] := 'Enter:Go';
        ALetters[1] := 'Del:Del';
        ALetters[2] := 'Ct+1-0:Key';
        ALetters[3] := 'Esc:Cancel';
      end;

    fbcColorCoding:
      begin
        AItems[3] := '4Edit';
        SetLength(ALetters, 6);
        ALetters[0] := 'Ins:Add';
        ALetters[1] := 'Del:Del';
        ALetters[2] := 'CtSp:On';
        ALetters[3] := 'CtUp:Move';
        ALetters[4] := 'Enter:Save';
        ALetters[5] := 'Esc:Cancel';
      end;

    fbcColorCodingEdit:
      begin
        SetLength(ALetters, 3);
        ALetters[0] := 'F9:Pick';
        ALetters[1] := 'Enter:OK';
        ALetters[2] := 'Esc:Cancel';
      end;

    fbcJob:
      begin
        SetLength(ALetters, 4);
        ALetters[0] := 'Enter:OK';
        ALetters[1] := 'Y:Yes';
        ALetters[2] := 'N:No';
        ALetters[3] := 'Esc:Cancel';
      end;

    fbcJobRunning:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Esc:Cancel';
        ALetters[1] := 'B:Background';
      end;

    fbcSearchDialog:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:Start';
        ALetters[1] := 'Esc:Cancel';
      end;

    fbcSearchRunning:
      begin
        SetLength(ALetters, 1);
        ALetters[0] := 'Esc:Cancel';
      end;

    fbcSearchResults:
      begin
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:Goto';
        ALetters[1] := 'Esc:Close';
      end;

    fbcSysFolders:
      begin
        // Synthetic category listing: only navigation and the always-available
        // Help/Menu/Quit apply — Copy/Move/MkDir/Delete etc. aren't supported
        // here, so they're left blank instead of shown and then rejected.
        AItems[0] := '1Help';
        AItems[1] := '2Menu';
        AItems[9] := '10Quit';
        SetLength(ALetters, 1);
        ALetters[0] := 'Enter:Open';
      end;

    fbcRecycleBin:
      begin
        // Read-only except for purge (permanent delete) and restore.
        AItems[0] := '1Help';
        AItems[1] := '2Menu';
        AItems[7] := '8Purge';
        AItems[9] := '10Quit';
        SetLength(ALetters, 2);
        ALetters[0] := 'Enter:Open';
        ALetters[1] := 'CtAlt+R:Restore';
      end;
  end;
  TranslateFBarItems(AItems, ALetters);
end;

function FunctionBarDefaultColors: TFunctionBarColors;
begin
  Result.Fg := TAlphaColor($FFE0E0E0);
  Result.Bg := TAlphaColor($FF0000A8);
  Result.HotFg := TAlphaColor($FFF0F000);
  Result.RuleFg := TAlphaColor($FF00B0B0);
end;

procedure DrawFunctionBar(const AGrid: TTerminalGrid; AY, AWidth: Integer;
  const AItems, ALetters: TArray<string>; AMods: TShiftState;
  const AColors: TFunctionBarColors; ATheme: IThemeRenderer);
var
  I, X, KeyLen, Colon, N: Integer;
  Item, KeyPart, LabelPart, Mode: string;
  Mods: TShiftState;
  ToolItems: TArray<string>;

  procedure PutHint(const AKey, ALabel: string);
  begin
    if (AKey = '') or (X > AWidth - 4) then
      Exit;
    PutGridText(AGrid, X, AY, AKey, AColors.HotFg, AColors.Bg, [ccaBold]);
    Inc(X, Length(AKey));
    if ALabel <> '' then
    begin
      PutGridText(AGrid, X, AY, ':' + ALabel + ' ', AColors.Fg, AColors.Bg);
      Inc(X, Length(ALabel) + 2);
    end
    else
    begin
      PutGridText(AGrid, X, AY, ' ', AColors.Fg, AColors.Bg);
      Inc(X);
    end;
  end;

begin
  if AWidth < 4 then
    Exit;
  FillGridRect(AGrid, 0, AY, AWidth - 1, AY, ' ', AColors.Fg, AColors.Bg);
  Mods := AMods * [ssShift, ssAlt, ssCtrl];
  X := 1;

  Mode := '';
  if ssCtrl in Mods then
    Mode := Mode + 'Ctrl+';
  if ssAlt in Mods then
    Mode := Mode + 'Alt+';
  if ssShift in Mods then
    Mode := Mode + 'Shift+';
  if Mode <> '' then
  begin
    Mode := '[' + Copy(Mode, 1, Length(Mode) - 1) + ']';
    PutGridText(AGrid, X, AY, Mode, AColors.HotFg, AColors.Bg, [ccaBold]);
    Inc(X, Length(Mode) + 1);
  end;

  for I := 0 to High(ALetters) do
  begin
    Item := ALetters[I];
    Colon := Pos(':', Item);
    if Colon <= 0 then
      Continue;
    KeyPart := Copy(Item, 1, Colon - 1);
    LabelPart := Copy(Item, Colon + 1, MaxInt);
    PutHint(KeyPart, LabelPart);
  end;

  if Length(ALetters) > 0 then
  begin
    if X <= AWidth - 3 then
    begin
      PutGridText(AGrid, X, AY, '| ', AColors.RuleFg, AColors.Bg);
      Inc(X, 2);
    end;
  end;

  SetLength(ToolItems, 0);
  for I := 0 to High(AItems) do
  begin
    Item := AItems[I];
    if Item = '' then
      Continue;
    KeyLen := 0;
    while (KeyLen < Length(Item)) and CharInSet(Item[KeyLen + 1], ['0'..'9']) do
      Inc(KeyLen);
    if (KeyLen = 0) or (Length(Item) = KeyLen) then
      Continue;
    N := Length(ToolItems);
    SetLength(ToolItems, N + 1);
    ToolItems[N] := Item;
  end;

  if Assigned(ATheme) and (Length(ToolItems) > 0) and (X < AWidth - 2) then
    ATheme.DrawToolBar(AGrid, TRectI.Make(X, AY, AWidth - 1, AY), ToolItems, [])
  else
    for I := 0 to High(ToolItems) do
    begin
      Item := ToolItems[I];
      KeyLen := 0;
      while (KeyLen < Length(Item)) and CharInSet(Item[KeyLen + 1], ['0'..'9']) do
        Inc(KeyLen);
      if X > AWidth - 2 then
        Break;
      KeyPart := Copy(Item, 1, KeyLen);
      PutGridText(AGrid, X, AY, KeyPart, AColors.HotFg, AColors.Bg, [ccaBold]);
      PutGridText(AGrid, X + KeyLen, AY, ' ' + Copy(Item, KeyLen + 1, MaxInt) + ' ',
        AColors.Fg, AColors.Bg);
      Inc(X, Length(Item) + 3);
    end;
end;

function FunctionBarHitTest(ACol, AWidth: Integer;
  const AItems, ALetters: TArray<string>; AMods: TShiftState;
  AThemeLayout: Boolean): TFunctionBarHit;
var
  I, X, KeyLen, Colon, N, Left, Right: Integer;
  Item, KeyPart, LabelPart, Mode: string;
  Mods: TShiftState;
  ToolItems: TArray<string>;
  ToolNums: TArray<Integer>;
begin
  Result.Kind := fbhNone;
  Result.FKeyNum := 0;
  Result.HintKey := '';
  if (AWidth < 4) or (ACol < 0) or (ACol >= AWidth) then
    Exit;

  Mods := AMods * [ssShift, ssAlt, ssCtrl];
  X := 1;

  Mode := '';
  if ssCtrl in Mods then
    Mode := Mode + 'Ctrl+';
  if ssAlt in Mods then
    Mode := Mode + 'Alt+';
  if ssShift in Mods then
    Mode := Mode + 'Shift+';
  if Mode <> '' then
  begin
    Mode := '[' + Copy(Mode, 1, Length(Mode) - 1) + ']';
    Inc(X, Length(Mode) + 1);
  end;

  for I := 0 to High(ALetters) do
  begin
    Item := ALetters[I];
    Colon := Pos(':', Item);
    if Colon <= 0 then
      Continue;
    KeyPart := Copy(Item, 1, Colon - 1);
    LabelPart := Copy(Item, Colon + 1, MaxInt);
    if (KeyPart = '') or (X > AWidth - 4) then
      Continue;
    Left := X;
    if LabelPart <> '' then
      Right := X + Length(KeyPart) + Length(LabelPart) + 1 // key + ':' + label
    else
      Right := X + Length(KeyPart) - 1;
    if (ACol >= Left) and (ACol <= Right) then
    begin
      Result.Kind := fbhHint;
      Result.HintKey := KeyPart;
      Exit;
    end;
    if LabelPart <> '' then
      Inc(X, Length(KeyPart) + Length(LabelPart) + 2)
    else
      Inc(X, Length(KeyPart) + 1);
  end;

  if Length(ALetters) > 0 then
  begin
    if X <= AWidth - 3 then
      Inc(X, 2); // '| '
  end;

  SetLength(ToolItems, 0);
  SetLength(ToolNums, 0);
  for I := 0 to High(AItems) do
  begin
    Item := AItems[I];
    if Item = '' then
      Continue;
    KeyLen := 0;
    while (KeyLen < Length(Item)) and CharInSet(Item[KeyLen + 1], ['0'..'9']) do
      Inc(KeyLen);
    if (KeyLen = 0) or (Length(Item) = KeyLen) then
      Continue;
    N := Length(ToolItems);
    SetLength(ToolItems, N + 1);
    SetLength(ToolNums, N + 1);
    ToolItems[N] := Item;
    ToolNums[N] := StrToIntDef(Copy(Item, 1, KeyLen), 0);
  end;

  for I := 0 to High(ToolItems) do
  begin
    Item := ToolItems[I];
    if X > AWidth - 2 then
      Break;
    Left := X;
    if AThemeLayout then
    begin
      Right := X + Length(Item) - 1;
      Inc(X, Length(Item) + 1);
    end
    else
    begin
      Right := X + Length(Item) + 1; // key + ' ' + label + ' '
      Inc(X, Length(Item) + 3);
    end;
    if Right >= AWidth then
      Right := AWidth - 1;
    if (ACol >= Left) and (ACol <= Right) and (ToolNums[I] > 0) then
    begin
      Result.Kind := fbhFKey;
      Result.FKeyNum := ToolNums[I];
      Exit;
    end;
  end;
end;

function FunctionBarHitToInput(const AHit: TFunctionBarHit; AMods: TShiftState;
  out AKey: Word; out AKeyChar: Char; out AShift: TShiftState): Boolean;
var
  S: string;
  Ch: Char;
  N: Integer;
begin
  Result := False;
  AKey := 0;
  AKeyChar := #0;
  AShift := AMods * [ssShift, ssAlt, ssCtrl];
  case AHit.Kind of
    fbhFKey:
      if (AHit.FKeyNum >= 1) and (AHit.FKeyNum <= 12) then
      begin
        AKey := Word(vkF1 + (AHit.FKeyNum - 1));
        Result := True;
      end;
    fbhHint:
      begin
        S := AHit.HintKey;
        // "Shift+F2"-style hints carry their own modifiers.
        while True do
        begin
          if S.StartsWith('Shift+', True) then
            Include(AShift, ssShift)
          else if S.StartsWith('Ctrl+', True) then
            Include(AShift, ssCtrl)
          else if S.StartsWith('Alt+', True) then
            Include(AShift, ssAlt)
          else
            Break;
          S := Copy(S, Pos('+', S) + 1, MaxInt);
        end;
        if SameText(S, 'Esc') or SameText(S, 'Escape') then
        begin
          AKey := vkEscape;
          Result := True;
        end
        else if SameText(S, 'Enter') or SameText(S, 'Return') then
        begin
          AKey := vkReturn;
          Result := True;
        end
        else if SameText(S, 'Tab') then
        begin
          AKey := vkTab;
          Result := True;
        end
        else if SameText(S, 'BkSp') or SameText(S, 'Backspace') then
        begin
          AKey := vkBack;
          Result := True;
        end
        else if SameText(S, 'Ins') or SameText(S, 'Insert') then
        begin
          AKey := vkInsert;
          Result := True;
        end
        else if SameText(S, 'Del') or SameText(S, 'Delete') then
        begin
          AKey := vkDelete;
          Result := True;
        end
        else if (Length(S) >= 2) and ((S[1] = 'F') or (S[1] = 'f')) then
        begin
          N := StrToIntDef(Copy(S, 2, MaxInt), 0);
          if (N >= 1) and (N <= 12) then
          begin
            AKey := Word(vkF1 + (N - 1));
            Result := True;
          end;
        end
        else if Length(S) = 1 then
        begin
          Ch := UpCase(S[1]);
          AKey := Word(Ord(Ch));
          AKeyChar := Ch;
          Result := True;
        end;
      end;
  else
    ;
  end;
end;

end.
