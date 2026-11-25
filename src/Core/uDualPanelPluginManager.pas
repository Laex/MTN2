unit uDualPanelPluginManager;

{ The Plugins list and the dialogs it opens: information, permissions,
  install and remove. The window still owns the dialog and the row to return
  to, because a drive's information page and a plugin settings page use the
  same return. }

interface

uses
  System.SysUtils, uDialogTypes, uDualPanelUiTypes;

type
  IDualPanelPluginManagerHost = interface
    ['{C4E8A1D7-6B20-4F93-8E15-2A7D9C0B4E61}']
    procedure OpenKindDialog(AKind: THostDialogKind; const ADecl: TDialogDeclaration);
    procedure CloseDialog;
    procedure NotifyChanged;
    function ListIndex(const AId: string): Integer;
    function ListScrollTop: Integer;
    procedure SetListScrollTop(ATop: Integer);
    function Checkbox(const AId: string): Boolean;
    function ShowHostDialog(const ADecl: TDialogDeclaration;
      const AOnCommand: TProc<string, string>; const AHelpTopic: string;
      const AOnChange: TFunc<string, string>): Boolean;
    procedure RequestOpenViewer(const AUri: string);
    function DialogVisible: Boolean;
    function PluginListReturnRow: Integer;
    procedure SetPluginListReturnRow(AValue: Integer);
    function PluginInfoRow: Integer;
    procedure SetPluginInfoRow(AValue: Integer);
    function PluginInfoHelp: string;
    procedure SetPluginInfoHelp(const AValue: string);
    function PluginPermsRow: Integer;
    procedure SetPluginPermsRow(AValue: Integer);
    function PluginPermsCount: Integer;
    procedure SetPluginPermsCount(AValue: Integer);
    function PluginPermsHasOverride: Boolean;
    procedure SetPluginPermsHasOverride(AValue: Boolean);
  end;

  TDualPanelPluginManager = class
  private
    FHost: IDualPanelPluginManagerHost;
  public
    constructor Create(const AHost: IDualPanelPluginManagerHost);
    procedure ShowList(ASelectedIndex: Integer);
    procedure ShowInfo(ARow: Integer);
    procedure ShowPermissions(ARow: Integer);
    function HandlePerms(const AControlId: string): Boolean;
    function HandleInfo(const AControlId: string): Boolean;
    function HandleList(const AControlId: string): Boolean;
    procedure AskInstall(ARow: Integer);
    procedure RunInstall(ASource: string; AReplace: Boolean);
    procedure AskRemove(ARow: Integer);
    procedure ShowNotice(const ATitle, AText: string);
  end;

implementation

uses
  System.JSON, uDialogBuilders, uDualPanelOperations, uPluginHost,
  uPluginInfo, uPluginInstall, uStrings, uVfsTypes;

constructor TDualPanelPluginManager.Create(const AHost: IDualPanelPluginManagerHost);
begin
  inherited Create;
  FHost := AHost;
end;

procedure TDualPanelPluginManager.ShowList(ASelectedIndex: Integer);
begin
  FHost.OpenKindDialog(hdkPluginList,
    BuildPluginListDialog(HostPluginRows, ASelectedIndex));
end;

procedure TDualPanelPluginManager.ShowInfo(ARow: Integer);
var
  Info: TPluginInfo;
begin
  if not HostPluginInfo(ARow, Info) then
  begin
    ShowList(ARow);
    Exit;
  end;
  FHost.SetPluginInfoRow(ARow);
  FHost.SetPluginInfoHelp(Info.HelpFile);
  FHost.OpenKindDialog(hdkPluginInfo, BuildPluginInfoDialog(Info.Name,
    PluginInfoLines(Info, 72), Info.HelpFile <> ''));
end;

procedure TDualPanelPluginManager.ShowPermissions(ARow: Integer);
var
  Name, Intro: string;
  Over, Perms, Texts: TArray<string>;
  OverOn: Boolean;
  Granted: TArray<Boolean>;
  I: Integer;
begin
  if not HostPluginPermissions(ARow, Name, Over, OverOn, Perms, Granted) then
  begin
    ShowList(ARow);
    Exit;
  end;
  SetLength(Texts, Length(Perms));
  for I := 0 to High(Perms) do
    Texts[I] := PermissionDescription(Perms[I]);
  FHost.SetPluginPermsRow(ARow);
  FHost.SetPluginPermsCount(Length(Perms));
  FHost.SetPluginPermsHasOverride(Length(Over) > 0);
  if (Length(Over) > 0) or (Length(Perms) > 0) then
    Intro := T('ui.plugins.permsIntro', 'The plugin asks to be allowed to:')
  else
    Intro := T('ui.plugins.permsNone', 'The plugin asks for no permissions.');
  FHost.OpenKindDialog(hdkPluginPerms, BuildPluginPermissionsDialog(Name, Intro,
    Format(T('ui.plugins.permsOverride', 'replace the built-in handlers: %s'),
      [string.Join(' ', Over)]),
    Length(Over) > 0, OverOn, Texts, Granted));
