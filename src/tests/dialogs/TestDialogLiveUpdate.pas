unit TestDialogLiveUpdate;

{ Live-dialog update JSON: labels, lists and accents the panel window applies. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogLiveUpdate = class
  public
    [Test] procedure EmptyOrNonObjectIsNotAnUpdate;
    [Test] procedure LabelTextAndListSelectionAreKept;
    [Test] procedure AListWithoutItemsIsSkipped;
    [Test] procedure AnAccentNeedsThreeNumbers;
  end;

implementation

uses
  System.SysUtils, uDialogLiveUpdate;

procedure TTestDialogLiveUpdate.EmptyOrNonObjectIsNotAnUpdate;
var
  Update: TDialogLiveUpdate;
begin
  Assert.IsFalse(TryParseDialogLiveUpdate('', Update));
  Assert.IsFalse(TryParseDialogLiveUpdate('not json', Update));
  Assert.IsFalse(TryParseDialogLiveUpdate('[1]', Update));
end;

procedure TTestDialogLiveUpdate.LabelTextAndListSelectionAreKept;
var
  Update: TDialogLiveUpdate;
begin
  Assert.IsTrue(TryParseDialogLiveUpdate(
    '{"labels":{"hint":"Ready","n":1},"lists":{"files":{"items":["a","b"],"selected":1}}}',
    Update));
  Assert.AreEqual<Integer>(2, Length(Update.Labels));
  Assert.AreEqual('hint', Update.Labels[0].Id);
  Assert.AreEqual('Ready', Update.Labels[0].Text);
  Assert.AreEqual('n', Update.Labels[1].Id);
  Assert.AreEqual('1', Update.Labels[1].Text);
  Assert.AreEqual<Integer>(1, Length(Update.Lists));
  Assert.AreEqual('files', Update.Lists[0].Id);
  Assert.AreEqual<Integer>(2, Length(Update.Lists[0].Items));
  Assert.AreEqual('a', Update.Lists[0].Items[0]);
  Assert.AreEqual('b', Update.Lists[0].Items[1]);
  Assert.AreEqual(1, Update.Lists[0].Selected);
end;

procedure TTestDialogLiveUpdate.AListWithoutItemsIsSkipped;
var
  Update: TDialogLiveUpdate;
begin
  Assert.IsTrue(TryParseDialogLiveUpdate(
    '{"lists":{"gone":{"selected":3},"kept":{"items":["x"]}}}', Update));
  Assert.AreEqual<Integer>(1, Length(Update.Lists));
  Assert.AreEqual('kept', Update.Lists[0].Id);
  Assert.AreEqual(0, Update.Lists[0].Selected);
  Assert.AreEqual('x', Update.Lists[0].Items[0]);
end;

procedure TTestDialogLiveUpdate.AnAccentNeedsThreeNumbers;
var
  Update: TDialogLiveUpdate;
begin
  Assert.IsTrue(TryParseDialogLiveUpdate(
    '{"lists":{"files":{"items":["ab"],"accents":[[0,1,2],[0,1],"no",["z",4,5]]}}}',
    Update));
  Assert.AreEqual<Integer>(2, Length(Update.Lists[0].Accents));
  Assert.AreEqual(0, Update.Lists[0].Accents[0].Item);
  Assert.AreEqual(1, Update.Lists[0].Accents[0].Col);
  Assert.AreEqual(2, Update.Lists[0].Accents[0].Len);
  Assert.AreEqual(0, Update.Lists[0].Accents[1].Item);
  Assert.AreEqual(4, Update.Lists[0].Accents[1].Col);
  Assert.AreEqual(5, Update.Lists[0].Accents[1].Len);
end;

end.
