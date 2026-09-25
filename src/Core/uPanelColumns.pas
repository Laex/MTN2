unit uPanelColumns;

{ Dual Panel column display modes (FAR-like brief/size/date/full/…).
  Host picks mode per panel; row model already holds full metadata.
  Column-header click sorts via SortPanelRows / HitPanelSortColumn.
  Name/extension keys use numeric (natural) compare so file2 < file10. }

interface

uses
  System.SysUtils, System.Math,
  uDualPanelTypes;

type
  /// <summary>Which optional columns pcmCustom shows — one flag per existing
  /// sortable field, independent of each other (Modified/Created/Accessed
  /// can all be on at once, unlike the single-date-column preset modes).</summary>
  TCustomColumnsConfig = record
    ShowExt: Boolean;
    ShowSize: Boolean;
    ShowModified: Boolean;
    ShowCreated: Boolean;
    ShowAccessed: Boolean;
    ShowType: Boolean;
    ShowAttr: Boolean;
  end;

  /// <summary>One resolved pcmCustom column: header text, cell width, and
  /// the sort key a header click on it should activate.</summary>
  TCustomColumnDef = record
    Title: string;
    Width: Integer;
    SortCol: TPanelSortColumn;
  end;
  TCustomColumnDefs = TArray<TCustomColumnDef>;

function DefaultCustomColumnsConfig: TCustomColumnsConfig;
/// <summary>Ordered list of AConfig's enabled columns (Ext, Size, Modified,
/// Created, Accessed, Type, Attr) — the single source of truth for
/// pcmCustom's width/header/format/hit-test, so they can't drift apart.</summary>
function BuildCustomColumnDefs(const AConfig: TCustomColumnsConfig): TCustomColumnDefs;

var
  /// <summary>Live app-wide "which columns" setting for pcmCustom. One
  /// setting shared by every panel currently in Custom mode (mirrors
  /// Theme/Zoom being global rather than per-panel) — loaded from the
  /// session in uSession.pas, mutated by the Columns... dialog in
  /// uDualPanelWindow.pas.</summary>
  GCustomColumnsConfig: TCustomColumnsConfig;
  /// <summary>Stage 55: leading shell-icon column. App-wide, like Theme/Zoom.
  /// False still leaves uShellIcons loaded; draw/hit-test just skip the
  /// reserve and do not enqueue icon work.</summary>
  GShowPanelIcons: Boolean;

function PanelColumnModeName(AMode: TPanelColumnMode): string;
function NextPanelColumnMode(AMode: TPanelColumnMode): TPanelColumnMode;
function TryPanelColumnModeFromName(const AName: string;
  out AMode: TPanelColumnMode): Boolean;

function PanelSortColumnName(ACol: TPanelSortColumn): string;
/// <summary>Column header shown on screen (translated). Unlike
/// PanelSortColumnName, which is a session.json identifier.</summary>
function PanelColumnTitle(ACol: TPanelSortColumn): string;
/// <summary>Column mode shown in the status line (translated). Unlike
/// PanelColumnModeName, which is a session.json identifier.</summary>
function PanelColumnModeTitle(AMode: TPanelColumnMode): string;
function TryPanelSortColumnFromName(const AName: string;
  out ACol: TPanelSortColumn): Boolean;
/// <summary>FAR panel-corner letter: n name, x extension, w write time,
/// s size, u unsorted, c created, a accessed, t attr, y type. Uppercase
/// means descending.</summary>
function PanelSortModeLetter(ACol: TPanelSortColumn; ADescending: Boolean): Char;
/// <summary>Sort arrow on active header: ▲ up / ▼ down / '' unsorted.</summary>
function PanelSortMark(AActive, ADescending: Boolean): string;
/// <summary>Default direction when switching to a new sort column.</summary>
function DefaultSortDescending(ACol: TPanelSortColumn): Boolean;
/// <summary>Header click: new column → ascending, same column →
/// descending, third click → unsorted.</summary>
procedure CycleHeaderSort(var ACol: TPanelSortColumn; var ADescending: Boolean;
  AClicked: TPanelSortColumn);
