unit uPluginHostAbi;

{ Cross-Platform x64 C-Compatible Host ABI Layer for MTN2 Plugins.
  All exported functions use cdecl calling convention, 64-bit data structures,
  and UTF-8 string encoding (PAnsiChar) for binary compatibility on Win64, Linux x64, macOS x64.

  Plugin-side contract (exported by the plugin DLL, see uPluginLoader.pas):
    function mtn_plugin_get_abi_version: Int64; cdecl;
    function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;   // 0 = success
    procedure mtn_plugin_shutdown; cdecl;
    function mtn_plugin_set_secret(AKeyUtf8, AValueUtf8: PAnsiChar): Int64; cdecl;
      // optional: archive password. Missing export is not a load failure.
      // AValueUtf8 = nil clears; empty string is a valid password.

  Host-side contract (this unit): a THostApiTable of cdecl function pointers
  is handed to the plugin's mtn_plugin_init. The pointer remains valid until
  mtn_plugin_shutdown (uPluginLoader keeps a heap copy per plugin). Plugins
  that stash AHostApi must not use it after shutdown; copying the record by
  value is also valid because the function pointers themselves are stable.
  The plugin calls back into the host through it - publish/invalidate for
  cross-cutting notifications, Register* to extend VFS/panels/keymap/menu/
  dialogs. Every host-side function wraps its Pascal body in try/except so
  an exception raised while servicing a plugin call can never unwind across
  the cdecl boundary into the plugin (which would corrupt the plugin's C
  runtime stack). }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  uMessageBus;

{$ALIGN 8} // 64-bit 8-byte structure alignment

const
  /// <summary>Bumped whenever THostApiTable gains fields. The table only
  /// grows at the end, so a plugin built against an older version reads a
  /// prefix of the table the host hands out and keeps working. Plugins must
  /// check this via mtn_plugin_get_abi_version before trusting the table
  /// (see uPluginLoader.TPluginLoader.LoadPluginsFrom).
  /// 2: RegisterCommand, RegisterCommandHook, ExecuteCommand,
  /// RegisterDocumentProvider, OpenExternal, ShowDialog, RegisterPanelActivate,
  /// SetCommandCaption, SetStatusSegment, RegisterSettings, GetSetting, SetSetting,
  /// SurfaceOpen, SurfaceSetFrame, SurfaceSetInfo, SurfaceSetTimer, SurfaceClose,
  /// HostInfo, DocInfo, DocGetText, DocReplace, DocSetCursor, PanelInfo, PanelGoto,
  /// PanelRefresh, ClipboardGet, ClipboardSet, ShowMessage, Subscribe, PanelList,
  /// PanelSetCursor, PanelSelect, DocSetSelection, DocLine, PostToMain, ProgressSet,
  /// ProgressEnd, SurfaceOpenEx, SurfaceSetFullscreen, SurfaceNativeHandle,
  /// RegisterHighlighter, VfsList, VfsExists, VfsRead, VfsOpen, VfsSize, VfsReadAt,
  /// VfsClose, VfsCancel, SurfaceGetFullscreen.
  /// 3: Translate.
  /// 4: RegisterDriveItem, RegisterVfsSchemeV2, SetPanelFBar, SetStatusSegmentStyled.</summary>
  cPluginAbiVersion: Int64 = 4;
  /// <summary>Oldest plugin ABI version the host still loads.</summary>
  cPluginMinAbiVersion: Int64 = 1;

