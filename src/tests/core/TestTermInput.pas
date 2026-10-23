unit TestTermInput;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTermInput = class
  public
    [Test] procedure TestPlainText;
    [Test] procedure TestControlKeys;
    [Test] procedure TestCursorAndFunctionKeys;
    [Test] procedure TestModifiedKeys;
    [Test] procedure TestShiftedFunctionKeysOfPlainTerminals;
    [Test] procedure TestAltKey;
    [Test] procedure TestLoneEscapeNeedsFlush;
    [Test] procedure TestKittyKeys;
    [Test] procedure TestModifyOtherKeys;
    [Test] procedure TestMouse;
    [Test] procedure TestBracketedPaste;
    [Test] procedure TestSplitInput;
    [Test] procedure TestCapabilityReplies;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections,
  uTermInput;

function Decode(const AText: string; AFlush: Boolean = False): TArray<TTermEvent>;
var
  P: TTermInputParser;
  L: TList<TTermEvent>;
  B: TBytes;
begin
  P := TTermInputParser.Create;
  L := TList<TTermEvent>.Create;
  try
    B := TEncoding.UTF8.GetBytes(AText);
    P.Feed(B, Length(B), L);
    if AFlush then
      P.FlushPending(L);
    Result := L.ToArray;
  finally
    L.Free;
    P.Free;
  end;
end;

procedure CheckKey(const E: TTermEvent; AKey: Word; AChar: Char; AShift: TShiftState;
  const AMsg: string);
begin
  Assert.AreEqual(Ord(tekKey), Ord(E.Kind), AMsg + ' kind');
  Assert.AreEqual(Integer(AKey), Integer(E.Key), AMsg + ' key');
  Assert.AreEqual(Ord(AChar), Ord(E.KeyChar), AMsg + ' char');
  Assert.IsTrue(E.Shift = AShift, AMsg + ' shift');
end;

procedure TTestTermInput.TestPlainText;
var
  E: TArray<TTermEvent>;
