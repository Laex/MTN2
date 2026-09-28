unit TestDialogTranslatedFit;

{ FitDialogToTranslatedText, the widening after a translation: a label with a
  field right of it pushes that field's column (and so every field in it)
  just past its caption; a line with nothing
  right of it grows in place and moves nothing else; buttons grow to their
  captions, keep their gaps and are centered with their shadow one cell clear
  of the frame; a dialog whose captions fit keeps its width. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogTranslatedFit = class
  public
    [Test] procedure TestLabelPushesItsFields;
    [Test] procedure TestLonelyLineGrowsInPlace;
    [Test] procedure TestGrowthMovesOnlyItsNeighbour;
    [Test] procedure TestFittingDialogKeepsWidth;
    [Test] procedure TestButtonRowPackedAndCentered;
  end;

implementation

uses
  System.SysUtils, uDialogTypes, uDialogLocaleLayout;

function Ctl(AKind: TDialogControlKind; const AId, AText: string;
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

function Dialog(AWidth: Integer; const AControls: TArray<TDialogControl>): TDialogDeclaration;
begin
  Result := Default(TDialogDeclaration);
  Result.Version := '2.0';
  Result.Title := 'T';
  Result.Width := AWidth;
  Result.Height := 10;
  Result.Controls := AControls;
end;

function ById(const D: TDialogDeclaration; const AId: string): TDialogControl;
var
  I: Integer;
begin
  for I := 0 to High(D.Controls) do
    if D.Controls[I].Id = AId then
      Exit(D.Controls[I]);
  raise Exception.Create('no control ' + AId);
end;

procedure TTestDialogTranslatedFit.TestLabelPushesItsFields;
var
  D: TDialogDeclaration;
begin
  D := Dialog(40, [
    Ctl(dckLabel, 'lbl_a', 'A longer caption:', 1, 0, 8),
    Ctl(dckInput, 'a', '', 10, 0, 27),
    Ctl(dckLabel, 'lbl_b', 'Size:', 1, 1, 8),
    Ctl(dckDropDown, 'b', '', 10, 1, 10)]);
  FitDialogToTranslatedText(D);
  Assert.AreEqual(19, ById(D, 'a').Col, 'field moved past the longer caption, gap kept');
  Assert.AreEqual(ById(D, 'a').Col, ById(D, 'b').Col, 'fields of one label column stay aligned');
  Assert.AreEqual(8, ById(D, 'lbl_b').BoxW, 'a label that fits keeps its box');
  Assert.AreEqual(D.Width - 2 - 1, ById(D, 'a').Col + ById(D, 'a').BoxW,
    'a field that reached the edge keeps its one-cell inset');
  Assert.AreEqual(10, ById(D, 'b').BoxW, 'a shorter field keeps its width');
  Assert.AreEqual(40, D.Width, 'the pushed field narrows instead of widening the dialog');
end;

procedure TTestDialogTranslatedFit.TestLonelyLineGrowsInPlace;
var
  D: TDialogDeclaration;
begin
  D := Dialog(40, [
    Ctl(dckLabel, 'hint', StringOfChar('h', 50), 1, 0, 36),
    Ctl(dckLabel, 'lbl_size', 'Size:', 1, 1, 8),
    Ctl(dckDropDown, 'size', '', 10, 1, 10),
    Ctl(dckButton, 'ok', 'OK', 10, 3, 8),
    Ctl(dckButton, 'cancel', 'Cancel', 20, 3, 10)]);
  FitDialogToTranslatedText(D);
  Assert.AreEqual(50, ById(D, 'hint').BoxW, 'the hint grows to its text');
  Assert.AreEqual(1 + 50 + 1 + 2, D.Width, 'dialog: the hint, one clear cell, the frame');
  Assert.AreEqual(10, ById(D, 'size').Col, 'the field does not move for the hint');
  Assert.AreEqual(8, ById(D, 'lbl_size').BoxW, 'nor does its label grow');
  Assert.AreEqual(8, ById(D, 'ok').BoxW, 'buttons keep their width');
  Assert.AreEqual(10, ById(D, 'cancel').BoxW, 'buttons keep their width');
end;

procedure TTestDialogTranslatedFit.TestGrowthMovesOnlyItsNeighbour;
var
  D: TDialogDeclaration;
begin
  D := Dialog(60, [
    Ctl(dckCheckbox, 'keep', 'Keep all timestamps and much more', 1, 0, 25),
    Ctl(dckCheckbox, 'newer', 'Newer', 30, 0, 12),
    Ctl(dckLabel, 'lbl_retry', 'Retries:', 1, 1, 18),
    Ctl(dckDropDown, 'retry', '', 20, 1, 8)]);
  FitDialogToTranslatedText(D);
  Assert.AreEqual(20, ById(D, 'retry').Col, 'a field whose label fits stays');
  Assert.AreEqual(1 + Length('Keep all timestamps and much more') + 4 + 4, ById(D, 'newer').Col,
    'the neighbour of the grown checkbox moves just past it, authored gap kept');
end;

procedure TTestDialogTranslatedFit.TestFittingDialogKeepsWidth;
var
  D, Before: TDialogDeclaration;
  I: Integer;
begin
  D := Dialog(40, [
    Ctl(dckLabel, 'lbl', 'Name:', 1, 0, 8),
    Ctl(dckInput, 'name', '', 10, 0, 27),
    Ctl(dckLabel, 'rule', StringOfChar(#$2500, 38), 0, 1, 38),
    Ctl(dckButton, 'ok', 'OK', 9, 3, 8),
    Ctl(dckButton, 'cancel', 'Cancel', 19, 3, 10)]);
  Before := D;
  Before.Controls := Copy(D.Controls);
  FitDialogToTranslatedText(D);
  Assert.AreEqual(40, D.Width, 'no growth when every caption fits');
  for I := 0 to High(D.Controls) do
    if D.Controls[I].Kind <> dckButton then
    begin
      Assert.AreEqual(Before.Controls[I].Col, D.Controls[I].Col, D.Controls[I].Id + ' col');
      Assert.AreEqual(Before.Controls[I].BoxW, D.Controls[I].BoxW, D.Controls[I].Id + ' width');
    end;
end;

procedure TTestDialogTranslatedFit.TestButtonRowPackedAndCentered;
var
  D: TDialogDeclaration;
  Ok, Mid, Cancel: TDialogControl;
  ClientW: Integer;
begin
  D := Dialog(30, [
    Ctl(dckLabel, 'lbl', 'Question', 1, 0, 20),
    Ctl(dckButton, 'ok', 'A long yes', 1, 2, 6),
    Ctl(dckButton, 'mid', 'Maybe later', 9, 2, 8),
    Ctl(dckButton, 'cancel', 'Cancel', 19, 2, 10)]);
  FitDialogToTranslatedText(D);
  Ok := ById(D, 'ok');
  Mid := ById(D, 'mid');
  Cancel := ById(D, 'cancel');
  ClientW := D.Width - 2;
  Assert.AreEqual(Length('A long yes') + 4, Ok.BoxW, 'button grows to its caption');
  Assert.AreEqual(Length('Maybe later') + 4, Mid.BoxW, 'button grows to its caption');
  Assert.AreEqual(Ok.Col + Ok.BoxW + 2, Mid.Col, 'authored gap kept');
  Assert.AreEqual(Mid.Col + Mid.BoxW + 2, Cancel.Col, 'authored gap kept');
  Assert.IsTrue(Ok.Col >= 1, 'one clear cell left of the row');
  // Cancel.Col + BoxW is its shadow cell.
  Assert.IsTrue(Cancel.Col + Cancel.BoxW + 1 <= ClientW - 1, 'one clear cell after the shadow');
  Assert.IsTrue(Abs(Ok.Col - (ClientW - (Cancel.Col + Cancel.BoxW + 1))) <= 1,
    'row centered with its shadow');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogTranslatedFit);

end.
