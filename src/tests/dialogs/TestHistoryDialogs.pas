unit TestHistoryDialogs;

{ Characterization tests for TFolderHistoryDialogController (Alt+F12),
  TCmdHistoryDialogController (Alt+F8) and the Alt+F11 file history
  (uFileHistory store + TFileHistoryDialogController; filehistory.json is
  backed up and restored the same way as folderhistory.json below).
  TCmdHistoryDialogController is fully dependency-injected (AOnTryGetItems /
  AOnApply), so it needs no real global state. TFolderHistoryDialogController
  reads/writes the real uFolderHistory global (persisted to
  %APPDATA%\MTN2\folderhistory.json) -- its tests back up that file first and
  restore it in a finally block so this run never touches the user's real
  folder history. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHistoryDialogs = class
  public
    [Test] procedure TestFolderHistory;
    [Test] procedure TestFileHistoryStore;
    [Test] procedure TestFileHistoryDialog;
    [Test] procedure TestCmdHistoryOpenAndAccept;
    [Test] procedure TestCmdHistoryReject;
    [Test] procedure TestCmdHistoryFilter;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils,
  uDialogTypes,
  uDialogJson,
  uDialogResources,
  uDialogHost,
  uDialogRenderer,
  uInputLine,
  uTerminalTypes,
  uThemeTypes,
  uThemeDrawing,
  uFunctionBar,
  uColorCoding,
  uColorCodingEditHelpers,
  uFileFind,
  uDualPanelUiTypes,
  uFolderHistory,
  uFileHistory,
  uPanelUriLabels,
  uVfsTypes,
  uConfigLocation,
  uDualPanelHistoryDialogs;

{ ---- TFolderHistoryDialogController ---------------------------------- }

var
  GNavigateCalled: Boolean;
  GNavigatedUri: string;
  GNotifyCount: Integer;
  GCanStartResult: Boolean;

function MakeFolderController(ADialog: TDialogHost): TFolderHistoryDialogController;
begin
  GNavigateCalled := False;
  GNavigatedUri := '';
  GNotifyCount := 0;
  GCanStartResult := True;
  Result := TFolderHistoryDialogController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string)
    begin
      // FOnCommand is only wired to the host's real dispatch loop; the
      // tests below call DispatchCommand directly instead of routing
      // through FDialog's own command firing, so this is never invoked.
    end,
    procedure(AKind: THostDialogKind)
    begin
    end,
    procedure
    begin
      Inc(GNotifyCount);
    end,
    function: Boolean
    begin
      Result := GCanStartResult;
    end,
    procedure
    begin
    end,
    procedure(const AUri: string)
    begin
      GNavigateCalled := True;
      GNavigatedUri := AUri;
    end);
end;

procedure TestFolderHistory;
var
  BackupPath, OriginalContent: string;
  HadOriginal: Boolean;
  Dialog: TDialogHost;
  C: TFolderHistoryDialogController;
  Uris: TArray<string>;
