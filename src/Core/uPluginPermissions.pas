unit uPluginPermissions;

{ What a plugin may do beyond the basics. A permission is named in the plugin's
  manifest ("permissions": ["vfs.read"]) and takes effect only once the user
  grants it (Plugins dialog, Permissions button; remembered in
  plugin-permissions.json in the settings folder). A host call that needs a
  permission is refused until both hold.

  The check keys on the plugin id the plugin passes to the host call, and a
  native plugin runs in the program's own process: the permissions keep honest
  plugins in the declared bounds and tell the user what a plugin wants, but do
  not sandbox a hostile DLL. A WASM plugin has no other way to reach the host. }

interface

uses
  System.SysUtils;

const
  /// <summary>List folders, check existence and read files through any scheme.</summary>
  cPermVfsRead = 'vfs.read';

/// <summary>True for a permission name this host knows.</summary>
function IsKnownPermission(const AName: string): Boolean;
/// <summary>The known permission names, in the order the dialogs show them.</summary>
function KnownPermissions: TArray<string>;

/// <summary>Records what the manifest of APluginId asks for (unknown names are
/// dropped). Called when the manifest is read; replaces an earlier declaration.</summary>
procedure PluginPermissionsDeclare(const APluginId: string; const APermissions: TArray<string>);
function PluginPermissionsDeclared(const APluginId: string): TArray<string>;

/// <summary>Replaces every grant with the ones in AFileName (settings folder);
/// a missing or malformed file grants nothing.</summary>
procedure LoadPermissionGrants(const AFileName: string);
procedure SavePermissionGrants(const AFileName: string);
procedure ClearPermissionGrants;
/// <summary>Grants or takes back one permission of one plugin.</summary>
procedure PluginPermissionGrant(const APluginId, APermission: string; AGranted: Boolean);
function PluginPermissionGranted(const APluginId, APermission: string): Boolean;
/// <summary>The permission is both asked for by the manifest and granted by the user.</summary>
function PluginHasPermission(const APluginId, APermission: string): Boolean;
/// <summary>Grants every permission the manifest asks for, or takes them all back.</summary>
procedure PluginPermissionsGrantAll(const APluginId: string; AGranted: Boolean);
/// <summary>True when every declared permission of the plugin is granted
/// (False when it declares none).</summary>
function PluginPermissionsAllGranted(const APluginId: string): Boolean;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Generics.Collections;

var
  GDeclared: TDictionary<string, TArray<string>>;
  GGranted: TDictionary<string, TArray<string>>;

function Key(const APluginId: string): string;
begin
  Result := LowerCase(Trim(APluginId));
end;

function IndexIn(const AList: TArray<string>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AList) do
    if SameText(AList[I], AName) then
      Exit(I);
  Result := -1;
end;

function KnownPermissions: TArray<string>;
begin
  Result := [cPermVfsRead];
end;

function IsKnownPermission(const AName: string): Boolean;
begin
  Result := IndexIn(KnownPermissions, Trim(AName)) >= 0;
end;

procedure PluginPermissionsDeclare(const APluginId: string; const APermissions: TArray<string>);
var
  List: TArray<string>;
  P: string;
begin
  if Key(APluginId) = '' then
    Exit;
  SetLength(List, 0);
  for P in APermissions do
    if IsKnownPermission(P) and (IndexIn(List, Trim(P)) < 0) then
      List := List + [LowerCase(Trim(P))];
  if Length(List) = 0 then
    GDeclared.Remove(Key(APluginId))
  else
    GDeclared.AddOrSetValue(Key(APluginId), List);
end;

function PluginPermissionsDeclared(const APluginId: string): TArray<string>;
begin
  if not GDeclared.TryGetValue(Key(APluginId), Result) then
    SetLength(Result, 0);
end;

procedure ClearPermissionGrants;
begin
  GGranted.Clear;
end;

procedure LoadPermissionGrants(const AFileName: string);
var
  Val: TJSONValue;
  Grants: TJSONObject;
  Pair: TJSONPair;
  Arr: TJSONArray;
  I: Integer;
  List: TArray<string>;
