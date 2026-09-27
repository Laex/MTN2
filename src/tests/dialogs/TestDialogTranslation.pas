unit TestDialogTranslation;

{ Dialog translation: every caption in dialogs\*.json has an id to be
  translated by; fixed drop-down choices are translated on screen while the
  dialog's values keep the English item; a column-aligned header keeps its
  inputs in place. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogTranslation = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestEveryCaptionHasId;
    [Test] procedure TestDropDownItems;
    [Test] procedure TestAlignedHeaderKeepsInputs;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.RegularExpressions,
  uStrings, uDialogTypes, uDialogResources, uDialogHost;

function IndexOfId(const D: TDialogDeclaration; const AId: string): Integer;
begin
  for Result := 0 to High(D.Controls) do
    if SameText(D.Controls[Result].Id, AId) then
      Exit;
  Result := -1;
end;

procedure TTestDialogTranslation.TearDown;
begin
  SetLocale('');
end;

// A caption without an id has no key in strings\<locale>.json and stays
// English. Rules (─── separators) are exempt.
procedure TTestDialogTranslation.TestEveryCaptionHasId;
var
  F, Bad: string;

  procedure Walk(AObj: TJSONObject);
  var
    Kids: TJSONArray;
    V: TJSONValue;
    O: TJSONObject;
    Typ, Text: string;
  begin
    Kids := AObj.Values['children'] as TJSONArray;
    if not Assigned(Kids) then
      Exit;
    for V in Kids do
    begin
      if not (V is TJSONObject) then
        Continue;
      O := TJSONObject(V);
      Typ := O.GetValue<string>('type', '');
      Text := O.GetValue<string>('text', '');
      if ((Typ = 'label') or (Typ = 'checkbox') or (Typ = 'radio') or
          (Typ = 'button') or (Typ = 'status')) and (Text <> '') and
         not TRegEx.IsMatch(Text, '^[\x{2500}\x{2501}\x{2550}=_ -]+$') and
         (O.GetValue<string>('id', '') = '') then
        Bad := Bad + sLineBreak + TPath.GetFileName(F) + ': ' + Text;
      Walk(O);
    end;
  end;

var
  Root: TJSONValue;
begin
  Bad := '';
  // Runner working dir is src\tests\dialogs.
  for F in TDirectory.GetFiles(TPath.GetFullPath('..\..\dialogs'), '*.json',
    TSearchOption.soAllDirectories) do
  begin
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(F, TEncoding.UTF8));
    try
      if Root is TJSONObject then
        Walk(TJSONObject(Root));
    finally
      Root.Free;
    end;
  end;
  Assert.IsTrue(Bad = '', 'captions without an id (not translatable):' + Bad);
end;

procedure TTestDialogTranslation.TestDropDownItems;
var
  D: TDialogDeclaration;
  I: Integer;
  Host: TDialogHost;
  Values: string;
begin
  SetLocale('ru');
  D := BuildCopyMoveDialog('Копирование', 'Копирование:', 'D:\x\', 1);
  I := IndexOfId(D, 'job_existing');
  Assert.IsTrue(I >= 0, 'job_existing');
  Assert.AreEqual('Спрашивать', D.Controls[I].Items[0], 'Ask on screen');
  Assert.AreEqual('Перезаписывать', D.Controls[I].Items[1], 'Overwrite on screen');
  Assert.AreEqual('Overwrite', D.Controls[I].ItemIds[1], 'English kept as the item id');
  I := IndexOfId(D, 'job_retry');
  Assert.IsTrue(Length(D.Controls[I].ItemIds) = 0, 'untranslated items get no ids');

  Host := TDialogHost.Create(nil);
  try
    Host.Open(D, nil);
    Values := Host.GetValuesJson;
    Assert.IsTrue(Values.Contains('"job_existing":"Overwrite"'),
      'values keep the English choice: ' + Values);
    Assert.IsTrue(Values.Contains('"job_retry":"1"'), 'untranslated values unchanged: ' + Values);
  finally
    Host.Free;
  end;

  // Replaced items drop the ids of the old ones.
  DialogSetListItems(D, 'job_existing', ['a', 'b']);
  I := IndexOfId(D, 'job_existing');
  Assert.IsTrue(Length(D.Controls[I].ItemIds) = 0, 'DialogSetListItems clears ItemIds');

  SetLocale('');
  D := BuildCopyMoveDialog('Copy', 'Copy to:', 'D:\x\');
  I := IndexOfId(D, 'job_existing');
  Assert.AreEqual('Ask', D.Controls[I].Items[0], 'English items as authored');
  Assert.IsTrue(Length(D.Controls[I].ItemIds) = 0, 'no ids in English');
end;

// colorcodingedit's "Fg / Bg / Sample" header is aligned with spaces to the
// inputs below it; a translation that widened the label column would shift
// the inputs away from their headings.
procedure TTestDialogTranslation.TestAlignedHeaderKeepsInputs;
var
  En, Ru: TDialogDeclaration;
  Id: string;
begin
  SetLocale('');
  RequireDialogResource(cResDialogColorCodingEdit, En);
  SetLocale('ru');
  RequireDialogResource(cResDialogColorCodingEdit, Ru);
  Assert.AreNotEqual(En.Controls[IndexOfId(En, 'lbl_columns')].Text,
    Ru.Controls[IndexOfId(Ru, 'lbl_columns')].Text, 'header is translated');
  for Id in ['cc_normal_fg', 'cc_normal_bg', 'cc_current_fg', 'cc_current_bg'] do
    Assert.AreEqual(En.Controls[IndexOfId(En, Id)].Col, Ru.Controls[IndexOfId(Ru, Id)].Col,
      Id + ' stays under its heading');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogTranslation);
end.
