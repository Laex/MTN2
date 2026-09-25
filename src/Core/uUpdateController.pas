unit uUpdateController;

{ Drives uUpdater from the UI: the quiet startup check, Help > Updates, and
  the user's answers. Nothing is downloaded or installed without the user
  choosing it:

    offer    "Version X is available"  -> Update / Later / Skip this version
    download (background, sha256-checked, unpacked into .update-staging)
    ready    "Restart now?"            -> Restart / On exit

  Restart swaps the files while MTN2 is still running (renaming loaded files
  is allowed), so a failure is reported and rolled back instead of leaving a
  half-installed folder behind; only then does it start the new exe (which
  waits for this process, see uUpdater.WaitForPreviousInstanceFromCommandLine)
  and close the form. "On exit" -- and "Restart" while a copy job is busy --
  installs from BeforeExit instead.

  Dialogs go through the panel window (TUpdateHost.ShowDialog); background
  work reports back via TThread.Queue, guarded by FLife so a callback that
  lands after the form is gone does nothing. }

interface

uses
  System.SysUtils, System.Classes, FMX.Types,
  uDialogTypes, uUpdater;

type
  TUpdateHost = record
    /// <summary>Opens a dialog; False while another one is up.</summary>
    ShowDialog: TFunc<TDialogDeclaration, TProc<string, string>, Boolean>;
    HasBusyJob: TFunc<Boolean>;
    /// <summary>Closes the main form through its normal exit path.</summary>
    RequestClose: TProc;
  end;

  TUpdateState = (usIdle, usChecking, usDownloading, usReady, usApplied);

  IUpdateLife = interface
    ['{4E0B2C71-8A33-4C55-9E3B-6B1C2A7D0F10}']
    function Alive: Boolean;
    function Cancelled: Boolean;
    procedure Kill;
  end;

  TUpdateController = class
  private
    FHost: TUpdateHost;
    FLife: IUpdateLife;
    FSettings: TUpdateSettings;
    FCurrent: string;
    FState: TUpdateState;
    FRelease: TUpdateRelease;
    FApplyOnExit: Boolean;
    FWorker: TThread;
    FRetryTimer: TTimer;
    /// <summary>A dialog that could not open (another one was up) and is
    /// retried by FRetryTimer.</summary>
    FPending: TProc;
    function RunWorker(const AWork: TProc): Boolean;
    procedure Show(const ADecl: TDialogDeclaration; const AOnCommand: TProc<string, string>);
    procedure RetryTick(Sender: TObject);
    procedure ShowMessageDlg(const AText, ADetails: string; const AOpenPage: Boolean = False);
    procedure StartCheck(AInteractive: Boolean);
    procedure CheckDone(AInteractive, AOk: Boolean; const ARelease: TUpdateRelease;
      const AError: string);
    procedure ShowOffer;
    procedure StartDownload;
    procedure DownloadDone(AOk: Boolean; const AError: string);
    procedure ShowReady;
    procedure RestartNow;
    procedure SaveSettings;
  public
    constructor Create(const AHost: TUpdateHost);
    destructor Destroy; override;
    /// <summary>Called once, a few seconds after startup: cleans up after a
    /// previous update and checks quietly if due (at most once a day).</summary>
    procedure StartupCheck;
    /// <summary>Help > Updates.</summary>
    procedure OpenUpdatesDialog;
    /// <summary>From FormClose: installs an update the user deferred.</summary>
    procedure BeforeExit;
    property CurrentVersion: string read FCurrent;
    property State: TUpdateState read FState;
  end;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.IOUtils, System.JSON,
  uStrings;

type
  TUpdateLife = class(TInterfacedObject, IUpdateLife)
  private
    FAlive: Boolean;
  public
    constructor Create;
    function Alive: Boolean;
    function Cancelled: Boolean;
    procedure Kill;
  end;

constructor TUpdateLife.Create;
begin
  inherited Create;
  FAlive := True;
end;

function TUpdateLife.Alive: Boolean;
begin
  Result := FAlive;
end;

function TUpdateLife.Cancelled: Boolean;
begin
  Result := not FAlive;
end;

procedure TUpdateLife.Kill;
begin
  FAlive := False;
end;

function JsonBoolField(const AJson, AName: string; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  Result := ADefault;
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if V is TJSONObject then
      Result := TJSONObject(V).GetValue<Boolean>(AName, ADefault);
  finally
    V.Free;
  end;
end;

function DownloadFileName(const ARelease: TUpdateRelease): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'MTN2-update'), ARelease.AssetName);
end;

{ TUpdateController }

