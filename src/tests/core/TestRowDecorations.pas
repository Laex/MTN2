unit TestRowDecorations;

{ uRowDecorations: the name colors a plugin sets per folder. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRowDecorations = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure RoleAndHexColorsAreLookedUpByFolderAndName;
    [Test] procedure FolderMatchIgnoresCaseAndTrailingSlash;
    [Test] procedure NewMarksReplaceTheFoldersOldOnes;
    [Test] procedure EmptyMarksForgetTheFolder;
    [Test] procedure UnknownColorsAreSkipped;
    [Test] procedure ClearPluginForgetsOnlyItsFolders;
  end;

implementation

uses
  System.UITypes, uRowDecorations;

const
  cFolder = 'file:///C:/Work/repo/';

procedure TTestRowDecorations.TearDown;
begin
  RowDecorationsClearPlugin('p1');
  RowDecorationsClearPlugin('p2');
end;

procedure TTestRowDecorations.RoleAndHexColorsAreLookedUpByFolderAndName;
var
  C: TAlphaColor;
begin
  Assert.IsTrue(RowDecorationsSet('p1', cFolder, '{"a.txt":"warn","b.txt":"#102030"}'));
  Assert.IsTrue(RowDecorationsAny);
  Assert.IsTrue(RowDecorationColor(cFolder, 'a.txt', C));
  Assert.AreEqual(Cardinal($FFE0A000), Cardinal(C));
  Assert.IsTrue(RowDecorationColor(cFolder, 'b.txt', C));
  Assert.AreEqual(Cardinal($FF102030), Cardinal(C));
  Assert.IsFalse(RowDecorationColor(cFolder, 'c.txt', C), 'unmarked row');
  Assert.IsFalse(RowDecorationColor('file:///C:/other/', 'a.txt', C), 'other folder');
end;

procedure TTestRowDecorations.FolderMatchIgnoresCaseAndTrailingSlash;
var
  C: TAlphaColor;
begin
  RowDecorationsSet('p1', cFolder, '{"A.TXT":"ok"}');
  Assert.IsTrue(RowDecorationColor('FILE:///c:/work/repo', 'a.txt', C));
end;

procedure TTestRowDecorations.NewMarksReplaceTheFoldersOldOnes;
var
  C: TAlphaColor;
begin
  RowDecorationsSet('p1', cFolder, '{"a.txt":"warn"}');
  RowDecorationsSet('p1', cFolder, '{"b.txt":"ok"}');
  Assert.IsFalse(RowDecorationColor(cFolder, 'a.txt', C));
  Assert.IsTrue(RowDecorationColor(cFolder, 'b.txt', C));
end;

procedure TTestRowDecorations.EmptyMarksForgetTheFolder;
var
  C: TAlphaColor;
begin
  RowDecorationsSet('p1', cFolder, '{"a.txt":"warn"}');
  RowDecorationsSet('p1', cFolder, '{}');
  Assert.IsFalse(RowDecorationColor(cFolder, 'a.txt', C));
  Assert.IsFalse(RowDecorationsAny);
  RowDecorationsSet('p1', cFolder, '{"a.txt":"warn"}');
  RowDecorationsSet('p1', cFolder, '');
  Assert.IsFalse(RowDecorationsAny, 'an empty text forgets the folder too');
end;

procedure TTestRowDecorations.UnknownColorsAreSkipped;
var
  C: TAlphaColor;
begin
  RowDecorationsSet('p1', cFolder, '{"a.txt":"purple-ish","b.txt":"ok","c.txt":5}');
  Assert.IsFalse(RowDecorationColor(cFolder, 'a.txt', C));
  Assert.IsFalse(RowDecorationColor(cFolder, 'c.txt', C));
  Assert.IsTrue(RowDecorationColor(cFolder, 'b.txt', C));
  Assert.IsFalse(RowDecorationsSet('', cFolder, '{}'), 'no plugin id');
  Assert.IsFalse(RowDecorationsSet('p1', '', '{}'), 'no folder');
end;

procedure TTestRowDecorations.ClearPluginForgetsOnlyItsFolders;
var
  C: TAlphaColor;
begin
  RowDecorationsSet('p1', cFolder, '{"a.txt":"warn"}');
  RowDecorationsSet('p2', 'file:///C:/Work/second/', '{"a.txt":"ok"}');
  RowDecorationsClearPlugin('p1');
  Assert.IsFalse(RowDecorationColor(cFolder, 'a.txt', C));
  Assert.IsTrue(RowDecorationColor('file:///C:/Work/second/', 'a.txt', C));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRowDecorations);

end.
