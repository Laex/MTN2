unit TestDialogButtonLayout;

{ Every built-in dialog (each DIALOG_* resource), laid out as the program
  shows it - translated and with captions fitted - in English and Russian.
  Also the dialogs code builds on top of a resource (the background-console
  profile picker, a one-button update message). The content starts on the
  row right under the title bar. The bottom button row keeps:
  - at least one empty cell between the frame and the leftmost face, and
    between the rightmost face's shadow and the frame;
  - exactly one empty row above it (a separator rule, if any, sits above
    that empty row);
  - below it the shadow row, then the frame.
  A block of two button rows (a shadow row apart) has an empty row above the
  block and the same space below it. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogButtonLayout = class
  public
    [Test] procedure TestEnglish;
    [Test] procedure TestRussian;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, Winapi.Windows,
  uTerminalTypes, uThemeTypes, uStrings, uDialogTypes, uDialogResources, uDialogHost;

const
  cAreaW = 120;
  cAreaH = 50;

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

// '' when the dialog follows the rules, else what is wrong with it.
function CheckDeclaration(const AName: string; const ADecl: TDialogDeclaration): string;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  Frame, R: TRectI;
  I, Top, Left, Right, BlockTop: Integer;
  RuleAbove: Boolean;
  Problems: TStringList;

  function RuleAt(ARow: Integer): Boolean;
  var
    J: Integer;
    B: TRectI;
  begin
    Result := False;
    for J := 0 to Host.ControlCount - 1 do
    begin
      B := Host.ControlBoundsAt(J);
      if (B.Top = ARow) and (Host.GetControl(J).Kind = dckLabel) and
         IsHRuleText(Host.GetControl(J).Text) then
        Exit(True);
    end;
  end;

  function RowUsed(ARow: Integer): Boolean;
  var
    J: Integer;
    B: TRectI;
  begin
    Result := False;
    for J := 0 to Host.ControlCount - 1 do
    begin
      B := Host.ControlBoundsAt(J);
      if (Host.GetControl(J).Kind = dckButton) and (B.Top >= BlockTop) then
        Continue;
      if (B.Top <= ARow) and (B.Bottom >= ARow) then
        Exit(True);
    end;
  end;

begin
  Result := '';
  Problems := TStringList.Create;
  Host := TDialogHost.Create(nil);
  try
    Host.Open(ADecl, nil);
    AllocTerminalGrid(Grid, cAreaW, cAreaH);
    Host.Draw(Grid, cAreaW, cAreaH);
    Frame := Host.Bounds;

    Top := -1;
    for I := 0 to Host.ControlCount - 1 do
      if Host.GetControl(I).Kind = dckButton then
        Top := Max(Top, Host.ControlBoundsAt(I).Top);
    if Top < 0 then
      Exit; // no buttons

    BlockTop := Top;
    for I := 0 to Host.ControlCount - 1 do
      if (Host.GetControl(I).Kind = dckButton) and
         (Host.ControlBoundsAt(I).Top = Top - 2) then
        BlockTop := Top - 2;
    RuleAbove := (not RowUsed(BlockTop - 1)) and RuleAt(BlockTop - 2);

    Left := MaxInt;
    Right := -1;
    for I := 0 to Host.ControlCount - 1 do
      if Host.GetControl(I).Kind = dckButton then
      begin
        R := Host.ControlBoundsAt(I);
        if R.Top <> Top then
          Continue;
        Left := Min(Left, R.Left);
        Right := Max(Right, R.Right);
      end;

    if Left - Frame.Left - 1 < 1 then
      Problems.Add(Format('left gap %d', [Left - Frame.Left - 1]));
    // Right + 1 is the shadow cell.
    if Frame.Right - (Right + 1) - 1 < 1 then
      Problems.Add(Format('right gap after the shadow %d', [Frame.Right - (Right + 1) - 1]));
    if Top <> Frame.Bottom - 2 then
      Problems.Add(Format('buttons %d rows above the frame (want 2: shadow, frame)',
        [Frame.Bottom - Top]));
    if RowUsed(BlockTop - 1) then
      Problems.Add('no empty row above the buttons')
    else if (not RuleAbove) and (BlockTop - 2 > Frame.Top) and
      not RowUsed(BlockTop - 2) then
      Problems.Add('more than one empty row above the buttons');
    if not RowUsed(Frame.Top + 1) then
      Problems.Add('empty row under the title');
    if RowUsed(Top + 1) then
      Problems.Add('controls on the shadow row');
    if Problems.Count > 0 then
      Result := AName + ': ' + String.Join(', ', Problems.ToStringArray);
  finally
    Host.Free;
    Problems.Free;
  end;
end;

function CheckDialog(const AName: string): string;
var
  Decl: TDialogDeclaration;
begin
  if not TryLoadDialogResource(AName, Decl) then
    Exit(AName + ': not loaded');
  Result := CheckDeclaration(AName, Decl);
end;

procedure CheckAll(const ALocale: string);
var
  Name: string;
  Report: TStringList;
  Names: TArray<string>;

  procedure Add(const AProblem: string);
  begin
    if AProblem <> '' then
      Report.Add(AProblem);
  end;

begin
  Names := DialogResourceNames;
  Assert.IsTrue(Length(Names) > 40, 'dialog resources found: ' + IntToStr(Length(Names)));
  Report := TStringList.Create;
  try
    SetLocale(ALocale);
    try
      for Name in Names do
        Add(CheckDialog(Name));
      Add(CheckDeclaration('console profile',
        BuildConsoleProfileDialog(['Command Prompt', 'PowerShell'], 0, False)));
      Add(CheckDeclaration('update message, one button',
        BuildUpdateMessageDialog('Message', 'Details', '', False)));
    finally
      SetLocale('');
    end;
    Assert.IsTrue(Report.Count = 0, sLineBreak + Report.Text);
  finally
    Report.Free;
  end;
end;

procedure TTestDialogButtonLayout.TestEnglish;
begin
  CheckAll('');
end;

procedure TTestDialogButtonLayout.TestRussian;
begin
  CheckAll('ru');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogButtonLayout);

end.
