unit TestDialogMnemonics;

{ Dialog hotkeys and Yes/No answers from any keyboard layout. A hotkey is
  the letter a button, checkbox or radio caption marks with '&': the typed
  letter matches first (Cyrillic hotkeys included), then the same key on the
  other layout, then the physical key; a caption without a marker has no
  hotkey. Yes/No go by meaning (y/д, n/н) before the physical Y/N key. Every
  built-in dialog, in English and Russian, marks a letter on each control
  other than its Enter and Esc buttons, and no letter twice. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogMnemonics = class
  public
    [Test] procedure TestYesNo;
    [Test] procedure TestMnemonics;
    [Test] procedure TestCheckboxHotKey;
    [Test] procedure TestResourceHotKeysEnglish;
    [Test] procedure TestResourceHotKeysRussian;
    [Test] procedure TestResourceHotKeysGerman;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.Character,
  uThemeTypes, uStrings, uDialogTypes, uDialogResources, uDialogHost,
  TestDialogAlignment;

function Button(const AId, AText: string): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckButton;
  Result.Id := AId;
  Result.Text := AText;
end;

function Decl(const AButtons: array of TDialogControl): TDialogDeclaration;
var
  I: Integer;
begin
  Result := Default(TDialogDeclaration);
  Result.Version := '1.0';
  Result.Title := 'Test';
  SetLength(Result.Controls, Length(AButtons));
  for I := 0 to High(AButtons) do
    Result.Controls[I] := AButtons[I];
end;

/// <summary>Opens ADecl, presses AKey/AChar (no modifiers) and returns the
/// command the dialog fired, '' if none.</summary>
function Press(const ADecl: TDialogDeclaration; AKey: Word; AChar: Char): string;
var
  Host: TDialogHost;
  Fired: string;
begin
  Fired := '';
  Host := TDialogHost.Create(nil);
  try
    Host.Open(ADecl,
      procedure(const AControlId, AValuesJson: string)
      begin
        Fired := AControlId;
      end);
    Host.HandleInput(AKey, [], AChar);
  finally
    Host.Free;
  end;
  Result := Fired;
end;

procedure TTestDialogMnemonics.TestYesNo;
var
  D: TDialogDeclaration;
begin
  D := Decl([Button(cDlgCmdYes, 'Да'), Button(cDlgCmdNo, 'Нет')]);
  Assert.AreEqual(cDlgCmdYes, Press(D, vkY, 'y'), 'y is Yes');
  Assert.AreEqual(cDlgCmdNo, Press(D, vkN, 'n'), 'n is No');
  Assert.AreEqual(cDlgCmdYes, Press(D, vkL, #$0434), 'д (on L) is Yes by meaning');
  Assert.AreEqual(cDlgCmdNo, Press(D, vkY, #$043D), 'н (on Y) is No by meaning');
  Assert.AreEqual(cDlgCmdNo, Press(D, vkN, #$0442), 'т is on N: No');
  Assert.AreEqual(cDlgCmdYes, Press(D, vkY, #0), 'the Y key without a character is Yes');
  Assert.AreEqual('', Press(D, vk1, '1'), 'a digit answers nothing');
end;

procedure TTestDialogMnemonics.TestMnemonics;
var
  D: TDialogDeclaration;
begin
  // No marker, no hotkey: neither the first letter nor the command id.
  D := Decl([Button('skip', 'Пропустить'), Button('cancel', 'Отмена')]);
  Assert.AreEqual('', Press(D, vkG, #$043F), 'п does not press Пропустить');
  Assert.AreEqual('', Press(D, vkS, 's'), 's does not press skip');
  Assert.AreEqual('', Press(D, vkC, #$0441), 'с does not press cancel');

  // A Cyrillic hotkey from the Latin layout: g is on the П key.
  D := Decl([Button('skip', '&Пропустить')]);
  Assert.AreEqual('skip', Press(D, vkG, 'g'), 'g (on П) is &Пропустить');
  // A Latin hotkey from the Russian layout: ы is on the S key.
  D := Decl([Button('skip', '&Skip')]);
  Assert.AreEqual('skip', Press(D, vkS, #$044B), 'ы (on S) is &Skip');

  // Cyrillic mnemonics work by the typed letter, either case.
  D := Decl([Button('del', '&Удалить'), Button('keep', '&Оставить')]);
  Assert.AreEqual('del', Press(D, vkE, #$0443), 'у is &Удалить');
  Assert.AreEqual('del', Press(D, vkE, #$0423), 'У is &Удалить');
  Assert.AreEqual('keep', Press(D, vkJ, #$043E), 'о is &Оставить');

  // The typed letter wins over the physical key; the physical key is the
  // fallback for a Latin mnemonic typed from another layout.
  D := Decl([Button('del', '&Удалить'), Button('edit', '&Edit')]);
  Assert.AreEqual('del', Press(D, vkE, #$0443), 'у on E: the typed letter wins');
  D := Decl([Button('edit', '&Edit')]);
  Assert.AreEqual('edit', Press(D, vkE, #$0443), 'у on E reaches &Edit by key');
  Assert.AreEqual('edit', Press(D, vkE, 'e'), 'e is &Edit');
  Assert.AreEqual('', Press(D, vkF, #$0430), 'а (on F) is not &Edit');
end;

procedure TTestDialogMnemonics.TestCheckboxHotKey;
var
  D: TDialogDeclaration;
  Host: TDialogHost;
  Key: Word;
  Ch: Char;
begin
  D := Decl([Button('ok', 'OK')]);
  SetLength(D.Controls, 2);
  D.Controls[1] := Default(TDialogControl);
  D.Controls[1].Kind := dckCheckbox;
  D.Controls[1].Id := 'remember';
  D.Controls[1].Text := '&Запомнить выбор';
  Host := TDialogHost.Create(nil);
  try
    Host.Open(D,
      procedure(const AControlId, AValuesJson: string)
      begin
      end);
    Key := vkP;
    Ch := #$0437;
    Host.HandleInput(Key, [], Ch);
    Assert.IsTrue(Host.GetControl(1).Checked, 'з toggles &Запомнить выбор on');
    Assert.AreEqual('remember', Host.FocusedControlId, 'and focuses it');
    Key := vkP;
    Ch := 'p';
    Host.HandleInput(Key, [], Ch);
    Assert.IsFalse(Host.GetControl(1).Checked, 'p (on З) toggles it off');
  finally
    Host.Free;
  end;
end;

procedure CheckHotKeys(const AName: string; const ADecl: TDialogDeclaration;
  AReport: TStrings);
var
  I: Integer;
  C: TDialogControl;
  Hot: Char;
  Seen: string;
  Cap: string;
begin
  Seen := '';
  for I := 0 to High(ADecl.Controls) do
  begin
    C := ADecl.Controls[I];
    if not (C.Kind in [dckButton, dckCheckbox, dckRadio]) then
      Continue;
    Cap := StripHotKeyMarker(C.Text);
    Hot := HotKeyCharOf(C.Text);
    if (C.Kind = dckButton) and (C.IsDefault or C.IsCancel) then
    begin
      if Hot <> #0 then
        AReport.Add(AName + ': "' + Cap + '" is the Enter / Esc button, no letter needed');
      Continue;
    end;
    if Hot = #0 then
      AReport.Add(AName + ': "' + Cap + '" has no hotkey letter')
    else if not Hot.IsLetter then
      AReport.Add(AName + ': "' + Cap + '" marks "' + Hot + '", not a letter')
    else if Pos(Hot, Seen) > 0 then
      AReport.Add(AName + ': "' + Cap + '" repeats the letter ' + Hot)
    else
      Seen := Seen + Hot;
  end;
end;

procedure CheckResourceHotKeys(const ALocale: string);
var
  Name: string;
  Decl: TDialogDeclaration;
  Report: TStringList;
begin
  Report := TStringList.Create;
  try
    SetLocale(ALocale);
    try
      for Name in DialogResourceNames do
        if TryLoadDialogResource(Name, Decl) then
          CheckHotKeys(Name, Decl, Report)
        else
          Report.Add(Name + ': not loaded');
      CheckHotKeys('console profile',
        BuildConsoleProfileDialog(['Command Prompt', 'PowerShell'], 0, False), Report);
    finally
      SetLocale('');
    end;
    Assert.IsTrue(Report.Count = 0, sLineBreak + Report.Text);
  finally
    Report.Free;
  end;
end;

procedure TTestDialogMnemonics.TestResourceHotKeysEnglish;
begin
  CheckResourceHotKeys('');
end;

procedure TTestDialogMnemonics.TestResourceHotKeysRussian;
begin
  CheckResourceHotKeys('ru');
end;

procedure TTestDialogMnemonics.TestResourceHotKeysGerman;
begin
  CheckResourceHotKeys('de');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogMnemonics);
end.
