library ExportListPlugin;

{ Native MTN2 plugin: Files > Export list saves the selected items of the
  active panel (or the item under the cursor) as a text list: aligned text,
  a Markdown table or CSV, with the fields of the user's choice. The choice is
  kept in the plugin's own settings. Items of local folders only. }

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginSdk in '..\..\Core\uPluginSdk.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uListExport in 'uListExport.pas';

const
  cPluginId = 'mtn.exportlist';
  cCommandId = 'exportlist.run';
  cDialogWidth = 72;
  cSettingKey = 'config';

var
  GItems: TArray<TListExportItem>;
  GDirUri: string;
  GConfig: TListExportConfig;

function LoadConfig: TListExportConfig;
var
  Text: string;
begin
  Result := DefaultListExportConfig;
  Text := GetSettingText(cSettingKey);
  if Text <> '' then
    Result := ListExportConfigFromText(Text);
end;

procedure SaveConfig(const AConfig: TListExportConfig);
begin
  SetSettingText(cSettingKey, ListExportConfigToText(AConfig));
end;

function Titles: TListExportTitles;
begin
  Result := DefaultListExportTitles;
  Result[lxfName] := Tr('col.name', Result[lxfName]);
  Result[lxfPath] := Tr('col.path', Result[lxfPath]);
  Result[lxfExt] := Tr('col.ext', Result[lxfExt]);
  Result[lxfSize] := Tr('col.size', Result[lxfSize]);
  Result[lxfModified] := Tr('col.modified', Result[lxfModified]);
  Result[lxfCreated] := Tr('col.created', Result[lxfCreated]);
  Result[lxfAccessed] := Tr('col.accessed', Result[lxfAccessed]);
  Result[lxfType] := Tr('col.type', Result[lxfType]);
  Result[lxfAttr] := Tr('col.attr', Result[lxfAttr]);
end;

{ ---- dialog ------------------------------------------------------------- }

procedure AddRadio(AChildren: TJSONArray; const AId, AText: string; AChecked: Boolean;
  ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'radio');
  O.AddPair('id', AId);
  O.AddPair('group', 'format');
  O.AddPair('text', AText);
  O.AddPair('checked', TJSONBool.Create(AChecked));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

function DefaultFileName(const AConfig: TListExportConfig): string;
var
  Dir, Ext: string;
begin
  case AConfig.Format of
    lefMarkdown: Ext := '.md';
    lefCsv: Ext := '.csv';
  else
    Ext := '.txt';
  end;
  Dir := FileUriToPath(GDirUri);
  if (Dir = '') or not TDirectory.Exists(Dir) then
    Dir := TPath.GetDocumentsPath;
  Result := TPath.Combine(Dir, 'filelist' + Ext);
end;

function BuildDeclaration: TJSONObject;
var
  Kids: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'dialog');
  Result.AddPair('version', '2.0');
  Result.AddPair('title', Tr('dlg.title', 'Export list'));
  Result.AddPair('width', TJSONNumber.Create(cDialogWidth));
  Result.AddPair('height', TJSONNumber.Create(18));
  Kids := TJSONArray.Create;
  Result.AddPair('children', Kids);
  AddItem(Kids, 'label', 'prompt', Tr('dlg.prompt', 'Save the list to the file:'), 1, 0, 68);
  AddField(Kids, 'name', DefaultFileName(GConfig), 1, 1, 68);
  AddItem(Kids, 'separator', '', '', 0, 2, 70);
  AddItem(Kids, 'label', 'format_lbl', Tr('dlg.format', 'Format:'), 1, 3, 68);
  AddRadio(Kids, 'fmt_auto', Tr('dlg.fmtAuto', 'A&uto (by extension)'), GConfig.Format = lefAuto, 1, 4, 33);
  AddRadio(Kids, 'fmt_text', Tr('dlg.fmtText', 'Pla&in text'), GConfig.Format = lefText, 35, 4, 33);
  AddRadio(Kids, 'fmt_md', Tr('dlg.fmtMd', 'Mar&kdown'), GConfig.Format = lefMarkdown, 1, 5, 33);
  AddRadio(Kids, 'fmt_csv', Tr('dlg.fmtCsv', 'CS&V'), GConfig.Format = lefCsv, 35, 5, 33);
  AddCheck(Kids, 'header', Tr('dlg.header', '&Header line'), GConfig.Header, 1, 6, 34);
  AddItem(Kids, 'separator', '', '', 0, 7, 70);
  AddItem(Kids, 'label', 'fields_lbl', Tr('dlg.fields', 'Fields:'), 1, 8, 68);
  AddCheck(Kids, 'f_name', Tr('dlg.fName', '&Name'), lxfName in GConfig.Fields, 1, 9, 22);
  AddCheck(Kids, 'f_path', Tr('dlg.fPath', '&Full path'), lxfPath in GConfig.Fields, 24, 9, 22);
  AddCheck(Kids, 'f_ext', Tr('dlg.fExt', '&Extension'), lxfExt in GConfig.Fields, 47, 9, 22);
  AddCheck(Kids, 'f_size', Tr('dlg.fSize', '&Size'), lxfSize in GConfig.Fields, 1, 10, 22);
  AddCheck(Kids, 'f_modified', Tr('dlg.fModified', '&Modified date'), lxfModified in GConfig.Fields, 24, 10, 22);
  AddCheck(Kids, 'f_created', Tr('dlg.fCreated', '&Created date'), lxfCreated in GConfig.Fields, 47, 10, 22);
  AddCheck(Kids, 'f_accessed', Tr('dlg.fAccessed', '&Accessed date'), lxfAccessed in GConfig.Fields, 1, 11, 22);
  AddCheck(Kids, 'f_type', Tr('dlg.fType', '&Type'), lxfType in GConfig.Fields, 24, 11, 22);
  AddCheck(Kids, 'f_attr', Tr('dlg.fAttr', 'Attri&butes'), lxfAttr in GConfig.Fields, 47, 11, 22);
  AddItem(Kids, 'separator', '', '', 0, 12, 70);
  AddItem(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), 24, 14, 10, True);
  AddItem(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), 36, 14, 10, False, True);