begin
  BackupPath := GetConfigFilePath('folderhistory.json');
  HadOriginal := TFile.Exists(BackupPath);
  if HadOriginal then
    OriginalContent := TFile.ReadAllText(BackupPath, TEncoding.UTF8);
  try
    FolderHistoryClear;
    FolderHistoryPush('file:///C:/alpha/');
    FolderHistoryPush('file:///C:/beta/');
    FolderHistoryPush('file:///C:/gamma/');
    // Newest-first: gamma, beta, alpha.
    Uris := FolderHistoryGetUris;
    Assert.IsTrue(Length(Uris) = 3, 'seeded 3 test URIs into the real folder history');
    Assert.IsTrue(Uris[0] = 'file:///C:/gamma/', 'newest push sorts first');

    Dialog := TDialogHost.Create(nil);
    try
      C := MakeFolderController(Dialog);
      try
        GCanStartResult := False;
        C.OpenList;
        Assert.IsTrue(not Dialog.Visible, 'OpenList declines to open when AOnCanStart returns False');
        GCanStartResult := True;

        C.OpenList;
        Assert.IsTrue(Dialog.Visible, 'OpenList opens the dialog when allowed to start');
        Assert.IsTrue(GNotifyCount = 1, 'OpenList notifies the host once');
        Assert.IsTrue(Dialog.GetListSelectedIndex('folders') = 0,
          'list opens with the first (newest) entry selected');

        // Move selection to index 2 (alpha) before accepting.
        Dialog.SetListItems('folders', ['gamma', 'beta', 'alpha'], 2);
        Assert.IsTrue(C.DispatchCommand('folders'),
          'DispatchCommand(''folders'') (Enter/dbl-click on the list) returns True');
        Assert.IsTrue(not Dialog.Visible, 'accepting closes the dialog');
        Assert.IsTrue(GNavigateCalled, 'accepting navigates');
        Assert.IsTrue(GNavigatedUri = 'file:///C:/alpha/', 'navigates to the selected (not the first) URI');
      finally
        C.Free;
      end;
    finally
      Dialog.Free;
    end;

    // Cancel: DispatchCommand with an unrelated control id must not navigate.
    Dialog := TDialogHost.Create(nil);
    try
      C := MakeFolderController(Dialog);
      try
        C.OpenList;
        Dialog.SetListItems('folders', ['gamma', 'beta', 'alpha'], 1);
        C.DispatchCommand('cancel');
        Assert.IsTrue(not Dialog.Visible, 'cancel closes the dialog');
        Assert.IsTrue(not GNavigateCalled, 'cancel does not navigate');
      finally
        C.Free;
      end;
    finally
      Dialog.Free;
    end;
  finally
    // Restore the real folder history exactly as it was before this test ran.
    FolderHistoryClear;
    if HadOriginal then
      TFile.WriteAllText(BackupPath, OriginalContent, TEncoding.UTF8)
    else if TFile.Exists(BackupPath) then
      TFile.Delete(BackupPath);
  end;
end;

{ ---- TCmdHistoryDialogController --------------------------------------- }

var
  GApplyCalled: Boolean;
  GAppliedCmd: string;
  GTryGetItemsResult: Boolean;
  GTryGetItems: TArray<string>;

function MakeCmdController(ADialog: TDialogHost): TCmdHistoryDialogController;
begin
  GApplyCalled := False;
  GAppliedCmd := '';
  GNotifyCount := 0;
  GCanStartResult := True;
  GTryGetItemsResult := True;
  Result := TCmdHistoryDialogController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string)
    begin
    end,
    procedure(AKind: THostDialogKind)
    begin
    end,
    procedure
    begin
      Inc(GNotifyCount);
    end,
    function: Boolean
    begin
      Result := GCanStartResult;
    end,
    procedure
    begin
    end,
    function(out AItems: TArray<string>): Boolean
    begin
      AItems := GTryGetItems;
      Result := GTryGetItemsResult;
    end,
    procedure(const ACommand: string)
    begin
      GApplyCalled := True;
      GAppliedCmd := ACommand;
    end);
end;

procedure TestCmdHistoryOpenAndAccept;
var
  Dialog: TDialogHost;
  C: TCmdHistoryDialogController;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeCmdController(Dialog);
    try
      GTryGetItemsResult := False;
      C.OpenList;
      Assert.IsTrue(not Dialog.Visible, 'OpenList declines when AOnTryGetItems returns False');

      GTryGetItemsResult := True;
      GTryGetItems := ['dir', 'cd ..', 'echo hi'];
      C.OpenList;
      Assert.IsTrue(Dialog.Visible, 'OpenList opens once items are available');
      Assert.IsTrue(GNotifyCount = 1, 'OpenList notifies the host once');

      Dialog.SetListItems('commands', GTryGetItems, 1);
      C.DispatchCommand('commands');
      Assert.IsTrue(GApplyCalled, 'accepting on the list applies the selected command');
      Assert.IsTrue(GAppliedCmd = 'cd ..', 'applies the command at the selected index, not index 0');
      Assert.IsTrue(not Dialog.Visible, 'accepting closes the dialog');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TestCmdHistoryReject;
