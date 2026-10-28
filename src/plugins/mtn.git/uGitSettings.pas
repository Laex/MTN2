unit uGitSettings;

{ Settings of the git status plugin: how often git is asked again and the
  colors of each badge. Stored by the host as key/value text; this unit turns
  them into a record, builds the settings dialog and reads its answer. No host
  calls here. }

interface

uses
  System.SysUtils, uGitStatus;

const
  cDefaultRefreshSec = 5;
  cMinRefreshSec = 1;
  cMaxRefreshSec = 600;
  /// <summary>The choices of the refresh drop-down, in seconds.</summary>
  cRefreshChoices: array[0..10] of Integer = (1, 2, 3, 5, 10, 15, 30, 60, 120, 300, 600);

type
  TGitSettings = record
    RefreshSec: Integer;
    Colors: TGitColors;
  end;

function DefaultGitSettings: TGitSettings;

/// <summary>"#RRGGBB" for AText given as "#RRGGBB", "RRGGBB" or a color name
/// (black, white, red, green, blue, yellow, cyan, magenta, orange, gray);
/// '' for an empty or unknown text, which means the default color.</summary>
function NormalizeColorSetting(const AText: string): string;

/// <summary>Seconds between two runs of git, from the text of the setting; the
/// default when it is not a number, clamped to the allowed range.</summary>
function ParseRefreshSeconds(const AText: string): Integer;

/// <summary>Reads the settings through AGet (key -> value, '' = never set).</summary>
function ReadGitSettings(const AGet: TFunc<string, string>): TGitSettings;

/// <summary>Writes every setting through ASet (key, value).</summary>
procedure WriteGitSettings(const ASettings: TGitSettings; const ASet: TProc<string, string>);

/// <summary>The settings dialog filled with ACurrent; ATr maps a key and its English
/// text to the text in the program language.</summary>
function GitSettingsDialogJson(const ACurrent: TGitSettings;
  const ATr: TFunc<string, string, string>): string;

/// <summary>The settings typed into the dialog (the values JSON of its answer).</summary>
function GitSettingsFromDialogValues(const AValuesJson: string): TGitSettings;

implementation

uses
  System.Classes, System.JSON;

const
  cBadgeKeys: array[TGitBadge] of string =
    ('branch', 'sync', 'staged', 'changed', 'untracked', 'conflicts', 'clean');
  cBadgeCaptions: array[TGitBadge] of string =
    ('Branch', 'Ahead / behind', 'Staged', 'Modified', 'New files', 'Conflicts', 'Clean');

function DefaultGitSettings: TGitSettings;
const
  cFg: array[TGitBadge] of string =
    ('#FFFFFF', '#FFFFFF', '#FFFFFF', '#000000', '#FFFFFF', '#FFFFFF', '#FFFFFF');
  cBg: array[TGitBadge] of string =
    ('#6A1B9A', '#1565C0', '#2E7D32', '#E0B000', '#616161', '#C62828', '#2E7D32');
var
  B: TGitBadge;
begin
  Result := Default(TGitSettings);
  Result.RefreshSec := cDefaultRefreshSec;
  for B := Low(TGitBadge) to High(TGitBadge) do
  begin
    Result.Colors.Fg[B] := cFg[B];
    Result.Colors.Bg[B] := cBg[B];
  end;
end;

/// <summary>The normalized color, or ADefault when the text is empty or not a color.</summary>
function ColorOrDefault(const AText, ADefault: string): string;
begin
  Result := NormalizeColorSetting(AText);
  if Result = '' then
    Result := ADefault;
end;

function NormalizeColorSetting(const AText: string): string;
const
  cNames: array[0..9] of string = ('black', 'white', 'red', 'green', 'blue', 'yellow',
    'cyan', 'magenta', 'orange', 'gray');
  cValues: array[0..9] of string = ('#000000', '#FFFFFF', '#C62828', '#2E7D32', '#1565C0',
    '#E0B000', '#00ACC1', '#6A1B9A', '#EF6C00', '#616161');
var
  S: string;
  I, V: Integer;
begin
  Result := '';
  S := Trim(AText);
  if S = '' then
    Exit;
  for I := 0 to High(cNames) do
    if SameText(S, cNames[I]) then
      Exit(cValues[I]);
  if S[1] = '#' then
    S := Copy(S, 2, MaxInt);
  if (Length(S) = 6) and TryStrToInt('$' + S, V) and (V >= 0) then
    Result := '#' + UpperCase(S);
end;

function ParseRefreshSeconds(const AText: string): Integer;
begin
  Result := StrToIntDef(Trim(AText), cDefaultRefreshSec);
  if Result < cMinRefreshSec then
    Result := cMinRefreshSec;
  if Result > cMaxRefreshSec then
    Result := cMaxRefreshSec;
end;

function ReadGitSettings(const AGet: TFunc<string, string>): TGitSettings;
var
  B: TGitBadge;
begin
  Result := DefaultGitSettings;
  Result.RefreshSec := ParseRefreshSeconds(AGet('refresh'));
  for B := Low(TGitBadge) to High(TGitBadge) do
  begin
    Result.Colors.Fg[B] := ColorOrDefault(AGet('fg.' + cBadgeKeys[B]), Result.Colors.Fg[B]);
    Result.Colors.Bg[B] := ColorOrDefault(AGet('bg.' + cBadgeKeys[B]), Result.Colors.Bg[B]);
  end;
end;

procedure WriteGitSettings(const ASettings: TGitSettings; const ASet: TProc<string, string>);
var
  B: TGitBadge;
