unit uHiddenDialogs;

{ Dialogs and notices the user switched off with "Don't show this again".
  The ids live in hidden-dialogs.json in the settings folder; Options >
  Restore hidden dialogs empties it. }

interface

function DialogHidden(const AId: string): Boolean;
procedure HideDialog(const AId: string);
/// <summary>Makes every hidden dialog appear again; returns how many there were.</summary>
function RestoreHiddenDialogs: Integer;
/// <summary>True when the checkbox AId is ticked in a dialog's values JSON.</summary>
function DialogValuesChecked(const AValuesJson, AId: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, uConfigLocation;

const
  cFileName = 'hidden-dialogs.json';

function LoadIds: TStringList;
var
  Path: string;
  Val: TJSONValue;
  Item: TJSONValue;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  Path := GetConfigFilePath(cFileName);
  try
    if not TFile.Exists(Path) then
      Exit;
    Val := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
    try
      if Val is TJSONArray then
        for Item in TJSONArray(Val) do
          if Item is TJSONString then
            Result.Add(TJSONString(Item).Value);
    finally
      Val.Free;
    end;
  except
    // an unreadable file counts as nothing hidden
    Result.Clear;
  end;
end;

procedure SaveIds(AIds: TStrings);
var
  Arr: TJSONArray;
  I: Integer;
  Path: string;
begin
  Path := GetConfigFilePath(cFileName);
  try
    if AIds.Count = 0 then
    begin
      if TFile.Exists(Path) then
        TFile.Delete(Path);
      Exit;
    end;
    Arr := TJSONArray.Create;
    try
      for I := 0 to AIds.Count - 1 do
        Arr.Add(AIds[I]);
      ForceDirectories(ExtractFileDir(Path));
      TFile.WriteAllText(Path, Arr.ToJSON, TEncoding.UTF8);
    finally
      Arr.Free;
    end;
  except
    // a setting that cannot be saved only means the dialog shows again
  end;
end;

function DialogHidden(const AId: string): Boolean;
var
  Ids: TStringList;
begin
  Ids := LoadIds;
  try
    Result := Ids.IndexOf(AId) >= 0;
  finally
    Ids.Free;
  end;
end;

procedure HideDialog(const AId: string);
var
  Ids: TStringList;
begin
  Ids := LoadIds;
  try
    Ids.Add(AId);
    SaveIds(Ids);
  finally
    Ids.Free;
  end;
end;

function DialogValuesChecked(const AValuesJson, AId: string): Boolean;
var
  Val: TJSONValue;
begin
  Result := False;
  Val := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if Val is TJSONObject then
      Result := TJSONObject(Val).GetValue<Boolean>(AId, False);
  finally
    Val.Free;
  end;
end;

function RestoreHiddenDialogs: Integer;
var
  Ids: TStringList;
begin
  Ids := LoadIds;
  try
    Result := Ids.Count;
    Ids.Clear;
    SaveIds(Ids);
  finally
    Ids.Free;
  end;
end;

end.