var
  Dialog: TDialogHost;
  C: TCmdHistoryDialogController;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeCmdController(Dialog);
    try
      GTryGetItems := ['dir', 'cd ..'];
      C.OpenList;
      Dialog.SetListItems('commands', GTryGetItems, 0);
      C.DispatchCommand('cancel');
      Assert.IsTrue(not GApplyCalled, 'a non-accept control id does not apply anything');
      Assert.IsTrue(not Dialog.Visible, 'cancel still closes the dialog');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TestCmdHistoryFilter;
var
  Dialog: TDialogHost;
  C: TCmdHistoryDialogController;
  Key: Word;
  KeyChar: Char;
begin
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeCmdController(Dialog);
    try
      GTryGetItems := ['dir', 'cd ..', 'echo hi', 'diff a b'];
      C.OpenList;

      Key := 0;
      KeyChar := 'd';
      Assert.IsTrue(C.HandleFilterInput(Key, [], KeyChar), 'typing a letter is consumed');
      KeyChar := 'i';
      C.HandleFilterInput(Key, [], KeyChar);
      // Filter is now "di" -- RefreshList narrows to ['dir', 'diff a b'],
      // reopened with index 0 selected.
      C.DispatchCommand('commands');
      Assert.IsTrue(GApplyCalled, 'accepting after filtering applies a filtered item');
      Assert.IsTrue(GAppliedCmd = 'dir', 'the filtered list still maps index 0 to the first match');

      GApplyCalled := False;
      GTryGetItems := ['dir', 'cd ..', 'echo hi', 'diff a b'];
      C.OpenList;
      KeyChar := 'z';
      C.HandleFilterInput(Key, [], KeyChar);
      // Filter "z" matches nothing -- RefreshList reopens with the
      // "(empty)" placeholder, but the controller's own FItems is empty.
      C.DispatchCommand('commands');
      Assert.IsTrue(not GApplyCalled, 'accepting with an empty filtered list applies nothing');

      Key := vkBack;
      KeyChar := #0;
      GTryGetItems := ['dir', 'cd ..'];
      C.OpenList;
      KeyChar := 'd';
      C.HandleFilterInput(Key, [], KeyChar);
      Key := vkBack;
      Assert.IsTrue(C.HandleFilterInput(Key, [], KeyChar), 'Backspace is consumed');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

{ ---- uFileHistory + TFileHistoryDialogController (Alt+F11) -------------- }

var
  GFileCtrl: TFileHistoryDialogController;
  GOpenCalled, GOpenEdit, GGotoCalled: Boolean;
  GOpenUri, GGotoUri: string;

// Real config file untouched: back it up, run AProc, restore.
procedure WithFileHistoryBackup(const AProc: TProc);
var
  Path, Original: string;
  HadOriginal: Boolean;
begin
  Path := GetConfigFilePath('filehistory.json');
  HadOriginal := TFile.Exists(Path);
  if HadOriginal then
    Original := TFile.ReadAllText(Path, TEncoding.UTF8);
  try
    AProc();
  finally
    FileHistoryClear;
    if HadOriginal then
      TFile.WriteAllText(Path, Original, TEncoding.UTF8)
    else if TFile.Exists(Path) then
      TFile.Delete(Path);
    FileHistoryReload;
  end;
end;

