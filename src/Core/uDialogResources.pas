unit uDialogResources;

{ Load DIALOG_PLUGIN JSON from RCDATA (MTN2.rc). Layouts live in src/dialogs/*.json.
  Application loads only from embedded resources. Tools/tests may fall back to
  the dialogs\ folder next to the exe or under the source tree. }

interface

uses
  System.SysUtils,
  uDialogTypes;

const
  cResDialogConfirm  = 'DIALOG_CONFIRM';
  cResDialogDelete   = 'DIALOG_DELETE';
  cResDialogHelp     = 'DIALOG_HELP';
  cResDialogInput    = 'DIALOG_INPUT';
  cResDialogSelectMask = 'DIALOG_SELECTMASK';
  cResDialogAskSave  = 'DIALOG_ASKSAVE';
  cResDialogSearch   = 'DIALOG_SEARCH';
  cResDialogCopyMove = 'DIALOG_COPYMOVE';
  cResDialogGotoLine = 'DIALOG_GOTOLINE';
  cResDialogEncoding = 'DIALOG_ENCODING';
  cResDialogReplace  = 'DIALOG_REPLACE';
  cResDialogOverwriteAsk = 'DIALOG_OVERWRITEASK';
  cResDialogDeleteError = 'DIALOG_DELETEERROR';
  cResDialogIOError = 'DIALOG_IOERROR';
  cResDialogFolderHistory = 'DIALOG_FOLDERHISTORY';
  cResDialogCmdHistory = 'DIALOG_CMDHISTORY';
  cResDialogFileHistory = 'DIALOG_FILEHISTORY';
  cResDialogFolderHotlist = 'DIALOG_FOLDERHOTLIST';
  cResDialogWorkspaces = 'DIALOG_WORKSPACES';
  cResDialogCreateLink = 'DIALOG_CREATELINK';
  cResDialogDirSync = 'DIALOG_DIRSYNC';
  cResDialogFileDiff = 'DIALOG_FILEDIFF';
  cResDialogTerminalProfile = 'DIALOG_TERMINALPROFILE';
  cResDialogAbout = 'DIALOG_ABOUT';
  cResDialogUpdate = 'DIALOG_UPDATE';
  cResDialogUpdateMsg = 'DIALOG_UPDATEMSG';
  cResDialogUpdates = 'DIALOG_UPDATES';
  cResDialogPluginList = 'DIALOG_PLUGINLIST';
  cResDialogColorCoding = 'DIALOG_COLORCODING';
  cResDialogColorCodingEdit = 'DIALOG_COLORCODINGEDIT';
  cResDialogColorPicker = 'DIALOG_COLORPICKER';
  cResDialogTheme = 'DIALOG_THEME';
  cResDialogColumnsConfig = 'DIALOG_COLUMNSCONFIG';
  cResDialogDisplay = 'DIALOG_DISPLAY';
  cResDialogExternalTools = 'DIALOG_EXTERNALTOOLS';
  cResDialogChecksumOpts = 'DIALOG_CHECKSUMOPTS';
  cResDialogChecksum = 'DIALOG_CHECKSUM';
  cResDialogArchivePassword = 'DIALOG_ARCHIVEPASSWORD';
  cResDialogSetAttr = 'DIALOG_SETATTR';
  cResDialogSshConnections = 'DIALOG_SSHCONNECTIONS';
  cResDialogSshConnectionEdit = 'DIALOG_SSHCONNECTIONEDIT';
  cResDialogAssociations = 'DIALOG_ASSOCIATIONS';
  cResDialogAssociationEdit = 'DIALOG_ASSOCIATIONEDIT';
  cResDialogUserMenuEdit = 'DIALOG_USERMENUEDIT';
  cResDialogKeymap = 'DIALOG_KEYMAP';
  cResDialogKeymapEdit = 'DIALOG_KEYMAPEDIT';
  cResDialogJobList = 'DIALOG_JOBLIST';
  cResDialogJobProgress = 'DIALOG_JOBPROGRESS';
  cResDialogJobProgressDelete = 'DIALOG_JOBPROGRESSDELETE';
  cResDialogJobProgressError = 'DIALOG_JOBPROGRESSERROR';

function TryLoadDialogResourceJson(const AResName: string;
  out AJson: string): Boolean;
function TryLoadDialogResource(const AResName: string;
  out ADecl: TDialogDeclaration): Boolean;
/// <summary>Load from RCDATA (or dialogs\ JSON for tools). Raises if missing.</summary>
procedure RequireDialogResource(const AResName: string;
  out ADecl: TDialogDeclaration);

/// <summary>Load a plugin-supplied dialog JSON from
/// &lt;ExeDir&gt;\plugins\&lt;APluginId&gt;\dialogs\&lt;ADialogName&gt;.json.
/// Distinct from the resource-only path used for built-in dialogs above:
/// plugins are not embedded in the exe, so they need a disk-backed source,
/// scoped to their own plugin directory only (no parent-directory walk).</summary>
function TryLoadPluginDialogJson(const APluginId, ADialogName: string;
  out AJson: string): Boolean;
function TryLoadPluginDialogResource(const APluginId, ADialogName: string;
  out ADecl: TDialogDeclaration): Boolean;
/// <summary>Applies the active locale to a dialog's title and static
/// captions. ANamespace is the RCDATA name, e.g. DIALOG_SEARCH. For non-en
/// locales also runs FitDialogToTranslatedText (widen + center buttons).</summary>
procedure TranslateDialogDeclaration(const ANamespace: string;
  var ADecl: TDialogDeclaration);

procedure DialogSetTitle(var ADecl: TDialogDeclaration; const ATitle: string);
procedure DialogSetLabelText(var ADecl: TDialogDeclaration; const AId, AText: string);
procedure DialogSetInputValue(var ADecl: TDialogDeclaration; const AId, AValue: string);
/// <summary>Gives a dckInput a uDialogHistory key (for shared resources like
/// the generic input dialog, where the key depends on the caller).</summary>
procedure DialogSetInputHistory(var ADecl: TDialogDeclaration; const AId, AKey: string);
procedure DialogSetCheckbox(var ADecl: TDialogDeclaration; const AId: string;
  AChecked: Boolean);
procedure DialogSetRadio(var ADecl: TDialogDeclaration; const AGroupId,
  ASelectedId: string);
procedure DialogSetButtonText(var ADecl: TDialogDeclaration; const AId, AText: string);
procedure DialogSetListSelected(var ADecl: TDialogDeclaration; const AId: string;
  ASelectedIndex: Integer);
procedure DialogSetDropDownSelected(var ADecl: TDialogDeclaration; const AId: string;
  ASelectedIndex: Integer);
procedure DialogSetListItems(var ADecl: TDialogDeclaration; const AId: string;
  const AItems: TArray<string>; ASelectedIndex: Integer = 0);
/// <summary>Repoints a dckColorSample control's live-preview sources — e.g.
/// the color picker's single "preview" control is reused for either a Fg or
/// a Bg pick by wiring it to 'picker_hex' on whichever side is being edited.</summary>
procedure DialogSetColorSampleSources(var ADecl: TDialogDeclaration; const AId: string;
  const AFgSourceId, ABgSourceId: string);

implementation

uses
  System.Classes, System.Math, System.IOUtils, Winapi.Windows,
  uDialogJson, uDialogLocaleLayout, uInputLine, uStrings;

function DialogResNameToJsonFile(const AResName: string): string;
var
  S: string;
begin
  S := UpperCase(Trim(AResName));
  if S.StartsWith('DIALOG_') then
    Delete(S, 1, Length('DIALOG_'));
  Result := LowerCase(S) + '.json';
end;

{ Loading from disk commented out per user request: dialogs must be loaded ONLY from resources }
(*
function TryLoadDialogJsonFromFile(const AFileName: string;
  out AJson: string): Boolean;
begin
  AJson := '';
  Result := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  try
    AJson := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    if (Length(AJson) > 0) and (Ord(AJson[1]) = $FEFF) then
      Delete(AJson, 1, 1);
    Result := Trim(AJson) <> '';
  except
    AJson := '';
    Result := False;
  end;
end;

function TryFindDialogJsonFile(const AResName: string; out APath: string): Boolean;
var
  FileName, ExeDir, Candidate, Walk: string;
begin
  Result := False;
  APath := '';
  FileName := DialogResNameToJsonFile(AResName);
  if FileName = '.json' then
    Exit;

  ExeDir := ExtractFilePath(ParamStr(0));
  Candidate := TPath.Combine(TPath.Combine(ExeDir, 'dialogs'), FileName);
  if TFile.Exists(Candidate) then
  begin
    APath := Candidate;
    Exit(True);
  end;

  Candidate := TPath.Combine(TPath.Combine(GetCurrentDir, 'dialogs'), FileName);
  if TFile.Exists(Candidate) then
  begin
    APath := Candidate;
    Exit(True);
  end;

  Walk := ExeDir;
  while Walk <> '' do
  begin
    Candidate := TPath.Combine(TPath.Combine(Walk, 'dialogs'), FileName);
    if TFile.Exists(Candidate) then
    begin
      APath := Candidate;
      Exit(True);
    end;
    Candidate := TPath.Combine(TPath.Combine(TPath.Combine(Walk, 'src'), 'dialogs'),
      FileName);
    if TFile.Exists(Candidate) then
    begin
      APath := Candidate;
      Exit(True);
    end;
    if SameText(Walk, ExpandFileName(TPath.Combine(Walk, '..'))) then
      Break;
    Walk := ExpandFileName(TPath.Combine(Walk, '..'));
  end;
end;
*)

function TryLoadDialogResourceJson(const AResName: string;
  out AJson: string): Boolean;
var
  RS: TResourceStream;
  Bytes: TBytes;
  ResHandle: HRSRC;
  UResName: string;
begin
  AJson := '';
//  Result := False;
  UResName := UpperCase(Trim(AResName));

  // Check whether resource RT_RCDATA exists in HInstance or MainInstance before loading
  ResHandle := FindResource(HInstance, PChar(UResName), RT_RCDATA);
  if ResHandle = 0 then
    ResHandle := FindResource(MainInstance, PChar(UResName), RT_RCDATA);

  if ResHandle = 0 then
  begin
    AJson := '';
    Exit(False);
  end;

  try
    RS := TResourceStream.Create(HInstance, UResName, RT_RCDATA);
    try
      SetLength(Bytes, RS.Size);
      if RS.Size > 0 then
        RS.ReadBuffer(Bytes[0], RS.Size);
      AJson := TEncoding.UTF8.GetString(Bytes);
      if (Length(AJson) > 0) and (Ord(AJson[1]) = $FEFF) then
        Delete(AJson, 1, 1);
      if Trim(AJson) <> '' then
        Exit(True);
    finally
      RS.Free;
    end;
  except
    AJson := '';
  end;

  // Loading from disk disabled per user request:
  // if TryFindDialogJsonFile(AResName, FilePath) and
  //    TryLoadDialogJsonFromFile(FilePath, AJson) then
  //   Exit(True);

  AJson := '';
  Result := False;
end;

function IsSafePluginPathComponent(const S: string): Boolean;
begin
  Result := (S <> '') and (Pos('..', S) = 0) and (Pos('/', S) = 0) and
    (Pos('\', S) = 0) and (Pos(':', S) = 0);
end;

function TryReadUtf8FileStripBom(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  try
    AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    if (Length(AText) > 0) and (Ord(AText[1]) = $FEFF) then
      Delete(AText, 1, 1);
    Result := Trim(AText) <> '';
  except
    AText := '';
    Result := False;
  end;
end;

function TryLoadPluginDialogJson(const APluginId, ADialogName: string;
  out AJson: string): Boolean;
var
  ExeDir, FilePath: string;
begin
  AJson := '';
  Result := False;
  if not IsSafePluginPathComponent(APluginId) or
     not IsSafePluginPathComponent(ADialogName) then
    Exit;

  ExeDir := ExtractFilePath(ParamStr(0));
  FilePath := TPath.Combine(TPath.Combine(TPath.Combine(TPath.Combine(
    ExeDir, 'plugins'), APluginId), 'dialogs'), ADialogName + '.json');
  Result := TryReadUtf8FileStripBom(FilePath, AJson);
end;

function TryLoadPluginDialogResource(const APluginId, ADialogName: string;
  out ADecl: TDialogDeclaration): Boolean;
var
  Json: string;
begin
  Result := TryLoadPluginDialogJson(APluginId, ADialogName, Json) and
    TryParseDialogJson(Json, ADecl);
  if not Result then
  begin
    ADecl.Version := '';
    ADecl.Title := '';
    ADecl.Width := 0;
    ADecl.Height := 0;
    ADecl.IsWarning := False;
    SetLength(ADecl.Controls, 0);
  end;
end;

// Static-caption translation for a dialog just parsed from its own
// (always-English) dialogs\*.json. Only kinds whose Text field is a fixed
// on-screen caption are touched -- dckInput/dckList/dckDropDown/
// dckColorSample carry user data or a live preview there instead, not UI
// chrome, so they're left alone. Runs before the caller's own
// Build*Dialog patches in any dynamic (e.g. a file name, a path) content on
// top, so a translated caption still gets correctly overwritten where the
// caller means to replace it outright. For non-en locales also widens the
// dialog and recenters button rows via FitDialogToTranslatedText.
procedure TranslateDialogDeclaration(const ANamespace: string;
  var ADecl: TDialogDeclaration);
var
  I: Integer;
begin
  ADecl.Title := TDialog(ANamespace, '', ADecl.Title);
  for I := 0 to High(ADecl.Controls) do
  begin
    if ADecl.Controls[I].Id = '' then
      Continue; // no stable key to translate by
    case ADecl.Controls[I].Kind of
      dckLabel, dckCheckbox, dckRadio, dckRadioGroup, dckButton, dckStatus:
        ADecl.Controls[I].Text :=
          TDialog(ANamespace, ADecl.Controls[I].Id, ADecl.Controls[I].Text);
    end;
  end;
  if not SameText(CurrentLocale, 'en') then
    FitDialogToTranslatedText(ADecl);
end;

function TryLoadDialogResource(const AResName: string;
  out ADecl: TDialogDeclaration): Boolean;
var
  Json: string;
begin
  Result := TryLoadDialogResourceJson(AResName, Json) and
    TryParseDialogJson(Json, ADecl);
  if not Result then
  begin
    ADecl.Version := '';
    ADecl.Title := '';
    ADecl.Width := 0;
    ADecl.Height := 0;
    ADecl.IsWarning := False;
    SetLength(ADecl.Controls, 0);
  end
  else
    TranslateDialogDeclaration(AResName, ADecl);
end;

procedure RequireDialogResource(const AResName: string;
  out ADecl: TDialogDeclaration);
begin
  if not TryLoadDialogResource(AResName, ADecl) then
    raise Exception.CreateFmt(
      'Dialog resource "%s" not found (RCDATA / dialogs\%s)',
      [AResName, DialogResNameToJsonFile(AResName)]);
end;

function FindControl(var ADecl: TDialogDeclaration; const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AId = '' then
    Exit;
  for I := 0 to High(ADecl.Controls) do
    if SameText(ADecl.Controls[I].Id, AId) then
      Exit(I);
end;

procedure DialogSetTitle(var ADecl: TDialogDeclaration; const ATitle: string);
begin
  ADecl.Title := ATitle;
end;

procedure DialogSetLabelText(var ADecl: TDialogDeclaration; const AId, AText: string);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I >= 0) and (ADecl.Controls[I].Kind = dckLabel) then
    ADecl.Controls[I].Text := AText;
end;

procedure DialogSetInputValue(var ADecl: TDialogDeclaration; const AId, AValue: string);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I >= 0) and (ADecl.Controls[I].Kind = dckInput) then
  begin
    InputLineSetText(ADecl.Controls[I].Edit, AValue);
    InputLineSelectAll(ADecl.Controls[I].Edit);
  end;
end;

procedure DialogSetInputHistory(var ADecl: TDialogDeclaration; const AId, AKey: string);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I >= 0) and (ADecl.Controls[I].Kind = dckInput) and not ADecl.Controls[I].Password then
    ADecl.Controls[I].History := AKey;
end;

procedure DialogSetCheckbox(var ADecl: TDialogDeclaration; const AId: string;
  AChecked: Boolean);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I >= 0) and (ADecl.Controls[I].Kind = dckCheckbox) then
    ADecl.Controls[I].Checked := AChecked;
end;

procedure DialogSetRadio(var ADecl: TDialogDeclaration; const AGroupId,
  ASelectedId: string);
var
  I: Integer;
  G: string;
begin
  for I := 0 to High(ADecl.Controls) do
  begin
    if ADecl.Controls[I].Kind <> dckRadio then
      Continue;
    G := ADecl.Controls[I].Group;
    if G = '' then
      G := ADecl.Controls[I].Id;
    if not SameText(G, AGroupId) then
      Continue;
    ADecl.Controls[I].Checked := SameText(ADecl.Controls[I].Id, ASelectedId);
  end;
end;

procedure DialogSetColorSampleSources(var ADecl: TDialogDeclaration; const AId: string;
  const AFgSourceId, ABgSourceId: string);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I >= 0) and (ADecl.Controls[I].Kind = dckColorSample) then
  begin
    ADecl.Controls[I].FgSourceId := AFgSourceId;
    ADecl.Controls[I].BgSourceId := ABgSourceId;
  end;
end;

procedure DialogSetButtonText(var ADecl: TDialogDeclaration; const AId, AText: string);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I >= 0) and (ADecl.Controls[I].Kind = dckButton) then
    ADecl.Controls[I].Text := AText;
end;

procedure DialogSetListSelected(var ADecl: TDialogDeclaration; const AId: string;
  ASelectedIndex: Integer);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I >= 0) and (ADecl.Controls[I].Kind in [dckList, dckDropDown, dckRadioGroup]) then
  begin
    if Length(ADecl.Controls[I].Items) = 0 then
      ADecl.Controls[I].SelectedIndex := 0
    else
      ADecl.Controls[I].SelectedIndex :=
        EnsureRange(ASelectedIndex, 0, High(ADecl.Controls[I].Items));
  end;
end;

procedure DialogSetDropDownSelected(var ADecl: TDialogDeclaration; const AId: string;
  ASelectedIndex: Integer);
begin
  DialogSetListSelected(ADecl, AId, ASelectedIndex);
end;

procedure DialogSetListItems(var ADecl: TDialogDeclaration; const AId: string;
  const AItems: TArray<string>; ASelectedIndex: Integer);
var
  I: Integer;
begin
  I := FindControl(ADecl, AId);
  if (I < 0) or not (ADecl.Controls[I].Kind in [dckList, dckDropDown, dckRadioGroup]) then
    Exit;
  ADecl.Controls[I].Items := Copy(AItems);
  if Length(AItems) = 0 then
    ADecl.Controls[I].SelectedIndex := 0
  else
    ADecl.Controls[I].SelectedIndex :=
      EnsureRange(ASelectedIndex, 0, High(AItems));
end;

end.