begin
  ASet('refresh', IntToStr(ASettings.RefreshSec));
  for B := Low(TGitBadge) to High(TGitBadge) do
  begin
    ASet('fg.' + cBadgeKeys[B], ASettings.Colors.Fg[B]);
    ASet('bg.' + cBadgeKeys[B], ASettings.Colors.Bg[B]);
  end;
end;

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth: Integer; const AValue: string = ''; ADefault: Boolean = False;
  ACancel: Boolean = False);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if AType = 'input' then
  begin
    O.AddPair('value', AValue);
    // The button at the end of the field opens the host's color picker.
    if AId <> 'refresh' then
      O.AddPair('colorpick', TJSONBool.Create(True));
  end;
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

/// <summary>A live preview of the text and background colors typed in two inputs.</summary>
procedure AddColorSample(AChildren: TJSONArray; const AId, AText, AFgFrom, ABgFrom: string;
  ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'colorsample');
  O.AddPair('id', AId);
  O.AddPair('text', AText);
  O.AddPair('fgFrom', AFgFrom);
  O.AddPair('bgFrom', ABgFrom);
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

/// <summary>The drop-down of refresh periods with the entry nearest to ASeconds chosen.</summary>
procedure AddRefreshDropDown(AChildren: TJSONArray; ASeconds, ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
  Items: TJSONArray;
  I, Best: Integer;
begin
  Best := 0;
  Items := TJSONArray.Create;
  for I := 0 to High(cRefreshChoices) do
  begin
    Items.Add(IntToStr(cRefreshChoices[I]));
    if Abs(cRefreshChoices[I] - ASeconds) < Abs(cRefreshChoices[Best] - ASeconds) then
      Best := I;
  end;
  O := TJSONObject.Create;
  O.AddPair('type', 'dropdown');
  O.AddPair('id', 'refresh');
  O.AddPair('items', Items);
  O.AddPair('selected', TJSONNumber.Create(Best));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

function GitSettingsDialogJson(const ACurrent: TGitSettings;
  const ATr: TFunc<string, string, string>): string;
const
  cRowFirst = 3;
  cLastRow = cRowFirst + Ord(High(TGitBadge));
var
  Root: TJSONObject;
  Kids: TJSONArray;
  B: TGitBadge;
  Row: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('type', 'dialog');
    Root.AddPair('version', '2.0');
    Root.AddPair('title', ATr('dlg.title', 'Git status'));
    Root.AddPair('width', TJSONNumber.Create(70));
    Root.AddPair('height', TJSONNumber.Create(cLastRow + 8));
    Kids := TJSONArray.Create;
    Root.AddPair('children', Kids);
    AddControl(Kids, 'label', '', ATr('dlg.refresh', 'Ask git every (seconds):'), 1, 0, 28);
    AddRefreshDropDown(Kids, ACurrent.RefreshSec, 30, 0, 8);
    AddControl(Kids, 'label', '', ATr('dlg.fg', 'Text'), 22, 2, 14);
    AddControl(Kids, 'label', '', ATr('dlg.bg', 'Background'), 38, 2, 14);
    AddControl(Kids, 'label', '', ATr('dlg.sample', 'Sample'), 54, 2, 12);
    for B := Low(TGitBadge) to High(TGitBadge) do
    begin
      Row := cRowFirst + Ord(B);
      AddControl(Kids, 'label', '', ATr('badge.' + cBadgeKeys[B], cBadgeCaptions[B]),
        1, Row, 20);
      AddControl(Kids, 'input', 'fg.' + cBadgeKeys[B], '', 22, Row, 14, ACurrent.Colors.Fg[B]);
      AddControl(Kids, 'input', 'bg.' + cBadgeKeys[B], '', 38, Row, 14, ACurrent.Colors.Bg[B]);
      AddColorSample(Kids, 'sample.' + cBadgeKeys[B], ' ' + ATr('dlg.sampleText', 'Sample') + ' ',
        'fg.' + cBadgeKeys[B], 'bg.' + cBadgeKeys[B], 54, Row, 12);
    end;
    AddControl(Kids, 'label', '', ATr('dlg.hint',
      '#RRGGBB; the button picks a color; empty = standard'), 1, cLastRow + 2, 64);
    AddControl(Kids, 'button', 'ok', ATr('dlg.ok', 'OK'), 22, cLastRow + 4, 12, '', True);
    AddControl(Kids, 'button', 'cancel', ATr('dlg.cancel', 'Cancel'), 36, cLastRow + 4, 12,
      '', False, True);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function GitSettingsFromDialogValues(const AValuesJson: string): TGitSettings;
var
  Root: TJSONValue;
  B: TGitBadge;

  // The keys hold dots, which a path lookup would split: match whole names.
  function Field(const AKey: string): string;
  var
    I: Integer;
    Obj: TJSONObject;
  begin
    Result := '';
    Obj := TJSONObject(Root);
    for I := 0 to Obj.Count - 1 do
      if Obj.Pairs[I].JsonString.Value = AKey then
        Exit(Obj.Pairs[I].JsonValue.Value);
  end;

begin
  Result := DefaultGitSettings;
  Root := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Result.RefreshSec := ParseRefreshSeconds(Field('refresh'));
    for B := Low(TGitBadge) to High(TGitBadge) do
    begin
      Result.Colors.Fg[B] := ColorOrDefault(Field('fg.' + cBadgeKeys[B]), Result.Colors.Fg[B]);
      Result.Colors.Bg[B] := ColorOrDefault(Field('bg.' + cBadgeKeys[B]), Result.Colors.Bg[B]);
    end;
  finally
    Root.Free;
  end;
end;

end.
