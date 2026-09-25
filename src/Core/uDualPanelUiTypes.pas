unit uDualPanelUiTypes;

{ Overlay / dialog state records used by TDualPanelWindow.
  Extracted so the main window unit can shrink without changing behaviour. }

interface

uses
  System.Classes,
  uThemeTypes, uDualPanelTypes, uVfsTypes, uDriveInfo, uFileFind, uDisplaySettings;

type
  TDrivePopupState = record
    Visible: Boolean;
    Side: TPanelSide;
    Drives: TDriveInfoArray;
    CursorIndex: Integer;
    ScrollOffset: Integer;
    Bounds: TRectI;
  end;

  TPanelJobKind = (pjkNone, pjkCopy, pjkMove, pjkDelete, pjkPack, pjkUnpack);
  TPanelJobPhase = (pjpNone, pjpConfirm, pjpQueued, pjpRunning, pjpOverwriteAsk,
    pjpDeleteAsk, pjpIOErrorAsk, pjpError);
  TJobPresentation = (jpForeground, jpBackground);
  TJobOverwriteMode = (jomAsk, jomOverwrite, jomSkip);
  /// <summary>Per-file conflict answer when OverwriteMode=jomAsk.</summary>
  TJobConflictAction = (jcaOverwrite, jcaSkip, jcaRename, jcaAppend, jcaCancel);
  /// <summary>Answer when a delete item fails (Recycle Bin / permanent).</summary>
  TJobDeleteFailAction = (jdaPermanent, jdaRetry, jdaSkip, jdaSkipAll, jdaCancel);
  /// <summary>Answer when a copy/move transfer fails with an I/O error (not a
  /// name conflict — those go through TJobConflictAction) after the job's
  /// automatic retry budget (RetryLimit/RetryLeft) is exhausted.</summary>
  TJobIOErrorAction = (jioRetry, jioSkip, jioSkipAll, jioCancel);

  TPanelJobState = record
    Phase: TPanelJobPhase;
    Kind: TPanelJobKind;
    Id: Integer;
    Presentation: TJobPresentation;
    OriginSrcDirURI: string;
    OriginDstDirURI: string;
    /// <summary>When Kind=pjkDelete: True = Recycle Bin (F8), False = permanent (Shift+F8).</summary>
    DeleteToRecycleBin: Boolean;
    /// <summary>Skip remaining delete errors without prompting.</summary>
    SkipAllDeleteErrors: Boolean;
    /// <summary>Skip remaining copy/move I/O errors without prompting, for
    /// the rest of this job only (reset on the next BeginJob).</summary>
    SkipAllIOErrors: Boolean;
    Sources: TArray<string>;
    /// <summary>When Length=Sources, exact per-item destinations; else DestDirURI+name.</summary>
    DestURIs: TArray<string>;
    DestDirURI: string;
    OverwriteMode: TJobOverwriteMode;
    PreserveTimestamps: Boolean;
    OnlyNewer: Boolean;
    FollowSymlinks: Boolean;
    ExcludeMask: string;
    RetryLimit: Integer;
    RetryLeft: Integer;
    /// <summary>Sticky Ask answer for the rest of the job (None = keep asking).</summary>
    RememberedAction: TJobConflictAction;
    HasRememberedAction: Boolean;
    PendingSrcURI: string;
    PendingDstURI: string;
    PendingIndex: Integer;
    /// <summary>True when the pjpOverwriteAsk prompt is for a folder that
    /// already exists at the destination (not a real conflict — the actual
    /// per-file decisions happen inside CopyTree). Skip on this kind of
    /// prompt means "merge, don't overwrite conflicting files", not
    /// "abandon the whole subtree" — see ResolveOverwriteAsk.</summary>
    PendingBothDirs: Boolean;
    /// <summary>Error text for pjpDeleteAsk / pjpIOErrorAsk / pjpError.</summary>
    PendingErrorMessage: string;
    /// <summary>Overwrite/Append flags the failed transfer was run with, so
    /// pjpIOErrorAsk's Retry can re-run ExecuteTransfer identically.</summary>
    PendingTransferOverwrite: Boolean;
    PendingTransferAppend: Boolean;
    Index: Integer;
    /// <summary>Cumulative byte progress for the current top-level item
    /// (base + this: a recursive tree copy reports running totals across
    /// the whole tree here) — feeds the "Total" bar / Bytes counter.</summary>
    ProgressDone: Int64;
    ProgressTotal: Int64;
    /// <summary>Byte progress of just the single file currently being
    /// transferred — feeds the per-file bar. Equal to ProgressDone/Total for
    /// a plain single-file item; distinct inside a recursive tree copy.</summary>
    FileProgressDone: Int64;
    FileProgressTotal: Int64;
    /// <summary>Bytes already finished in prior items (Total = Base+ProgressDone).</summary>
    BytesDoneBase: Int64;
    /// <summary>Estimated total bytes for the job (grows as sizes are learned).</summary>
    BytesTotal: Int64;
    FilesTotal: Integer;
    /// <summary>Files actually finished transferring so far — counted per
    /// real file (including ones inside a recursive tree copy), not per
    /// top-level selected source. See TPanelJobController.NoteItemProgress /
    /// AdvanceJobAfterItem.</summary>
    FilesDone: Integer;
    CurrentName: string;
    CurrentSrcPath: string;
    CurrentDstPath: string;
    Message: string;
    Bounds: TRectI;
    Cancel: IJobCancelToken;
    /// <summary>Last ask-dialog copy so a deferred / FIFO ask can reopen
    /// the same overwrite / delete / I/O prompt.</summary>
    AskPath: string;
    AskNewLine: string;
    AskExistingLine: string;
    AskHeadline: string;
    AskQuestion: string;
    AskErrorLine: string;
    AskOfferPermanent: Boolean;
  end;

  TSortMenuItem = record
    Caption: string;
    HotChar: Char;
    HotPos: Integer; // 1-based in Caption, 0 = none (MenuResolveMnemonic)
    Shortcut: string;
    Column: TPanelSortColumn;
  end;

  TColumnModeMenuItem = record
    Caption: string;
    HotChar: Char;
    HotPos: Integer; // 1-based in Caption, 0 = none (MenuResolveMnemonic)
    Shortcut: string;
    Mode: TPanelColumnMode;
  end;

  TStubKind = (skNone, skShellInfo);
  THostDialogKind = (hdkNone, hdkMkDir, hdkNewFile, hdkRename, hdkCopyInPlace, hdkJobConfirm,
    hdkSearch,
    hdkHelp, hdkSelectMask, hdkUnselectMask, hdkOverwriteAsk, hdkOverwriteRename,
    hdkDeleteError, hdkFolderHistory, hdkDirSync, hdkTerminalProfile,
    hdkConsoleProfile, hdkCmdHistory, hdkFileHistory,
    hdkFolderHotlist, hdkFolderHotlistAdd, hdkFolderHotlistRename, hdkCreateLink,
    hdkCompareResult, hdkColorCoding, hdkColorCodingEdit, hdkColorPicker,     hdkTheme,
    hdkColumnsConfig, hdkDisplay, hdkArchivePassword, hdkTmpSaveList,
    hdkWorkspaceLibrary, hdkWorkspaceSave, hdkWorkspaceRename, hdkWorkspaceConfirm,
    hdkSetAttributes,
    hdkSshConnections, hdkSshConnectionEdit, hdkSshConnectionConfirm,
    hdkAssociations, hdkAssociationEdit, hdkAssociationConfirm,
    hdkUserMenuEdit, hdkUserMenuConfirm, hdkUserMenuPrompt,
    hdkKeymap, hdkKeymapEdit, hdkIOError, hdkJobList, hdkJobProgress,
    hdkWorkspaceTabRename, hdkExternalTools, hdkChecksumOptions, hdkChecksumResult,
    // Opened by the form (updater) via TDualPanelWindow.ShowHostDialog; the
    // command goes back to the opener's callback.
    hdkHost);

  /// <summary>Dialog-field values DialogCommand reads unconditionally before
  /// dispatching on FDialogKind — see DispatchDialogCommand. Each field is
  /// only meaningful to the branches that actually use it.</summary>
  TDialogCommandFields = record
    Name, Mask, Containing, DestPath, ExcludeMask, Password: string;
    ExistingIdx, RetryIdx: Integer;
    PreserveTs, OnlyNewer, FollowSymlinks, UseExclude, DryRun, Remember,
      Subdirs, CaseSens, WholeWords, SearchFolders, UseRegex, SyncTwoWay,
      SyncByContent: Boolean;
  end;

  TSearchPhase = (spNone, spDialog, spRunning, spResults);

  TSearchState = record
    Phase: TSearchPhase;
    Mask: string;
    ContainingText: string;
    Subdirs: Boolean;
    CaseSensitive: Boolean;
    WholeWords: Boolean;
    SearchFolders: Boolean;
    UseRegex: Boolean;
    FocusField: Integer; // legacy
    RootPath: string;
    Results: TArray<TFindHit>;
    Cursor: Integer;
    Scroll: Integer;
    FoundCount: Integer;
    CurrentDir: string;
    Message: string;
    Bounds: TRectI;
    Cancel: IJobCancelToken;
  end;

  TOpenViewerEvent = procedure(const AURI: string) of object;
  TOpenEditorEvent = procedure(const AURI: string) of object;
  /// <summary>Alt+Enter: TMainForm shows the OS Properties window (it owns
  /// the native window handle the shell call needs).</summary>
  TShowPropertiesEvent = procedure(const APaths: TArray<string>) of object;
  TRunCommandEvent = procedure(const ACommand, AWorkingDir: string) of object;
  TShellCwdSyncEvent = procedure(const APath: string) of object;
  TOpenTerminalEvent = procedure(const AProfileId, ACwd: string) of object;
  /// <summary>Background console dialog: TMainForm switches the persistent
  /// Ctrl+O console to this profile.</summary>
  TSetConsoleProfileEvent = procedure(const AProfileId: string) of object;
  TGetConsoleProfileEvent = function: string of object;
  /// <summary>Background console dialog: start the shell in FormCreate
  /// (True) or on the first Ctrl+O / command-line command (False).</summary>
  TGetConsoleStartOnLaunchEvent = function: Boolean of object;
  TSetConsoleStartOnLaunchEvent = procedure(AValue: Boolean) of object;
  TQuitRequestEvent = TNotifyEvent;
  /// <summary>Stage 27: Theme dialog reports the uThemeRegistry id the user
  /// picked / TMainForm reports which one is currently active.</summary>
  TThemeSelectEvent = procedure(const AThemeId: string) of object;
  TGetThemeIdEvent = function: string of object;
  TDisplaySettingsEvent = procedure(const ASettings: TDisplaySettings) of object;
  TGetDisplaySettingsEvent = function: TDisplaySettings of object;

implementation

end.
