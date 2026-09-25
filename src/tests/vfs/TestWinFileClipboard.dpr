program TestWinFileClipboard;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uWinFileDragDrop in '..\..\Core\uWinFileDragDrop.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestEncodeDecode;
var
  Text: string;
  Uris: TArray<string>;
  Cut: Boolean;
begin
  Writeln('MTN2 file clipboard payload');
  Text := EncodeMtnFileClip(TArray<string>.Create('file:///C:/a.txt', 'zip://C:/x.zip!/b'), False);
  Expect(DecodeMtnFileClip(Text, Uris, Cut), 'copy payload decodes');
  Expect(not Cut, 'copy is not cut');
  Expect(Length(Uris) = 2, 'two URIs');
  Expect(Uris[0] = 'file:///C:/a.txt', 'first URI');
  Expect(Uris[1] = 'zip://C:/x.zip!/b', 'zip URI kept');

  Text := EncodeMtnFileClip(TArray<string>.Create('file:///D:/dir'), True);
  Expect(DecodeMtnFileClip(Text, Uris, Cut), 'cut payload decodes');
  Expect(Cut, 'cut flag');
  Expect((Length(Uris) = 1) and (Uris[0] = 'file:///D:/dir'), 'cut URI');

  Expect(not DecodeMtnFileClip('', Uris, Cut), 'empty payload rejected');
  Expect(not DecodeMtnFileClip('hello'#10'file:///x', Uris, Cut), 'unknown header rejected');
end;

begin
  try
    TestEncodeDecode;
    Writeln('All WinFileClipboard tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
