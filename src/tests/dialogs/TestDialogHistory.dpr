program TestDialogHistory;

{$APPTYPE CONSOLE}
{$R '..\..\MTN2.dres'}

{ Dialog input history: the uDialogHistory store (newest first, no
  duplicates, limit, file round trip, corrupt file) and a history input in
  TDialogHost -- ↓ in the last cell, Ctrl+Down / Alt+Down / click on ↓ drop
  the list down, Enter puts the entry into the field, Del forgets it, OK
  records the field and Cancel does not. Uses the real select-mask dialog
  resource. }

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils,
  uTerminalTypes, uThemeTypes, uInputLine, uDialogTypes, uDialogJson, uDialogHost,
  uDialogHistory;

const
  W = 100;
  H = 30;

var
  Failed: Integer;
  GLastCmd: string;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

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
  Writeln('Store');
  DialogHistoryUseFile(APath);
  Expect(Length(DialogHistoryItems('masks')) = 0, 'empty without a file');
  DialogHistoryAdd('masks', '*.txt');
  DialogHistoryAdd('masks', '*.pas');
  DialogHistoryAdd('masks', '*.TXT');
  Expect(Joined(DialogHistoryItems('masks')) = '*.TXT|*.pas',
    'newest first, case-insensitive duplicate moves up: ' + Joined(DialogHistoryItems('masks')));
  DialogHistoryAdd('masks', '   ');
  Expect(Length(DialogHistoryItems('masks')) = 2, 'blank value ignored');
  Expect(Length(DialogHistoryItems('MASKS')) = 2, 'key is case-insensitive');
  Expect(Length(DialogHistoryItems('other')) = 0, 'keys are separate');
  for I := 1 to cDialogHistoryMax + 5 do
    DialogHistoryAdd('many', 'v' + IntToStr(I));
  Expect(Length(DialogHistoryItems('many')) = cDialogHistoryMax, 'limit per key');
  Expect(DialogHistoryItems('many')[0] = 'v' + IntToStr(cDialogHistoryMax + 5), 'limit drops the oldest');

  DialogHistoryAdd('path', 'C:\Программы\a b');
  DialogHistoryUseFile(APath); // reload from disk
  Expect(Joined(DialogHistoryItems('masks')) = '*.TXT|*.pas', 'file round trip');
  Expect(DialogHistoryItems('path')[0] = 'C:\Программы\a b', 'Cyrillic and backslash survive');

  DialogHistoryRemove('masks', '*.txt');
  Expect(Joined(DialogHistoryItems('masks')) = '*.pas', 'remove (case-insensitive)');

  TFile.WriteAllText(APath, '{ broken', TEncoding.UTF8);
  DialogHistoryUseFile(APath);
  Expect(Length(DialogHistoryItems('masks')) = 0, 'corrupt file -> empty');
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
  Writeln('Dialog host');
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
    Expect(Idx >= 0, 'select-mask dialog has the name field');
    Expect(Host.GetControl(Idx).History = 'masks', 'name field carries the masks history key');
    Expect(Joined(Host.GetControl(Idx).Items) = '*.pas|*.log', 'history loaded on Open');

    Host.Draw(Grid, W, H);
    R := Host.ControlBoundsAt(Idx);
    Expect(Grid[R.Top][R.Left + R.Width - 1].CharValue = WideChar($2193),
      'arrow in the last cell of the field');

    // Ctrl+Down drops the list down on the newest entry; Down + Enter picks.
    Key(Host, vkDown, [ssCtrl]);
    Key(Host, vkDown);
    Key(Host, vkReturn);
    Expect(Host.Visible, 'Enter in the open list does not close the dialog');
    Expect(Host.GetInputValue('name') = '*.log', 'Enter puts the entry into the field: ' +
      Host.GetInputValue('name'));

    // Alt+Down works too; Esc closes only the list.
    Key(Host, vkDown, [ssAlt]);
    Key(Host, vkEscape);
    Expect(Host.Visible and (Host.GetInputValue('name') = '*.log'),
      'Esc closes the list, keeps the dialog and the text');

    // Click on the arrow opens; Del forgets the highlighted entry.
    Host.Draw(Grid, W, H);
    Host.HandleClick(R.Left + R.Width - 1, R.Top);
    Key(Host, vkDelete);
    Expect(Joined(DialogHistoryItems('masks')) = '*.pas',
      'Del removes the highlighted (current) entry from the store: ' + Joined(DialogHistoryItems('masks')));
    Key(Host, vkEscape);

    // Typing still edits the field; OK records it on top.
    Host.SetInputValue('name', '*.dpr');
    Key(Host, vkReturn);
    Expect(not Host.Visible and (GLastCmd = 'ok'), 'Enter in the field accepts');
    Expect(Joined(DialogHistoryItems('masks')) = '*.dpr|*.pas', 'OK records the field on top');

    // Cancel records nothing.
    OpenSelectMask(Host, '*.zzz');
    Key(Host, vkEscape);
    Expect(not Host.Visible, 'Esc cancels the dialog');
    Expect(Joined(DialogHistoryItems('masks')) = '*.dpr|*.pas', 'Cancel records nothing');

    // Ctrl+Down with no history does nothing harmful.
    if TFile.Exists(APath) then
      TFile.Delete(APath);
    DialogHistoryUseFile(APath);
    OpenSelectMask(Host, 'x');
    Key(Host, vkDown, [ssCtrl]);
    Key(Host, vkReturn);
    Expect(not Host.Visible and (GLastCmd = 'ok'),
      'empty history: Ctrl+Down opens nothing, Enter still accepts');
  finally
    Host.Free;
  end;

  // The key survives the JSON round trip (dialogs opened via OpenJson).
  Decl := BuildSelectMaskDialog('Select', 'Mask:', '*.*', False);
  Json := DeclarationToJson(Decl);
  Expect(Pos('"history":"masks"', Json) > 0, 'DeclarationToJson writes history');
  Expect(TryParseDialogJson(Json, Decl) and
    (Decl.Controls[FindControlById(Decl, 'name')].History = 'masks'), 'and parses it back');
end;

var
  Path: string;
begin
  Failed := 0;
  try
    Path := TPath.Combine(TPath.GetTempPath, 'mtn2-dialoghistory-test.json');
    if TFile.Exists(Path) then
      TFile.Delete(Path);
    TestStore(Path);
    TestHost(Path);
    if TFile.Exists(Path) then
      TFile.Delete(Path);
    if Failed = 0 then
      Writeln('All DialogHistory tests PASSED')
    else
    begin
      Writeln('FAILED: ', Failed, ' check(s)');
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
