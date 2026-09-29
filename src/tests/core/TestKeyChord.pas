unit TestKeyChord;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestKeyChord = class
  public
    [Test] procedure TestMatching;
    [Test] procedure TestNormalize;
    [Test] procedure TestTerminalHostPassthrough;
    [Test] procedure TestNoLowercaseKeyCodes;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils,
  System.RegularExpressions,
  uKeyChord, uTerminalWorkspace;

function KC(AKey: Word; AShift: TShiftState; ACh: Char = #0): TKeyChord;
begin
  Result := TKeyChord.Make(AKey, ACh, AShift);
end;

procedure TTestKeyChord.TestMatching;
begin
  Assert.IsTrue(KC(vkC, [ssCtrl]).Matches(vkC, [ssCtrl]), 'Ctrl+C');
  Assert.IsFalse(KC(vkC, [ssCtrl, ssShift]).Matches(vkC, [ssCtrl]), 'Matches is exact');
  Assert.IsFalse(KC(vkC, []).Matches(vkC, [ssCtrl]), 'Ctrl required');
  Assert.IsTrue(KC(vkC, [ssCtrl, ssLeft]).Matches(vkC, [ssCtrl]),
    'mouse buttons are not modifiers');

  Assert.IsTrue(KC(vkTab, [ssCtrl, ssShift]).MatchesAny(vkTab, [ssCtrl], [ssShift]),
    'optional Shift held');
  Assert.IsTrue(KC(vkTab, [ssCtrl]).MatchesAny(vkTab, [ssCtrl], [ssShift]),
    'optional Shift not held');
  Assert.IsFalse(KC(vkTab, [ssCtrl, ssAlt]).MatchesAny(vkTab, [ssCtrl], [ssShift]),
    'Alt is neither required nor optional');

  Assert.IsTrue(KC(vkA, [ssCtrl]).MatchesLetter('A', [ssCtrl]), 'letter by key');
  Assert.IsTrue(KC(0, [ssCtrl], 'a').MatchesLetter('A', [ssCtrl]), 'letter by typed char');
  Assert.IsTrue(KC(0, [ssCtrl], 'A').MatchesLetter('A', [ssCtrl]), 'letter by typed capital');
  // Ord('a') = vkNumpad1, Ord('k') = vkAdd: not letters.
  Assert.IsFalse(KC(vkNumpad1, [ssCtrl]).MatchesLetter('A', [ssCtrl]), 'Num1 is not A');
  Assert.IsFalse(KC(vkAdd, [ssCtrl]).MatchesLetter('K', [ssCtrl]), 'Num+ is not K');

  Assert.IsTrue(KC(vkA, [], 'a').IsPrintable, 'a printable');
  Assert.IsFalse(KC(vkBack, [], #8).IsPrintable, 'BS not printable');
  Assert.IsFalse(KC(vkDelete, [], #127).IsPrintable, 'DEL not printable');
end;

procedure TTestKeyChord.TestNormalize;
var
  K: Word;
  S: TShiftState;
begin
  K := 0; S := [];
  NormalizeKeyInput(K, #13, S, False);
  Assert.IsTrue(K = vkReturn, '#13 char is Enter');
  K := vkAccept; S := [];
  NormalizeKeyInput(K, #0, S, False);
  Assert.IsTrue(K = vkReturn, 'vkAccept is Enter');
  K := 10; S := [];
  NormalizeKeyInput(K, #0, S, False);
  Assert.IsTrue(K = vkReturn, 'raw 10 is Enter');
  K := vkTab; S := [];
  NormalizeKeyInput(K, #13, S, False);
  Assert.IsTrue(K = vkTab, 'Tab stays Tab');

  K := vkReturn; S := [ssCtrl, ssAlt];
  NormalizeKeyInput(K, #13, S, True);
  Assert.IsTrue(S = [ssAlt], 'AltGr+Enter is Alt+Enter');
  K := vkReturn; S := [ssCtrl, ssAlt];
  NormalizeKeyInput(K, #13, S, False);
  Assert.IsTrue(S = [ssCtrl, ssAlt], 'real Ctrl+Alt+Enter kept');
  K := vkA; S := [ssCtrl, ssAlt];
  NormalizeKeyInput(K, 'a', S, True);
  Assert.IsTrue((K = vkA) and (S = [ssCtrl, ssAlt]), 'only Enter is touched');
end;

procedure TTestKeyChord.TestTerminalHostPassthrough;
begin
  Assert.IsTrue(IsTerminalHostPassthrough(KC(vkNext, [ssCtrl, ssAlt])), 'Ctrl+Alt+PgDn');
  Assert.IsTrue(IsTerminalHostPassthrough(KC(vkPrior, [ssCtrl, ssAlt])), 'Ctrl+Alt+PgUp');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkTab, [])), 'Tab goes to the shell');
  Assert.IsTrue(IsTerminalHostPassthrough(KC(vkN, [ssCtrl, ssShift])), 'Ctrl+Shift+N');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkN, [ssCtrl])), 'Ctrl+N goes to the shell');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkDecimal, [ssCtrl, ssShift])),
    'Ctrl+Shift+Num. (= Ord(''n'')) is not Ctrl+Shift+N');
  // Passthrough = the keymap's Global actions (uKeymap kcGlobal).
  Assert.IsTrue(IsTerminalHostPassthrough(KC(vk0, [ssCtrl], '0')), 'Ctrl+0 zoom reset');
  Assert.IsTrue(IsTerminalHostPassthrough(KC(vkF9, [])), 'F9 top menu');
  Assert.IsTrue(IsTerminalHostPassthrough(KC(vkO, [ssCtrl])), 'Ctrl+O console');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkAdd, [ssCtrl, ssAlt])), 'Ctrl+Alt+Num+');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkF10, [])), 'F10 is the panels'' Quit, not Global');
  Assert.IsTrue(IsTerminalHostPassthrough(KC(vkX, [ssAlt])), 'Alt+X');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkF9, [ssAlt])), 'Alt+F9 (= Ord(''x'')) is not Alt+X');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkX, [])), 'x goes to the shell');
  Assert.IsFalse(IsTerminalHostPassthrough(KC(vkC, [ssCtrl], #3)), 'Ctrl+C goes to the shell');
end;

// Only uppercase letters and digits have their own ASCII code as virtual key
// code. Ord('a')..Ord('z') are numpad and F-keys, and punctuation is some
// other key too (Ord('-') = vkInsert, Ord('+') = vkExecute), see uKeyChord.
// Guards against comparing a key code with one: "Key = Ord('x')",
// "AKey <> Ord('-')", "AKey >= Ord('a')", "case AKey of Ord('y'), ...".
procedure TTestKeyChord.TestNoLowercaseKeyCodes;
const
  cKeyCompare = '\b\w*Key\s*(=|<>|>=|<=|>|<)\s*Ord\(''[^A-Z0-9'']''\)';
  cCaseLabel = 'Ord\(''[a-z]''\)\s*(,|:[^=]|\.\.)';
var
  Root, Dir, F, Line, Hits: string;
  Lines: TArray<string>;
  I: Integer;
begin
  // Runner working dir is src\tests\core.
  Root := TPath.GetFullPath(TPath.Combine(GetCurrentDir, '..\..'));
  Hits := '';
  for Dir in TArray<string>.Create('Core', 'Forms') do
    for F in TDirectory.GetFiles(TPath.Combine(Root, Dir), '*.pas') do
    begin
      Lines := TFile.ReadAllLines(F);
      for I := 0 to High(Lines) do
      begin
        Line := Lines[I];
        if Line.Contains('//') then // comments may name the aliases
          Line := Copy(Line, 1, Line.IndexOf('//'));
        if TRegEx.IsMatch(Line, cKeyCompare) or
           TRegEx.IsMatch(Line, cCaseLabel) then
          Hits := Hits + sLineBreak + Format('%s:%d: %s',
            [TPath.GetFileName(F), I + 1, Trim(Line)]);
      end;
    end;
  Assert.IsTrue(Hits = '', 'key code compared with a character that is not its code:' + Hits);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestKeyChord);
end.
