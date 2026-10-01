unit TestFolderHotlistDialog;

{ TFolderHotlistDialogController: edits made in the list (delete, group,
  folding) apply while it is open; Cancel rolls the stored list back and an
  accepted jump keeps it. The runner points the config folder at a temp
  directory. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFolderHotlistDialog = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CancelRollsBackEdits;
    [Test] procedure AcceptKeepsEdits;
    [Test] procedure FoldingHidesGroupEntries;
    [Test] procedure KeysOpenGroupsAndGoToEntries;
    [Test] procedure SaveKeepsEditsBeforeCancel;
    [Test] procedure CtrlUpTakesLastEntryOutOfGroup;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uFolderHotlist,
  uDualPanelFolderHotlist;

const
  cA = 'file:///C:/hotlist-a';
  cB = 'file:///C:/hotlist-b';
  cC = 'file:///C:/hotlist-c';

var
  GNavigated: string;
  GKind: THostDialogKind;

function MakeController(ADialog: TDialogHost): TFolderHotlistDialogController;
begin
  GNavigated := '';
  Result := TFolderHotlistDialogController.Create(ADialog,
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
    function: Boolean
    begin
      Result := True;
    end,
    procedure
    begin
    end,
    function(out AUri: string): Boolean
    begin
      AUri := '';
      Result := False;
    end,
    procedure(const AUri: string)
    begin
      GNavigated := AUri;
    end,
    procedure
    begin
    end);
end;

procedure TTestFolderHotlistDialog.Setup;
begin
  FolderHotlistClear;
  FolderHotlistAdd('a', cA);
  FolderHotlistAdd('b', cB);
  FolderHotlistAdd('c', cC);
end;

procedure TTestFolderHotlistDialog.TearDown;
begin
  FolderHotlistClear;
end;

procedure TTestFolderHotlistDialog.CancelRollsBackEdits;
var
  Dialog: TDialogHost;
  C: TFolderHotlistDialogController;
  Key: Word;
  Ch: Char;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      Key := vkDelete;
      Ch := #0;
      Assert.IsTrue(C.HandleListInput(Key, [], Ch), 'Del is handled');
      Assert.AreEqual<Integer>(2, Length(FolderHotlistGetEntries), 'Del removes the entry at once');
      Assert.IsTrue(C.DispatchCommand(hdkFolderHotlist, 'cancel'));
      Assert.AreEqual<Integer>(3, Length(FolderHotlistGetEntries), 'Cancel restores the list');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestFolderHotlistDialog.AcceptKeepsEdits;
var
  Dialog: TDialogHost;
  C: TFolderHotlistDialogController;
  Key: Word;
  Ch: Char;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      Key := vkDelete;
      Ch := #0;
      C.HandleListInput(Key, [], Ch);
      Assert.IsTrue(C.DispatchCommand(hdkFolderHotlist, 'ok'));
      Assert.AreEqual<Integer>(2, Length(FolderHotlistGetEntries), 'accepting keeps the edits');
      Assert.AreEqual(cB, GNavigated, 'jumps to the entry under the cursor');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestFolderHotlistDialog.SaveKeepsEditsBeforeCancel;
var
  Dialog: TDialogHost;
  C: TFolderHotlistDialogController;
  Key: Word;
  Ch: Char;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      Key := vkDelete;
      Ch := #0;
      C.HandleListInput(Key, [], Ch);
      Assert.IsTrue(C.DispatchCommand(hdkFolderHotlist, 'save'));
      Assert.IsTrue(Dialog.Visible, 'Save leaves the list open');
      Assert.IsTrue(GKind = hdkFolderHotlist, 'the list keeps its dialog kind');
      Key := vkDelete;
      C.HandleListInput(Key, [], Ch);
      Assert.AreEqual<Integer>(1, Length(FolderHotlistGetEntries));
      C.DispatchCommand(hdkFolderHotlist, 'cancel');
      Assert.AreEqual<Integer>(2, Length(FolderHotlistGetEntries),
        'Cancel rolls back only what was done after Save');
      Assert.AreEqual('', GNavigated, 'Cancel does not jump');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestFolderHotlistDialog.CtrlUpTakesLastEntryOutOfGroup;
var
  Dialog: TDialogHost;
  C: TFolderHotlistDialogController;
  Key: Word;
  Ch: Char;
  E: TFolderHotlistEntry;
  Groups: Integer;
begin
  // rows: [G], a, [H], b, c - a is the only entry of G, first in the list.
  FolderHotlistSetGroupByUri(cA, 'G');
  FolderHotlistSetGroupByUri(cB, 'H');
  FolderHotlistSetGroupByUri(cC, 'H');
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      Key := vkDown;
      Ch := #0;
      // Cursor on the header; Down is the list's own key, so reopen on a
      // fresh dialog is not needed: select a's row by moving it directly.
      Dialog.SetListItems('hotlist', ['', '', '', '', ''], 1);
      C.RefreshList;
      Assert.IsTrue(Dialog.GetListSelectedText('hotlist') <> '');
      Key := vkUp;
      Assert.IsTrue(C.HandleListInput(Key, [ssCtrl], Ch), 'Ctrl+Up is handled');
      Groups := 0;
      for E in FolderHotlistGetEntries do
        if E.Group = 'G' then
          Inc(Groups);
      Assert.AreEqual<Integer>(1, Groups, 'the group stays, empty');
      Assert.AreEqual('', FolderHotlistGetEntries[FolderHotlistFindByUri(cA)].Group,
        'the entry left the group');
      C.DispatchCommand(hdkFolderHotlist, 'cancel');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestFolderHotlistDialog.KeysOpenGroupsAndGoToEntries;
var
  Dialog: TDialogHost;
  C: TFolderHotlistDialogController;
  Key: Word;
  Ch: Char;
begin
  FolderHotlistRenameByUri(cA, '&Alpha');
  FolderHotlistRenameByUri(cC, '&Cee');
  FolderHotlistSetGroupByUri(cA, '&One');
  FolderHotlistSetGroupByUri(cB, '&One');
  FolderHotlistSetGroupByUri(cC, '&Two');
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      Key := 0;
      // The Russian layout's key for T (the Latin key of Two).
      Ch := WideChar($0435);
      Assert.IsTrue(C.HandleListInput(Key, [], Ch), 'a group key is handled on the other layout too');
      Assert.IsTrue(Dialog.GetListSelectedText('hotlist').StartsWith('[-]') and Dialog.GetListSelectedText('hotlist').EndsWith('Two'), 'Two is open');
      Ch := 'a';
      Assert.IsFalse(C.HandleListInput(Key, [], Ch), 'an entry of the folded group is not on show');
      Assert.AreEqual('', GNavigated);
      Ch := 'c';
      Assert.IsTrue(C.HandleListInput(Key, [], Ch), 'an entry key is handled');
      Assert.IsFalse(Dialog.Visible, 'an entry key closes the list');
      Assert.AreEqual(cC, GNavigated, 'and jumps to the entry');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TTestFolderHotlistDialog.FoldingHidesGroupEntries;
var
  Dialog: TDialogHost;
  C: TFolderHotlistDialogController;
  Key: Word;
  Ch: Char;
begin
  FolderHotlistSetGroupByUri(cA, 'G');
  FolderHotlistSetGroupByUri(cB, 'G');
  FolderHotlistSetGroupByUri(cC, 'G');
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      // rows: [G], a, b, c - the cursor is on the group header.
      Assert.IsTrue(Dialog.GetListSelectedText('hotlist').StartsWith('[-]'));
      Key := vkLeft;
      Ch := #0;
      Assert.IsTrue(C.HandleListInput(Key, [], Ch), 'Left is handled');
      Assert.IsTrue(Dialog.GetListSelectedText('hotlist').StartsWith('[+]'), 'Left folds the group');
      Key := vkRight;
      Assert.IsTrue(C.HandleListInput(Key, [], Ch), 'Right is handled');
      Assert.IsTrue(Dialog.GetListSelectedText('hotlist').StartsWith('[-]'), 'Right unfolds it');
      Assert.IsTrue(C.DispatchCommand(hdkFolderHotlist, 'hotlist'));
      Assert.IsTrue(Dialog.Visible, 'a double-click on a header does not close the list');
      Assert.IsTrue(GKind = hdkFolderHotlist, 'the list keeps its dialog kind');
      Assert.IsTrue(Dialog.GetListSelectedText('hotlist').StartsWith('[+]'), 'a double-click folds the group');
      C.DispatchCommand(hdkFolderHotlist, 'cancel');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

end.