end;

function TDualPanelPluginManager.HandlePerms(const AControlId: string): Boolean;
var
  Row, I: Integer;
  Granted: TArray<Boolean>;
  OverOn: Boolean;
begin
  Result := True;
  Row := FHost.PluginPermsRow;
  if DialogCmdIsAccept(AControlId) then
  begin
    SetLength(Granted, FHost.PluginPermsCount);
    for I := 0 to High(Granted) do
      Granted[I] := FHost.Checkbox('perm_' + IntToStr(I));
    OverOn := FHost.PluginPermsHasOverride and FHost.Checkbox('perm_override');
    FHost.CloseDialog;
    HostApplyPluginPermissions(Row, OverOn, Granted);
  end
  else
    FHost.CloseDialog;
  ShowList(Row);
end;

function TDualPanelPluginManager.HandleInfo(const AControlId: string): Boolean;
var
  Row: Integer;
  HelpFile: string;
begin
  Result := True;
  Row := FHost.PluginInfoRow;
  HelpFile := FHost.PluginInfoHelp;
  FHost.CloseDialog;
  // Opened from the drive list: no plugin list behind it.
  if Row < 0 then
    Exit;
  if (AControlId = 'help') and (HelpFile <> '') then
  begin
    // The help page opens in the viewer; the Plugins list is not brought back.
    FHost.RequestOpenViewer(PathToFileUri(HelpFile));
    Exit;
  end;
  ShowList(Row);
end;

procedure TDualPanelPluginManager.ShowNotice(const ATitle, AText: string);
var
  Row: Integer;
begin
  if FHost.ShowHostDialog(BuildConfirmDialog(ATitle, AText), nil,
    'settings.md#plugins', nil) then
    Exit;
  Row := FHost.PluginListReturnRow;
  FHost.SetPluginListReturnRow(-1);
  if Row >= 0 then
    ShowList(Row);
end;

procedure TDualPanelPluginManager.AskInstall(ARow: Integer);
begin
  FHost.SetPluginListReturnRow(ARow);
  if FHost.ShowHostDialog(BuildInputDialog(
       T('ui.plugins.installTitle', 'Install plugin'),
       T('ui.plugins.installPrompt', 'Folder or .zip file with the plugin:'), ''),
     procedure(AControl, AValues: string)
     var
       V: TJSONValue;
       Source: string;
     begin
       if not DialogCmdIsAccept(AControl) then
         Exit;
       Source := '';
       V := TJSONObject.ParseJSONValue(AValues);
       try
         if V is TJSONObject then
           TJSONObject(V).TryGetValue<string>('name', Source);
       finally
         V.Free;
       end;
       if Trim(Source) <> '' then
         RunInstall(Source, False);
     end, 'settings.md#plugins', nil) then
    Exit;
  FHost.SetPluginListReturnRow(-1);
  ShowList(ARow);
end;

procedure TDualPanelPluginManager.RunInstall(ASource: string; AReplace: Boolean);
var
  R: TPluginInstallResult;
  Title: string;
begin
  Title := T('ui.plugins.installTitle', 'Install plugin');
  R := HostInstallPlugin(ASource, AReplace);
  case R.Status of
    pisOk:
      if R.Replaced then
        ShowNotice(Title, Format(T('ui.plugins.replaced',
          'Plugin %s replaced. A loaded plugin keeps its old version until the next start.'), [R.Id]))
      else
        ShowNotice(Title, Format(T('ui.plugins.installed',
          'Plugin %s installed. It is switched off: turn it on in the list with Space, then OK.'), [R.Id]));
    pisExists:
      FHost.ShowHostDialog(BuildConfirmDialog(Title, Format(T('ui.plugins.exists',
          'The plugin %s is installed already. Replace it?'), [R.Id])),
        procedure(AControl, AValues: string)
        begin
          if DialogCmdIsAccept(AControl) then
            RunInstall(ASource, True);
        end, 'settings.md#plugins', nil);
    pisSourceMissing:
      ShowNotice(Title, Format(T('ui.plugins.sourceMissing', 'Not found: %s'), [Trim(ASource)]));
    pisNoManifest:
      ShowNotice(Title, T('ui.plugins.noManifest', 'The source has no plugin.json.'));
    pisBadId:
      ShowNotice(Title, Format(T('ui.plugins.badId',
        'The plugin id "%s" is not allowed: use letters, digits, ".", "_" and "-".'), [R.Id]));
    pisUnsafeArchive:
      ShowNotice(Title, T('ui.plugins.unsafeArchive',
        'The archive is refused: it has paths outside the plugin folder or is too large.'));
  else
    ShowNotice(Title, Format(T('ui.plugins.installFailed', 'Installing failed: %s'), [R.Detail]));
  end;
