program TestToast;

{$APPTYPE CONSOLE}

{ uToast text fitting and placement (pure functions; TToast itself owns an
  FMX timer and is exercised in the running app). }

uses
  System.SysUtils,
  uThemeTypes, uToast;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create('FAIL: ' + AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestFitText;
const
  Tpl = 'Full path "%s" copied to the clipboard';
  LongPath = 'C:\Users\someone\Documents\Projects\very\deep\folder\structure\file.txt';
var
  S: string;
begin
  Writeln('ToastFitText');
  S := ToastFitText(Tpl, 'C:\a.txt', 200);
  Expect(S = 'Full path "C:\a.txt" copied to the clipboard', 'short arg kept whole');

  S := ToastFitText(Tpl, LongPath, 60);
  Expect(Length(S) <= 60, 'fits max length');
  Expect(S.StartsWith('Full path "C:\...'), 'path keeps drive, middle elided');
  Expect(S.EndsWith('file.txt" copied to the clipboard'), 'path keeps tail and template end');

  S := ToastFitText('Nothing to copy', '', 200);
  Expect(S = 'Nothing to copy', 'no arg: template as is');

  S := ToastFitText('Nothing to copy', '', 8);
  Expect(S = 'Nothi...', 'no arg: cut with ellipsis');

  S := ToastFitText('Copied:', 'name.txt', 200);
  Expect(S = 'Copied: name.txt', 'template without %s: arg appended');

  S := ToastFitText('Bad %d template', 'x', 200);
  Expect(S = 'Bad %d template x', 'bad placeholder degrades, no exception');

  Expect(ToastFitText(Tpl, LongPath, 0) = '', 'zero width -> empty');
end;

procedure TestBounds;
var
  R: TRectI;
begin
  Writeln('ToastBounds');
  R := ToastBounds(20, 100, 30);
  Expect(R.Width = 24, 'box = text + frame + padding');
  Expect(R.Height = 3, 'three rows');
  Expect(R.Right = 97, 'right margin 2');
  Expect(R.Bottom = 25, 'bottom frame above panel frame / cmdline');

  R := ToastBounds(20, 10, 30);
  Expect(R.Width <= 0, 'too narrow -> empty');
  R := ToastBounds(20, 100, 5);
  Expect(R.Width <= 0, 'too low -> empty');
  R := ToastBounds(0, 100, 30);
  Expect(R.Width <= 0, 'no text -> empty');

  Expect(ToastMaxTextLen(100) + 4 + 2 < 100, 'max text leaves room for frame and margin');
end;

begin
  try
    TestFitText;
    TestBounds;
    Writeln('All Toast tests PASSED');
  except
    on E: Exception do
    begin
      Writeln(E.Message);
      ExitCode := 1;
    end;
  end;
end.
