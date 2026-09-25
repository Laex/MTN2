unit uUserMenu;

{ User menu (F2) data: a tree of commands, submenus and separators kept in
  usermenu.json in the config directory, plus FAR-style macro expansion for
  the commands. The popup lives in uUserMenuController.pas, the editing
  dialogs and execution in uDualPanelUserMenu.pas.

  Folder menus: a .mtn2menu.json (same format) in a folder applies to that
  folder and every folder below it; the nearest one wins
  (FindFolderUserMenu).

  Macros (FAR Manager names):
    !!                a literal '!'
    !.!               file name under the cursor, with extension
    !                 the same name without extension
    !\                panel folder with a trailing '\'
    !:                drive of the panel folder ("C:")
    !&                selected names (or the current one), space separated,
                      quoted when needed
    !@!               path of a temp file listing the selected items' full
                      paths, one per line (UTF-8)
    !?Title?Default!  ask the user; replaced by the answer
    !#  /  !^         following macros refer to the passive / active panel }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TUserMenuKind = (umkCommand, umkSubmenu, umkSeparator);

  TUserMenuItem = class
  private
    FItems: TObjectList<TUserMenuItem>;
  public
    Kind: TUserMenuKind;
    /// <summary>One character; '' = no hotkey.</summary>
    HotKey: string;
    Caption: string;
    Command: string;
    constructor Create(AKind: TUserMenuKind = umkCommand);
    destructor Destroy; override;
    /// <summary>Submenu children. Allocated for every item so a kind change
    /// in the editor never needs a nil check; only submenus save it.</summary>
    property Items: TObjectList<TUserMenuItem> read FItems;
  end;

  TUserMenuPanelInfo = record
    /// <summary>Local folder of the panel; '' when it is not a local folder
    /// (archive, SFTP, ...).</summary>
    Path: string;
    /// <summary>Name under the cursor; '' on the ".." row.</summary>
    CurrentName: string;
    /// <summary>Selected names, or just CurrentName when nothing is
    /// selected.</summary>
    SelectedNames: TArray<string>;
  end;

  TUserMenuContext = record
    Active, Passive: TUserMenuPanelInfo;
  end;

  TUserMenuPrompt = record
    Title: string;
    Default: string;
  end;

  /// <summary>Creates the !@! list file from full paths and returns its
  /// path.</summary>
  TUserMenuListFileFactory = reference to function(
    const APaths: TArray<string>): string;

const
  cFolderUserMenuFile = '.mtn2menu.json';

function DefaultUserMenuFilePath: string;
/// <summary>AFolder\.mtn2menu.json (whether or not it exists).</summary>
function FolderUserMenuPath(const AFolder: string): string;
/// <summary>The folder menu file of AFolder or of its nearest ancestor that
/// has one; '' when there is none (or AFolder is not a local folder).</summary>
function FindFolderUserMenu(const AFolder: string): string;
/// <summary>Built-in menu shown until the user saves their own.</summary>
function DefaultUserMenu: TUserMenuItem;
/// <summary>Root (a umkSubmenu) parsed from JSON; nil when the text is not
/// a user menu.</summary>
function UserMenuFromJson(const AText: string): TUserMenuItem;
function UserMenuToJson(ARoot: TUserMenuItem): string;
/// <summary>The saved menu; when the file is missing, DefaultUserMenu (or an
/// empty menu with AExamplesIfMissing = False); an empty menu when it is
/// unreadable. Never nil.</summary>
function LoadUserMenu(const APath: string;
  AExamplesIfMissing: Boolean = True): TUserMenuItem;
function SaveUserMenu(const APath: string; ARoot: TUserMenuItem): Boolean;

/// <summary>The !?Title?Default! prompts of ATemplate, in order.</summary>
function ParseUserMenuPrompts(const ATemplate: string): TArray<TUserMenuPrompt>;
/// <summary>ATemplate with every macro replaced. APromptValues answer the
/// prompts in order (missing answers fall back to the prompt default).
/// AListFile creates the !@! file; nil = WriteUserMenuListFile.</summary>
function ExpandUserMenuCommand(const ATemplate: string;
  const ACtx: TUserMenuContext; const APromptValues: TArray<string>;
  const AListFile: TUserMenuListFileFactory = nil): string;
/// <summary>Default !@! factory: a UTF-8 file in %TEMP%\MTN2 (files there
/// older than a day are removed on the way).</summary>
function WriteUserMenuListFile(const APaths: TArray<string>): string;
/// <summary>Quotes AName for a command line when it contains a space or a
/// shell metacharacter.</summary>
function UserMenuQuote(const AName: string): string;

implementation

uses
  System.IOUtils, System.JSON, System.DateUtils, uConfigLocation, uStrings;

const
  cUserMenuFile = 'usermenu.json';

{ TUserMenuItem }

constructor TUserMenuItem.Create(AKind: TUserMenuKind);
begin
  inherited Create;
  Kind := AKind;
  FItems := TObjectList<TUserMenuItem>.Create(True);
end;

destructor TUserMenuItem.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

{ Storage }

function DefaultUserMenuFilePath: string;
begin
  Result := GetConfigFilePath(cUserMenuFile);
end;

function FolderUserMenuPath(const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, cFolderUserMenuFile);
end;

function FindFolderUserMenu(const AFolder: string): string;
var
  Dir, Parent: string;
begin
  Result := '';
  Dir := ExcludeTrailingPathDelimiter(AFolder);
  while Dir <> '' do
  begin
    if TFile.Exists(FolderUserMenuPath(Dir)) then
      Exit(FolderUserMenuPath(Dir));
    Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if SameText(Parent, Dir) then
      Break; // drive root ("C:") or UNC share root
    Dir := Parent;
  end;
end;

function NewItem(AKind: TUserMenuKind; const AHotKey, ACaption,
  ACommand: string): TUserMenuItem;
begin
  Result := TUserMenuItem.Create(AKind);
  Result.HotKey := AHotKey;
  Result.Caption := ACaption;
  Result.Command := ACommand;
end;

function DefaultUserMenu: TUserMenuItem;
var
  Sub: TUserMenuItem;
begin
  // Examples only, until the user saves a menu of their own. Commands run
  // in the panel console, whose shell may be cmd, PowerShell or WSL, so
  // they avoid shell-specific syntax (no "start", no "&&").
  Result := TUserMenuItem.Create(umkSubmenu);
  Result.Items.Add(NewItem(umkCommand, 'E',
    T('ui.userMenu.sample.explorer', 'Show in Explorer'),
    'explorer.exe /select,"!\!.!"'));
  Result.Items.Add(NewItem(umkCommand, 'N',
    T('ui.userMenu.sample.notepad', 'Open in Notepad'),
    'notepad.exe "!\!.!"'));
  Result.Items.Add(NewItem(umkCommand, 'H',
    T('ui.userMenu.sample.hash', 'SHA-256 of the file'),
    'certutil -hashfile "!.!" SHA256'));
  Result.Items.Add(NewItem(umkSeparator, '', '', ''));
  Sub := NewItem(umkSubmenu, 'G', 'Git', '');
  Sub.Items.Add(NewItem(umkCommand, 'S',
    T('ui.userMenu.sample.gitStatus', 'Status'), 'git status'));
  Sub.Items.Add(NewItem(umkCommand, 'L',
    T('ui.userMenu.sample.gitLog', 'Log (last 20)'), 'git log --oneline -20'));
  Sub.Items.Add(NewItem(umkCommand, 'D',
    T('ui.userMenu.sample.gitDiff', 'Diff of the file'), 'git diff -- "!.!"'));
  Sub.Items.Add(NewItem(umkCommand, 'C',
    T('ui.userMenu.sample.gitCommit', 'Commit all...'),
    'git commit -am "!?' + T('ui.userMenu.sample.gitCommitPrompt', 'Commit message') + '?!"'));
  Result.Items.Add(Sub);
end;

function KindToJson(AKind: TUserMenuKind): string;
begin
  case AKind of
    umkSubmenu: Result := 'submenu';
    umkSeparator: Result := 'separator';
  else
    Result := 'command';
  end;
end;

function JsonToKind(const AStr: string): TUserMenuKind;
var
  S: string;
begin
  S := LowerCase(Trim(AStr));
  if S = 'submenu' then
    Result := umkSubmenu
  else if S = 'separator' then
    Result := umkSeparator
  else
    Result := umkCommand;
end;

function JsonStr(AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONString then
    Result := TJSONString(V).Value
  else
    Result := '';
end;

procedure ReadItems(AArr: TJSONArray; AParent: TUserMenuItem);
var
  I: Integer;
  Obj: TJSONObject;
  Item: TUserMenuItem;
  Sub: TJSONValue;
begin
  for I := 0 to AArr.Count - 1 do
  begin
    if not (AArr.Items[I] is TJSONObject) then
      Continue; // a corrupt row is skipped, not fatal
    Obj := TJSONObject(AArr.Items[I]);
    Sub := Obj.GetValue('items');
    // "kind" is optional: a row with "items" is a submenu.
    if Obj.GetValue('kind') is TJSONString then
      Item := TUserMenuItem.Create(JsonToKind(JsonStr(Obj, 'kind')))
    else if Sub is TJSONArray then
      Item := TUserMenuItem.Create(umkSubmenu)
    else
      Item := TUserMenuItem.Create(umkCommand);
    Item.HotKey := Copy(JsonStr(Obj, 'hotkey'), 1, 1);
    Item.Caption := JsonStr(Obj, 'caption');
    Item.Command := JsonStr(Obj, 'command');
    if (Item.Kind = umkSubmenu) and (Sub is TJSONArray) then
      ReadItems(TJSONArray(Sub), Item);
    AParent.Items.Add(Item);
  end;
end;

function UserMenuFromJson(const AText: string): TUserMenuItem;
var
  Val, Items: TJSONValue;
begin
  Result := nil;
  Val := TJSONObject.ParseJSONValue(AText);
  if not Assigned(Val) then
    Exit;
  try
    if not (Val is TJSONObject) then
      Exit;
    Items := TJSONObject(Val).GetValue('items');
    if not (Items is TJSONArray) then
      Exit;
    Result := TUserMenuItem.Create(umkSubmenu);
    ReadItems(TJSONArray(Items), Result);
  finally
    Val.Free;
  end;
end;

function ItemsToJson(AParent: TUserMenuItem): TJSONArray;
var
  Item: TUserMenuItem;
  Obj: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Item in AParent.Items do
  begin
    Obj := TJSONObject.Create;
    Obj.AddPair('kind', KindToJson(Item.Kind));
    if Item.Kind <> umkSeparator then
    begin
      if Item.HotKey <> '' then
        Obj.AddPair('hotkey', Item.HotKey);
      Obj.AddPair('caption', Item.Caption);
    end;
    case Item.Kind of
      umkCommand: Obj.AddPair('command', Item.Command);
      umkSubmenu: Obj.AddPair('items', ItemsToJson(Item));
    end;
    Result.Add(Obj);
  end;
end;

function UserMenuToJson(ARoot: TUserMenuItem): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Root.AddPair('items', ItemsToJson(ARoot));
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

function LoadUserMenu(const APath: string;
  AExamplesIfMissing: Boolean): TUserMenuItem;
begin
  if not TFile.Exists(APath) then
  begin
    if AExamplesIfMissing then
      Exit(DefaultUserMenu);
    Exit(TUserMenuItem.Create(umkSubmenu));
  end;
  try
    Result := UserMenuFromJson(TFile.ReadAllText(APath, TEncoding.UTF8));
  except
    Result := nil;
  end;
  // Unreadable file: an empty menu rather than the examples, so a save
  // from the editor does not silently replace the user's broken file with
  // demo items they never asked for.
  if not Assigned(Result) then
    Result := TUserMenuItem.Create(umkSubmenu);
end;

function SaveUserMenu(const APath: string; ARoot: TUserMenuItem): Boolean;
var
  Dir: string;
begin
  Result := False;
  if not Assigned(ARoot) then
    Exit;
  try
    Dir := ExtractFilePath(APath);
    if Dir <> '' then
      ForceDirectories(Dir);
    TFile.WriteAllText(APath, UserMenuToJson(ARoot), TEncoding.UTF8);
    Result := True;
  except
    { leave Result = False }
  end;
end;

{ Macros }

function UserMenuQuote(const AName: string): string;
begin
  if (AName <> '') and (AName.IndexOfAny([' ', '&', '(', ')', '^', ';', ',', '=']) < 0) then
    Result := AName
  else
    Result := '"' + AName + '"';
end;

function WriteUserMenuListFile(const APaths: TArray<string>): string;
var
  Dir, F: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'MTN2');
  ForceDirectories(Dir);
  try
    for F in TDirectory.GetFiles(Dir, 'list-*.txt') do
      if HoursBetween(Now, TFile.GetLastWriteTime(F)) >= 24 then
        TFile.Delete(F);
  except
    // Cleanup is best effort: a file still open elsewhere just stays.
  end;
  Result := TPath.Combine(Dir, 'list-' + TPath.GetGUIDFileName + '.txt');
  TFile.WriteAllLines(Result, APaths, TEncoding.UTF8);
end;

function NameWithoutExt(const AName: string): string;
var
  P: Integer;
begin
  P := AName.LastDelimiter('.');
  // ".gitignore" has no extension to strip.
  if P > 0 then
    Result := Copy(AName, 1, P)
  else
    Result := AName;
end;

function PanelFolder(const AInfo: TUserMenuPanelInfo): string;
begin
  if AInfo.Path = '' then
    Result := ''
  else
    Result := IncludeTrailingPathDelimiter(AInfo.Path);
end;

// One pass shared by prompt collection and expansion so both agree on
// what is a macro ('!!', '!.!' ...) and what is plain text.
function ScanUserMenuCommand(const ATemplate: string; const ACtx: TUserMenuContext;
  const APromptValues: TArray<string>; const AListFile: TUserMenuListFileFactory;
  APrompts: TList<TUserMenuPrompt>): string;
var
  SB: TStringBuilder;
  I, N, Q, E, PromptIdx: Integer;
  Info: TUserMenuPanelInfo;
  Next: Char;
  Prompt: TUserMenuPrompt;
  Names, Paths: TArray<string>;
  J: Integer;
begin
  SB := TStringBuilder.Create;
  try
    N := Length(ATemplate);
    Info := ACtx.Active;
    PromptIdx := 0;
    I := 1;
    while I <= N do
    begin
      if ATemplate[I] <> '!' then
      begin
        SB.Append(ATemplate[I]);
        Inc(I);
        Continue;
      end;
      if I < N then
        Next := ATemplate[I + 1]
      else
        Next := #0;
      case Next of
        '!':
          begin
            SB.Append('!');
            Inc(I, 2);
          end;
        '#':
          begin
            Info := ACtx.Passive;
            Inc(I, 2);
          end;
        '^':
          begin
            Info := ACtx.Active;
            Inc(I, 2);
          end;
        '\':
          begin
            SB.Append(PanelFolder(Info));
            Inc(I, 2);
          end;
        ':':
          begin
            SB.Append(ExtractFileDrive(Info.Path));
            Inc(I, 2);
          end;
        '&':
          begin
            Names := Info.SelectedNames;
            for J := 0 to High(Names) do
            begin
              if J > 0 then
                SB.Append(' ');
              SB.Append(UserMenuQuote(Names[J]));
            end;
            Inc(I, 2);
          end;
        '?':
          begin
            // !?Title?Default!
            Q := Pos('?', ATemplate, I + 2);
            E := 0;
            if Q > 0 then
              E := Pos('!', ATemplate, Q + 1);
            if E = 0 then
            begin
              // Not a well-formed prompt: keep the text as typed.
              SB.Append(Copy(ATemplate, I, MaxInt));
              Break;
            end;
            Prompt.Title := Copy(ATemplate, I + 2, Q - I - 2);
            Prompt.Default := Copy(ATemplate, Q + 1, E - Q - 1);
            if Assigned(APrompts) then
              APrompts.Add(Prompt);
            if PromptIdx <= High(APromptValues) then
              SB.Append(APromptValues[PromptIdx])
            else
              SB.Append(Prompt.Default);
            Inc(PromptIdx);
            I := E + 1;
          end;
      else
        if (Next = '.') and (I + 2 <= N) and (ATemplate[I + 2] = '!') then
        begin
          SB.Append(Info.CurrentName);
          Inc(I, 3);
        end
        else if (Next = '@') and (I + 2 <= N) and (ATemplate[I + 2] = '!') then
        begin
          // Only a real expansion writes the file, not prompt collection.
          if not Assigned(APrompts) then
          begin
            SetLength(Paths, Length(Info.SelectedNames));
            for J := 0 to High(Paths) do
              Paths[J] := PanelFolder(Info) + Info.SelectedNames[J];
            if Assigned(AListFile) then
              SB.Append(AListFile(Paths))
            else
              SB.Append(WriteUserMenuListFile(Paths));
          end;
          Inc(I, 3);
        end
        else
        begin
          // Lone '!': the name without its extension.
          SB.Append(NameWithoutExt(Info.CurrentName));
          Inc(I);
        end;
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function ParseUserMenuPrompts(const ATemplate: string): TArray<TUserMenuPrompt>;
var
  List: TList<TUserMenuPrompt>;
  Ctx: TUserMenuContext;
begin
  Ctx := Default(TUserMenuContext);
  List := TList<TUserMenuPrompt>.Create;
  try
    ScanUserMenuCommand(ATemplate, Ctx, nil, nil, List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ExpandUserMenuCommand(const ATemplate: string;
  const ACtx: TUserMenuContext; const APromptValues: TArray<string>;
  const AListFile: TUserMenuListFileFactory): string;
begin
  Result := ScanUserMenuCommand(ATemplate, ACtx, APromptValues, AListFile, nil);
end;

end.