end;

procedure TDualPanelPluginManager.AskRemove(ARow: Integer);
var
  Id: string;
begin
  Id := HostPluginIdAt(ARow);
  FHost.SetPluginListReturnRow(ARow);
  if (Id <> '') and
     FHost.ShowHostDialog(BuildConfirmDialog(T('ui.plugins.removeTitle', 'Remove plugin'),
       Format(T('ui.plugins.removeAsk', 'Delete the plugin %s and its files?'), [Id])),
       procedure(AControl, AValues: string)
       var
         Detail: string;
         Title: string;
       begin
         if not DialogCmdIsAccept(AControl) then
           Exit;
         Title := T('ui.plugins.removeTitle', 'Remove plugin');
         if HostRemovePlugin(ARow, Detail) then
           ShowNotice(Title, Format(T('ui.plugins.removed', 'Plugin %s removed.'), [Id]))
         else
           ShowNotice(Title, Format(T('ui.plugins.removeFailed',
             'Plugin %s could not be removed: %s. Switch it off, restart the program and try again.'),
             [Id, Detail]));
       end, 'settings.md#plugins', nil) then
    Exit;
  FHost.SetPluginListReturnRow(-1);
  ShowList(ARow);
end;

function TDualPanelPluginManager.HandleList(const AControlId: string): Boolean;
var
  Row, Delta, Top: Integer;
  Kind: TPluginListCommandKind;
begin
  Result := True;
  Kind := ClassifyPluginListCommand(AControlId);
  if Kind = plcDismiss then
  begin
    // OK applies the pending on/off choices; Cancel, Esc and the close box drop them.
    FHost.CloseDialog;
    if DialogCmdIsAccept(AControlId) then
      HostPluginsCommit
    else
      HostPluginsCancel;
    FHost.NotifyChanged;
    Exit;
  end;
  Row := FHost.ListIndex('plugins');
  Top := FHost.ListScrollTop;
  FHost.CloseDialog;
  case Kind of
    plcUp, plcDown:
      begin
        // The selection follows the plugin to its new place.
        if Kind = plcUp then
          Delta := -1
        else
          Delta := 1;
        if HostMovePlugin(Row, Delta) then
          Inc(Row, Delta);
        ShowList(Row);
        FHost.SetListScrollTop(Top);
      end;
    plcInfo:
      ShowInfo(Row);
    plcAdd:
      AskInstall(Row);
    plcRemove:
      AskRemove(Row);
    plcSettings:
      begin
        // The plugin shows its own dialog and the list comes back when it is closed;
        // one without settings gets a message.
        FHost.SetPluginListReturnRow(Row);
        if HostConfigurePlugin(Row) then
        begin
          if FHost.DialogVisible then
            Exit;
          FHost.SetPluginListReturnRow(-1);
        end
        else
        begin
          // A message dialog; closing it brings the list back (hdkHost branch).
          if not FHost.ShowHostDialog(BuildConfirmDialog(
               T('ui.plugins.noSettingsTitle', 'Plugin settings'),
               Format(T('ui.plugins.noSettings', 'The plugin %s has no settings.'),
                 [HostPluginIdAt(Row)])), nil, 'settings.md', nil) then
          begin
            FHost.SetPluginListReturnRow(-1);
            ShowList(Row);
          end;
          Exit;
        end;
        ShowList(Row);
        FHost.SetListScrollTop(Top);
      end;
    plcPermissions:
      ShowPermissions(Row);
    plcToggle:
      begin
        HostTogglePlugin(Row);
        // The list is rebuilt so the marks show the new state; the menu is rebuilt
        // too, since a plugin that left or arrived takes its items with it. The rows
        // stay where they were: the list does not jump.
        ShowList(Row);
        FHost.SetListScrollTop(Top);
      end;
  end;
end;

end.