type
  /// <summary>C-compatible VFS callbacks table (cdecl calling convention).
  /// Mirrors IVirtualFileSystem (uVfsTypes.pas) one-to-one, but synchronous:
  /// the host-side adapter (uVfsCdeclAdapter.TCdeclVfsBackend) runs each call
  /// on a background thread and turns it back into the async IVirtualFileSystem
  /// shape expected by the rest of the app.
  ///
  /// Buffer-fill functions (ListDirectory/ReadText/ReadBytes) write into a
  /// caller-supplied buffer of ABufSize bytes. On success (result = 0), the
  /// plugin MUST set ANegotiatedSize to the number of bytes written.
  /// If the encoded result doesn't fit, the plugin must not write partial
  /// data, set ANegotiatedSize to the required size, and return
  /// verNeedsBiggerBuffer (see TVfsCdeclResult). The host adapter currently
  /// treats that as a hard failure (no retry) - plugins should keep
  /// listings/reads within a practical single-shot size
  /// (uVfsCdeclAdapter.cCdeclVfsBufferSize, 4 MB by default).
  ///
  /// ListDirectory's ABuf receives a UTF-8 JSON array; see
  /// uVfsCdeclAdapter.EntriesFromJson for the exact per-entry field names.</summary>
  TVfsCallbacksCdecl = record
    ListDirectory: function(AURI: PAnsiChar; AUserData: Pointer;
      ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
    Delete: function(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer): Int64; cdecl;
    CreateDirectory: function(AURI: PAnsiChar; AUserData: Pointer): Int64; cdecl;
    CopyItem: function(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
      AUserData: Pointer): Int64; cdecl;
    MoveItem: function(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
      AUserData: Pointer): Int64; cdecl;
    ReadText: function(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
      ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
    ReadBytes: function(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
      ABuf: PByte; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
    WriteText: function(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer): Int64; cdecl;
    Exists: function(AURI: PAnsiChar; AUserData: Pointer; out AIsDirectory: Int64): Int64; cdecl;
    GetFreeSpace: function(ARootURI: PAnsiChar; AUserData: Pointer;
      out AFree, ATotal: Int64): Int64; cdecl;
  end;
  PVfsCallbacksCdecl = ^TVfsCallbacksCdecl;

  /// <summary>Result codes returned by TVfsCallbacksCdecl methods (0 = ok).
  /// verCancelled, verAuthFailed and verTimeout are understood by the version 2
  /// table only; verAuthFailed and verTimeout appear as "access denied" and
  /// "I/O error" with the text the plugin gave through SetErrorText.</summary>
  TVfsCdeclResult = (
    verOk = 0,
    verNotFound = 1,
    verAccessDenied = 2,
    verAlreadyExists = 3,
    verNotSupported = 4,
    verIOError = 5,
    verInvalidURI = 6,
    verNeedsBiggerBuffer = 7,
    verCancelled = 8,
    verAuthFailed = 9,
    verTimeout = 10
  );

  PVfsOpContext = ^TVfsOpContext;
  /// <summary>Handed to every call of a version 2 VFS table. The plugin reports
  /// progress and polls for cancellation through it while the call runs; the
  /// host owns the record and it is valid until the call returns. Calls may
  /// come from any thread (the one running the VFS call).
  /// ReportProgress: ADone/ATotal count the whole operation (bytes, or items
  /// when the size is not known; ATotal 0 = unknown), AItemDone/AItemTotal the
  /// file being transferred, AName its name (nil = none). Returns 1 when the
  /// user cancelled; the plugin should stop and return verCancelled.
  /// IsCancelled: 1 when the user cancelled.
  /// SetErrorText: text (UTF-8) the host shows with the error the call returns.</summary>
  TVfsOpContext = record
    Cookie: Pointer;
    ReportProgress: function(ACtx: PVfsOpContext; ADone, ATotal, AItemDone,
      AItemTotal: Int64; AName: PAnsiChar): Int64; cdecl;
    IsCancelled: function(ACtx: PVfsOpContext): Int64; cdecl;
    SetErrorText: procedure(ACtx: PVfsOpContext; AText: PAnsiChar); cdecl;
  end;

  /// <summary>VFS callbacks of ABI 4. Like TVfsCallbacksCdecl, every call gets
  /// the operation context, and:
  /// ListDirectory returns the entries from index AOffset on (JSON array as in
  /// version 1) and sets AMore to 1 when entries follow; the host calls again
  /// with AOffset advanced by the number of entries it received, so the plugin
  /// keeps the listing for the duration of one list operation.
  /// CopyItem / MoveItem: AFlags bit 0 = overwrite, bit 1 = keep timestamps.
  /// One side of a copy is always a local file:// URI unless both URIs belong
  /// to this plugin. When the result does not fit the buffer the plugin returns
  /// verNeedsBiggerBuffer with ANegotiatedSize set to the size it needs, and
  /// the host calls again with a buffer that big (up to 256 MB).</summary>
  TVfsCallbacksCdeclV2 = record
    ListDirectory: function(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
      AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
      out AMore: Int64): Int64; cdecl;
    Delete: function(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer;
      ACtx: PVfsOpContext): Int64; cdecl;
    CreateDirectory: function(AURI: PAnsiChar; AUserData: Pointer;
      ACtx: PVfsOpContext): Int64; cdecl;
    CopyItem: function(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
      ACtx: PVfsOpContext): Int64; cdecl;
    MoveItem: function(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
      ACtx: PVfsOpContext): Int64; cdecl;
    ReadText: function(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
      ACtx: PVfsOpContext; ABuf: PAnsiChar; ABufSize: Int64;
      out ANegotiatedSize: Int64): Int64; cdecl;
    ReadBytes: function(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
      ACtx: PVfsOpContext; ABuf: PByte; ABufSize: Int64;
      out ANegotiatedSize: Int64): Int64; cdecl;
    WriteText: function(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer;
      ACtx: PVfsOpContext): Int64; cdecl;
    Exists: function(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
      out AIsDirectory: Int64): Int64; cdecl;
    GetFreeSpace: function(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
      out AFree, ATotal: Int64): Int64; cdecl;
  end;
  PVfsCallbacksCdeclV2 = ^TVfsCallbacksCdeclV2;

  { C-ABI Host Function Pointers - handed to the plugin at init time. }
  THostPublishFn = function(APluginId, ATopicUtf8, APayloadJsonUtf8: PAnsiChar): Int64; cdecl;
  THostInvalidateFn = function(AWindowId: Int64): Int64; cdecl;
  THostRegisterVfsSchemeFn = function(APluginId, AScheme: PAnsiChar;
    ACallbacks: PVfsCallbacksCdecl; AUserData: Pointer; APriority: Int64): Int64; cdecl;
  THostRegisterPanelPluginFn = function(APluginId, AScheme: PAnsiChar;
    APriority: Int64): Int64; cdecl;
  THostRegisterKeyBindingFn = function(APluginId, AAction, AKeyCombo: PAnsiChar): Int64; cdecl;
  THostRegisterMenuItemCallback = procedure(AUserData: Pointer); cdecl;
  THostRegisterMenuItemFn = function(APluginId, AParentPath, AItemId, ACaption: PAnsiChar;
    AOnClick: THostRegisterMenuItemCallback; AUserData: Pointer; APriority: Int64): Int64; cdecl;
  /// <summary>Handler of a plugin command (see RegisterCommand).</summary>
  THostCommandCallback = procedure(AUserData: Pointer); cdecl;
  /// <summary>Hook on a built-in command (see RegisterCommandHook). ACommand
  /// is the built-in command name ("Copy"), AOrigin is "key" or "menu".
  /// Returns 1 when the plugin handled the command (the built-in handler is
  /// skipped), 0 to let it run.</summary>
  THostCommandHookCallback = function(AUserData: Pointer;
    ACommand, AOrigin: PAnsiChar): Int64; cdecl;
  /// <summary>Adds the plugin command ACommandId. Run from ExecuteCommand and
  /// from a key chord bound with RegisterKeyBinding, whose AAction is then
  /// this command id. 0 = ok, -1 = refused (empty id, built-in name, id owned
  /// by another plugin).</summary>
  THostRegisterCommandFn = function(APluginId, ACommandId: PAnsiChar;
    AOnRun: THostCommandCallback; AUserData: Pointer): Int64; cdecl;
  /// <summary>Hooks the built-in command ACommand (a keymap action name such
  /// as "Copy", "View", "Delete"): the hook runs before the built-in handler,
  /// ascending APriority. 0 = ok, -1 = unknown command name.</summary>
  THostRegisterCommandHookFn = function(APluginId, ACommand: PAnsiChar;
    AHook: THostCommandHookCallback; AUserData: Pointer; APriority: Int64): Int64; cdecl;
  /// <summary>Runs a plugin command by id. 0 = ran, -1 = no such command or it
  /// failed.</summary>
  THostExecuteCommandFn = function(ACommandId: PAnsiChar): Int64; cdecl;
  /// <summary>Asked when the host opens a file the provider registered for.
  /// AMode is "view" or "edit". Returns 0 = not mine (the next provider, then
  /// the built-in window, runs), 1 = the plugin opened the file itself,
  /// 2 = open the URI the plugin wrote into ARedirect (UTF-8, NUL-terminated,
  /// at most ARedirectCap bytes) in the built-in window instead.</summary>
  THostDocumentProviderCallback = function(AUserData: Pointer; AURI, AMode: PAnsiChar;
    ARedirect: PAnsiChar; ARedirectCap: Int64): Int64; cdecl;
  /// <summary>Registers a provider for the file name extensions in
  /// AExtensions (comma-separated, ".md,.markdown"; "*" = all files).
  /// AModes: bit 0 = view (F3), bit 1 = edit (F4). Providers run in ascending
  /// APriority before the built-in viewer / editor. 0 = ok, -1 = refused.</summary>
  THostRegisterDocumentProviderFn = function(APluginId, AExtensions: PAnsiChar;
    AModes: Int64; AHandler: THostDocumentProviderCallback; AUserData: Pointer;
    APriority: Int64): Int64; cdecl;
  /// <summary>Answer of a plugin dialog: the control id that closed it and the
  /// values of the dialog as JSON (see DIALOG_PLUGIN.md).</summary>
  THostDialogCommandCallback = procedure(AUserData: Pointer;
    AControlId, AValuesJson: PAnsiChar); cdecl;
  /// <summary>Shows a modal dialog described by ADeclJson (the declaration
  /// format of the built-in dialogs). Any button, Enter or Esc closes it and
  /// calls AOnCommand once, on the main thread. 0 = shown, -1 = invalid
  /// declaration or no dialog can be shown now (another one is open, the host
  /// is not over the panels).</summary>
  THostShowDialogFn = function(APluginId, ADeclJson: PAnsiChar;
    AOnCommand: THostDialogCommandCallback; AUserData: Pointer): Int64; cdecl;
  /// <summary>Asked when the user activates a row of a panel whose URI has the
  /// registered scheme (Enter, double click; not the ".." row). Returns 1 when
  /// the plugin dealt with the row (the host does nothing more), 0 to let the
  /// host go on.</summary>
  THostPanelActivateCallback = function(AUserData: Pointer;
    APanelURI, ARowURI: PAnsiChar; AIsDirectory: Int64): Int64; cdecl;
  /// <summary>Registers the activation handler for panels showing AScheme
  /// ("file" for local folders). 0 = ok, -1 = refused.</summary>
  THostRegisterPanelActivateFn = function(APluginId, AScheme: PAnsiChar;
    AHandler: THostPanelActivateCallback; AUserData: Pointer): Int64; cdecl;
  /// <summary>Sets the short label the function bar shows for the plugin
  /// command ACommandId (the F-key its chord is bound to). Empty clears it.
  /// 0 = ok, -1 = unknown command or not owned by the plugin.</summary>
  THostSetCommandCaptionFn = function(APluginId, ACommandId, ACaption: PAnsiChar): Int64; cdecl;
  /// <summary>Sets (empty text removes) a named segment of the status line of
  /// the file panels. The host draws it; colors stay the theme's. 0 = ok.</summary>
  THostSetStatusSegmentFn = function(APluginId, ASegmentId, AText: PAnsiChar): Int64; cdecl;
  /// <summary>Registers the handler the Plugins dialog calls when the user presses
  /// "Settings" for this plugin. The handler shows the plugin's dialog (ShowDialog)
  /// and stores the result with SetSetting. 0 = ok.</summary>
  THostRegisterSettingsFn = function(APluginId: PAnsiChar;
    AOnConfigure: THostCommandCallback; AUserData: Pointer): Int64; cdecl;
  /// <summary>Reads a value of the plugin's own key/value store (the host keeps it
  /// in the settings folder). Writes the UTF-8 value and a NUL into ABuf and returns
  /// the value's length in bytes; -1 = never set, -2 = ABuf (ABufSize bytes) is too
  /// small.</summary>
  THostGetSettingFn = function(APluginId, AKey: PAnsiChar; ABuf: PAnsiChar;
    ABufSize: Int64): Int64; cdecl;
  /// <summary>Stores a value in the plugin's key/value store. 0 = stored, -1 = the
  /// settings file could not be written (the value holds for this run).</summary>
  THostSetSettingFn = function(APluginId, AKey, AValue: PAnsiChar): Int64; cdecl;
  /// <summary>Opens a local file:// URI with the program the system associates
  /// with it (native plugins only). 0 = started, -1 = refused or failed.</summary>
  THostOpenExternalFn = function(AURI: PAnsiChar): Int64; cdecl;

  /// <summary>A key pressed on a picture surface, named like "Left", "Space", "Ctrl+C",
  /// "+". Returns 1 when the plugin used the key.</summary>
  THostSurfaceKeyCallback = function(AUserData: Pointer; AKey: PAnsiChar): Int64; cdecl;
  /// <summary>Timer tick of a picture surface (see SurfaceSetTimer).</summary>
  THostSurfaceTickCallback = procedure(AUserData: Pointer); cdecl;
  /// <summary>The user closed the surface's tab. Not called when the plugin closed it.</summary>
  THostSurfaceClosedCallback = procedure(AUserData: Pointer); cdecl;
  /// <summary>Opens a viewer tab that shows a picture the plugin supplies (see
  /// SurfaceSetFrame). Any of the callbacks may be nil. Returns the surface handle
  /// (above 0), or -1 when no tab can be opened now (the host is not over the
  /// panels).</summary>
  THostSurfaceOpenFn = function(APluginId, ATitle: PAnsiChar; AOnKey: THostSurfaceKeyCallback;
    AOnTick: THostSurfaceTickCallback; AOnClosed: THostSurfaceClosedCallback;
    AUserData: Pointer): Int64; cdecl;
  /// <summary>Replaces the picture: AWidth x AHeight pixels of 4 bytes in B, G, R, A
  /// order, rows top to bottom without padding, ALength bytes in all. The host
  /// copies them, fits the picture into the tab and centers it. 0 = shown,
  /// -1 = unknown handle or the length does not match the size.</summary>
  THostSurfaceSetFrameFn = function(AHandle, AWidth, AHeight: Int64; APixels: PByte;
    ALength: Int64): Int64; cdecl;
  /// <summary>Sets the tab title and the text of the status line (either may be empty).
  /// 0 = ok, -1 = unknown handle.</summary>
  THostSurfaceSetInfoFn = function(AHandle: Int64; ATitle, AStatus: PAnsiChar): Int64; cdecl;
  /// <summary>Calls the tick callback every AIntervalMs milliseconds while the tab is
  /// on screen (a video player pulls its next frame there); 0 stops it. 0 = ok,
  /// -1 = unknown handle.</summary>
  THostSurfaceSetTimerFn = function(AHandle, AIntervalMs: Int64): Int64; cdecl;
  /// <summary>Closes the tab; no callback follows. 0 = closed, -1 = unknown handle.</summary>
  THostSurfaceCloseFn = function(AHandle: Int64): Int64; cdecl;

  /// <summary>Functions that return text (HostInfo, DocInfo, DocGetText, PanelInfo,
  /// ClipboardGet) share one convention: the result is the length of the UTF-8
  /// text in bytes; the text and a NUL are written to ABuf only when
  /// length < ABufSize, so a result >= ABufSize means "too small, call again with
  /// ABufSize above the result" (a nil ABuf measures). -1 = not available.</summary>
  THostTextOutFn = function(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
  /// <summary>Text of the active document in the viewer / editor: AWhat 0 = the
  /// selection (empty when nothing is selected), 1 = the whole document with LF
  /// line breaks, 2 = the line with the cursor. -1 = no text document on screen
  /// (the panels, a picture tab, the hex view).</summary>
  THostDocGetTextFn = function(AWhat: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
  /// <summary>Replaces that text as one undo step (AWhat 0 with no selection inserts at
  /// the cursor; 1 replaces the document; 2 the cursor line). 0 = done, -1 = no
  /// editable text document.</summary>
  THostDocReplaceFn = function(AWhat: Int64; AText: PAnsiChar): Int64; cdecl;
  /// <summary>Moves the cursor of the document (0-based line and column). 0 = done.</summary>
  THostDocSetCursorFn = function(ARow, ACol: Int64): Int64; cdecl;
  /// <summary>Opens a URI in a file panel: ASide 0 = left, 1 = right, -1 = the active one.
  /// 0 = done, -1 = the panels are not on screen or a dialog is open.</summary>
  THostPanelGotoFn = function(ASide: Int64; AURI: PAnsiChar): Int64; cdecl;
  THostPanelRefreshFn = function: Int64; cdecl;
  /// <summary>Puts plain text on the system clipboard. 0 = done.</summary>
  THostClipboardSetFn = function(AText: PAnsiChar): Int64; cdecl;
  /// <summary>Shows a short notice (AKind 0 = information, 1 = warning). 0 = shown.</summary>
  THostShowMessageFn = function(AText: PAnsiChar; AKind: Int64): Int64; cdecl;
  /// <summary>A host event: "doc.opened", "doc.saved" or "doc.closed" with the payload
  /// {"uri": "..."}.</summary>
  THostEventCallback = procedure(AUserData: Pointer; ATopic, APayloadJson: PAnsiChar); cdecl;
  /// <summary>Calls AOnEvent for the events of ATopic ("*" = all of them). The same
  /// plugin subscribing to a topic again replaces its callback. 0 = ok.</summary>
  THostSubscribeFn = function(APluginId, ATopic: PAnsiChar; AOnEvent: THostEventCallback;
    AUserData: Pointer): Int64; cdecl;

  /// <summary>JSON list of the rows of a panel (ASide 0 = left, 1 = right, -1 = active):
  /// "uri" of the folder, "cursor" (index in "rows"), "rows" of {uri, name, dir, size}.
  /// Text-out convention as above; -1 = the panels are not on screen.</summary>
  THostPanelListFn = function(ASide: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
  /// <summary>Puts the cursor of a panel on the row AURI. A row of another folder is
  /// shown by going to that folder; the cursor follows when it is listed. 0 = done.</summary>
  THostPanelSetCursorFn = function(ASide: Int64; AURI: PAnsiChar): Int64; cdecl;
  /// <summary>Selection of a panel: AMode 0 = select the files matching the mask AArg
  /// ("*.txt"), 1 = unselect them, 2 = clear, 3 = select the row AArg (URI), 4 = unselect it.
  /// 0 = done.</summary>
  THostPanelSelectFn = function(ASide, AMode: Int64; AArg: PAnsiChar): Int64; cdecl;
  /// <summary>Selects from (row1, col1) to (row2, col2), 0-based; the cursor goes to the end.</summary>
  THostDocSetSelectionFn = function(ARow1, ACol1, ARow2, ACol2: Int64): Int64; cdecl;
  /// <summary>One line of the document by index (text-out convention).</summary>
  THostDocLineFn = function(AIndex: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
  /// <summary>Called on the main thread by PostToMain.</summary>
  THostMainCallback = procedure(AUserData: Pointer); cdecl;
  /// <summary>Runs ACallback on the main thread; the only host function that may be called
  /// from any thread. Dropped when the plugin has been unloaded. 0 = queued.</summary>
  THostPostToMainFn = function(APluginId: PAnsiChar; ACallback: THostMainCallback;
    AUserData: Pointer): Int64; cdecl;
  /// <summary>A progress notice for background work (main thread only; from another thread
  /// call it through PostToMain). APercent below 0 shows no percentage. One notice per
  /// AId; it stays until ProgressEnd. 0 = shown.</summary>
  THostProgressSetFn = function(APluginId, AId, AText: PAnsiChar; APercent: Int64): Int64; cdecl;
  THostProgressEndFn = function(APluginId, AId: PAnsiChar): Int64; cdecl;
  /// <summary>Mouse on the surface (pixels of the picture area; the position is the
  /// distance from its top-left corner): AKind 0 = button down, 1 = button up, 2 = move
  /// (only while a button is held), 3 = wheel (AExtra = clicks, positive away from the user),
  /// 4 = double click, 5 = the size of the area changed (AWidth, AHeight; sent before the
  /// first picture is needed and whenever the window or the layout changes). AButton 1 = left, 2 = right, 3 = middle. AShift is a bit set:
  /// 1 = Shift, 2 = Ctrl, 4 = Alt. AWidth / AHeight are the size of the area. Returns 1
  /// when the plugin used the event.</summary>
  THostSurfaceMouseCallback = function(AUserData: Pointer; AKind, AX, AY, AWidth, AHeight,
    AButton, AExtra, AShift: Int64): Int64; cdecl;
  /// <summary>As SurfaceOpen, with a place and mouse events. AMode: 0 = a tab of its own,
  /// 1 = the same, full screen (no menu, tabs or key bar), 2 = the panel opposite to the
  /// active one (like Quick View; closing Quick View closes it); add 256 for a native
  /// window: the host creates a child window over the area (see SurfaceNativeHandle)
  /// instead of drawing frames.</summary>
  THostSurfaceOpenExFn = function(APluginId, ATitle: PAnsiChar; AMode: Int64;
    AOnKey: THostSurfaceKeyCallback; AOnTick: THostSurfaceTickCallback;
    AOnClosed: THostSurfaceClosedCallback; AOnMouse: THostSurfaceMouseCallback;
    AUserData: Pointer): Int64; cdecl;
  /// <summary>Switches a tab surface between normal and full screen. 0 = done.</summary>
  THostSurfaceSetFullscreenFn = function(AHandle, AOn: Int64): Int64; cdecl;
  /// <summary>1 when the surface is full screen, 0 when it is not, -1 for an unknown handle.</summary>
  THostSurfaceGetFullscreenFn = function(AHandle: Int64): Int64; cdecl;
  /// <summary>The window handle (HWND on Windows) of a native surface; 0 when the surface
  /// has none. The host keeps it over the area, hides it under dialogs and menus and
  /// resizes the windows inside it to fill it; the plugin draws in it (or hands it to a
  /// player as the output window). It receives its own mouse messages.</summary>
  THostSurfaceNativeHandleFn = function(AHandle: Int64): Int64; cdecl;
  /// <summary>Colors a line of text in the viewer and editor: for the file name extensions
  /// the plugin registered (".json,.ini"), the host calls it with a line (UTF-8) and room
  /// for ASpanCap spans of three 32-bit integers each: start (byte offset in the line),
  /// length (bytes) and class (0 plain, 1 comment, 2 string, 3 number, 4 keyword, 5 type,
  /// 6 function, 7 operator, 8 preprocessor, 9 constant, 10 key, 11 error). Returns the
  /// number of spans written. 0 = registered.</summary>
  THostHighlightCallback = function(AUserData: Pointer; ALine: PAnsiChar; ASpans: PInteger;
    ASpanCap: Int64): Int64; cdecl;
  THostRegisterHighlighterFn = function(APluginId, AExtensions: PAnsiChar;
    AHandler: THostHighlightCallback; AUserData: Pointer): Int64; cdecl;

  /// <summary>Result of VfsList or VfsExists: AStatus 0 = ok (AText is JSON), else
  /// 1 not found, 2 access denied, 3 not supported (or too large), 4 cancelled, 5 I/O error,
  /// 6 invalid URI. Runs once, on the main thread; AText is valid during the call.</summary>
  THostVfsTextCallback = procedure(AUserData: Pointer; AStatus: Int64; AText: PAnsiChar); cdecl;
  /// <summary>Result of VfsRead: the status as above and the bytes of the file (valid during
  /// the call). Runs once, on the main thread.</summary>
  THostVfsDataCallback = procedure(AUserData: Pointer; AStatus: Int64; AData: PByte;
    ALength: Int64); cdecl;
  /// <summary>Starts listing a folder (permission "vfs.read"). 0 = started and the callback
  /// follows; -1 = bad arguments; -2 = the plugin has no such permission (no callback). The
  /// JSON holds uri and entries of name, uri, dir, size and modified (seconds since 1970).
  /// Main thread only.</summary>
  THostVfsListFn = function(APluginId, AUri: PAnsiChar; ACallback: THostVfsTextCallback;
    AUserData: Pointer): Int64; cdecl;
  /// <summary>Starts an existence check (JSON: exists, dir); results as VfsList.</summary>
  THostVfsExistsFn = function(APluginId, AUri: PAnsiChar; ACallback: THostVfsTextCallback;
    AUserData: Pointer): Int64; cdecl;
  /// <summary>Starts reading a whole file of at most AMaxBytes (0 = 2 MB, at most 64 MB).</summary>
  THostVfsReadFn = function(APluginId, AUri: PAnsiChar; AMaxBytes: Int64;
    ACallback: THostVfsDataCallback; AUserData: Pointer): Int64; cdecl;
  /// <summary>Result of VfsOpen: the status as above and, when it is 0, the handle of the open
  /// file. Runs once, on the main thread.</summary>
  THostVfsOpenCallback = procedure(AUserData: Pointer; AStatus: Int64; AHandle: Int64); cdecl;
  /// <summary>Opens a file for reading in pieces (permission "vfs.read"). Returns the number of
  /// the job (above 0) and the callback follows; -1 = bad arguments; -2 = no permission; -3 = too
  /// many open files (16 per plugin). A file that is not local is copied to a temporary file first, with a progress
  /// notice. Main thread only.</summary>
  THostVfsOpenFn = function(APluginId, AUri: PAnsiChar; ACallback: THostVfsOpenCallback;
    AUserData: Pointer): Int64; cdecl;
  /// <summary>Cancels a VfsOpen that has not finished: its callback still follows once, with status
  /// 4. 0 = cancelled, -1 = no such job. Main thread only.</summary>
  THostVfsCancelFn = function(AJob: Int64): Int64; cdecl;
  /// <summary>Size of an open file in bytes; -1 for an unknown handle. Any thread.</summary>
  THostVfsSizeFn = function(AHandle: Int64): Int64; cdecl;
  /// <summary>Reads up to ASize bytes from AOffset into ABuf. Returns the bytes read, 0 at the
  /// end of the file, a negative number on an error. Blocks only the calling thread; any
  /// thread.</summary>
  THostVfsReadAtFn = function(AHandle, AOffset: Int64; ABuf: PByte; ASize: Int64): Int64; cdecl;
  /// <summary>Closes an open file. 0 = closed, -1 = unknown handle. Any thread.</summary>
  THostVfsCloseFn = function(AHandle: Int64): Int64; cdecl;
  /// <summary>The text of AKey from the plugin's resource\<language>\strings.json
  /// for the program language, or ADefault (the plugin's English text) when the
  /// language is English or the pack or the key is missing. Text result as for
  /// THostTextOutFn: the length in bytes, the text written to ABuf only when it
  /// fits (a nil ABuf measures). -1 = bad arguments. The host event
  /// "language.changed" (payload {"language":"ru"}) says when to ask again.</summary>
  THostTranslateFn = function(APluginId, AKey, ADefault: PAnsiChar;
    ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;

  /// <summary>Adds a numbered item to the Change Drive list (Alt+F1/F2) and to
  /// the drive bar, after the built-in items. Enter on it opens AUri in the
  /// panel; it is marked while the panel is on a URI of the same scheme. AItemId
  /// is the plugin's own id for the item (registering it again replaces it),
  /// ACaption is shown as is (translate it first), items go in ascending
  /// APriority. 0 = added, -1 = refused (empty id or caption, AUri without a
  /// scheme or with the "file" scheme, or five plugin items exist already).
  /// Main thread only. Unloading the plugin removes its items.</summary>
  THostRegisterDriveItemFn = function(APluginId, AItemId, ACaption, AUri: PAnsiChar;
    APriority: Int64): Int64; cdecl;

  /// <summary>As RegisterVfsScheme, with the version 2 callback table (progress,
  /// cancellation, error text, paged listings). 0 = registered, -1 = refused.</summary>
  THostRegisterVfsSchemeV2Fn = function(APluginId, AScheme: PAnsiChar;
    ACallbacks: PVfsCallbacksCdeclV2; AUserData: Pointer; APriority: Int64): Int64; cdecl;

  /// <summary>Sets the function-bar labels shown while a panel is in a folder of
  /// AScheme (see IPluginChrome.SetSchemeFBar for the AJson layout: "root" and
  /// "inside" objects mapping "F7" / "Shift+F4" to a label). An empty or nil AJson
  /// removes the labels of the scheme. 0 = set, -1 = refused. Main thread only.
  /// Unloading the plugin removes its labels.</summary>
  THostSetPanelFBarFn = function(APluginId, AScheme, AJson: PAnsiChar): Int64; cdecl;

  /// <summary>As SetStatusSegment, with colored parts. AJson is an array of parts:
  /// [{"t": "main", "role": "info", "fg": "#RRGGBB", "bg": "#RRGGBB", "b": true}, ...];
  /// "t" is the text, "role" one of ok, warn, error, info, accent, neutral (a
  /// text and background color pair that reads on any theme), "fg" / "bg"
  /// override a color of the role, "b" makes the part bold. A part without
  /// colors takes the theme's status colors. An empty or nil AJson, or one
  /// without text, removes the segment. 0 = ok, -1 = bad arguments.</summary>
  THostSetStatusSegmentStyledFn = function(APluginId, ASegmentId, AJson: PAnsiChar): Int64; cdecl;

  /// <summary>Table of host-exported functions passed to mtn_plugin_init.
  /// Field order/types are the ABI - see cPluginAbiVersion.</summary>
  THostApiTable = record
    AbiVersion: Int64;
    HostPublish: THostPublishFn;
    HostInvalidate: THostInvalidateFn;
    RegisterVfsScheme: THostRegisterVfsSchemeFn;
    RegisterPanelPlugin: THostRegisterPanelPluginFn;
    RegisterKeyBinding: THostRegisterKeyBindingFn;
    RegisterMenuItem: THostRegisterMenuItemFn;
    // ABI 2
    RegisterCommand: THostRegisterCommandFn;
    RegisterCommandHook: THostRegisterCommandHookFn;
    ExecuteCommand: THostExecuteCommandFn;
    RegisterDocumentProvider: THostRegisterDocumentProviderFn;
    OpenExternal: THostOpenExternalFn;
    ShowDialog: THostShowDialogFn;
    RegisterPanelActivate: THostRegisterPanelActivateFn;
    SetCommandCaption: THostSetCommandCaptionFn;
    SetStatusSegment: THostSetStatusSegmentFn;
    RegisterSettings: THostRegisterSettingsFn;
    GetSetting: THostGetSettingFn;
    SetSetting: THostSetSettingFn;
    SurfaceOpen: THostSurfaceOpenFn;
    SurfaceSetFrame: THostSurfaceSetFrameFn;
    SurfaceSetInfo: THostSurfaceSetInfoFn;
    SurfaceSetTimer: THostSurfaceSetTimerFn;
    SurfaceClose: THostSurfaceCloseFn;
    HostInfo: THostTextOutFn;
    DocInfo: THostTextOutFn;
    DocGetText: THostDocGetTextFn;
    DocReplace: THostDocReplaceFn;
    DocSetCursor: THostDocSetCursorFn;
    PanelInfo: THostTextOutFn;
    PanelGoto: THostPanelGotoFn;
    PanelRefresh: THostPanelRefreshFn;
    ClipboardGet: THostTextOutFn;
    ClipboardSet: THostClipboardSetFn;
    ShowMessage: THostShowMessageFn;
    Subscribe: THostSubscribeFn;
    PanelList: THostPanelListFn;
    PanelSetCursor: THostPanelSetCursorFn;
    PanelSelect: THostPanelSelectFn;
    DocSetSelection: THostDocSetSelectionFn;
    DocLine: THostDocLineFn;
    PostToMain: THostPostToMainFn;
    ProgressSet: THostProgressSetFn;
    ProgressEnd: THostProgressEndFn;
    SurfaceOpenEx: THostSurfaceOpenExFn;
    SurfaceSetFullscreen: THostSurfaceSetFullscreenFn;
    SurfaceNativeHandle: THostSurfaceNativeHandleFn;
    RegisterHighlighter: THostRegisterHighlighterFn;
    VfsList: THostVfsListFn;
    VfsExists: THostVfsExistsFn;
    VfsRead: THostVfsReadFn;
    VfsOpen: THostVfsOpenFn;
    VfsSize: THostVfsSizeFn;
    VfsReadAt: THostVfsReadAtFn;
    VfsClose: THostVfsCloseFn;
    VfsCancel: THostVfsCancelFn;
    SurfaceGetFullscreen: THostSurfaceGetFullscreenFn;
    // ABI 3
    Translate: THostTranslateFn;
    // ABI 4
    RegisterDriveItem: THostRegisterDriveItemFn;
    RegisterVfsSchemeV2: THostRegisterVfsSchemeV2Fn;
    SetPanelFBar: THostSetPanelFBarFn;
    SetStatusSegmentStyled: THostSetStatusSegmentStyledFn;
  end;
  PHostApiTable = ^THostApiTable;

  /// <summary>Plugin-side entry points a DLL must export (see uPluginLoader.pas).</summary>
  TPluginGetAbiVersionFn = function: Int64; cdecl;
  TPluginInitFn = function(AHostApi: PHostApiTable): Int64; cdecl;
  TPluginShutdownProc = procedure; cdecl;
  TPluginSetSecretFn = function(AKeyUtf8, AValueUtf8: PAnsiChar): Int64; cdecl;

/// <summary>Wraps a JSON payload as a TObject so it survives the cdecl
/// boundary and reaches MessageBus subscribers (uMessageBus.TMessageListener
/// takes a TObject payload). Subscribers should free-cast to TPluginPayload.</summary>
type
  TPluginPayload = class(TObject)
  public
    PluginId: string;
    Json: string;
    constructor Create(const APluginId, AJson: string);
  end;

function mtn_host_publish(APluginId, ATopicUtf8, APayloadJsonUtf8: PAnsiChar): Int64; cdecl;
function mtn_host_invalidate(AWindowId: Int64): Int64; cdecl;

/// <summary>True when a plugin built against AAbi can be loaded by this host.</summary>
function IsSupportedPluginAbi(AAbi: Int64): Boolean;

/// <summary>Registers a window (by an opaque host-assigned Int64 id) so a
/// plugin can later request a repaint via mtn_host_invalidate. Returns the
/// assigned id. Called from host code (e.g. uMainForm), not by plugins.</summary>
function RegisterInvalidatableWindow(AInvalidateProc: TProc): Int64;
procedure UnregisterInvalidatableWindow(AWindowId: Int64);

/// <summary>Fills in the fixed fields (AbiVersion + Host*) of a THostApiTable.
/// uPluginLoader.pas adds the Register* function pointers.</summary>
procedure InitHostApiTableCore(var ATable: THostApiTable);

implementation

var
  GWindows: TDictionary<Int64, TProc>;
  GNextWindowId: Int64 = 1;

constructor TPluginPayload.Create(const APluginId, AJson: string);
begin
  inherited Create;
  PluginId := APluginId;
  Json := AJson;
end;

function RegisterInvalidatableWindow(AInvalidateProc: TProc): Int64;
begin
  Result := TInterlocked.Increment(GNextWindowId);
  GWindows.AddOrSetValue(Result, AInvalidateProc);
end;

procedure UnregisterInvalidatableWindow(AWindowId: Int64);
begin
  GWindows.Remove(AWindowId);
end;

function mtn_host_publish(APluginId, ATopicUtf8, APayloadJsonUtf8: PAnsiChar): Int64; cdecl;
var
  LTopic, LPluginId, LPayloadJson: string;
  LPayload: TPluginPayload;
begin
  try
    if ATopicUtf8 = nil then
      Exit(-1);
    LTopic := UTF8ToString(ATopicUtf8);
    if APluginId <> nil then
      LPluginId := UTF8ToString(APluginId)
    else
      LPluginId := '';
    if APayloadJsonUtf8 <> nil then
      LPayloadJson := UTF8ToString(APayloadJsonUtf8)
    else
      LPayloadJson := '';

    LPayload := TPluginPayload.Create(LPluginId, LPayloadJson);
    try
      MessageBus.Publish(LTopic, LPayload);
    finally
      LPayload.Free;
    end;
    Result := 0;
  except
    Result := -1;
  end;
end;

function mtn_host_invalidate(AWindowId: Int64): Int64; cdecl;
var
  Proc: TProc;
begin
  try
    if not Assigned(GWindows) or not GWindows.TryGetValue(AWindowId, Proc) then
      Exit(-1);
    if Assigned(Proc) then
      TThread.Queue(nil, procedure begin Proc(); end);
    Result := 0;
  except
    Result := -1;
  end;
end;

function IsSupportedPluginAbi(AAbi: Int64): Boolean;
begin
  Result := (AAbi >= cPluginMinAbiVersion) and (AAbi <= cPluginAbiVersion);
end;

procedure InitHostApiTableCore(var ATable: THostApiTable);
begin
  FillChar(ATable, SizeOf(ATable), 0);
  ATable.AbiVersion := cPluginAbiVersion;
  ATable.HostPublish := @mtn_host_publish;
  ATable.HostInvalidate := @mtn_host_invalidate;
end;

initialization
  GWindows := TDictionary<Int64, TProc>.Create;

finalization
  FreeAndNil(GWindows);

end.
