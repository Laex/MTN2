unit TestDialogCaptionFit;

{ FitDialogCaptions / TDialogHost.Open: a caption set after the dialog was
  loaded (Build* naming a button after the operation) grows its control,
  pushes only the controls after it in the same row (a field keeps its right
  edge), widens the dialog only when a row still overflows, and leaves a
  dialog whose captions fit untouched. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogCaptionFit = class
  public
    [Test] procedure TestCopyButton;
    [Test] procedure TestCheckboxPushesField;
    [Test] procedure TestFittingDialogUnchanged;
    [Test] procedure TestNoResourceOverflows;
    [Test] procedure TestConsoleProfileCheckboxesFit;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uDialogTypes, uDialogJson, uDialogResources, uDialogLocaleLayout, uDialogHost, uStrings;

function Ctl(const AKind: TDialogControlKind; const AId, AText: string;
  ACol, ARow, AW: Integer): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := AKind;
  Result.Id := AId;
  Result.Text := AText;
  Result.Col := ACol;
  Result.Row := ARow;
  Result.BoxW := AW;
  Result.BoxH := 1;
end;

function FindControl(const D: TDialogDeclaration; const AId: string): Integer;
begin
  for Result := 0 to High(D.Controls) do
    if SameText(D.Controls[Result].Id, AId) then
      Exit;
  Result := -1;
end;

procedure AssertButtonsApart(const D: TDialogDeclaration);
var
  I, J: Integer;
  A, B: TDialogControl;
begin
  for I := 0 to High(D.Controls) do
    for J := 0 to High(D.Controls) do
    begin
      A := D.Controls[I];
      B := D.Controls[J];
      if (I = J) or (A.Kind <> dckButton) or (B.Kind <> dckButton) or
         (A.Row <> B.Row) or (B.Col < A.Col) then
        Continue;
      // B starts after A's face and its shadow cell.
      Assert.IsTrue(B.Col >= A.Col + A.BoxW + 1,
        Format('%s (col %d, w %d) runs into %s (col %d)', [A.Id, A.Col, A.BoxW, B.Id, B.Col]));
    end;
end;

procedure TTestDialogCaptionFit.TestCopyButton;
var
  D: TDialogDeclaration;
  Host: TDialogHost;
  Ok: Integer;
begin
  // The copy dialog names its OK button after the operation.
  D := BuildCopyMoveDialog('Копирование', 'Копирование «README.md» в:', 'D:\x\');
  Ok := FindControl(D, cDlgCmdOk);
  Assert.IsTrue(Ok >= 0, 'ok button');
  Assert.IsTrue(D.Controls[Ok].BoxW < Length('Копирование') + 4,
    'precondition: the resource box is narrower than the caption');

  Host := TDialogHost.Create(nil);
  try
    Host.Open(D, nil);
    Assert.IsTrue(Host.GetControl(Ok).BoxW >= Length('Копирование') + 4,
      'Open fits the caption: ' + IntToStr(Host.GetControl(Ok).BoxW));
  finally
    Host.Free;
  end;

  FitDialogCaptions(D);
  Assert.IsTrue(D.Controls[Ok].BoxW = Length('Копирование') + 4, 'button is caption + brackets');
  AssertButtonsApart(D);
  Assert.IsTrue(D.Width = 76, 'the row still fits: dialog width unchanged, got ' + IntToStr(D.Width));
end;

procedure TTestDialogCaptionFit.TestCheckboxPushesField;
var
  D: TDialogDeclaration;
begin
  D := Default(TDialogDeclaration);
  D.Version := '2.0';
  D.Width := 76;
  D.Height := 6;
  D.Controls := [
    Ctl(dckCheckbox, 'filter', 'Маска исключения:', 1, 0, 16),
    Ctl(dckInput, 'mask', '', 18, 0, 55),
    Ctl(dckLabel, 'rule', StringOfChar(#$2500, 74), 0, 1, 74),
    Ctl(dckLabel, 'other', 'Label', 1, 2, 10),
    Ctl(dckInput, 'other_in', '', 12, 2, 20)];
  FitDialogCaptions(D);
  Assert.IsTrue(D.Controls[0].BoxW = Length('Маска исключения:') + 4, 'checkbox grows to its caption');
  Assert.IsTrue(D.Controls[1].Col = 1 + D.Controls[0].BoxW + 1, 'field starts one cell after it');
  Assert.IsTrue(D.Controls[1].Col + D.Controls[1].BoxW = 18 + 55, 'field keeps its right edge');
  Assert.IsTrue((D.Controls[3].Col = 1) and (D.Controls[4].Col = 12) and (D.Controls[4].BoxW = 20),
    'other rows keep their columns');
  Assert.IsTrue(D.Width = 76, 'full-width rule does not widen the dialog');
end;

procedure TTestDialogCaptionFit.TestFittingDialogUnchanged;
var
  D, Before: TDialogDeclaration;
  I: Integer;
begin
  D := BuildCopyMoveDialog('Copy', 'Copy "README.md" to:', 'D:\x\');
  Before := D;
  Before.Controls := Copy(D.Controls);
  Assert.IsFalse(DialogCaptionsOverflow(D), 'English copy dialog fits');
  FitDialogCaptions(D);
  Assert.IsTrue(D.Width = Before.Width, 'width unchanged');
  for I := 0 to High(D.Controls) do
    Assert.IsTrue((D.Controls[I].Col = Before.Controls[I].Col) and
      (D.Controls[I].BoxW = Before.Controls[I].BoxW), 'control unchanged: ' + D.Controls[I].Id);
end;

// The English dialogs\*.json must fit their own captions; Open fixes an
// overflow at run time, but the authored layout should not need it.
procedure TTestDialogCaptionFit.TestConsoleProfileCheckboxesFit;
var
  D: TDialogDeclaration;
begin
  SetLocale('ru');
  try
    D := BuildConsoleProfileDialog(['cmd'], 0, False, True);
    Assert.IsFalse(DialogCaptionsOverflow(D), 'the translated checkbox captions fit their boxes');
    Assert.AreEqual('Фоновая консоль', D.Title, 'the title is translated');
  finally
    SetLocale('');
  end;
end;

procedure TTestDialogCaptionFit.TestNoResourceOverflows;
var
  F, Bad: string;
  D: TDialogDeclaration;
  N: Integer;
begin
  Bad := '';
  N := 0;
  // Runner working dir is src\tests\dialogs.
  for F in TDirectory.GetFiles(TPath.GetFullPath('..\..\dialogs'), '*.json',
    TSearchOption.soAllDirectories) do
    if TryParseDialogJson(TFile.ReadAllText(F, TEncoding.UTF8), D) then
    begin
      Inc(N);
      if DialogCaptionsOverflow(D) then
        Bad := Bad + ' ' + TPath.GetFileName(F);
    end;
  Assert.IsTrue(N > 20, 'dialog resources found: ' + IntToStr(N));
  Assert.IsTrue(Bad = '', 'captions overflow their box in:' + Bad);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogCaptionFit);
end.
