unit uGitActions;

{ The commands that change the repository: add to the index, remove from it,
  commit, switch the branch. git runs on a worker thread with an entry in the
  host's job list; one command runs at a time. }

interface

uses
  System.SysUtils;

var
  /// <summary>Called on the main thread after git has changed something, or
  /// may have.</summary>
  GOnRepoChanged: TProc;

procedure CmdStage(AUserData: Pointer); cdecl;
procedure CmdUnstage(AUserData: Pointer); cdecl;
procedure CmdCommit(AUserData: Pointer); cdecl;
procedure CmdSwitch(AUserData: Pointer); cdecl;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.SyncObjs,
  uPluginHostAbi, uPluginSdk, uVfsTypes, uGitRepo, uGitDiff, uGitOps;

const
  cJobKey = 'git.action';
  cDialogWidth = 72;

type
  TGitAction = (gaStage, gaUnstage, gaListStaged, gaCommit, gaListBranches, gaSwitch);

var
  // Written on the main thread before the worker starts, and by the worker
  // before it posts its result back; the busy flag keeps the two apart.
  GBusy: Boolean;
  GCancel: Integer;
  GAction: TGitAction;
  GDir: string;
  GNames: TArray<string>;
  GArgument: string;
  GOk: Boolean;
  GOutput: string;
  GItems: TArray<string>;
  GBranch: string;
  /// <summary>The message of a commit that has not succeeded, offered again.</summary>
  GMessage: string;

procedure OnJobCancel(AUserData: Pointer); cdecl;
begin
  TInterlocked.Exchange(GCancel, 1);
end;

function Cancelled: Boolean;
begin
  Result := GShutdown or (TInterlocked.CompareExchange(GCancel, 0, 0) <> 0);
end;

{ ---- the worker --------------------------------------------------------- }

procedure ListStaged;
var
  Current, Ignored: string;
  Branches: TArray<string>;
begin
  GOk := GitStagedFiles(GDir, Cancelled, GItems, GOutput);
  // The branch is a caption only: the list of files decides about success.
  if GOk and GitBranches(GDir, Cancelled, Branches, Current, Ignored) then
    GBranch := Current;
end;

procedure RunGitAction;
begin
  case GAction of
    gaStage: GOk := GitStagePaths(GDir, GNames, Cancelled, GOutput);
    gaUnstage: GOk := GitUnstagePaths(GDir, GNames, Cancelled, GOutput);
    gaListStaged: ListStaged;
    gaCommit: GOk := GitCommitStaged(GDir, GArgument, Cancelled, GOutput);
    gaListBranches: GOk := GitBranches(GDir, Cancelled, GItems, GBranch, GOutput);
    gaSwitch: GOk := GitSwitchBranch(GDir, GArgument, Cancelled, GOutput);
  end;
end;

procedure MainDone(AUserData: Pointer); cdecl; forward;

procedure Start(AAction: TGitAction; const ATitle: string);
begin
  GAction := AAction;
  GOk := False;
  GOutput := '';
  GItems := nil;
  GBranch := '';
  GBusy := True;
  TInterlocked.Exchange(GCancel, 0);
  JobBeginNow(cJobKey, ATitle, OnJobCancel);
  SdkRunWorker(
    procedure
    begin
      try
        try
          RunGitAction;
        except
          on E: Exception do
          begin
            GOk := False;
            GOutput := E.Message;
          end;
        end;
      finally
        SdkPostToMain(MainDone);
      end;
    end);
end;

{ ---- results ------------------------------------------------------------ }

{ A one-line answer fits a notice; a longer one, a refused hook for one, opens
  in the viewer. }
procedure ShowFailure(const AOutput: string);
var
  Text, FileName: string;
  Uri: UTF8String;
begin
  Text := AOutput.Replace(#13, '').Trim;
  if Text = '' then
    Text := Tr('msg.error', 'git did not answer.');
  if (Pos(#10, Text) > 0) and Assigned(GHostApi.OpenDocument) then
  begin
    FileName := TPath.Combine(TPath.GetTempPath, 'mtn2-git-output.txt');
    TFile.WriteAllText(FileName, Text, TEncoding.UTF8);
    Uri := UTF8String(PathToFileUri(FileName));
    if GHostApi.OpenDocument(PAnsiChar(Uri), 0) = 0 then
      Exit;
  end;
  Notice(Text, 1);
end;

function DialogValue(AValuesJson: PAnsiChar; const AName: string): string;
var
  Root: TJSONValue;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
  try
    if Root is TJSONObject then
      Root.TryGetValue<string>(AName, Result);
  finally
    Root.Free;
  end;
end;

procedure AddList(AChildren: TJSONArray; const AId: string; const AItems: TArray<string>;
  ASelected, ARow, AHeight: Integer);
var
  List: TJSONObject;
  Items: TJSONArray;
  Item: string;
begin
  List := TJSONObject.Create;
  List.AddPair('type', 'list');
  List.AddPair('id', AId);
  Items := TJSONArray.Create;
  for Item in AItems do
    Items.Add(Item);
  List.AddPair('items', Items);
  List.AddPair('selected', TJSONNumber.Create(ASelected));
  List.AddPair('col', TJSONNumber.Create(2));
  List.AddPair('row', TJSONNumber.Create(ARow));
  List.AddPair('width', TJSONNumber.Create(cDialogWidth - 6));
  List.AddPair('height', TJSONNumber.Create(AHeight));
  AChildren.AddElement(List);
end;

procedure AddButtons(AChildren: TJSONArray; const AOkText: string; ARow: Integer);
begin
  AddItem(AChildren, 'button', 'ok', AOkText, cDialogWidth div 2 - 16, ARow, 14, True);
  AddItem(AChildren, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), cDialogWidth div 2 + 1,
    ARow, 12, False, True);
end;

function BranchCaption(const ABranch: string): string;
begin
  if ABranch = '' then
    Result := Tr('dlg.detached', '(detached HEAD)')
  else
    Result := ABranch;
end;

{ ---- commit ------------------------------------------------------------- }

procedure OnCommitDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
begin
  try
    if not SameText(string(AControlId), 'ok') or GBusy then
      Exit;
    GMessage := DialogValue(AValuesJson, 'message').Trim;
    if GMessage = '' then
    begin
      Notice(Tr('msg.noMessage', 'The commit message is empty.'), 1);
      Exit;
    end;
    GArgument := GMessage;
    Start(gaCommit, Tr('msg.commitJob', 'Git commit'));
  except
  end;
end;

procedure ShowCommitDialog;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
begin
  if Length(GItems) = 0 then
  begin
    Notice(Tr('msg.nothingStaged', 'Nothing is in the index. Add files first.'), 0);
    Exit;
  end;
  Decl := NewDialog(Tr('dlg.commitTitle', 'Git commit'), cDialogWidth, 18, Kids);
  try
    AddItem(Kids, 'label', '', Tr('dlg.message', 'Message:'), 2, 1, cDialogWidth - 6);
    AddField(Kids, 'message', GMessage, 2, 2, cDialogWidth - 6);
    AddItem(Kids, 'label', '', Format('%s %s - %d', [Tr('dlg.staged', 'In the index of'),
      BranchCaption(GBranch), Length(GItems)]), 2, 4, cDialogWidth - 6);
    AddList(Kids, 'files', GItems, 0, 5, 8);
    AddButtons(Kids, Tr('dlg.commit', 'Commit'), 14);
    ShowDeclaration(Decl, OnCommitDialog);
  finally
    Decl.Free;
  end;
end;

{ ---- switch ------------------------------------------------------------- }

procedure OnSwitchDialog(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Branch: string;
begin
  try
    if not SameText(string(AControlId), 'ok') or GBusy then
      Exit;
    Branch := DialogValue(AValuesJson, 'branch');
    if (Branch = '') or (Branch = GBranch) then
      Exit;
    GArgument := Branch;
    Start(gaSwitch, Tr('msg.switchJob', 'Git switch branch'));
  except
  end;
end;

procedure ShowSwitchDialog;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  I, Selected: Integer;
begin
  if Length(GItems) = 0 then
  begin
    Notice(Tr('msg.noBranches', 'The repository has no branches yet.'), 0);
    Exit;
  end;
  Selected := 0;
  for I := 0 to High(GItems) do
    if GItems[I] = GBranch then
      Selected := I;
  Decl := NewDialog(Tr('dlg.switchTitle', 'Git switch branch'), cDialogWidth, 18, Kids);
  try
    AddItem(Kids, 'label', '', Tr('dlg.current', 'Current:') + ' ' + BranchCaption(GBranch),
      2, 1, cDialogWidth - 6);
    AddList(Kids, 'branch', GItems, Selected, 3, 10);
    AddButtons(Kids, Tr('dlg.switch', 'Switch'), 14);
    ShowDeclaration(Decl, OnSwitchDialog);
  finally
    Decl.Free;
  end;
end;

{ ---- completion --------------------------------------------------------- }

procedure RepoChanged;
begin
  if Assigned(GOnRepoChanged) then
    GOnRepoChanged();
end;

procedure Finish;
begin
  case GAction of
    gaListStaged: ShowCommitDialog;
    gaListBranches: ShowSwitchDialog;
    gaStage: Notice(Tr('msg.staged', 'Added to the index.'), 0);
    gaUnstage: Notice(Tr('msg.unstaged', 'Removed from the index.'), 0);
    gaCommit:
      begin
        GMessage := '';
        Notice(Tr('msg.committed', 'Committed.'), 0);
      end;
    gaSwitch:
      begin
        Notice(Tr('msg.switched', 'Switched to') + ' ' + GArgument, 0);
        // The files on disk are those of the other branch.
        if Assigned(GHostApi.PanelRefresh) then
          GHostApi.PanelRefresh();
      end;
  end;
end;

procedure MainDone(AUserData: Pointer); cdecl;
begin
  try
    JobEndNow(cJobKey);
    GBusy := False;
    // A command stopped halfway may have changed part of what it was given.
    if not (GAction in [gaListStaged, gaListBranches]) then
      RepoChanged;
    if TInterlocked.CompareExchange(GCancel, 0, 0) <> 0 then
      Notice(Tr('msg.cancelled', 'Cancelled.'), 0)
    else if GOk then
      Finish
    else
      ShowFailure(GOutput);
  except
  end;
end;

{ ---- commands ----------------------------------------------------------- }

{ The folder of the active panel when it is inside a git working tree. }
function RepoFolder(out ADir: string): Boolean;
var
  Info: TJSONValue;
  Active, Uri: string;
  Side: TJSONValue;
begin
  ADir := '';
  Info := TJSONObject.ParseJSONValue(HostText(GHostApi.PanelInfo));
  try
    if (Info is TJSONObject) and Info.TryGetValue<string>('active', Active) then
    begin
      Side := TJSONObject(Info).GetValue(Active);
      if (Side is TJSONObject) and Side.TryGetValue<string>('uri', Uri) and
         Uri.StartsWith('file:', True) then
        ADir := FileUriToPath(Uri);
    end;
  finally
    Info.Free;
  end;
  Result := (ADir <> '') and IsInsideGitWorkTree(ADir);
  if not Result then
    Notice(Tr('msg.notRepo', 'This folder is not in a git working tree.'), 0);
end;

{ The names of the marked rows, or of the row under the cursor. }
function ChosenNames: TArray<string>;
var
  DirUri: string;
  Names: TArray<string>;
begin
  Names := nil;
  ForEachSelectedRow(DirUri,
    procedure(ARow: TJSONObject)
    var
      Uri: string;
    begin
      if ARow.TryGetValue<string>('uri', Uri) and Uri.StartsWith('file:', True) then
        Names := Names + [ExtractFileName(ExcludeTrailingPathDelimiter(FileUriToPath(Uri)))];
    end);
  Result := Names;
end;

procedure StartOnNames(AAction: TGitAction; const ATitle: string);
begin
  if GBusy or not RepoFolder(GDir) then
    Exit;
  GNames := ChosenNames;
  if Length(GNames) = 0 then
  begin
    Notice(Tr('msg.noFile', 'Put the cursor on a file or folder of a local git folder.'), 0);
    Exit;
  end;
  Start(AAction, ATitle);
end;

procedure CmdStage(AUserData: Pointer); cdecl;
begin
  try
    StartOnNames(gaStage, Tr('msg.stageJob', 'Git add'));
  except
  end;
end;

procedure CmdUnstage(AUserData: Pointer); cdecl;
begin
  try
    StartOnNames(gaUnstage, Tr('msg.unstageJob', 'Git remove from the index'));
  except
  end;
end;

procedure CmdCommit(AUserData: Pointer); cdecl;
begin
  try
    if not GBusy and RepoFolder(GDir) then
      Start(gaListStaged, Tr('msg.commitJob', 'Git commit'));
  except
  end;
end;

procedure CmdSwitch(AUserData: Pointer); cdecl;
begin
  try
    if not GBusy and RepoFolder(GDir) then
      Start(gaListBranches, Tr('msg.switchJob', 'Git switch branch'));
  except
  end;
end;

end.
