unit TestDialogHistory;

{ Dialog input history: the uDialogHistory store (newest first, no
  duplicates, limit, file round trip, corrupt file) and a history input in
  TDialogHost -- ↓ in the last cell, Ctrl+Down / Alt+Down / click on ↓ drop
  the list down, Enter puts the entry into the field, Del forgets it, OK
  records the field and Cancel does not. Uses the real select-mask dialog
  resource. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogHistory = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestStore;
    [Test] procedure TestHost;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils,
  uTerminalTypes, uThemeTypes, uInputLine, uDialogTypes, uDialogJson, uDialogHost,
  uDialogHistory;

const
  W = 100;
  H = 30;

var
  GLastCmd: string;

function FindControlById(const ADecl: TDialogDeclaration; const AId: string): Integer;
begin
  for Result := 0 to High(ADecl.Controls) do
    if ADecl.Controls[Result].Id = AId then
      Exit;
  Result := -1;
end;

function Joined(const A: TArray<string>): string;
begin
  Result := string.Join('|', A);
end;

procedure TestStore(const APath: string);
var
  I: Integer;
begin
  DialogHistoryUseFile(APath);
  Assert.IsTrue(Length(DialogHistoryItems('masks')) = 0, 'empty without a file');
  DialogHistoryAdd('masks', '*.txt');
  DialogHistoryAdd('masks', '*.pas');
  DialogHistoryAdd('masks', '*.TXT');
  Assert.IsTrue(Joined(DialogHistoryItems('masks')) = '*.TXT|*.pas',
    'newest first, case-insensitive duplicate moves up: ' + Joined(DialogHistoryItems('masks')));
  DialogHistoryAdd('masks', '   ');
  Assert.IsTrue(Length(DialogHistoryItems('masks')) = 2, 'blank value ignored');
  Assert.IsTrue(Length(DialogHistoryItems('MASKS')) = 2, 'key is case-insensitive');
  Assert.IsTrue(Length(DialogHistoryItems('other')) = 0, 'keys are separate');
  for I := 1 to cDialogHistoryMax + 5 do
    DialogHistoryAdd('many', 'v' + IntToStr(I));
  Assert.IsTrue(Length(DialogHistoryItems('many')) = cDialogHistoryMax, 'limit per key');
  Assert.IsTrue(DialogHistoryItems('many')[0] = 'v' + IntToStr(cDialogHistoryMax + 5), 'limit drops the oldest');

  DialogHistoryAdd('path', 'C:\Программы\a b');
  DialogHistoryUseFile(APath); // reload from disk
  Assert.IsTrue(Joined(DialogHistoryItems('masks')) = '*.TXT|*.pas', 'file round trip');
  Assert.IsTrue(DialogHistoryItems('path')[0] = 'C:\Программы\a b', 'Cyrillic and backslash survive');

  DialogHistoryRemove('masks', '*.txt');
  Assert.IsTrue(Joined(DialogHistoryItems('masks')) = '*.pas', 'remove (case-insensitive)');

  TFile.WriteAllText(APath, '{ broken', TEncoding.UTF8);
  DialogHistoryUseFile(APath);
  Assert.IsTrue(Length(DialogHistoryItems('masks')) = 0, 'corrupt file -> empty');
end;

function OpenSelectMask(AHost: TDialogHost; const AValue: string): Integer;
var
  Decl: TDialogDeclaration;
begin
  Decl := BuildSelectMaskDialog('Select', 'Mask:', AValue, False);
  AHost.Open(Decl,
    procedure(const AId, AValues: string)
    begin
      GLastCmd := AId;
      AHost.Close;
    end);
  Result := -1;
  for var I := 0 to AHost.ControlCount - 1 do
    if AHost.GetControl(I).Id = 'name' then
      Exit(I);
end;

procedure Key(AHost: TDialogHost; AKey: Word; AShift: TShiftState = [];
  AChar: Char = #0);
begin
  AHost.HandleInput(AKey, AShift, AChar);
end;

procedure TestHost(const APath: string);
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  Idx, X, Y: Integer;
  R: TRectI;
  Json: string;
  Decl: TDialogDeclaration;
begin
  if TFile.Exists(APath) then
    TFile.Delete(APath);
  DialogHistoryUseFile(APath);
  DialogHistoryAdd('masks', '*.log');
  DialogHistoryAdd('masks', '*.pas');

  SetLength(Grid, H);
  for Y := 0 to H - 1 do
  begin
    SetLength(Grid[Y], W);
    for X := 0 to W - 1 do
      Grid[Y][X] := TCharCell.Make(' ', TAlphaColor($FFAAAAAA), TAlphaColor($FF000000));
  end;

  Host := TDialogHost.Create(nil);
  try
    Idx := OpenSelectMask(Host, '*.*');
    Assert.IsTrue(Idx >= 0, 'select-mask dialog has the name field');
    Assert.IsTrue(Host.GetControl(Idx).History = 'masks', 'name field carries the masks history key');
    Assert.IsTrue(Joined(Host.GetControl(Idx).Items) = '*.pas|*.log', 'history loaded on Open');

    Host.Draw(Grid, W, H);
    R := Host.ControlBoundsAt(Idx);
    Assert.IsTrue(Grid[R.Top][R.Left + R.Width - 1].CharValue = WideChar($2193),
      'arrow in the last cell of the field');

    // Ctrl+Down drops the list down on the newest entry; Down + Enter picks.
    Key(Host, vkDown, [ssCtrl]);
    Key(Host, vkDown);
    Key(Host, vkReturn);
    Assert.IsTrue(Host.Visible, 'Enter in the open list does not close the dialog');
    Assert.IsTrue(Host.GetInputValue('name') = '*.log', 'Enter puts the entry into the field: ' +
      Host.GetInputValue('name'));

    // Alt+Down works too; Esc closes only the list.
    Key(Host, vkDown, [ssAlt]);
    Key(Host, vkEscape);
    Assert.IsTrue(Host.Visible and (Host.GetInputValue('name') = '*.log'),
      'Esc closes the list, keeps the dialog and the text');

    // Click on the arrow opens; Del forgets the highlighted entry.
    Host.Draw(Grid, W, H);
    Host.HandleClick(R.Left + R.Width - 1, R.Top);
    Key(Host, vkDelete);
    Assert.IsTrue(Joined(DialogHistoryItems('masks')) = '*.pas',
      'Del removes the highlighted (current) entry from the store: ' + Joined(DialogHistoryItems('masks')));
    Key(Host, vkEscape);

    // Typing still edits the field; OK records it on top.
    Host.SetInputValue('name', '*.dpr');
    Key(Host, vkReturn);
    Assert.IsTrue(not Host.Visible and (GLastCmd = 'ok'), 'Enter in the field accepts');
    Assert.IsTrue(Joined(DialogHistoryItems('masks')) = '*.dpr|*.pas', 'OK records the field on top');

    // Cancel records nothing.
    OpenSelectMask(Host, '*.zzz');
    Key(Host, vkEscape);
    Assert.IsTrue(not Host.Visible, 'Esc cancels the dialog');
    Assert.IsTrue(Joined(DialogHistoryItems('masks')) = '*.dpr|*.pas', 'Cancel records nothing');

    // Ctrl+Down with no history does nothing harmful.
    if TFile.Exists(APath) then
      TFile.Delete(APath);
    DialogHistoryUseFile(APath);
    OpenSelectMask(Host, 'x');
    Key(Host, vkDown, [ssCtrl]);
    Key(Host, vkReturn);
    Assert.IsTrue(not Host.Visible and (GLastCmd = 'ok'),
      'empty history: Ctrl+Down opens nothing, Enter still accepts');
  finally
    Host.Free;
  end;

  // The key survives the JSON round trip (dialogs opened via OpenJson).
  Decl := BuildSelectMaskDialog('Select', 'Mask:', '*.*', False);
  Json := DeclarationToJson(Decl);
  Assert.IsTrue(Pos('"history":"masks"', Json) > 0, 'DeclarationToJson writes history');
  Assert.IsTrue(TryParseDialogJson(Json, Decl) and
    (Decl.Controls[FindControlById(Decl, 'name')].History = 'masks'), 'and parses it back');
end;

var
  Path: string;

{ TTestDialogHistory }

procedure TTestDialogHistory.SetupFixture;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-dialoghistory-test.json');
  if TFile.Exists(Path) then
    TFile.Delete(Path);
end;

procedure TTestDialogHistory.TearDownFixture;
begin
  if TFile.Exists(Path) then
    TFile.Delete(Path);
end;

procedure TTestDialogHistory.TestStore;
begin
  TestDialogHistory.TestStore(Path);
end;

procedure TTestDialogHistory.TestHost;
begin
  TestDialogHistory.TestHost(Path);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogHistory);

end.