end;

function BoolOf(ARoot: TJSONObject; const AId: string): Boolean;
begin
  Result := False;
  ARoot.TryGetValue<Boolean>(AId, Result);
end;

procedure OnDialogCommand(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Cfg: TListExportConfig;
  Path, Fmt: string;
  Bytes: TBytes;
  Dir: string;
begin
  try
    if GShutdown or not SameText(string(AControlId), 'ok') or (AValuesJson = nil) then
      Exit;
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) then
        Exit;
      Path := '';
      TJSONObject(Root).TryGetValue<string>('name', Path);
      Path := Trim(Path);
      if Path = '' then
        Exit;
      Cfg.Fields := [];
      if BoolOf(TJSONObject(Root), 'f_name') then Include(Cfg.Fields, lxfName);
      if BoolOf(TJSONObject(Root), 'f_path') then Include(Cfg.Fields, lxfPath);
      if BoolOf(TJSONObject(Root), 'f_ext') then Include(Cfg.Fields, lxfExt);
      if BoolOf(TJSONObject(Root), 'f_size') then Include(Cfg.Fields, lxfSize);
      if BoolOf(TJSONObject(Root), 'f_modified') then Include(Cfg.Fields, lxfModified);
      if BoolOf(TJSONObject(Root), 'f_created') then Include(Cfg.Fields, lxfCreated);
      if BoolOf(TJSONObject(Root), 'f_accessed') then Include(Cfg.Fields, lxfAccessed);
      if BoolOf(TJSONObject(Root), 'f_type') then Include(Cfg.Fields, lxfType);
      if BoolOf(TJSONObject(Root), 'f_attr') then Include(Cfg.Fields, lxfAttr);
      if Cfg.Fields = [] then
      begin
        Notice(Tr('msg.noFields', 'Select at least one field'), 1);
        Exit;
      end;
      Cfg.Header := BoolOf(TJSONObject(Root), 'header');
      Fmt := '';
      TJSONObject(Root).TryGetValue<string>('format', Fmt);
      Cfg.Format := ParseListExportFormatRadio(Fmt);
    finally
      Root.Free;
    end;
    GConfig := Cfg;
    SaveConfig(Cfg);
    Dir := FileUriToPath(GDirUri);
    Path := ResolveExportListPath(Path, Dir, TPath.GetDocumentsPath);
    try
      Bytes := TEncoding.UTF8.GetBytes(FormatItemList(GItems, Cfg, Path, Titles));
      if ListExportNeedsBom(Cfg.Format, Path) then
        Bytes := TEncoding.UTF8.GetPreamble + Bytes;
      TFile.WriteAllBytes(Path, Bytes);
      Notice(Format(Tr('msg.saved', 'Saved %d items to %s'), [Length(GItems), Path]), 0);
    except
      on E: Exception do
        Notice(Tr('msg.failed', 'Could not save the list') + ': ' + E.Message, 1);
    end;
  except
    // Never let an exception cross into the host.
  end;