begin
  E := Decode('aZ5 ;');
  Assert.AreEqual(5, Integer(Length(E)));
  CheckKey(E[0], Ord('A'), 'a', [], 'a');
  CheckKey(E[1], Ord('Z'), 'Z', [ssShift], 'Z');
  CheckKey(E[2], Ord('5'), '5', [], '5');
  CheckKey(E[3], vkSpace, ' ', [], 'space');
  CheckKey(E[4], vkSemicolon, ';', [], 'semicolon');
  // UTF-8: a Cyrillic letter has no virtual key.
  E := Decode(#$0436);
  Assert.AreEqual(1, Integer(Length(E)));
  CheckKey(E[0], 0, #$0436, [], 'cyrillic');
end;

procedure TTestTermInput.TestControlKeys;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#13#9#127#3#1);
  Assert.AreEqual(5, Integer(Length(E)));
  CheckKey(E[0], vkReturn, #0, [], 'enter');
  CheckKey(E[1], vkTab, #0, [], 'tab');
  CheckKey(E[2], vkBack, #0, [], 'backspace');
  CheckKey(E[3], Ord('C'), #0, [ssCtrl], 'ctrl+c');
  CheckKey(E[4], Ord('A'), #0, [ssCtrl], 'ctrl+a');
end;

procedure TTestTermInput.TestCursorAndFunctionKeys;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'[A'#27'[B'#27'[C'#27'[D'#27'[H'#27'[F');
  Assert.AreEqual(6, Integer(Length(E)));
  CheckKey(E[0], vkUp, #0, [], 'up');
  CheckKey(E[1], vkDown, #0, [], 'down');
  CheckKey(E[2], vkRight, #0, [], 'right');
  CheckKey(E[3], vkLeft, #0, [], 'left');
  CheckKey(E[4], vkHome, #0, [], 'home');
  CheckKey(E[5], vkEnd, #0, [], 'end');
  E := Decode(#27'OP'#27'OS'#27'[15~'#27'[17~'#27'[21~'#27'[24~');
  Assert.AreEqual(6, Integer(Length(E)));
  CheckKey(E[0], vkF1, #0, [], 'F1');
  CheckKey(E[1], vkF4, #0, [], 'F4');
  CheckKey(E[2], vkF5, #0, [], 'F5');
  CheckKey(E[3], vkF6, #0, [], 'F6');
  CheckKey(E[4], vkF10, #0, [], 'F10');
  CheckKey(E[5], vkF12, #0, [], 'F12');
  E := Decode(#27'[2~'#27'[3~'#27'[5~'#27'[6~'#27'[Z');
  Assert.AreEqual(5, Integer(Length(E)));
  CheckKey(E[0], vkInsert, #0, [], 'insert');
  CheckKey(E[1], vkDelete, #0, [], 'delete');
  CheckKey(E[2], vkPrior, #0, [], 'page up');
  CheckKey(E[3], vkNext, #0, [], 'page down');
  CheckKey(E[4], vkTab, #0, [ssShift], 'shift+tab');
end;

procedure TTestTermInput.TestShiftedFunctionKeysOfPlainTerminals;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'[25~'#27'[26~'#27'[28~'#27'[29~'#27'[34~'#27'[23~');
  Assert.AreEqual(6, Integer(Length(E)));
  CheckKey(E[0], vkF3, #0, [ssShift], 'shift+F3');
  CheckKey(E[1], vkF4, #0, [ssShift], 'shift+F4');
  CheckKey(E[2], vkF5, #0, [ssShift], 'shift+F5');
  CheckKey(E[3], vkF6, #0, [ssShift], 'shift+F6');
  CheckKey(E[4], vkF10, #0, [ssShift], 'shift+F10');
  CheckKey(E[5], vkF11, #0, [], 'F11 stays unshifted');
end;

procedure TTestTermInput.TestModifiedKeys;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'[1;5A'#27'[1;2D'#27'[5;3~'#27'[15;6~');
  Assert.AreEqual(4, Integer(Length(E)));
  CheckKey(E[0], vkUp, #0, [ssCtrl], 'ctrl+up');
  CheckKey(E[1], vkLeft, #0, [ssShift], 'shift+left');
  CheckKey(E[2], vkPrior, #0, [ssAlt], 'alt+pgup');
  CheckKey(E[3], vkF5, #0, [ssShift, ssCtrl], 'ctrl+shift+F5');
end;

procedure TTestTermInput.TestAltKey;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'x'#27#13);
  Assert.AreEqual(2, Integer(Length(E)));
  CheckKey(E[0], Ord('X'), #0, [ssAlt], 'alt+x');
  CheckKey(E[1], vkReturn, #0, [ssAlt], 'alt+enter');
end;

procedure TTestTermInput.TestLoneEscapeNeedsFlush;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27);
  Assert.AreEqual(0, Integer(Length(E)), 'a lone ESC waits for more bytes');
  E := Decode(#27, True);
  Assert.AreEqual(1, Integer(Length(E)));
  CheckKey(E[0], vkEscape, #0, [], 'escape');
end;

procedure TTestTermInput.TestKittyKeys;
var
  E: TArray<TTermEvent>;
begin
  // Ctrl+D on a Cyrillic layout: key 1074 (в), base layout key 100 (d).
  E := Decode(#27'[1074::100;5u');
  Assert.AreEqual(1, Integer(Length(E)));
  CheckKey(E[0], Ord('D'), #0, [ssCtrl], 'ctrl+d by base layout');
  E := Decode(#27'[27u'#27'[13;2u'#27'[97;3u'#27'[59;5u');
  Assert.AreEqual(4, Integer(Length(E)));
  CheckKey(E[0], vkEscape, #0, [], 'escape');
  CheckKey(E[1], vkReturn, #0, [ssShift], 'shift+enter');
  CheckKey(E[2], Ord('A'), #0, [ssAlt], 'alt+a');
  CheckKey(E[3], vkSemicolon, #0, [ssCtrl], 'ctrl+;');
end;

procedure TTestTermInput.TestModifyOtherKeys;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'[27;5;59~'#27'[27;6;9~');
  Assert.AreEqual(2, Integer(Length(E)));
  CheckKey(E[0], vkSemicolon, #0, [ssCtrl], 'ctrl+;');
  CheckKey(E[1], vkTab, #0, [ssCtrl, ssShift], 'ctrl+shift+tab');
end;

procedure TTestTermInput.TestMouse;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'[<0;10;5M'#27'[<0;10;5m'#27'[<2;3;4M'#27'[<32;11;6M'#27'[<64;1;1M'#27'[<65;1;1M');
  Assert.AreEqual(6, Integer(Length(E)));
  Assert.AreEqual(Ord(tekMouse), Ord(E[0].Kind));
  Assert.AreEqual(9, E[0].Col, 'columns are zero-based');
  Assert.AreEqual(4, E[0].Row);
  Assert.AreEqual(Ord(tmaPress), Ord(E[0].MouseAction));
  Assert.AreEqual(Ord(TMouseButton.mbLeft), Ord(E[0].Button));
  Assert.AreEqual(Ord(tmaRelease), Ord(E[1].MouseAction));
  Assert.AreEqual(Ord(TMouseButton.mbRight), Ord(E[2].Button));
  Assert.AreEqual(Ord(tmaMove), Ord(E[3].MouseAction));
  Assert.AreEqual(Ord(tmaWheelUp), Ord(E[4].MouseAction));
  Assert.AreEqual(Ord(tmaWheelDown), Ord(E[5].MouseAction));
  E := Decode(#27'[<20;5;5M');
  Assert.IsTrue(E[0].Shift = [ssShift, ssCtrl], 'modifiers of a mouse report');
end;

procedure TTestTermInput.TestBracketedPaste;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'[200~line 1'#10'line 2'#27'[201~x');
  Assert.AreEqual(2, Integer(Length(E)));
  Assert.AreEqual(Ord(tekPaste), Ord(E[0].Kind));
  Assert.AreEqual('line 1'#10'line 2', E[0].Text);
  CheckKey(E[1], Ord('X'), 'x', [], 'text after the paste');
end;

procedure TTestTermInput.TestSplitInput;
var
  P: TTermInputParser;
  L: TList<TTermEvent>;
  B: TBytes;
begin
  P := TTermInputParser.Create;
  L := TList<TTermEvent>.Create;
  try
    // An escape sequence and a multi-byte character cut in the middle.
    B := TBytes.Create(27, Ord('['));
    P.Feed(B, 2, L);
    Assert.AreEqual(0, Integer(L.Count));
    B := TBytes.Create(Ord('1'), Ord(';'), Ord('5'), Ord('A'));
    P.Feed(B, 4, L);
    Assert.AreEqual(1, Integer(L.Count));
    CheckKey(L[0], vkUp, #0, [ssCtrl], 'ctrl+up in two pieces');
    L.Clear;
    B := TBytes.Create($D0);
    P.Feed(B, 1, L);
    Assert.AreEqual(0, Integer(L.Count));
    B := TBytes.Create($B6);
    P.Feed(B, 1, L);
    Assert.AreEqual(1, Integer(L.Count));
    Assert.AreEqual($0436, Ord(L[0].KeyChar));
  finally
    L.Free;
    P.Free;
  end;
end;

procedure TTestTermInput.TestCapabilityReplies;
var
  E: TArray<TTermEvent>;
begin
  E := Decode(#27'[?0u'#27'[?62;4c');
  Assert.AreEqual(2, Integer(Length(E)));
  Assert.AreEqual(Ord(tekCapabilities), Ord(E[0].Kind));
  Assert.IsTrue(E[0].KittyKeyboard, 'kitty keyboard reply');
  Assert.IsFalse(E[1].KittyKeyboard, 'device attributes reply');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTermInput);

end.