begin
  GGranted.Clear;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  try
    Val := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if not (Val is TJSONObject) then
      Exit;
    Grants := TJSONObject(Val).Values['grant'] as TJSONObject;
    if Grants = nil then
      Exit;
    for Pair in Grants do
      if Pair.JsonValue is TJSONArray then
      begin
        Arr := TJSONArray(Pair.JsonValue);
        SetLength(List, 0);
        for I := 0 to Arr.Count - 1 do
          if (Arr.Items[I] is TJSONString) and IsKnownPermission(TJSONString(Arr.Items[I]).Value) then
            List := List + [LowerCase(Trim(TJSONString(Arr.Items[I]).Value))];
        if Length(List) > 0 then
          GGranted.AddOrSetValue(Key(Pair.JsonString.Value), List);
      end;
  finally
    Val.Free;
  end;
end;

procedure SavePermissionGrants(const AFileName: string);
var
  Root, Grants: TJSONObject;
  Arr: TJSONArray;
  Pair: TPair<string, TArray<string>>;
  P: string;
begin
  if AFileName = '' then
    Exit;
  try
    if GGranted.Count = 0 then
    begin
      if TFile.Exists(AFileName) then
        TFile.Delete(AFileName);
      Exit;
    end;
    Root := TJSONObject.Create;
    try
      Grants := TJSONObject.Create;
      Root.AddPair('grant', Grants);
      for Pair in GGranted do
      begin
        Arr := TJSONArray.Create;
        for P in Pair.Value do
          Arr.Add(P);
        Grants.AddPair(Pair.Key, Arr);
      end;
      TDirectory.CreateDirectory(ExtractFilePath(AFileName));
      TFile.WriteAllText(AFileName, Root.ToJSON, TEncoding.UTF8);
    finally
      Root.Free;
    end;
  except
    // A settings file that cannot be written leaves the choice for this run only.
  end;
end;

procedure PluginPermissionGrant(const APluginId, APermission: string; AGranted: Boolean);
var
  List: TArray<string>;
  I: Integer;
begin
  if (Key(APluginId) = '') or not IsKnownPermission(APermission) then
    Exit;
  if not GGranted.TryGetValue(Key(APluginId), List) then
    SetLength(List, 0);
  I := IndexIn(List, Trim(APermission));
  if AGranted and (I < 0) then
    List := List + [LowerCase(Trim(APermission))]
  else if not AGranted and (I >= 0) then
    Delete(List, I, 1);
  if Length(List) = 0 then
    GGranted.Remove(Key(APluginId))
  else
    GGranted.AddOrSetValue(Key(APluginId), List);
end;

function PluginPermissionGranted(const APluginId, APermission: string): Boolean;
var
  List: TArray<string>;
begin
  Result := GGranted.TryGetValue(Key(APluginId), List) and (IndexIn(List, Trim(APermission)) >= 0);
end;

function PluginHasPermission(const APluginId, APermission: string): Boolean;
begin
  Result := (IndexIn(PluginPermissionsDeclared(APluginId), Trim(APermission)) >= 0) and
    PluginPermissionGranted(APluginId, APermission);
end;

procedure PluginPermissionsGrantAll(const APluginId: string; AGranted: Boolean);
var
  P: string;
begin
  for P in PluginPermissionsDeclared(APluginId) do
    PluginPermissionGrant(APluginId, P, AGranted);
  if not AGranted then
    // A grant left over from an earlier manifest goes too.
    for P in KnownPermissions do
      PluginPermissionGrant(APluginId, P, False);
end;

function PluginPermissionsAllGranted(const APluginId: string): Boolean;
var
  P: string;
  Declared: TArray<string>;
begin
  Declared := PluginPermissionsDeclared(APluginId);
  Result := Length(Declared) > 0;
  for P in Declared do
    if not PluginPermissionGranted(APluginId, P) then
      Exit(False);
end;

initialization
  GDeclared := TDictionary<string, TArray<string>>.Create;
  GGranted := TDictionary<string, TArray<string>>.Create;

finalization
  GGranted.Free;
  GDeclared.Free;

end.
