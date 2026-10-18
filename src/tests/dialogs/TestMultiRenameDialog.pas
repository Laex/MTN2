unit TestMultiRenameDialog;

{ TMultiRenameController: the preview follows the fields, an accepted batch
  hands the move pairs to the job starter, and a batch with a conflict or
  items from several folders never starts. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMultiRenameDialog = class
  public
    [Test] procedure PreviewFollowsTheFields;
    [Test] procedure ChangedPartOfTheNewNameIsAccented;
    [Test] procedure AcceptStartsTheMoves;
    [Test] procedure ConflictKeepsTheDialogOpen;
    [Test] procedure ItemsOfSeveralFoldersAreRefused;
    [Test] procedure CancelStartsNothing;
  end;

implementation

uses
  System.SysUtils, uDialogHost, uDialogTypes, uDualPanelUiTypes, uDualPanelTypes,
  uDualPanelMultiRename, uVfsTypes;

const
  cDir = 'file:///C:/mr-test';

var
  GStarted: Integer;
  GSources, GDests: TArray<string>;
  GStub: string;
  GKind: THostDialogKind;

function Row(const AName: string; const ADir: string = cDir): TPanelRow;
begin
  Result := Default(TPanelRow);
  Result.Text := AName;
  Result.URI := JoinFileUri(ADir, AName);
end;

function MakeRows: TPanelRows;
var
  Parent: TPanelRow;
begin
  Parent := Default(TPanelRow);
  Parent.Text := '..';
  Parent.IsParent := True;
  Result := [Parent, Row('a.txt'), Row('b.txt'), Row('keep.txt')];
end;

// The cells of a preview row: old name, new name, note; padding removed.
function Cells(const ARow: string): TArray<string>;
var
  I: Integer;
begin
  Result := ARow.Split([' | ']);
  for I := 0 to High(Result) do
    Result[I] := Trim(Result[I]);
  Result[0] := Trim(Result[0].TrimLeft(['!', ' ']));
end;

function MakeController(ADialog: TDialogHost): TMultiRenameController;
begin
  GStarted := 0;
  GStub := '';
  SetLength(GSources, 0);
  SetLength(GDests, 0);
  Result := TMultiRenameController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string)
    begin
    end,
    procedure(AKind: THostDialogKind)
    begin
      GKind := AKind;
    end,
    procedure
    begin
    end,
    procedure(const ATitle, ADetail: string)
    begin
      GStub := ADetail;
    end,
    procedure(const ASources, ADests: TArray<string>)
    begin
      Inc(GStarted);
      GSources := ASources;
      GDests := ADests;
    end,
    procedure
    begin
    end,
    function: Integer
    begin
      Result := 130;
    end);
end;

procedure TTestMultiRenameDialog.PreviewFollowsTheFields;
var
  Dialog: TDialogHost;
  C: TMultiRenameController;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.Open([Row('a.txt').URI, Row('b.txt').URI], MakeRows);
      Assert.IsTrue(Dialog.Visible, 'the dialog opens');
      Assert.IsTrue(GKind = hdkMultiRename, 'its kind is set');
      Assert.AreEqual('a.txt', Cells(Dialog.GetListSelectedText('preview'))[0],
        'default rules leave the names as they are');
      Assert.AreEqual('', Cells(Dialog.GetListSelectedText('preview'))[1],
        'an unchanged name has no new name');
      Dialog.SetInputValue('name_mask', 'f[C]');
      C.NotifyDialogChanged;
      Assert.AreEqual('a.txt', Cells(Dialog.GetListSelectedText('preview'))[0], 'old name column');
      Assert.AreEqual('f1.txt', Cells(Dialog.GetListSelectedText('preview'))[1], 'new name column');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestMultiRenameDialog.ChangedPartOfTheNewNameIsAccented;
var
  Dialog: TDialogHost;
  C: TMultiRenameController;
  I: Integer;
  Text: string;
  Accents: TArray<TListAccent>;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.Open([Row('a.txt').URI], MakeRows);
      Dialog.SetInputValue('name_mask', 'f[C]');
      C.NotifyDialogChanged;
      for I := 0 to Dialog.ControlCount - 1 do
        if Dialog.GetControl(I).Id = 'preview' then
          Accents := Dialog.GetControl(I).ItemAccents;
      Text := Dialog.GetListSelectedText('preview');
      Assert.AreEqual<Integer>(1, Length(Accents), 'one changed stretch in the row');
      Assert.AreEqual(0, Accents[0].Item);
      Assert.AreEqual('f1', Copy(Text, Accents[0].Col + 1, Accents[0].Len),
        'the accent covers what differs from the old name; ".txt" stays plain');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestMultiRenameDialog.AcceptStartsTheMoves;
var
  Dialog: TDialogHost;
  C: TMultiRenameController;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.Open([Row('a.txt').URI, Row('b.txt').URI], MakeRows);
      Dialog.SetInputValue('name_mask', 'f[C]');
      C.NotifyDialogChanged;
      Assert.IsTrue(C.DispatchCommand('ok'));
      Assert.AreEqual(1, GStarted, 'one job for the batch');
      Assert.IsFalse(Dialog.Visible, 'the dialog closes');
      Assert.AreEqual<Integer>(2, Length(GSources));
      Assert.AreEqual(Row('a.txt').URI, GSources[0]);
      Assert.AreEqual(JoinFileUri(cDir, 'f1.txt'), GDests[0]);
      Assert.AreEqual(Row('b.txt').URI, GSources[1]);
      Assert.AreEqual(JoinFileUri(cDir, 'f2.txt'), GDests[1]);
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestMultiRenameDialog.ConflictKeepsTheDialogOpen;
var
  Dialog: TDialogHost;
  C: TMultiRenameController;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.Open([Row('a.txt').URI], MakeRows);
      Dialog.SetInputValue('name_mask', 'keep');
      C.NotifyDialogChanged;
      Assert.StartsWith('! ', Dialog.GetListSelectedText('preview'), 'a taken name is marked');
      Assert.IsTrue(Pos('keep.txt', Dialog.GetListSelectedText('preview')) > 0);
      Assert.IsTrue(C.DispatchCommand('ok'));
      Assert.AreEqual(0, GStarted, 'nothing starts while a name is taken');
      Assert.IsTrue(Dialog.Visible, 'the dialog stays open to fix the name');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestMultiRenameDialog.ItemsOfSeveralFoldersAreRefused;
var
  Dialog: TDialogHost;
  C: TMultiRenameController;
  Rows: TPanelRows;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      Rows := MakeRows + [Row('z.txt', cDir + '/sub')];
      C.Open([Row('a.txt').URI, Row('z.txt', cDir + '/sub').URI], Rows);
      Assert.IsFalse(Dialog.Visible, 'no dialog');
      Assert.AreNotEqual('', GStub, 'the user is told why');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestMultiRenameDialog.CancelStartsNothing;
var
  Dialog: TDialogHost;
  C: TMultiRenameController;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.Open([Row('a.txt').URI], MakeRows);
      Dialog.SetInputValue('name_mask', 'x');
      C.NotifyDialogChanged;
      Assert.IsTrue(C.DispatchCommand('cancel'));
      Assert.AreEqual(0, GStarted);
      Assert.IsFalse(Dialog.Visible);
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMultiRenameDialog);

end.
