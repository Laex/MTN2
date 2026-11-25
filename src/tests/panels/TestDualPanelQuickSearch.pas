unit TestDualPanelQuickSearch;

{ Alt quick search: it lingers only when asked, a click drops it unless the
  filter is kept, and ending that filter leaves the cursor on the same name. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelQuickSearch = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure AltReleaseClearsASearchThatDoesNotLinger;
    [Test] procedure AStickySearchSurvivesAltRelease;
    [Test] procedure AClickDropsTheSearchUnlessTheFilterIsKept;
    [Test] procedure TypingALetterMovesTheCursorToThatName;
    [Test] procedure ClearingTheFilterKeepsTheCursorOnTheSameName;
    [Test] procedure StartDoesNothingOutsideThePanels;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDualPanelTypes, uDualPanelQuickSearch;

type
  TSearchHost = class(TInterfacedObject, IDualPanelQuickSearchHost)
  public
    Ws: TDualPanelWorkspaceTab;
    Panel: TPanelState;
    Rows: TPanelRows;
    Needle: string;
    NeedleSide: TPanelSide;
    Notified: Integer;
    function ActiveWorkspace: TDualPanelWorkspaceTab;
    function ActivePanel(var AWs: TDualPanelWorkspaceTab): TPanelState;
    procedure SetActivePanel(var AWs: TDualPanelWorkspaceTab; const APanel: TPanelState);
    function RowsForSide(ASide: TPanelSide): TPanelRows;
    procedure SetNeedle(ASide: TPanelSide; const ANeedle: string; AFuzzy: Boolean);
    procedure SaveActiveWorkspace(const AWs: TDualPanelWorkspaceTab);
    function ListViewHeight: Integer;
    function ListColCount(ASide: TPanelSide): Integer;
    procedure ClampCursor(ASide: TPanelSide);
    procedure NotifyChanged;
  end;

function TSearchHost.ActiveWorkspace: TDualPanelWorkspaceTab;
begin
  Result := Ws;
end;

function TSearchHost.ActivePanel(var AWs: TDualPanelWorkspaceTab): TPanelState;
begin
  Result := Panel;
end;

procedure TSearchHost.SetActivePanel(var AWs: TDualPanelWorkspaceTab;
  const APanel: TPanelState);
begin
  Panel := APanel;
  AWs.State.LeftPanel := APanel;
end;

function TSearchHost.RowsForSide(ASide: TPanelSide): TPanelRows;
begin
  Result := Rows;
end;

procedure TSearchHost.SetNeedle(ASide: TPanelSide; const ANeedle: string;
  AFuzzy: Boolean);
begin
  Needle := ANeedle;
  NeedleSide := ASide;
end;

procedure TSearchHost.SaveActiveWorkspace(const AWs: TDualPanelWorkspaceTab);
begin
  Ws := AWs;
  Panel := AWs.State.LeftPanel;
end;

function TSearchHost.ListViewHeight: Integer;
begin
  Result := 10;
end;

function TSearchHost.ListColCount(ASide: TPanelSide): Integer;
begin
  Result := 1;
end;

procedure TSearchHost.ClampCursor(ASide: TPanelSide);
begin
end;

procedure TSearchHost.NotifyChanged;
begin
  Inc(Notified);
end;

var
  GHost: TSearchHost;
  GSearch: TDualPanelQuickSearch;

procedure TTestDualPanelQuickSearch.Setup;
begin
  GHost := TSearchHost.Create;
  GHost.Ws.Kind := wkPanels;
  GHost.Ws.State.ActiveSide := psLeft;
  SetLength(GHost.Panel.Tabs, 1);
  GHost.Panel.Tabs[0] := MakeTab(1, 'home', 'file:///C:/work');
  GHost.Panel.Tabs[0].CursorIndex := 2;
  GHost.Panel.ActiveTabIndex := 0;
  GHost.Ws.State.LeftPanel := GHost.Panel;
  SetLength(GHost.Rows, 3);
  GHost.Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///', True);
  GHost.Rows[1] := MakePanelRow('alpha.txt', False);
  GHost.Rows[2] := MakePanelRow('note.txt', False);
  GSearch := TDualPanelQuickSearch.Create(GHost);
end;

procedure TTestDualPanelQuickSearch.TearDown;
begin
  GSearch.Free;
end;

procedure TypeLetter(AChar: Char);
var
  Key: Word;
  Shift: TShiftState;
begin
  Key := 0;
  Shift := [];
  Assert.IsTrue(GSearch.HandleInput(Key, Shift, AChar));
end;

procedure TTestDualPanelQuickSearch.AltReleaseClearsASearchThatDoesNotLinger;
begin
  TypeLetter('n');
  Assert.IsTrue(GSearch.Active);
  Assert.IsTrue(GSearch.TakeAltRelease);
  Assert.IsFalse(GSearch.Active);
  Assert.AreEqual('', GSearch.Text);
end;

procedure TTestDualPanelQuickSearch.AStickySearchSurvivesAltRelease;
begin
  GSearch.Sticky := True;
  TypeLetter('n');
  Assert.IsFalse(GSearch.TakeAltRelease);
  Assert.IsTrue(GSearch.Active);
  Assert.AreEqual('n', GSearch.Text);
end;

procedure TTestDualPanelQuickSearch.AClickDropsTheSearchUnlessTheFilterIsKept;
begin
  TypeLetter('n');
  Assert.IsTrue(GSearch.ClearsOnClick);
  GSearch.Clear;
  Assert.IsFalse(GSearch.Active);
  GSearch.Filter := True;
  GSearch.KeepFilter := True;
  TypeLetter('n');
  Assert.IsFalse(GSearch.ClearsOnClick);
end;

procedure TTestDualPanelQuickSearch.TypingALetterMovesTheCursorToThatName;
begin
  GHost.Panel.Tabs[0].CursorIndex := 0;
  TypeLetter('n');
  Assert.AreEqual<Integer>(2, ActiveTab(GHost.Panel).CursorIndex);
  Assert.AreEqual('n', GSearch.Text);
end;

procedure TTestDualPanelQuickSearch.ClearingTheFilterKeepsTheCursorOnTheSameName;
var
  Key: Word;
  Shift: TShiftState;
  Ch: Char;
begin
  GSearch.Filter := True;
  TypeLetter('n');
  Assert.AreEqual('n', GHost.Needle);
  Key := vkBack;
  Shift := [];
  Ch := #0;
  Assert.IsTrue(GSearch.HandleInput(Key, Shift, Ch));
  Assert.AreEqual('', GHost.Needle);
  Assert.AreEqual('note.txt', GHost.Rows[ActiveTab(GHost.Panel).CursorIndex].Text);
end;

procedure TTestDualPanelQuickSearch.StartDoesNothingOutsideThePanels;
begin
  GHost.Ws.Kind := wkDocument;
  GSearch.Start;
  Assert.IsFalse(GSearch.Active);
  Assert.AreEqual<Integer>(0, GHost.Notified);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelQuickSearch);

end.
