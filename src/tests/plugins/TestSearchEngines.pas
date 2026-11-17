unit TestSearchEngines;

{ The engine list of the Find dialog and the mapping between its index and the choice
  kept in the search state. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSearchEngines = class
  public
    [Test] procedure TestItemsStartWithAutoAndBuiltIn;
    [Test] procedure TestItemFallsBackToTheIdWithoutATitle;
    [Test] procedure TestIndexOfTheChoice;
    [Test] procedure TestUnknownEngineMeansAuto;
    [Test] procedure TestChoiceOfTheIndex;
    [Test] procedure TestIndexOutOfRangeMeansAuto;
    [Test] procedure TestChoiceRoundTrips;
    [Test] procedure TestListerSuppliesTheEngines;
    [Test] procedure TestStageEnginesKeepOnlyTheCapableProviders;
    [Test] procedure TestPipelineCaptionNamesTheChoices;
  end;

implementation

uses
  System.SysUtils, uSearchEngines;

function Engines: TArray<TSearchEngine>;
begin
  SetLength(Result, 2);
  Result[0].Id := 'mtn.everything';
  Result[0].Title := 'Everything';
  Result[1].Id := 'mtn.ripgrep';
  Result[1].Title := 'ripgrep';
end;

procedure TTestSearchEngines.TestItemsStartWithAutoAndBuiltIn;
var
  Items: TArray<string>;
begin
  Items := SearchEngineItems(Engines, 'Auto', 'Built-in');
  Assert.AreEqual<Integer>(4, Length(Items));
  Assert.AreEqual('Auto', Items[0]);
  Assert.AreEqual('Built-in', Items[1]);
  Assert.AreEqual('Everything', Items[2]);
  Assert.AreEqual('ripgrep', Items[3]);
  Items := SearchEngineItems(nil, 'Auto', 'Built-in');
  Assert.AreEqual<Integer>(2, Length(Items), 'no plugin, two items');
end;

procedure TTestSearchEngines.TestItemFallsBackToTheIdWithoutATitle;
var
  E: TArray<TSearchEngine>;
begin
  E := Engines;
  E[0].Title := '';
  Assert.AreEqual('mtn.everything', SearchEngineItems(E, 'A', 'B')[2]);
end;

procedure TTestSearchEngines.TestIndexOfTheChoice;
begin
  Assert.AreEqual(cEngineIdxAuto, SearchEngineIndex(True, '', Engines));
  Assert.AreEqual(cEngineIdxBuiltIn, SearchEngineIndex(False, '', Engines));
  Assert.AreEqual(cEngineIdxBuiltIn, SearchEngineIndex(False, 'mtn.ripgrep', Engines),
    'the built-in walk wins over a remembered engine');
  Assert.AreEqual(2, SearchEngineIndex(True, 'mtn.everything', Engines));
  Assert.AreEqual(3, SearchEngineIndex(True, 'MTN.RIPGREP', Engines));
end;

procedure TTestSearchEngines.TestUnknownEngineMeansAuto;
begin
  Assert.AreEqual(cEngineIdxAuto, SearchEngineIndex(True, 'mtn.gone', Engines));
end;

procedure TTestSearchEngines.TestChoiceOfTheIndex;
var
  Use: Boolean;
  Id: string;
begin
  SearchEngineFromIndex(0, Engines, Use, Id);
  Assert.IsTrue(Use);
  Assert.AreEqual('', Id);
  SearchEngineFromIndex(1, Engines, Use, Id);
  Assert.IsFalse(Use);
  Assert.AreEqual('', Id);
  SearchEngineFromIndex(3, Engines, Use, Id);
  Assert.IsTrue(Use);
  Assert.AreEqual('mtn.ripgrep', Id);
end;

procedure TTestSearchEngines.TestIndexOutOfRangeMeansAuto;
var
  Use: Boolean;
  Id: string;
begin
  SearchEngineFromIndex(-1, Engines, Use, Id);
  Assert.IsTrue(Use);
  Assert.AreEqual('', Id);
  SearchEngineFromIndex(4, Engines, Use, Id);
  Assert.IsTrue(Use);
  Assert.AreEqual('', Id);
end;

procedure TTestSearchEngines.TestChoiceRoundTrips;
var
  I: Integer;
  Use: Boolean;
  Id: string;
begin
  for I := 0 to 3 do
  begin
    SearchEngineFromIndex(I, Engines, Use, Id);
    Assert.AreEqual(I, SearchEngineIndex(Use, Id, Engines));
  end;
end;

procedure TTestSearchEngines.TestListerSuppliesTheEngines;
begin
  SetSearchEngineLister(nil);
  Assert.AreEqual<Integer>(0, Length(SearchEngines));
  SetSearchEngineLister(
    function: TArray<TSearchEngine>
    begin
      Result := Engines;
    end);
  try
    Assert.AreEqual<Integer>(2, Length(SearchEngines));
  finally
    SetSearchEngineLister(nil);
  end;
end;

procedure TTestSearchEngines.TestStageEnginesKeepOnlyTheCapableProviders;
var
  All, Names, Text: TArray<TSearchEngine>;
begin
  All := Engines;
  All[0].CanList := True;
  All[1].CanFiles := True;
  Names := SearchStageEngines(All, ssNames);
  Text := SearchStageEngines(All, ssText);
  Assert.AreEqual<Integer>(1, Length(Names));
  Assert.AreEqual('mtn.everything', Names[0].Id);
  Assert.AreEqual<Integer>(1, Length(Text));
  Assert.AreEqual('mtn.ripgrep', Text[0].Id);
end;

procedure TTestSearchEngines.TestPipelineCaptionNamesTheChoices;
var
  Names, Text: TArray<string>;
begin
  Names := TArray<string>.Create('Auto', 'Built-in', 'Ev');
  Text := TArray<string>.Create('Auto', 'Built-in', 'rg');
  Assert.AreEqual('Pipeline: Auto', SearchPipelineCaption('Pipeline', 'Auto', Names, Text, 0, 0));
  Assert.AreEqual('Pipeline: Ev > rg',
    SearchPipelineCaption('Pipeline', 'Auto', Names, Text, 2, 2));
  Names[2] := 'A very long provider name';
  Assert.AreEqual('Pipeline...', SearchPipelineCaption('Pipeline', 'Auto', Names, Text, 2, 2));
  Assert.AreEqual('Pipeline...', SearchPipelineCaption('Pipeline', 'Auto', Names, Text, 7, 1));
end;

end.