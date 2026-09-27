unit TestWinFileClipboard;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWinFileClipboard = class
  public
    [Test] procedure TestEncodeDecode;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uWinFileDragDrop;

procedure TestEncodeDecode;
var
  Text: string;
  Uris: TArray<string>;
  Cut: Boolean;
begin
  Text := EncodeMtnFileClip(TArray<string>.Create('file:///C:/a.txt', 'zip://C:/x.zip!/b'), False);
  Assert.IsTrue(DecodeMtnFileClip(Text, Uris, Cut), 'copy payload decodes');
  Assert.IsTrue(not Cut, 'copy is not cut');
  Assert.IsTrue(Length(Uris) = 2, 'two URIs');
  Assert.IsTrue(Uris[0] = 'file:///C:/a.txt', 'first URI');
  Assert.IsTrue(Uris[1] = 'zip://C:/x.zip!/b', 'zip URI kept');

  Text := EncodeMtnFileClip(TArray<string>.Create('file:///D:/dir'), True);
  Assert.IsTrue(DecodeMtnFileClip(Text, Uris, Cut), 'cut payload decodes');
  Assert.IsTrue(Cut, 'cut flag');
  Assert.IsTrue((Length(Uris) = 1) and (Uris[0] = 'file:///D:/dir'), 'cut URI');

  Assert.IsTrue(not DecodeMtnFileClip('', Uris, Cut), 'empty payload rejected');
  Assert.IsTrue(not DecodeMtnFileClip('hello'#10'file:///x', Uris, Cut), 'unknown header rejected');
end;

{ TTestWinFileClipboard }

procedure TTestWinFileClipboard.TestEncodeDecode;
begin
  TestWinFileClipboard.TestEncodeDecode;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWinFileClipboard);

end.
