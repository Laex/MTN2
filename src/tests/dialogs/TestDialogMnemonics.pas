unit TestDialogMnemonics;

{ Dialog mnemonics and Yes/No answers from any keyboard layout: the typed
  letter first (Cyrillic mnemonics included), then the physical key, and
  Yes/No by meaning (y/д, n/н) before the physical Y/N key. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogMnemonics = class
  public
    [Test] procedure TestYesNo;
    [Test] procedure TestMnemonics;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogTypes, uDialogHost;

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
  // Id-based Latin hotkeys (skip = S) from the Russian layout: ы sits on S.
  D := Decl([Button('skip', 'Пропустить'), Button('cancel', 'Отмена')]);
  Assert.AreEqual('skip', Press(D, vkS, 's'), 's is Skip');
  Assert.AreEqual('skip', Press(D, vkS, #$044B), 'ы (on S) is Skip');
  Assert.AreEqual('cancel', Press(D, vkC, #$0441), 'с (on C) is Cancel');

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

initialization
  TDUnitX.RegisterTestFixture(TTestDialogMnemonics);
end.