constructor TUpdateController.Create(const AHost: TUpdateHost);
begin
  inherited Create;
  FHost := AHost;
  FLife := TUpdateLife.Create;
  FSettings := LoadUpdateSettings;
  FCurrent := AppVersionString;
  FState := usIdle;
  FRetryTimer := TTimer.Create(nil);
  FRetryTimer.Enabled := False;
  FRetryTimer.Interval := 5000;
  FRetryTimer.OnTimer := RetryTick;
end;

destructor TUpdateController.Destroy;
begin
  FLife.Kill; // queued callbacks become no-ops; a download aborts
  FreeAndNil(FRetryTimer);
  if Assigned(FWorker) then
  begin
    // Give a running check/download a moment to notice and finish; a thread
    // still blocked in the network is orphaned rather than blocking exit.
    if WaitForSingleObject(FWorker.Handle, 3000) = WAIT_OBJECT_0 then
      FWorker.Free
    else
      FWorker.FreeOnTerminate := True;
    FWorker := nil;
  end;
  inherited Destroy;
end;

function TUpdateController.RunWorker(const AWork: TProc): Boolean;
begin
  if Assigned(FWorker) then
  begin
    // One background job at a time. The previous one is normally the quick
    // startup cleanup; a check/download in flight is excluded by FState.
    if WaitForSingleObject(FWorker.Handle, 2000) <> WAIT_OBJECT_0 then
      Exit(False);
    FreeAndNil(FWorker);
  end;
  FWorker := TThread.CreateAnonymousThread(AWork);
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
  Result := True;
end;

procedure TUpdateController.Show(const ADecl: TDialogDeclaration;
  const AOnCommand: TProc<string, string>);
var
  Decl: TDialogDeclaration;
  Life: IUpdateLife;
  Guarded: TProc<string, string>;
begin
  Life := FLife;
  Guarded :=
    procedure(ACmd, AValues: string)
    begin
      if Life.Alive and Assigned(AOnCommand) then
        AOnCommand(ACmd, AValues);
    end;
  if Assigned(FHost.ShowDialog) and FHost.ShowDialog(ADecl, Guarded) then
    Exit;
  // Another dialog is open (or the form is busy): try again shortly rather
  // than dropping an answer the user is waiting for.
  Decl := ADecl;
  FPending :=
    procedure
    begin
      Show(Decl, AOnCommand);
    end;
  FRetryTimer.Enabled := True;
end;

procedure TUpdateController.RetryTick(Sender: TObject);
var
  P: TProc;
begin
  FRetryTimer.Enabled := False;
  P := FPending;
  FPending := nil;
  if Assigned(P) then
    P();
end;

procedure TUpdateController.ShowMessageDlg(const AText, ADetails: string; const AOpenPage: Boolean);
var
  Url: string;
begin
  if AOpenPage and (FRelease.HtmlUrl <> '') then
  begin
    Url := FRelease.HtmlUrl;
    Show(BuildUpdateMessageDialog(AText, ADetails, T('ui.update.openPage', 'Open page'),
      True),
      procedure(ACmd, AValues: string)
      begin
        if SameText(ACmd, cDlgCmdOk) then
          ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
      end);
  end
  else
    Show(BuildUpdateMessageDialog(AText, ADetails, '', False), nil);
end;

procedure TUpdateController.SaveSettings;
begin
  SaveUpdateSettings(FSettings);
end;

procedure TUpdateController.StartupCheck;
var
  Due: Boolean;
begin
  Due := (FCurrent <> '') and UpdateCheckDue(FSettings, Now);
  if not Due then
  begin
    // Still tidy up after a previous update, off the UI thread.
    RunWorker(
      procedure
      begin
        CleanupOldFiles(AppDir);
      end);
    Exit;
  end;
  StartCheck(False);
end;

procedure TUpdateController.OpenUpdatesDialog;
begin
  Show(BuildUpdatesDialog(FCurrent, FSettings.CheckOnStart),
    procedure(ACmd, AValues: string)
    begin
      FSettings.CheckOnStart := JsonBoolField(AValues, 'check_on_start',
        FSettings.CheckOnStart);
      SaveSettings;
      if SameText(ACmd, 'check') then
        StartCheck(True);
    end);
end;

procedure TUpdateController.StartCheck(AInteractive: Boolean);
var
  Life: IUpdateLife;
  Interactive: Boolean;
begin
  case FState of
    usChecking, usDownloading:
      Exit;
    usReady:
      begin
        ShowReady;
        Exit;
      end;
    usApplied:
      Exit;
  end;
  FState := usChecking;
  Life := FLife;
  Interactive := AInteractive;
  if not RunWorker(
    procedure
    var
      Rel: TUpdateRelease;
      Err: string;
      Ok: Boolean;
    begin
      CleanupOldFiles(AppDir);
      Ok := FetchLatestRelease(Rel, Err);
      TThread.Queue(nil,
        procedure
        begin
          if Life.Alive then
            CheckDone(Interactive, Ok, Rel, Err);
        end);
    end) then
    FState := usIdle;
