unit TestDialogAlignment;

{ Every built-in dialog (each DIALOG_* resource), laid out as the program
  shows it - translated and with captions fitted - in English and Russian:
  - no two controls overlap, and every control stays inside the frame;
  - captions are not cut: a label's text, a checkbox / radio / button caption
    with its brackets fit the box;
  - a label and the field right of it have at least one blank cell between
    the text and the field;
  - rows whose label starts in the same column put their fields in the same
    column too. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogAlignment = class
  public
    [Test] procedure TestEnglish;
    [Test] procedure TestRussian;
    [Test] procedure TestGerman;
  end;

/// <summary>Names of the DIALOG_* resources linked into the test runner.</summary>
function DialogResourceNames: TArray<string>;

implementation

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  uTerminalTypes, uThemeTypes, uStrings, uDialogTypes, uDialogResources, uDialogRenderer,
  uDialogHost;

var
  GNames: TStringList;

function CollectName(hModule: HMODULE; lpType, lpName: PChar;
  lParam: LONG_PTR): BOOL; stdcall;
var
  Name: string;
begin
  if NativeUInt(lpName) > $FFFF then
  begin
    Name := lpName;
    if Name.StartsWith('DIALOG_', True) then
      GNames.Add(UpperCase(Name));
  end;
  Result := True;
end;

function DialogResourceNames: TArray<string>;
begin
  GNames := TStringList.Create;
  try
    GNames.Sorted := True;
    GNames.Duplicates := dupIgnore;
    EnumResourceNames(HInstance, RT_RCDATA, @CollectName, 0);
    Result := GNames.ToStringArray;
  finally
    FreeAndNil(GNames);
  end;
end;

function IsRule(const C: TDialogControl): Boolean;
var
  I: Integer;
begin
  Result := (C.Kind = dckLabel) and (C.Text <> '');
  for I := 1 to Length(C.Text) do
    if not CharInSet(C.Text[I], ['-', '=', '_']) and (Ord(C.Text[I]) <> $2500) and
       (Ord(C.Text[I]) <> $2550) then
      Exit(False);
end;

function IsField(const C: TDialogControl): Boolean;
begin
  Result := C.Kind in [dckInput, dckDropDown, dckList, dckRadioGroup];
end;

function Caption(const C: TDialogControl): string;
begin
  Result := StripHotKeyMarker(C.Text);
end;

procedure CheckDeclaration(const AName: string; const ADecl: TDialogDeclaration;
  AReport: TStrings);
type
  TBox = record
    L, T, R, B: Integer;
  end;
var
  Host: TDialogHost;
  Ctl: TArray<TDialogControl>;
  Box: TArray<TBox>;
  I, J, N, ClientW, ClientH, Need: Integer;
  LabelCol, FieldCol: TArray<Integer>;
  LabelText: TArray<string>;
  Lines: TArray<string>;
  Grid: TTerminalGrid;

  procedure Problem(const AText: string);
  begin
    AReport.Add(AName + ': ' + AText);
  end;

  function Named(AIndex: Integer): string;
  begin
    if Ctl[AIndex].Id <> '' then
      Result := Ctl[AIndex].Id
    else
      Result := '"' + Caption(Ctl[AIndex]) + '"';
  end;

begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(ADecl, nil);
    N := Host.ControlCount;
    SetLength(Ctl, N);
    SetLength(Box, N);
    for I := 0 to N - 1 do
    begin
      Ctl[I] := Host.GetControl(I);
      Box[I].L := Max(Ctl[I].Col, 0);
      Box[I].T := Max(Ctl[I].Row, 0);
      Box[I].R := Box[I].L + Max(Ctl[I].BoxW, 1) - 1;
      Box[I].B := Box[I].T + Max(Ctl[I].BoxH, 1) - 1;
    end;
    // Drawn on a screen large enough that the frame is not clamped.
    AllocTerminalGrid(Grid, 200, 80);
    Host.Draw(Grid, 200, 80);
    ClientW := Host.Bounds.Width - 2;
    ClientH := Host.Bounds.Height - 2;
  finally
    Host.Free;
  end;

  for I := 0 to N - 1 do
  begin
    if (Box[I].R > ClientW - 1) or (Box[I].B > ClientH - 1) then
      Problem(Format('%s outside the frame (%d..%d, row %d; client %dx%d)',
        [Named(I), Box[I].L, Box[I].R, Box[I].T, ClientW, ClientH]));
    for J := I + 1 to N - 1 do
      if (Box[I].L <= Box[J].R) and (Box[J].L <= Box[I].R) and
         (Box[I].T <= Box[J].B) and (Box[J].T <= Box[I].B) then
        Problem(Format('%s overlaps %s', [Named(I), Named(J)]));
    case Ctl[I].Kind of
      dckButton, dckCheckbox, dckRadio:
        begin
          Need := Length(Caption(Ctl[I])) + 4;
          if Need > Box[I].R - Box[I].L + 1 then
            Problem(Format('%s caption cut (%d > %d)', [Named(I), Need, Box[I].R - Box[I].L + 1]));
        end;
      dckLabel:
        if not IsRule(Ctl[I]) and (Ctl[I].Text <> '') then
        begin
          Lines := TDialogRenderer.WrapLabelLines(Ctl[I].Text, Box[I].R - Box[I].L + 1);
          if Length(Lines) > Box[I].B - Box[I].T + 1 then
            Problem(Format('%s text cut (%d lines in %d)',
              [Named(I), Length(Lines), Box[I].B - Box[I].T + 1]));
        end;
    end;
  end;

  // Label -> field pairs: the label is the leftmost control of its row and
  // the field is the next control right of it.
  SetLength(LabelCol, 0);
  SetLength(FieldCol, 0);
  SetLength(LabelText, 0);
  for I := 0 to N - 1 do
  begin
    if (Ctl[I].Kind <> dckLabel) or IsRule(Ctl[I]) or (Ctl[I].Text = '') then
      Continue;
    Need := -1; // nearest control right of the label in its row
    for J := 0 to N - 1 do
      if (J <> I) and (Box[J].T = Box[I].T) and (Box[J].L > Box[I].L) and
         ((Need < 0) or (Box[J].L < Box[Need].L)) then
        Need := J;
    if (Need < 0) or not IsField(Ctl[Need]) then
      Continue;
    if Box[I].L + Length(Caption(Ctl[I])) >= Box[Need].L then
      Problem(Format('%s runs into %s', [Named(I), Named(Need)]));
    // Only rows the label starts.
    J := 0;
    while (J < N) and not ((Box[J].T = Box[I].T) and (Box[J].L < Box[I].L)) do
      Inc(J);
    if J < N then
      Continue;
    LabelCol := LabelCol + [Box[I].L];
    FieldCol := FieldCol + [Box[Need].L];
    LabelText := LabelText + [Named(I)];
  end;
  for I := 0 to High(LabelCol) do
    for J := I + 1 to High(LabelCol) do
      if (LabelCol[I] = LabelCol[J]) and (FieldCol[I] <> FieldCol[J]) then
        Problem(Format('fields of %s and %s start in columns %d and %d',
          [LabelText[I], LabelText[J], FieldCol[I], FieldCol[J]]));
end;

procedure CheckAll(const ALocale: string);
var
  Name: string;
  Decl: TDialogDeclaration;
  Report: TStringList;
begin
  Report := TStringList.Create;
  try
    SetLocale(ALocale);
    try
      for Name in DialogResourceNames do
        if TryLoadDialogResource(Name, Decl) then
          CheckDeclaration(Name, Decl, Report)
        else
          Report.Add(Name + ': not loaded');
      CheckDeclaration('console profile',
        BuildConsoleProfileDialog(['Command Prompt', 'PowerShell'], 0, False), Report);
    finally
      SetLocale('');
    end;
    Assert.IsTrue(Report.Count = 0, sLineBreak + Report.Text);
  finally
    Report.Free;
  end;
end;

procedure TTestDialogAlignment.TestEnglish;
begin
  CheckAll('');
end;

procedure TTestDialogAlignment.TestRussian;
begin
  CheckAll('ru');
end;

procedure TTestDialogAlignment.TestGerman;
begin
  CheckAll('de');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogAlignment);

end.
