unit uUserAssociations;

{ User-defined file associations (Enter override layer, mirrors Far's F9 ->
  Commands -> File associations / TC's Internal Associations). Sits between
  "always launch" executables and the built-in extension table in
  uAssociations.pas:

    1. Launchable (.exe/.bat/...) -- always platform shell, never overridden.
    2. Archive navigation -- decided upstream in uDualPanelWindow.ActivateCurrent
       via uVfsRegistry, before this unit is even consulted.
    3. User-defined rule for the extension, if any (this unit).
    4. uAssociations.ResolveAssociation's hardcoded table / OS ShellExecute.

  Persisted as a flat list to <config>\associations.json, following the same
  hand-rolled System.JSON convention as uSession.pas (missing/corrupt file =
  empty list, never blocks startup). }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAssociations;

type
  TUserAssocAction = (
    uaaView,
    uaaEdit,
    uaaShell,
    /// <summary>Runs Command with %1 substituted for the quoted file path
    /// (see BuildAssocCommandLine).</summary>
    uaaCommand
  );

  TUserAssocRule = record
    /// <summary>Normalized via NormalizeFileExtension: lowercase, leading
    /// dot (e.g. '.log'); '' matches extension-less files.</summary>
    Extension: string;
    Action: TUserAssocAction;
    /// <summary>Only meaningful when Action = uaaCommand.</summary>
    Command: string;
  end;

  TUserAssociations = class
  private
    FRules: TList<TUserAssocRule>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function GetRule(AIndex: Integer): TUserAssocRule;
    procedure SetRule(AIndex: Integer; const ARule: TUserAssocRule);
    procedure AddRule(const ARule: TUserAssocRule);
    procedure DeleteRule(AIndex: Integer);
    /// <summary>-1 if ARule.Extension (already-normalized) is not present.</summary>
    function IndexOfExtension(const AExtension: string): Integer;
    /// <summary>Upserts by extension: replaces an existing rule for the same
    /// extension, otherwise appends. Extension is normalized first.</summary>
    procedure SetRuleForExtension(const ARule: TUserAssocRule);
    function TryResolve(const AFileName: string; out ARule: TUserAssocRule): Boolean;
  end;

function NormalizeAssocExtension(const AExtOrName: string): string;
function UserAssocActionLabel(AAction: TUserAssocAction): string;
/// <summary>Display row for the associations list dialog, e.g.
/// ".iso        Run command   mount.exe "%1"" -- see
/// uDualPanelUserAssociations.TUserAssociationsDialogController.OpenList.</summary>
function UserAssocRuleDisplayLabel(const ARule: TUserAssocRule): string;
/// <summary>Substitutes the (quoted) file path for every "%1" in ATemplate;
/// if ATemplate has no "%1" placeholder, appends the quoted path instead
/// (so a bare "notepad.exe"-style template still works).</summary>
function BuildAssocCommandLine(const ATemplate, AFilePath: string): string;

function DefaultUserAssociationsFilePath: string;
function TryLoadUserAssociations(const APath: string; AAssoc: TUserAssociations): Boolean;
function SaveUserAssociations(const APath: string; AAssoc: TUserAssociations): Boolean;

/// <summary>Process-wide singleton, lazily loaded from
/// DefaultUserAssociationsFilePath on first access -- mirrors
/// uVfsRegistry.GlobalVfsRegistry. Callers that change rules through this
/// instance are responsible for calling SaveUserAssociations themselves
/// (the settings dialog controller does this on OK).</summary>
function GlobalUserAssociations: TUserAssociations;

/// <summary>ResolveAssociation (uAssociations.pas) with the user-rule layer
/// spliced in ahead of the hardcoded extension table, but still behind
/// "always launch" executables. ACommand is only meaningful when the result
/// is aaCommand -- pass it to BuildAssocCommandLine's caller as-is (already
/// the raw user template; the file path is substituted by the caller since
/// only it knows the file's URI/local path).</summary>
function ResolveAssociationWithUserRules(const AName: string; AIsDirectory: Boolean;
  out ACommand: string): TAssocAction;

implementation

uses
  System.Classes, System.IOUtils, System.JSON,
  uConfigLocation, uShellAssoc;

function NormalizeAssocExtension(const AExtOrName: string): string;
begin
  Result := NormalizeFileExtension(AExtOrName);
end;

function UserAssocActionLabel(AAction: TUserAssocAction): string;
begin
  case AAction of
    uaaView: Result := 'View';
    uaaEdit: Result := 'Edit';
    uaaShell: Result := 'Shell';
    uaaCommand: Result := 'Run command';
  else
    Result := '';
  end;
end;

function PadRight(const S: string; AWidth: Integer): string;
begin
  if Length(S) >= AWidth then
    Result := S + ' '
  else
    Result := S + StringOfChar(' ', AWidth - Length(S));
end;

function UserAssocRuleDisplayLabel(const ARule: TUserAssocRule): string;
begin
  Result := PadRight(ARule.Extension, 12) + PadRight(UserAssocActionLabel(ARule.Action), 14);
  if ARule.Action = uaaCommand then
    Result := Result + ARule.Command;
end;

function BuildAssocCommandLine(const ATemplate, AFilePath: string): string;
var
  Quoted: string;
begin
  Quoted := '"' + AFilePath + '"';
  if Pos('%1', ATemplate) > 0 then
    Result := StringReplace(ATemplate, '%1', Quoted, [rfReplaceAll])
  else
    Result := Trim(Trim(ATemplate) + ' ' + Quoted);
end;

constructor TUserAssociations.Create;
begin
  inherited Create;
  FRules := TList<TUserAssocRule>.Create;
end;

destructor TUserAssociations.Destroy;
begin
  FreeAndNil(FRules);
  inherited Destroy;
end;

procedure TUserAssociations.Clear;
begin
  FRules.Clear;
end;

function TUserAssociations.Count: Integer;
begin
  Result := FRules.Count;
end;

function TUserAssociations.GetRule(AIndex: Integer): TUserAssocRule;
begin
  Result := FRules[AIndex];
end;

procedure TUserAssociations.SetRule(AIndex: Integer; const ARule: TUserAssocRule);
var
  Rule: TUserAssocRule;
begin
  Rule := ARule;
  Rule.Extension := NormalizeAssocExtension(ARule.Extension);
  FRules[AIndex] := Rule;
end;

procedure TUserAssociations.AddRule(const ARule: TUserAssocRule);
var
  Rule: TUserAssocRule;
begin
  Rule := ARule;
  Rule.Extension := NormalizeAssocExtension(ARule.Extension);
  FRules.Add(Rule);
end;

procedure TUserAssociations.DeleteRule(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FRules.Count) then
    FRules.Delete(AIndex);
end;

function TUserAssociations.IndexOfExtension(const AExtension: string): Integer;
var
  Norm: string;
  I: Integer;
begin
  Norm := NormalizeAssocExtension(AExtension);
  for I := 0 to FRules.Count - 1 do
    if FRules[I].Extension = Norm then
      Exit(I);
  Result := -1;
end;

procedure TUserAssociations.SetRuleForExtension(const ARule: TUserAssocRule);
var
  Rule: TUserAssocRule;
  Idx: Integer;
begin
  Rule := ARule;
  Rule.Extension := NormalizeAssocExtension(ARule.Extension);
  Idx := IndexOfExtension(Rule.Extension);
  if Idx >= 0 then
    FRules[Idx] := Rule
  else
    FRules.Add(Rule);
end;

function TUserAssociations.TryResolve(const AFileName: string;
  out ARule: TUserAssocRule): Boolean;
var
  Idx: Integer;
begin
  Idx := IndexOfExtension(NormalizeAssocExtension(AFileName));
  Result := Idx >= 0;
  if Result then
    ARule := FRules[Idx];
end;

function DefaultUserAssociationsFilePath: string;
begin
  Result := GetConfigFilePath('associations.json');
end;

function ActionToJsonStr(AAction: TUserAssocAction): string;
begin
  case AAction of
    uaaView: Result := 'view';
    uaaEdit: Result := 'edit';
    uaaShell: Result := 'shell';
    uaaCommand: Result := 'command';
  else
    Result := 'view';
  end;
end;

function JsonStrToAction(const AStr: string; out AAction: TUserAssocAction): Boolean;
var
  S: string;
begin
  S := LowerCase(Trim(AStr));
  Result := True;
  if S = 'view' then AAction := uaaView
  else if S = 'edit' then AAction := uaaEdit
  else if S = 'shell' then AAction := uaaShell
  else if S = 'command' then AAction := uaaCommand
  else Result := False;
end;

function SaveUserAssociations(const APath: string; AAssoc: TUserAssociations): Boolean;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Rule: TUserAssocRule;
  RuleObj: TJSONObject;
  Dir, Text: string;
begin
  Result := False;
  if AAssoc = nil then
    Exit;
  Root := TJSONObject.Create;
  try
    try
      Arr := TJSONArray.Create;
      for I := 0 to AAssoc.Count - 1 do
      begin
        Rule := AAssoc.GetRule(I);
        RuleObj := TJSONObject.Create;
        RuleObj.AddPair('ext', Rule.Extension);
        RuleObj.AddPair('action', ActionToJsonStr(Rule.Action));
        if Rule.Action = uaaCommand then
          RuleObj.AddPair('command', Rule.Command);
        Arr.Add(RuleObj);
      end;
      Root.AddPair('rules', Arr);
      Dir := ExtractFilePath(APath);
      if Dir <> '' then
        ForceDirectories(Dir);
      Text := Root.ToJSON;
      TFile.WriteAllText(APath, Text, TEncoding.UTF8);
      Result := True;
    except
      { leave Result = False }
    end;
  finally
    Root.Free;
  end;
end;

function TryLoadUserAssociations(const APath: string; AAssoc: TUserAssociations): Boolean;
var
  Text: string;
  RootVal: TJSONValue;
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONValue;
  RuleObj: TJSONObject;
  V: TJSONValue;
  Rule: TUserAssocRule;
  Action: TUserAssocAction;
begin
  Result := False;
  if AAssoc = nil then
    Exit;
  AAssoc.Clear;
  if not TFile.Exists(APath) then
    Exit;
  try
    Text := TFile.ReadAllText(APath, TEncoding.UTF8);
    RootVal := TJSONObject.ParseJSONValue(Text);
    if not (RootVal is TJSONObject) then
    begin
      RootVal.Free;
      Exit;
    end;
    Root := TJSONObject(RootVal);
    try
      V := Root.GetValue('rules');
      if V is TJSONArray then
      begin
        Arr := TJSONArray(V);
        for I := 0 to Arr.Count - 1 do
        begin
          Item := Arr.Items[I];
          if not (Item is TJSONObject) then
            Continue;
          RuleObj := TJSONObject(Item);
          Rule.Extension := '';
          Rule.Command := '';
          Rule.Action := uaaShell;
          if (RuleObj.GetValue('ext') is TJSONString) then
            Rule.Extension := NormalizeAssocExtension(
              TJSONString(RuleObj.GetValue('ext')).Value);
          if Rule.Extension = '' then
            Continue; // corrupt row -- skip rather than fail the whole load
          if (RuleObj.GetValue('action') is TJSONString) and
            JsonStrToAction(TJSONString(RuleObj.GetValue('action')).Value, Action) then
            Rule.Action := Action;
          if RuleObj.GetValue('command') is TJSONString then
            Rule.Command := TJSONString(RuleObj.GetValue('command')).Value;
          AAssoc.AddRule(Rule);
        end;
      end;
      Result := True;
    finally
      Root.Free;
    end;
  except
    { corrupt file -- fall back to the empty list already set above }
  end;
end;

var
  GGlobalUserAssociations: TUserAssociations;

function GlobalUserAssociations: TUserAssociations;
begin
  if GGlobalUserAssociations = nil then
  begin
    GGlobalUserAssociations := TUserAssociations.Create;
    TryLoadUserAssociations(DefaultUserAssociationsFilePath, GGlobalUserAssociations);
  end;
  Result := GGlobalUserAssociations;
end;

function ResolveAssociationWithUserRules(const AName: string; AIsDirectory: Boolean;
  out ACommand: string): TAssocAction;
var
  Ext: string;
  Rule: TUserAssocRule;
begin
  ACommand := '';
  if AIsDirectory then
    Exit(aaNavigate);

  Ext := NormalizeFileExtension(AName);
  // Priority 1 (matches Far/TC/NDN): executables always launch, never
  // overridable by a user rule.
  if IsLaunchableExt(Ext) then
    Exit(ResolveAssociation(AName, False));

  if GlobalUserAssociations.TryResolve(AName, Rule) then
  begin
    case Rule.Action of
      uaaView: Exit(aaView);
      uaaEdit: Exit(aaEdit);
      uaaShell: Exit(aaShell);
      uaaCommand:
        begin
          ACommand := Rule.Command;
          Exit(aaCommand);
        end;
    end;
  end;

  Result := ResolveAssociation(AName, False);
end;

initialization

finalization
  FreeAndNil(GGlobalUserAssociations);

end.
