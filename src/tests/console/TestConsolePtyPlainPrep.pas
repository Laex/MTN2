unit TestConsolePtyPlainPrep;

{ Characterization of PTY plain-buffer prompt heuristics extracted from
  TConsoleBuffer.AppendOutputEx / BreakLineBeforeChunkLocked. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsolePtyPlainPrep = class
  public
    [Test] procedure LooksLikeDrivePromptRecognizesShells;
    [Test] procedure FindPromptEndAndProtectedPadding;
    [Test] procedure FixPromptNewlinesSplitsGluedContent;
    [Test] procedure PlainChunkLineBreakClassification;
  end;

implementation

uses
  System.SysUtils,
  uConsolePtyPlainPrep;

procedure TTestConsolePtyPlainPrep.LooksLikeDrivePromptRecognizesShells;
begin
  Assert.IsTrue(LooksLikeDrivePrompt('C:\Work'), 'drive path');
  Assert.IsTrue(LooksLikeDrivePrompt('PS D:\Work'), 'powershell prefix');
  Assert.IsTrue(LooksLikeDrivePrompt('user@host:~$'), 'unix dollar');
  Assert.IsTrue(LooksLikeDrivePrompt('root#'), 'hash prompt');
  Assert.IsFalse(LooksLikeDrivePrompt('hello'), 'plain text');
  Assert.IsFalse(LooksLikeDrivePrompt('C:'), 'drive without slash');
end;

procedure TTestConsolePtyPlainPrep.FindPromptEndAndProtectedPadding;
begin
  Assert.IsTrue(FindPromptEndIndex('C:\Work>') = 8, 'cmd prompt end');
  Assert.IsTrue(FindPromptEndIndex('PS C:\Work>') = 11, 'ps prompt end');
  Assert.IsTrue(FindPromptEndIndex('\\server\share>') = 15, 'unc prompt');
  Assert.IsTrue(FindPromptEndIndex('host$') = 5, 'dollar');
  Assert.IsTrue(FindPromptEndIndex('no prompt') = 0, 'none');
  Assert.IsTrue(FindPromptProtectedEnd('C:\Work> ') = 9,
    'trailing space after > is protected');
  Assert.IsTrue(FindPromptProtectedEnd('C:\Work>') = 8, 'no padding');
  Assert.IsTrue(LineHasInputAfterPrompt('C:\Work>dir'), 'input after prompt');
  Assert.IsFalse(LineHasInputAfterPrompt('C:\Work> '), 'padding only');
  Assert.IsFalse(HasPrintableChunkContent(#8#8), 'bs only');
  Assert.IsFalse(HasPrintableChunkContent(' '), 'spaces only');
  Assert.IsTrue(HasPrintableChunkContent('a'), 'letter');
end;

procedure TTestConsolePtyPlainPrep.FixPromptNewlinesSplitsGluedContent;
begin
  Assert.AreEqual('C:\a>', FixPromptNewlines('C:\a>', False), 'shortish prompt');
  Assert.AreEqual(#13'C:\a>x', FixPromptNewlines(#13'C:\a>x', False),
    'CR-led redraw untouched');
  Assert.AreEqual('C:\a>x', FixPromptNewlines('C:\a>x', True),
    'pending redraw untouched');
  Assert.AreEqual('C:\a>'#13#10'next', FixPromptNewlines('C:\a>next', False),
    'glued content splits');
  Assert.AreEqual('C:\a> ', FixPromptNewlines('C:\a> ', False),
    'trailing space stays');
end;

procedure TTestConsolePtyPlainPrep.PlainChunkLineBreakClassification;
var
  B, Empty: TPlainChunkBreaks;
begin
  Empty := [];
  B := ClassifyPlainChunkLineBreaks('C:\Work>', 'D:\Other', False, False);
  Assert.IsTrue(pcbGluedPrompt in B, 'glued next prompt');
  Assert.IsFalse(pcbOutputAfterInput in B, 'no input on current');

  B := ClassifyPlainChunkLineBreaks('C:\Work>dir', 'output', False, False);
  Assert.IsTrue(pcbOutputAfterInput in B, 'output after submitted cmd');

  B := ClassifyPlainChunkLineBreaks('C:\Work>dir', #8#8, False, False);
  Assert.IsFalse(pcbOutputAfterInput in B, 'bs burst stays in place');

  B := ClassifyPlainChunkLineBreaks('C:\Work>', 'D:\Other', True, False);
  Assert.IsTrue(B = Empty, 'grid skips');

  B := ClassifyPlainChunkLineBreaks('C:\Work>', 'D:\Other', False, True);
  Assert.IsTrue(B = Empty, 'local input skips');

  B := ClassifyPlainChunkLineBreaks('C:\Work>', #13'x', False, False);
  Assert.IsTrue(B = Empty, 'CR-led chunk skips');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsolePtyPlainPrep);

end.