end;

{ ---- panel -------------------------------------------------------------- }

function DateOrZero(AValue: Double): TDateTime;
begin
  if AValue > 0 then
    Result := AValue
  else
    Result := 0;
end;

procedure AddRow(ARow: TJSONObject);
var
  Item: TListExportItem;
  Uri, S: string;
  D: Double;
  Size: Int64;
begin
  if not ARow.TryGetValue<string>('uri', Uri) or not Uri.StartsWith('file:', True) or
     (Pos('!/', Uri) > 0) then
    Exit;
  Item := Default(TListExportItem);
  Item.FullPath := FileUriToPath(Uri);
  if Item.FullPath = '' then
    Exit;
  Item.Name := ExtractFileName(ExcludeTrailingPathDelimiter(Item.FullPath));
  ARow.TryGetValue<Boolean>('dir', Item.IsDir);
  if (not Item.IsDir) and ARow.TryGetValue<Int64>('size', Size) then
    Item.Size := Size;
  if ARow.TryGetValue<Double>('mtime', D) then
    Item.Modified := DateOrZero(D);
  if ARow.TryGetValue<Double>('ctime', D) then
    Item.Created := DateOrZero(D);
  if ARow.TryGetValue<Double>('atime', D) then
    Item.Accessed := DateOrZero(D);
  if ARow.TryGetValue<string>('ext', S) then
    Item.Ext := S;
  if ARow.TryGetValue<string>('type', S) then
    Item.TypeName := S;
  if ARow.TryGetValue<string>('attr', S) then
    Item.Attr := S;
  GItems := GItems + [Item];
end;

{ Reads the panel: the selected rows of the active panel, or the row under the
  cursor, become the list. False, with a message shown, when there is none. }
function CollectItems: Boolean;
begin
  GItems := nil;
  Result := ForEachSelectedRow(GDirUri, AddRow) and (Length(GItems) > 0);
  if not Result then
    Notice(Tr('msg.nothing', 'Nothing to save'), 1);
end;

procedure CmdRun(AUserData: Pointer); cdecl;
var
  Decl: TJSONObject;
  Json, Plugin: UTF8String;
begin
  try
    if not CollectItems then
      Exit;
    GConfig := LoadConfig;
    Decl := BuildDeclaration;
    try
      Json := UTF8String(Decl.ToJSON);
    finally
      Decl.Free;
    end;
    Plugin := UTF8String(cPluginId);
    if not Assigned(GHostApi.ShowDialog) or
       (GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), @OnDialogCommand, nil) <> 0) then
      Notice(Tr('msg.noDialog', 'The dialog cannot be shown now'), 1);
  except
    // Never let an exception cross into the host.
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  PluginId, CommandId: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 13) or not Assigned(AHostApi.PanelInfo) or
     not Assigned(AHostApi.PanelList) or not Assigned(AHostApi.ShowDialog) or
     not Assigned(AHostApi.RegisterCommand) then
    Exit(-1);
  SdkAttach(AHostApi, cPluginId);
  PluginId := UTF8String(cPluginId);
  CommandId := UTF8String(cCommandId);
  GHostApi.RegisterCommand(PAnsiChar(PluginId), PAnsiChar(CommandId), @CmdRun, nil);
  if Assigned(GHostApi.RegisterMenuItem) then
    GHostApi.RegisterMenuItem(PAnsiChar(PluginId), 'Files', PAnsiChar(CommandId),
      PAnsiChar(UTF8String(Tr('menu.run', 'Export list...'))), @CmdRun, nil, 50);
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GItems := nil;
  SdkDetach;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