/// <summary>Sort menu / keymap: pscNone clears; same column toggles
/// direction; new column uses DefaultSortDescending.</summary>
procedure CycleMenuSort(var ACol: TPanelSortColumn; var ADescending: Boolean;
  ARequested: TPanelSortColumn);

procedure PanelColumnWidths(AMode: TPanelColumnMode; AListWidth: Integer;
  out ANameW, AMetaW: Integer);

procedure PanelColumnHeaders(AMode: TPanelColumnMode;
  out ASizeTitle, ADateTitle, AAttrTitle, AExtTitle, ATypeTitle: string;
  out AShowSize, AShowDate, AShowAttr, AShowExt, AShowType: Boolean);

/// <summary>Width of the leading icon column (cells).</summary>
function PanelIconColumnWidth: Integer;
/// <summary>Icon column + gap before Name.</summary>
function PanelIconReserve: Integer;
/// <summary>Single-cell type glyph for a row (folder / file kind / ..).</summary>
function FormatPanelRowIcon(const ARow: TPanelRow): Char;

/// <summary>Which sort key the click column maps to (False = miss).</summary>
function HitPanelSortColumn(AMode: TPanelColumnMode; AListWidth, ARelCol: Integer;
  out ACol: TPanelSortColumn): Boolean;

procedure SortPanelRows(var ARows: TPanelRows; ACol: TPanelSortColumn;
  ADescending: Boolean);

function FormatPanelRowMeta(AMode: TPanelColumnMode;
  const ARow: TPanelRow; AMetaW: Integer): string;

function FormatPanelRowName(const ARow: TPanelRow; ANameW: Integer;
  AStripExt: Boolean = False): string;

/// <summary>FAR Brief multi-column: how many name columns fit in AListWidth.</summary>
function BriefColumnCount(AListWidth: Integer): Integer;
function BriefCellWidth(AListWidth, AColCount: Integer): Integer;
function BriefPageSize(AViewH, AColCount: Integer): Integer;
function BriefIndexAt(AScroll, ACol, ARow, AViewH: Integer): Integer;
/// <summary>Hit-test in Brief grid; -1 if empty cell / OOB.</summary>
function BriefHitIndex(AScroll, ARelCol, ARelRow, AViewH, ACellW, AColCount,
  ACount: Integer): Integer;
/// <summary>Snap scroll down to a column boundary (multiple of AViewH).</summary>
function AlignBriefScroll(AScroll, AViewH: Integer): Integer;
/// <summary>Columns for mode: Brief uses width; others always 1.</summary>
function PanelListColumnCount(AMode: TPanelColumnMode; AListWidth: Integer): Integer;
/// <summary>Clamp cursor into the list and scroll so it stays in view.
/// Brief (AColCount>1) snaps ScrollOffset to a column boundary.</summary>
procedure EnsurePanelCursorVisible(var ATab: TTab; ARowCount, AViewH: Integer;
  AColCount: Integer = 1);

/// <summary>Left-pads (or truncates) S to AWidth.</summary>
function PadLeft(const S: string; AWidth: Integer): string;
/// <summary>Right-pads (or truncates) S to AWidth.</summary>
function PadRight(const S: string; AWidth: Integer): string;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, uVfsUtils, uStrings;

const
  cSizeW = 8;
  cDateW = 14;
  cAttrW = 5;
  cExtW  = 5;
  cTypeW = 8;
  cIconW = 2;
  cBriefMinColW = 28;

function PanelIconColumnWidth: Integer;
begin
  if not GShowPanelIcons then
    Exit(0);
  Result := cIconW;
end;

function PanelIconReserve: Integer;
begin
  if not GShowPanelIcons then
    Exit(0);
  // Shell icons span cIconW cells, then one blank gap before Name.
  Result := cIconW + 1;
end;