procedure TestFileHistoryStore;
begin
  WithFileHistoryBackup(
    procedure
    var
      E: TArray<TFileHistoryEntry>;
      I: Integer;
    begin
      FileHistoryClear;
      FileHistoryPush('file:///C:/a.txt', False);
      FileHistoryPush('file:///C:/b.txt', True);
      FileHistoryPush('file:///C:/c.txt', False);
      E := FileHistoryGetEntries;
      Assert.IsTrue((Length(E) = 3) and (E[0].URI = 'file:///C:/c.txt') and
        (E[2].URI = 'file:///C:/a.txt'), 'newest first');
      Assert.IsTrue(E[1].Edit and not E[0].Edit, 'mode kept per entry');

      FileHistoryPush('file:///C:/A.TXT', True);
      E := FileHistoryGetEntries;
      Assert.IsTrue(Length(E) = 3, 'reopening a file does not duplicate it (case-insensitive URI)');
      Assert.IsTrue((E[0].URI = 'file:///C:/A.TXT') and E[0].Edit,
        'reopened file moves to the top with its latest mode');

      FileHistoryReload;
      E := FileHistoryGetEntries;
      Assert.IsTrue((Length(E) = 3) and (E[0].URI = 'file:///C:/A.TXT') and E[0].Edit and
        (E[1].URI = 'file:///C:/c.txt') and not E[1].Edit,
        'filehistory.json round-trips order and mode');

      FileHistoryRemove('file:///c:/b.txt');
      E := FileHistoryGetEntries;
      Assert.IsTrue((Length(E) = 2) and (E[1].URI = 'file:///C:/c.txt'), 'Remove drops only that file');

      for I := 1 to cFileHistoryMax + 5 do
        FileHistoryPush(Format('file:///C:/f%d.txt', [I]), False);
      E := FileHistoryGetEntries;
      Assert.IsTrue(Length(E) = cFileHistoryMax, 'capped at cFileHistoryMax');
      Assert.IsTrue(E[0].URI = Format('file:///C:/f%d.txt', [cFileHistoryMax + 5]),
        'the cap drops the oldest entries');
    end);
end;

function MakeFileController(ADialog: TDialogHost): TFileHistoryDialogController;
begin
  GOpenCalled := False;
  GOpenEdit := False;
  GOpenUri := '';
  GGotoCalled := False;
  GGotoUri := '';
  GNotifyCount := 0;
  GCanStartResult := True;
  Result := TFileHistoryDialogController.Create(ADialog,
    // Like the host: a dialog command lands in the controller's DispatchCommand.
    procedure(const AControlId, AValuesJson: string)
    begin
      GFileCtrl.DispatchCommand(AControlId);
    end,
    procedure(AKind: THostDialogKind)
    begin
    end,
    procedure
    begin
      Inc(GNotifyCount);
    end,
    function: Boolean
    begin
      Result := GCanStartResult;
    end,
    procedure
    begin
    end,
    procedure(const AUri: string; AEdit: Boolean)
    begin
      GOpenCalled := True;
      GOpenUri := AUri;
      GOpenEdit := AEdit;
    end,
    procedure(const AUri: string)
    begin
      GGotoCalled := True;
      GGotoUri := AUri;
    end);
end;

procedure SeedFiles;
begin
  FileHistoryClear;
  FileHistoryPush('file:///C:/alpha.txt', True);   // oldest, Editor
  FileHistoryPush('file:///C:/beta.pas', False);
  FileHistoryPush('file:///C:/gamma.md', False);   // newest, Viewer
end;

