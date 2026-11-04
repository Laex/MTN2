unit TestPluginInputChord;

{ Plugin key chords round-trip through the (Key, KeyChar, Shift) triple a window takes. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginInputChord = class
  public
    [Test] procedure TestFunctionKeyWithCtrl;
    [Test] procedure TestPlainLetterCarriesItsCharacter;
    [Test] procedure TestCtrlLetterCarriesNoCharacter;
    [Test] procedure TestSingleCharacterIsTypedText;
    [Test] procedure TestUnknownNameIsRejected;
    [Test] procedure TestChordTextRoundTrip;
    [Test] procedure TestModifierAloneNamesNothing;
    [Test] procedure TestOwnerOfBoundAndFreeChords;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, uPluginInputChord;

procedure TTestPluginInputChord.TestFunctionKeyWithCtrl;
var
  K: Word;
  C: Char;
  S: TShiftState;
begin
  Assert.IsTrue(TryParseInputChord('Ctrl+F5', K, C, S));
  Assert.AreEqual(Integer(vkF5), Integer(K));
  Assert.IsTrue(ssCtrl in S);
  Assert.IsFalse(ssShift in S);
end;

procedure TTestPluginInputChord.TestPlainLetterCarriesItsCharacter;
var
  K: Word;
  C: Char;
  S: TShiftState;
begin
  Assert.IsTrue(TryParseInputChord('K', K, C, S));
  Assert.AreEqual('k', string(C));
end;

procedure TTestPluginInputChord.TestCtrlLetterCarriesNoCharacter;
var
  K: Word;
  C: Char;
  S: TShiftState;
begin
  Assert.IsTrue(TryParseInputChord('Ctrl+K', K, C, S));
  Assert.AreEqual(Integer(Ord('K')), Integer(K));
  Assert.AreEqual(0, Integer(C));
end;

procedure TTestPluginInputChord.TestSingleCharacterIsTypedText;
var
  K: Word;
  C: Char;
  S: TShiftState;
begin
  Assert.IsTrue(TryParseInputChord('Q', K, C, S));
  Assert.AreEqual('Q', string(C));
  Assert.IsTrue(TryParseInputChord('q', K, C, S));
  Assert.AreEqual('q', string(C));
  Assert.IsFalse(ssShift in S);
end;

procedure TTestPluginInputChord.TestUnknownNameIsRejected;
var
  K: Word;
  C: Char;
  S: TShiftState;
begin
  Assert.IsFalse(TryParseInputChord('NoSuchKey', K, C, S));
  Assert.IsFalse(TryParseInputChord('', K, C, S));
end;

procedure TTestPluginInputChord.TestChordTextRoundTrip;
var
  K: Word;
  C: Char;
  S: TShiftState;
begin
  Assert.IsTrue(TryParseInputChord('Ctrl+Shift+F5', K, C, S));
  Assert.AreEqual('Ctrl+Shift+F5', InputChordText(K, C, S));
  Assert.AreEqual('x', InputChordText(0, 'x', []));
end;

procedure TTestPluginInputChord.TestModifierAloneNamesNothing;
begin
  Assert.AreEqual('', InputChordText(vkControl, #0, [ssCtrl]));
end;

procedure TTestPluginInputChord.TestOwnerOfBoundAndFreeChords;
var
  Chord: string;
begin
  Chord := ActionChordText('Copy');
  Assert.AreNotEqual('', Chord, 'the default keymap binds Copy');
  Assert.AreEqual('Copy', ChordOwnerName(Chord), 'a bound chord names its action');
  Assert.AreEqual('', ChordOwnerName('Ctrl+Alt+Shift+F12'), 'a free chord has no owner');
  Assert.AreEqual('', ChordOwnerName('nonsense+'), 'text that is no key has no owner');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginInputChord);

end.