function FormatPanelRowIcon(const ARow: TPanelRow): Char;
begin
  // Single-width glyphs only (emoji / wide arrows break the cell grid).
  if ARow.IsParent then
    Exit('^');
  if ARow.IsDirectory then
  begin
    if ARow.IsLink then
      Exit('~');
    Exit(#$25A0); // ■
  end;
  if ARow.IsLink then
    Exit('@');
  if SameText(ARow.FileType, 'archive') then
    Exit('#');
  if SameText(ARow.FileType, 'executable') then
    Exit('*');
  if SameText(ARow.FileType, 'media') then
    Exit('~');
  Result := #$00B7; // · document / other
end;

function PanelColumnModeName(AMode: TPanelColumnMode): string;
begin
  case AMode of
    pcmBrief:   Result := 'Brief';
    pcmSize:    Result := 'Size';
    pcmDate:    Result := 'Date';
    pcmFull:    Result := 'Full';
    pcmCreated: Result := 'Created';
    pcmTypes:   Result := 'Types';
    pcmCustom:  Result := 'Custom';
  else
    Result := 'Full';
  end;
end;

function NextPanelColumnMode(AMode: TPanelColumnMode): TPanelColumnMode;
begin
  if AMode >= High(TPanelColumnMode) then
    Result := Low(TPanelColumnMode)
  else
    Result := Succ(AMode);
end;

function TryPanelColumnModeFromName(const AName: string;
  out AMode: TPanelColumnMode): Boolean;
var
  M: TPanelColumnMode;
begin
  for M := Low(TPanelColumnMode) to High(TPanelColumnMode) do
    if SameText(PanelColumnModeName(M), Trim(AName)) then
    begin
      AMode := M;
      Exit(True);
    end;
  Result := False;
  AMode := pcmFull;
end;

function PanelSortColumnName(ACol: TPanelSortColumn): string;
begin
  case ACol of
    pscNone:     Result := 'None';
    pscName:     Result := 'Name';
    pscExt:      Result := 'Ext';
    pscSize:     Result := 'Size';
    pscModified: Result := 'Modified';
    pscCreated:  Result := 'Created';
    pscAccessed: Result := 'Accessed';
    pscAttr:     Result := 'Attr';
    pscType:     Result := 'Type';
  else
    Result := 'None';
  end;
end;

function PanelColumnTitle(ACol: TPanelSortColumn): string;
begin
  // Headers are centered in fixed-width columns (Ext/Attr 5, Size/Type 8,
  // dates 14): translations must fit those widths.
  case ACol of
    pscName:     Result := T('col.name', 'Name');
    pscExt:      Result := T('col.ext', 'Ext');
    pscSize:     Result := T('col.size', 'Size');
    pscModified: Result := T('col.modified', 'Modified');
    pscCreated:  Result := T('col.created', 'Created');
    pscAccessed: Result := T('col.accessed', 'Accessed');
    pscAttr:     Result := T('col.attr', 'Attr');
    pscType:     Result := T('col.type', 'Type');
  else
    Result := '';
  end;
end;

function PanelColumnModeTitle(AMode: TPanelColumnMode): string;
begin
  Result := T('colMode.' + PanelColumnModeName(AMode), PanelColumnModeName(AMode));
end;

function TryPanelSortColumnFromName(const AName: string;
  out ACol: TPanelSortColumn): Boolean;
var
  C: TPanelSortColumn;
  N: string;
begin
  N := Trim(AName);
  if N = '' then
  begin
    ACol := pscNone;
    Exit(True);
  end;
  for C := Low(TPanelSortColumn) to High(TPanelSortColumn) do
    if SameText(PanelSortColumnName(C), N) then
    begin
      ACol := C;
      Exit(True);
    end;
  Result := False;
  ACol := pscNone;
end;

function PanelSortModeLetter(ACol: TPanelSortColumn; ADescending: Boolean): Char;
begin
  // Classic FAR file-panel corner glyphs (FarEng: n/x/w/s/u/c/a). Attr/Type
  // are this app's extras and reuse the Sort-by menu mnemonics t/y.
  case ACol of
    pscName:     Result := 'n';
    pscExt:      Result := 'x';
    pscSize:     Result := 's';
    pscModified: Result := 'w';
    pscCreated:  Result := 'c';
    pscAccessed: Result := 'a';
    pscAttr:     Result := 't';
    pscType:     Result := 'y';
  else
    Result := 'u';
  end;
  if ADescending then
    Result := UpCase(Result);
end;

function PanelSortMark(AActive, ADescending: Boolean): string;
begin
  // Three states: unsorted (no glyph), ascending ▲, descending ▼.
  // Same codepoints as panel scrollbar arrows (grid font already draws them).
  if not AActive then
    Exit('');
  if ADescending then
    Result := #$25BC  // ▼
  else
    Result := #$25B2; // ▲
end;

function DefaultSortDescending(ACol: TPanelSortColumn): Boolean;
begin
  Result := ACol in [pscSize, pscModified, pscCreated, pscAccessed];
end;

procedure CycleHeaderSort(var ACol: TPanelSortColumn; var ADescending: Boolean;
  AClicked: TPanelSortColumn);
begin
  if ACol <> AClicked then
  begin
    ACol := AClicked;
    ADescending := False;
  end
  else if not ADescending then
    ADescending := True
  else
  begin
    ACol := pscNone;
    ADescending := False;
  end;
end;

procedure CycleMenuSort(var ACol: TPanelSortColumn; var ADescending: Boolean;
  ARequested: TPanelSortColumn);
begin
  if ARequested = pscNone then
  begin
    ACol := pscNone;
    ADescending := False;
  end
  else if ACol = ARequested then
    ADescending := not ADescending
  else
  begin
    ACol := ARequested;
    ADescending := DefaultSortDescending(ARequested);
  end;
end;

function PadLeft(const S: string; AWidth: Integer): string;
begin
  if Length(S) >= AWidth then
    Result := Copy(S, 1, AWidth)
  else
    Result := StringOfChar(' ', AWidth - Length(S)) + S;
end;

function PadRight(const S: string; AWidth: Integer): string;
begin
  if Length(S) >= AWidth then
    Result := Copy(S, 1, AWidth)
  else
    Result := S + StringOfChar(' ', AWidth - Length(S));
end;

function DefaultCustomColumnsConfig: TCustomColumnsConfig;
begin
  FillChar(Result, SizeOf(Result), 0);
  // Mirrors pcmFull's default shape (Size | Modified | Attr).
  Result.ShowSize := True;
  Result.ShowModified := True;
  Result.ShowAttr := True;
end;

function BuildCustomColumnDefs(const AConfig: TCustomColumnsConfig): TCustomColumnDefs;

  procedure Add(const ATitle: string; AWidth: Integer; ASortCol: TPanelSortColumn);
  var
    N: Integer;
  begin
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Title := ATitle;
    Result[N].Width := AWidth;
    Result[N].SortCol := ASortCol;
  end;

begin
  SetLength(Result, 0);
  if AConfig.ShowExt then Add(PanelColumnTitle(pscExt), cExtW, pscExt);
  if AConfig.ShowSize then Add(PanelColumnTitle(pscSize), cSizeW, pscSize);
  if AConfig.ShowModified then Add(PanelColumnTitle(pscModified), cDateW, pscModified);
  if AConfig.ShowCreated then Add(PanelColumnTitle(pscCreated), cDateW, pscCreated);
  if AConfig.ShowAccessed then Add(PanelColumnTitle(pscAccessed), cDateW, pscAccessed);
  if AConfig.ShowType then Add(PanelColumnTitle(pscType), cTypeW, pscType);
  if AConfig.ShowAttr then Add(PanelColumnTitle(pscAttr), cAttrW, pscAttr);
end;

procedure PanelColumnWidths(AMode: TPanelColumnMode; AListWidth: Integer;
  out ANameW, AMetaW: Integer);
var
  IconRes, I: Integer;
  Defs: TCustomColumnDefs;
begin
  case AMode of
    pcmBrief:
      AMetaW := 0;
    pcmSize:
      AMetaW := cSizeW;
    pcmDate:
      AMetaW := cSizeW + 1 + cDateW;
    pcmFull, pcmCreated:
      AMetaW := cSizeW + 1 + cDateW + 1 + cAttrW;
    pcmTypes:
      AMetaW := cExtW + 1 + cSizeW + 1 + cTypeW + 1 + cAttrW;
    pcmCustom:
      begin
        Defs := BuildCustomColumnDefs(GCustomColumnsConfig);
        AMetaW := 0;
        for I := 0 to High(Defs) do
        begin
          if I > 0 then
            Inc(AMetaW);
          Inc(AMetaW, Defs[I].Width);
        end;
      end;
  else
    AMetaW := cSizeW + 1 + cDateW + 1 + cAttrW;
  end;
  IconRes := PanelIconReserve;
  if AMetaW > 0 then
    ANameW := Max(AListWidth - AMetaW - 1 - IconRes, 4)
  else
    ANameW := Max(AListWidth - IconRes, 4);
end;

procedure PanelColumnHeaders(AMode: TPanelColumnMode;
  out ASizeTitle, ADateTitle, AAttrTitle, AExtTitle, ATypeTitle: string;
  out AShowSize, AShowDate, AShowAttr, AShowExt, AShowType: Boolean);
begin
  ASizeTitle := PanelColumnTitle(pscSize);
  ADateTitle := T('col.date', 'Date');
  AAttrTitle := PanelColumnTitle(pscAttr);
  AExtTitle := PanelColumnTitle(pscExt);
  ATypeTitle := PanelColumnTitle(pscType);
  AShowSize := False;
  AShowDate := False;
  AShowAttr := False;
  AShowExt := False;
  AShowType := False;
  case AMode of
    pcmBrief: ;
    pcmSize:
      AShowSize := True;
    pcmDate:
      begin
        AShowSize := True;
        AShowDate := True;
        ADateTitle := PanelColumnTitle(pscModified);
      end;
    pcmFull:
      begin
        AShowSize := True;
        AShowDate := True;
        AShowAttr := True;
        ADateTitle := PanelColumnTitle(pscModified);
      end;
    pcmCreated:
      begin
        AShowSize := True;
        AShowDate := True;
        AShowAttr := True;
        ADateTitle := PanelColumnTitle(pscCreated);
      end;
    pcmTypes:
      begin
        AShowExt := True;
        AShowSize := True;
        AShowType := True;
        AShowAttr := True;
      end;
  end;
end;

function HitPanelSortColumn(AMode: TPanelColumnMode; AListWidth, ARelCol: Integer;
  out ACol: TPanelSortColumn): Boolean;
var
  NameW, MetaW, X, ColW, IconRes, I: Integer;
  SizeTitle, DateTitle, AttrTitle, ExtTitle, TypeTitle: string;
  ShowSize, ShowDate, ShowAttr, ShowExt, ShowType: Boolean;
  Defs: TCustomColumnDefs;
begin
  Result := False;
  ACol := pscName;
  if (ARelCol < 0) or (AListWidth <= 0) then
    Exit;
  PanelColumnWidths(AMode, AListWidth, NameW, MetaW);
  IconRes := PanelIconReserve;
  // Icon + Name share the name sort key.
  if ARelCol < IconRes + NameW then
  begin
    ACol := pscName;
    Exit(True);
  end;
  X := IconRes + NameW + 1;
  if AMode = pcmCustom then
  begin
    // Dynamic column list — can't reuse the fixed Show* walk below.
    Defs := BuildCustomColumnDefs(GCustomColumnsConfig);
    for I := 0 to High(Defs) do
    begin
      if (ARelCol >= X) and (ARelCol < X + Defs[I].Width) then
      begin
        ACol := Defs[I].SortCol;
        Exit(True);
      end;
      Inc(X, Defs[I].Width + 1);
    end;
    Exit;
  end;
  PanelColumnHeaders(AMode, SizeTitle, DateTitle, AttrTitle, ExtTitle, TypeTitle,
    ShowSize, ShowDate, ShowAttr, ShowExt, ShowType);
  if ShowExt then
  begin
    ColW := cExtW;
    if (ARelCol >= X) and (ARelCol < X + ColW) then
    begin
      ACol := pscExt;
      Exit(True);
    end;
    Inc(X, ColW + 1);
  end;
  if ShowSize then
  begin
    ColW := cSizeW;
    if (ARelCol >= X) and (ARelCol < X + ColW) then
    begin
      ACol := pscSize;
      Exit(True);
    end;
    Inc(X, ColW + 1);
  end;
  if ShowDate then
  begin
    ColW := cDateW;
    if (ARelCol >= X) and (ARelCol < X + ColW) then
    begin
      if AMode = pcmCreated then
        ACol := pscCreated
      else
        ACol := pscModified;
      Exit(True);
    end;
    Inc(X, ColW + 1);
  end;
  if ShowType then
  begin
    ColW := cTypeW;
    if (ARelCol >= X) and (ARelCol < X + ColW) then
    begin
      ACol := pscType;
      Exit(True);
    end;
    Inc(X, ColW + 1);
  end;
  if ShowAttr then
  begin
    ColW := cAttrW;
    if (ARelCol >= X) and (ARelCol < X + ColW) then
    begin
      ACol := pscAttr;
      Exit(True);
    end;
  end;
end;

function RowNameKey(const ARow: TPanelRow): string;
begin
  Result := ARow.Text;
  if (Result <> '') and (Result[Length(Result)] = '/') then
    SetLength(Result, Length(Result) - 1);
end;

function ComparePanelRows(const Left, Right: TPanelRow; ACol: TPanelSortColumn;
  ADescending: Boolean): Integer;
var
  Primary: Integer;

  function CmpInt64(A, B: Int64): Integer;
  begin
    if A < B then
      Result := -1
    else if A > B then
      Result := 1
    else
      Result := 0;
  end;

  function CmpDT(const A, B: TDateTime): Integer;
  begin
    if A < B then
      Result := -1
    else if A > B then
      Result := 1
    else
      Result := 0;
  end;

begin
  if Left.IsParent <> Right.IsParent then
  begin
    if Left.IsParent then
      Exit(-1)
    else
      Exit(1);
  end;
  if Left.IsDirectory <> Right.IsDirectory then
  begin
    if Left.IsDirectory then
      Exit(-1)
    else
      Exit(1);
  end;

  case ACol of
    pscNone, pscName:
      Primary := CompareNaturalText(RowNameKey(Left), RowNameKey(Right));
    pscExt:
      Primary := CompareNaturalText(Left.Extension, Right.Extension);
    pscSize:
      Primary := CmpInt64(Left.Size, Right.Size);
    pscModified:
      begin
        Primary := CmpDT(Left.ModificationTime, Right.ModificationTime);
        if Primary = 0 then
          Primary := CompareText(Left.DateText, Right.DateText);
      end;
    pscCreated:
      begin
        Primary := CmpDT(Left.CreationTime, Right.CreationTime);
        if Primary = 0 then
          Primary := CompareText(Left.CreatedText, Right.CreatedText);
      end;
    pscAccessed:
      begin
        Primary := CmpDT(Left.AccessTime, Right.AccessTime);
        if Primary = 0 then
          Primary := CompareText(Left.AccessedText, Right.AccessedText);
      end;
    pscAttr:
      Primary := CompareText(Left.AttrText, Right.AttrText);
    pscType:
      Primary := CompareText(Left.FileType, Right.FileType);
  else
    Primary := CompareNaturalText(RowNameKey(Left), RowNameKey(Right));
  end;

  if ADescending then
    Primary := -Primary;
  if Primary = 0 then
    Primary := CompareNaturalText(RowNameKey(Left), RowNameKey(Right));
  Result := Primary;
end;

procedure SortPanelRows(var ARows: TPanelRows; ACol: TPanelSortColumn;
  ADescending: Boolean);
begin
  if (ACol = pscNone) or (Length(ARows) < 2) then
    Exit;
  TArray.Sort<TPanelRow>(ARows,
    TComparer<TPanelRow>.Construct(
      function(const Left, Right: TPanelRow): Integer
      begin
        Result := ComparePanelRows(Left, Right, ACol, ADescending);
      end));
end;

// Ext already has its own column — don't repeat it inside Name too. Dirs/
// parent excluded even if Extension were ever wrongly non-empty: Text
// carries a trailing '/' for dirs, so blindly trimming Extension's length
// back out of it would eat into the name, not an extension.
function ShouldStripPanelRowExt(const ARow: TPanelRow; AStripExt: Boolean;
  const AName: string): Boolean;
begin
  Result := AStripExt and not ARow.IsDirectory and not ARow.IsParent and
    (ARow.Extension <> '') and (Length(AName) > Length(ARow.Extension));
end;

function FormatPanelRowName(const ARow: TPanelRow; ANameW: Integer;
  AStripExt: Boolean): string;
begin
  // ASCII only — Unicode arrows (→) break under Consolas/grid glyph path.
  Result := ARow.Text;
  if ShouldStripPanelRowExt(ARow, AStripExt, Result) then
  begin
    Result := Copy(Result, 1, Length(Result) - Length(ARow.Extension));
    // Extension lives in its own column — end-ellipsis only, do not re-parse
    // dots inside the stem as a fake extension.
    if Length(Result) > ANameW then
    begin
      if ANameW < 4 then
        Result := Copy(Result, 1, ANameW)
      else
        Result := Copy(Result, 1, ANameW - 3) + '...';
    end
    else
      Result := PadRight(Result, ANameW);
  end
  else if Length(Result) > ANameW then
    Result := PadRight(EllipsizeKeepingExt(Result, ANameW), ANameW)
  else
    Result := PadRight(Result, ANameW);
end;

// Fixed-width date column: cDateW blanks when there's no date, else the
// date text truncated/padded to width. Shared by pcmDate/pcmFull/pcmCreated
// below, which otherwise repeated this verbatim.
function FormatMetaDateField(const ADateText: string): string;
begin
  if ADateText = '' then
    Result := StringOfChar(' ', cDateW)
  else
    Result := PadRight(Copy(ADateText, 1, cDateW), cDateW);
end;

function FormatPanelRowMeta(AMode: TPanelColumnMode;
  const ARow: TPanelRow; AMetaW: Integer): string;
var
  SizePart, DateSrc, AttrPart, ExtPart, TypePart, FieldText: string;
  Defs: TCustomColumnDefs;
  I: Integer;
begin
  Result := '';
  if AMetaW <= 0 then
    Exit;

  SizePart := PadLeft(ARow.SizeText, cSizeW);
  AttrPart := ARow.AttrText;
  if AttrPart = '' then
    AttrPart := '-----';
  AttrPart := PadRight(Copy(AttrPart, 1, cAttrW), cAttrW);

  ExtPart := ARow.Extension;
  if (ExtPart <> '') and (ExtPart[1] = '.') then
    ExtPart := Copy(ExtPart, 2, MaxInt);
  ExtPart := PadRight(Copy(ExtPart, 1, cExtW), cExtW);

  TypePart := PadRight(Copy(ARow.FileType, 1, cTypeW), cTypeW);

  case AMode of
    pcmBrief:
      Result := '';
    pcmSize:
      Result := SizePart;
    pcmDate:
      Result := SizePart + ' ' + FormatMetaDateField(ARow.DateText);
    pcmFull:
      Result := SizePart + ' ' + FormatMetaDateField(ARow.DateText) + ' ' + AttrPart;
    pcmCreated:
      begin
        DateSrc := ARow.CreatedText;
        if DateSrc = '' then
          DateSrc := ARow.DateText;
        Result := SizePart + ' ' + FormatMetaDateField(DateSrc) + ' ' + AttrPart;
      end;
    pcmTypes:
      Result := ExtPart + ' ' + SizePart + ' ' + TypePart + ' ' + AttrPart;
    pcmCustom:
      begin
        Defs := BuildCustomColumnDefs(GCustomColumnsConfig);
        Result := '';
        for I := 0 to High(Defs) do
        begin
          case Defs[I].SortCol of
            pscExt:      FieldText := ExtPart;
            pscSize:     FieldText := SizePart;
            pscModified: FieldText := PadRight(Copy(ARow.DateText, 1, cDateW), cDateW);
            pscCreated:  FieldText := PadRight(Copy(ARow.CreatedText, 1, cDateW), cDateW);
            pscAccessed: FieldText := PadRight(Copy(ARow.AccessedText, 1, cDateW), cDateW);
            pscType:     FieldText := TypePart;
            pscAttr:     FieldText := AttrPart;
          else
            FieldText := '';
          end;
          if I > 0 then
            Result := Result + ' ';
          Result := Result + FieldText;
        end;
      end;
  end;

  if Length(Result) > AMetaW then
    Result := Copy(Result, 1, AMetaW)
  else if Length(Result) < AMetaW then
    Result := Result + StringOfChar(' ', AMetaW - Length(Result));
end;

function BriefColumnCount(AListWidth: Integer): Integer;
begin
  if AListWidth < cBriefMinColW then
    Exit(1);
  Result := Max(AListWidth div cBriefMinColW, 1);
end;

function BriefCellWidth(AListWidth, AColCount: Integer): Integer;
begin
  if AColCount < 1 then
    AColCount := 1;
  Result := Max(AListWidth div AColCount, 1);
end;

function BriefPageSize(AViewH, AColCount: Integer): Integer;
begin
  if AViewH < 1 then
    AViewH := 1;
  if AColCount < 1 then
    AColCount := 1;
  Result := AViewH * AColCount;
end;

function BriefIndexAt(AScroll, ACol, ARow, AViewH: Integer): Integer;
begin
  if AViewH < 1 then
    AViewH := 1;
  Result := AScroll + ACol * AViewH + ARow;
end;

function BriefHitIndex(AScroll, ARelCol, ARelRow, AViewH, ACellW, AColCount,
  ACount: Integer): Integer;
var
  Col: Integer;
begin
  Result := -1;
  if (ARelRow < 0) or (ARelCol < 0) or (ACount <= 0) then
    Exit;
  if AViewH < 1 then
    AViewH := 1;
  if AColCount < 1 then
    AColCount := 1;
  if ACellW < 1 then
    ACellW := 1;
  if ARelRow >= AViewH then
    Exit;
  Col := ARelCol div ACellW;
  if (Col < 0) or (Col >= AColCount) then
    Exit;
  Result := BriefIndexAt(AScroll, Col, ARelRow, AViewH);
  if (Result < 0) or (Result >= ACount) then
    Result := -1;
end;

function AlignBriefScroll(AScroll, AViewH: Integer): Integer;
begin
  if AViewH < 1 then
    AViewH := 1;
  if AScroll <= 0 then
    Exit(0);
  Result := (AScroll div AViewH) * AViewH;
end;

function PanelListColumnCount(AMode: TPanelColumnMode; AListWidth: Integer): Integer;
begin
  if AMode = pcmBrief then
    Result := BriefColumnCount(AListWidth)
  else
    Result := 1;
end;

procedure EnsurePanelCursorVisible(var ATab: TTab; ARowCount, AViewH: Integer;
  AColCount: Integer);
var
  PageSize, MaxScroll, Need: Integer;
begin
  if ARowCount <= 0 then
  begin
    ATab.CursorIndex := 0;
    ATab.ScrollOffset := 0;
    Exit;
  end;
  ATab.CursorIndex := EnsureRange(ATab.CursorIndex, 0, ARowCount - 1);
  if AViewH < 1 then
    AViewH := 1;
  if AColCount < 1 then
    AColCount := 1;
  PageSize := BriefPageSize(AViewH, AColCount);
  MaxScroll := Max(ARowCount - PageSize, 0);
  if AColCount > 1 then
  begin
    Need := MaxScroll;
    MaxScroll := AlignBriefScroll(MaxScroll, AViewH);
    if MaxScroll < Need then
      Inc(MaxScroll, AViewH);
    ATab.ScrollOffset := AlignBriefScroll(ATab.ScrollOffset, AViewH);
    if ATab.CursorIndex < ATab.ScrollOffset then
      ATab.ScrollOffset := AlignBriefScroll(ATab.CursorIndex, AViewH);
    if ATab.CursorIndex >= ATab.ScrollOffset + PageSize then
    begin
      Need := ATab.CursorIndex - PageSize + 1;
      ATab.ScrollOffset := AlignBriefScroll(Need, AViewH);
      if ATab.CursorIndex >= ATab.ScrollOffset + PageSize then
        Inc(ATab.ScrollOffset, AViewH);
    end;
  end
  else
  begin
    if ATab.CursorIndex < ATab.ScrollOffset then
      ATab.ScrollOffset := ATab.CursorIndex;
    if ATab.CursorIndex >= ATab.ScrollOffset + PageSize then
      ATab.ScrollOffset := ATab.CursorIndex - PageSize + 1;
  end;
  if ATab.ScrollOffset < 0 then
    ATab.ScrollOffset := 0;
  if ATab.ScrollOffset > MaxScroll then
    ATab.ScrollOffset := MaxScroll;
end;

initialization
  GCustomColumnsConfig := DefaultCustomColumnsConfig;
  GShowPanelIcons := True;
end.
