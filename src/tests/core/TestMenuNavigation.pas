unit TestMenuNavigation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMenuNavigation = class
  public
    [Test] procedure StepSkipsRowsThatCannotHoldTheCursor;
    [Test] procedure StepStopsAtTheEndsWithoutWrapping;
    [Test] procedure EdgeKeysLandOnSelectableRows;
    [Test] procedure PageKeysMoveByPageRows;
    [Test] procedure OtherKeysAreNotNavigation;
  end;

implementation

uses
  System.UITypes,
  uMenuNavigation;

// Rows 0 and 3 are separators; 1, 2, 4 and 5 can hold the cursor.
function NotSeparator(AIndex: Integer): Boolean;
begin
  Result := (AIndex <> 0) and (AIndex <> 3);
end;

procedure TTestMenuNavigation.StepSkipsRowsThatCannotHoldTheCursor;
begin
  Assert.AreEqual(4, MenuStepIndex(2, 6, 1, NotSeparator), 'down passes the separator');
  Assert.AreEqual(2, MenuStepIndex(4, 6, -1, NotSeparator), 'up passes the separator');
  Assert.AreEqual(3, MenuStepIndex(2, 6, 1, nil), 'without a predicate every row counts');
end;

procedure TTestMenuNavigation.StepStopsAtTheEndsWithoutWrapping;
begin
  Assert.AreEqual(5, MenuStepIndex(5, 6, 1, NotSeparator), 'last row stays');
  Assert.AreEqual(1, MenuStepIndex(1, 6, -1, NotSeparator), 'first selectable row stays');
  Assert.AreEqual(5, MenuStepIndex(4, 6, 10, NotSeparator), 'a long step ends at the last selectable row');
  Assert.AreEqual(0, MenuStepIndex(3, 0, 1, nil), 'an empty list gives row 0');
end;

procedure TTestMenuNavigation.EdgeKeysLandOnSelectableRows;
var
  I: Integer;
begin
  I := 4;
  Assert.IsTrue(MenuNavigateKey(vkHome, I, 6, 3, NotSeparator));
  Assert.AreEqual(1, I, 'Home skips the leading separator');
  Assert.IsTrue(MenuNavigateKey(vkEnd, I, 6, 3, NotSeparator));
  Assert.AreEqual(5, I, 'End goes to the last row');
  I := 2;
  Assert.IsTrue(MenuNavigateKey(vkEnd, I, 4, 3, function(AIndex: Integer): Boolean
    begin Result := AIndex < 2; end));
  Assert.AreEqual(1, I, 'End skips trailing rows that cannot hold the cursor');
  I := 7;
  Assert.IsTrue(MenuNavigateKey(vkHome, I, 3, 3, function(AIndex: Integer): Boolean
    begin Result := False; end));
  Assert.AreEqual(7, I, 'no selectable row leaves the index alone');
end;

procedure TTestMenuNavigation.PageKeysMoveByPageRows;
var
  I: Integer;
begin
  I := 1;
  Assert.IsTrue(MenuNavigateKey(vkNext, I, 6, 2, NotSeparator));
  Assert.AreEqual(4, I, 'PgDn moves two selectable rows');
  Assert.IsTrue(MenuNavigateKey(vkPrior, I, 6, 2, NotSeparator));
  Assert.AreEqual(1, I, 'PgUp moves back two selectable rows');
  Assert.IsTrue(MenuNavigateKey(vkNext, I, 6, 0, NotSeparator));
  Assert.AreEqual(2, I, 'a page is at least one row');
end;

procedure TTestMenuNavigation.OtherKeysAreNotNavigation;
var
  I: Integer;
begin
  I := 2;
  Assert.IsFalse(MenuNavigateKey(vkReturn, I, 6, 3, NotSeparator));
  Assert.IsFalse(MenuNavigateKey(Ord('A'), I, 6, 3, NotSeparator));
  Assert.AreEqual(2, I, 'the index is untouched');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMenuNavigation);

end.
