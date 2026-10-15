unit TestCharWidth;

{ uCharWidth: cells a character occupies, fitting text to a cell budget and
  removing the filler cells of wide characters from cell-aligned lines. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCharWidth = class
  public
    [Test] procedure TestNarrowCharacters;
    [Test] procedure TestChineseJapaneseKoreanAreWide;
    [Test] procedure TestRangeBoundaries;
    [Test] procedure TestTextDisplayWidth;
    [Test] procedure TestTextFitCharsNeverSplitsWideCharacter;
    [Test] procedure TestStripWideFillers;
    [Test] procedure TestTextHasWide;
    [Test] procedure TestCellsBetween;
    [Test] procedure TestCharAtCell;
  end;

implementation

uses
  System.SysUtils, uCharWidth;

const
  // Han (U+6F22), Hiragana (U+3072), Katakana (U+30AB), Hangul (U+D55C),
  // fullwidth letter A (U+FF21), ideographic space (U+3000).
  cHan = #$6F22;
  cHira = #$3072;
  cKata = #$30AB;
  cHangul = #$D55C;
  cFullA = #$FF21;
  cIdeoSpace = #$3000;

procedure TTestCharWidth.TestNarrowCharacters;
var
  C: Char;
begin
  for C := #0 to #$10FF do
    Assert.AreEqual(1, CharDisplayWidth(C), 'width of U+' + IntToHex(Ord(C), 4));
  Assert.AreEqual(1, CharDisplayWidth(#$0416), 'Cyrillic');
  Assert.AreEqual(1, CharDisplayWidth(#$2502), 'box drawing');
  Assert.AreEqual(1, CharDisplayWidth(#$FF61), 'halfwidth ideographic full stop');
  Assert.AreEqual(1, CharDisplayWidth(#$D800), 'surrogate is left alone');
end;

procedure TTestCharWidth.TestChineseJapaneseKoreanAreWide;
begin
  Assert.AreEqual(2, CharDisplayWidth(cHan), 'Han');
  Assert.AreEqual(2, CharDisplayWidth(cHira), 'Hiragana');
  Assert.AreEqual(2, CharDisplayWidth(cKata), 'Katakana');
  Assert.AreEqual(2, CharDisplayWidth(cHangul), 'Hangul syllable');
  Assert.AreEqual(2, CharDisplayWidth(cFullA), 'fullwidth letter');
  Assert.AreEqual(2, CharDisplayWidth(cIdeoSpace), 'ideographic space');
  Assert.IsTrue(IsWideChar(cHan));
  Assert.IsFalse(IsWideChar('A'));
end;

procedure TTestCharWidth.TestRangeBoundaries;
begin
  Assert.AreEqual(2, CharDisplayWidth(#$4E00), 'first unified ideograph');
  Assert.AreEqual(2, CharDisplayWidth(#$9FFF), 'last unified ideograph');
  Assert.AreEqual(1, CharDisplayWidth(#$A4D0), 'after Yi');
  Assert.AreEqual(2, CharDisplayWidth(#$AC00), 'first Hangul syllable');
  Assert.AreEqual(2, CharDisplayWidth(#$D7A3), 'last Hangul syllable');
  Assert.AreEqual(1, CharDisplayWidth(#$D7A4), 'after Hangul syllables');
  Assert.AreEqual(2, CharDisplayWidth(#$FF01), 'first fullwidth form');
  Assert.AreEqual(2, CharDisplayWidth(#$FF60), 'last fullwidth form');
  Assert.AreEqual(1, CharDisplayWidth(#$FF61), 'halfwidth form');
  Assert.AreEqual(2, CharDisplayWidth(#$FFE6), 'fullwidth won sign');
  Assert.AreEqual(1, CharDisplayWidth(#$FFE8), 'halfwidth form after fullwidth signs');
  Assert.AreEqual(1, CharDisplayWidth(#$303F), 'ideographic half fill space');
end;

procedure TTestCharWidth.TestTextDisplayWidth;
begin
  Assert.AreEqual(0, TextDisplayWidth(''));
  Assert.AreEqual(3, TextDisplayWidth('abc'));
  Assert.AreEqual(4, TextDisplayWidth(cHan + cHira));
  Assert.AreEqual(5, TextDisplayWidth('a' + cHan + cHangul));
end;

procedure TTestCharWidth.TestTextFitCharsNeverSplitsWideCharacter;
begin
  Assert.AreEqual(3, TextFitChars('abcdef', 3));
  Assert.AreEqual(3, TextFitChars('abc', 6), 'whole text fits');
  Assert.AreEqual(2, TextFitChars(cHan + cHira + cKata, 4));
  Assert.AreEqual(1, TextFitChars(cHan + cHira, 3), 'second wide character would cross the edge');
  Assert.AreEqual(0, TextFitChars(cHan, 1));
  Assert.AreEqual(2, TextFitChars('a' + cHan + 'b', 3));
  Assert.AreEqual(0, TextFitChars('abc', 0));
end;

procedure TTestCharWidth.TestStripWideFillers;
begin
  Assert.AreEqual('abc', StripWideFillers('abc'));
  Assert.AreEqual('a' + cHan + 'b', StripWideFillers('a' + cHan + ' b'));
  Assert.AreEqual(cHan + cHira, StripWideFillers(cHan + ' ' + cHira + ' '));
  Assert.AreEqual(cHan, StripWideFillers(cHan), 'filler cut off by the end of the line');
  Assert.AreEqual('', StripWideFillers(''));
end;

procedure TTestCharWidth.TestTextHasWide;
begin
  Assert.IsFalse(TextHasWide(''));
  Assert.IsFalse(TextHasWide('abc ' + #$0416));
  Assert.IsTrue(TextHasWide('abc' + cHan));
  Assert.IsTrue(TextHasWide(cHangul));
end;

procedure TTestCharWidth.TestCellsBetween;
begin
  // cHan cHira a b c = 2 + 2 + 3 cells.
  Assert.AreEqual(4, CellsBetween(cHan + cHira + 'abc', 0, 2));
  Assert.AreEqual(3, CellsBetween(cHan + cHira + 'abc', 1, 3));
  Assert.AreEqual(7, CellsBetween(cHan + cHira + 'abc', 0, 5));
  Assert.AreEqual(7, CellsBetween(cHan + cHira + 'abc', -3, 99), 'ends are clamped');
  Assert.AreEqual(0, CellsBetween(cHan, 1, 1));
  Assert.AreEqual(0, CellsBetween('', 0, 4));
end;

procedure TTestCharWidth.TestCharAtCell;
const
  cText = cHan + cHira + 'abc';
begin
  Assert.AreEqual(0, CharAtCell(cText, 0, 0), 'first half of the first character');
  Assert.AreEqual(0, CharAtCell(cText, 0, 1), 'second half of the first character');
  Assert.AreEqual(1, CharAtCell(cText, 0, 2));
  Assert.AreEqual(2, CharAtCell(cText, 0, 4), 'first narrow character');
  Assert.AreEqual(4, CharAtCell(cText, 0, 6));
  Assert.AreEqual(5, CharAtCell(cText, 0, 7), 'just past the end');
  Assert.AreEqual(8, CharAtCell(cText, 0, 10), 'every cell past the end is a character');
  Assert.AreEqual(0, CharAtCell(cText, 1, 1), 'counted from the start character');
  Assert.AreEqual(1, CharAtCell(cText, 1, 2));
  Assert.AreEqual(3, CharAtCell('abc', 0, 3));
end;

end.