end;

procedure TUpdateController.CheckDone(AInteractive, AOk: Boolean;
  const ARelease: TUpdateRelease; const AError: string);
begin
  FState := usIdle;
  if not AOk then
  begin
    if AInteractive then
      ShowMessageDlg(T('ui.update.failed', 'Could not update MTN2.'), AError);
    Exit;
  end;
  FSettings.LastCheck := Now;
  SaveSettings;
  FRelease := ARelease;
  if not IsNewerVersion(ARelease.Version, FCurrent) then
  begin
    if AInteractive then
      ShowMessageDlg(T('ui.update.upToDate', 'You have the latest version (%s).', [FCurrent]), '');
    Exit;
  end;
  if not AInteractive and SameText(FSettings.SkipVersion, ARelease.Version) then
    Exit;
  ShowOffer;
end;

procedure TUpdateController.ShowOffer;
begin
  Show(BuildUpdateOfferDialog(FRelease.Version, FCurrent),
    procedure(ACmd, AValues: string)
    begin
      if SameText(ACmd, 'update') then
        StartDownload
      else if SameText(ACmd, 'skip') then
      begin
        FSettings.SkipVersion := FRelease.Version;
        SaveSettings;
      end;
    end);
end;

procedure TUpdateController.StartDownload;
var
  Life: IUpdateLife;
  Rel: TUpdateRelease;
begin
  if FState <> usIdle then
    Exit;
  if not CanWriteToDir(AppDir) then
  begin
    ShowMessageDlg(T('ui.update.failed', 'Could not update MTN2.'),
      T('ui.update.noWrite', 'The program folder is not writable.'), True);
    Exit;
  end;
  FState := usDownloading;
  Life := FLife;
  Rel := FRelease;
  if not RunWorker(
    procedure
    var
      Zip, Err: string;
      Ok: Boolean;
    begin
      Zip := DownloadFileName(Rel);
      Ok := DownloadAsset(Rel, Zip,
        function(ADone, ATotal: Int64): Boolean
        begin
          Result := not Life.Cancelled;
        end, Err) and ExtractUpdate(Zip, StagingDir, Err);
      System.SysUtils.DeleteFile(Zip);
      TThread.Queue(nil,
        procedure
        begin
          if Life.Alive then
            DownloadDone(Ok, Err);
        end);
    end) then
    FState := usIdle;
end;

procedure TUpdateController.DownloadDone(AOk: Boolean; const AError: string);
begin
  if not AOk then
  begin
    FState := usIdle;
    ShowMessageDlg(T('ui.update.failed', 'Could not update MTN2.'), AError, True);
    Exit;
  end;
  FState := usReady;
  ShowReady;
end;

procedure TUpdateController.ShowReady;
begin
  Show(BuildUpdateMessageDialog(
    T('ui.update.ready', 'Version %s is downloaded and ready to install.', [FRelease.Version]),
    T('ui.update.readyDetails', 'Restart MTN2 now?'),
    T('ui.update.restartNow', 'Restart'), True, T('ui.update.onExit', 'On exit')),
    procedure(ACmd, AValues: string)
    begin
      if SameText(ACmd, cDlgCmdOk) then
        RestartNow
      else
        FApplyOnExit := True;
    end);
end;

procedure TUpdateController.RestartNow;
var
  Err: string;
begin
  if FState <> usReady then
    Exit;
  if Assigned(FHost.HasBusyJob) and FHost.HasBusyJob() then
  begin
    FApplyOnExit := True;
    ShowMessageDlg(T('ui.update.busy', 'Background jobs are running.'),
      T('ui.update.busyDetails', 'The update will be installed when MTN2 exits.'));
    Exit;
  end;
  if not ApplyStagedUpdate(StagingDir, AppDir, Err) then
  begin
    // Rolled back: this copy keeps running unchanged.
    FState := usIdle;
    ShowMessageDlg(T('ui.update.failed', 'Could not update MTN2.'), Err, True);
    Exit;
  end;
  FState := usApplied;
  if not RestartApplication(ParamStr(0), Err) then
  begin
    ShowMessageDlg(T('ui.update.failed', 'Could not update MTN2.'), Err);
    Exit; // installed; takes effect on the next manual start
  end;
  if Assigned(FHost.RequestClose) then
    FHost.RequestClose();
end;

procedure TUpdateController.BeforeExit;
var
  Err: string;
begin
  if (FState = usReady) and FApplyOnExit then
    if ApplyStagedUpdate(StagingDir, AppDir, Err) then
      FState := usApplied;
end;

end.