procedure SendKey(AKey: Word; AShift: TShiftState; AChar: Char = #0);
var
  K: Word;
  C: Char;
begin
  K := AKey;
  C := AChar;
  Assert.IsTrue(GFileCtrl.HandleListInput(K, AShift, C), Format('key %d consumed', [AKey]));
end;

procedure TestFileHistoryDialog;
begin
  WithFileHistoryBackup(
    procedure
    var
      Dialog: TDialogHost;
      K: Word;
      C: Char;
    begin
      Dialog := TDialogHost.Create(nil);
      try
        GFileCtrl := MakeFileController(Dialog);
        try
          SeedFiles;
          GCanStartResult := False;
          GFileCtrl.OpenList;
          Assert.IsTrue(not Dialog.Visible, 'OpenList declines when AOnCanStart returns False');
          GCanStartResult := True;

          // Enter: reopen in the mode last used.
          GFileCtrl.OpenList;
          Assert.IsTrue(Dialog.Visible and (Dialog.GetListSelectedIndex('files') = 0),
            'opens with the newest file selected');
          Dialog.SetListItems('files', ['g', 'b', 'a'], 2);
          GFileCtrl.DispatchCommand('files');
          Assert.IsTrue(GOpenCalled and (GOpenUri = 'file:///C:/alpha.txt') and GOpenEdit,
            'Enter reopens the selected file in its last mode (Editor)');
          Assert.IsTrue(not Dialog.Visible, 'Enter closes the list');

          // F3 / F4 force the mode.
          GOpenCalled := False;
          GFileCtrl.OpenList;
          Dialog.SetListItems('files', ['g', 'b', 'a'], 2);
          SendKey(vkF3, []);
          Assert.IsTrue(GOpenCalled and (GOpenUri = 'file:///C:/alpha.txt') and not GOpenEdit,
            'F3 opens in the Viewer even if last opened in the Editor');
          GOpenCalled := False;
          GFileCtrl.OpenList;
          SendKey(vkF4, []);
          Assert.IsTrue(GOpenCalled and (GOpenUri = 'file:///C:/gamma.md') and GOpenEdit,
            'F4 opens in the Editor');

          // Ctrl+Enter: show in panel, do not open.
          GOpenCalled := False;
          GFileCtrl.OpenList;
          Dialog.SetListItems('files', ['g', 'b', 'a'], 1);
          SendKey(vkReturn, [ssCtrl]);
          Assert.IsTrue(GGotoCalled and (GGotoUri = 'file:///C:/beta.pas') and not GOpenCalled,
            'Ctrl+Enter goes to the file in the panel');
          Assert.IsTrue(not Dialog.Visible, 'Ctrl+Enter closes the list');

          // Plain Enter is left to the dialog (list accept).
          GFileCtrl.OpenList;
          K := vkReturn;
          C := #0;
          Assert.IsTrue(not GFileCtrl.HandleListInput(K, [], C), 'plain Enter is not consumed by the list keys');

          // Del forgets the entry, list stays open.
          Dialog.SetListItems('files', ['g', 'b', 'a'], 0);
          SendKey(vkDelete, []);
          Assert.IsTrue(Dialog.Visible, 'Del keeps the list open');
          Assert.IsTrue((Length(FileHistoryGetEntries) = 2) and
            (FileHistoryGetEntries[0].URI = 'file:///C:/beta.pas'), 'Del removes the file from history');

          // Typing filters by path.
          GOpenCalled := False;
          SeedFiles;
          GFileCtrl.OpenList;
          SendKey(0, [], 'B');
          SendKey(0, [], 'E');
          GFileCtrl.DispatchCommand('files');
          Assert.IsTrue(GOpenCalled and (GOpenUri = 'file:///C:/beta.pas'),
            'typing "BE" narrows to beta.pas (case-insensitive)');

          GOpenCalled := False;
          GFileCtrl.OpenList;
          SendKey(0, [], 'z');
          GFileCtrl.DispatchCommand('files');
          Assert.IsTrue(not GOpenCalled, 'accept on an empty filtered list opens nothing');

          // Cancel.
          GFileCtrl.OpenList;
          GFileCtrl.DispatchCommand('cancel');
          Assert.IsTrue(not GOpenCalled and not Dialog.Visible, 'cancel closes without opening');
        finally
          FreeAndNil(GFileCtrl);
        end;
      finally
        Dialog.Free;
      end;
    end);
end;

{ TTestHistoryDialogs }

procedure TTestHistoryDialogs.TestFolderHistory;
begin
  TestHistoryDialogs.TestFolderHistory;
end;

procedure TTestHistoryDialogs.TestFileHistoryStore;
begin
  TestHistoryDialogs.TestFileHistoryStore;
end;

procedure TTestHistoryDialogs.TestFileHistoryDialog;
begin
  TestHistoryDialogs.TestFileHistoryDialog;
end;

procedure TTestHistoryDialogs.TestCmdHistoryOpenAndAccept;
begin
  TestHistoryDialogs.TestCmdHistoryOpenAndAccept;
end;

procedure TTestHistoryDialogs.TestCmdHistoryReject;
begin
  TestHistoryDialogs.TestCmdHistoryReject;
end;

procedure TTestHistoryDialogs.TestCmdHistoryFilter;
begin
  TestHistoryDialogs.TestCmdHistoryFilter;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHistoryDialogs);

end.
