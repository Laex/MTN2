unit TestToast;

{ uToast text fitting and placement (pure functions; TToast itself owns an
  FMX timer and is exercised in the running app). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestToast = class
  public
    [Test] procedure TestFitText;
    [Test] procedure TestBounds;
  end;

implementation

uses
  System.SysUtils,
  uThemeTypes, uToast;

procedure TestFitText;
const
  Tpl = 'Full path "%s" copied to the clipboard';
  LongPath = 'C:\Users\someone\Documents\Projects\very\deep\folder\structure\file.txt';
var
  S: string;
begin
  S := ToastFitText(Tpl, 'C:\a.txt', 200);
  Assert.IsTrue(S = 'Full path "C:\a.txt" copied to the clipboard', 'short arg kept whole');

  S := ToastFitText(Tpl, LongPath, 60);
  Assert.IsTrue(Length(S) <= 60, 'fits max length');
  Assert.IsTrue(S.StartsWith('Full path "C:\...'), 'path keeps drive, middle elided');
  Assert.IsTrue(S.EndsWith('file.txt" copied to the clipboard'), 'path keeps tail and template end');

  S := ToastFitText('Nothing to copy', '', 200);
  Assert.IsTrue(S = 'Nothing to copy', 'no arg: template as is');

  S := ToastFitText('Nothing to copy', '', 8);
  Assert.IsTrue(S = 'Nothi...', 'no arg: cut with ellipsis');

  S := ToastFitText('Copied:', 'name.txt', 200);
  Assert.IsTrue(S = 'Copied: name.txt', 'template without %s: arg appended');

  S := ToastFitText('Bad %d template', 'x', 200);
  Assert.IsTrue(S = 'Bad %d template x', 'bad placeholder degrades, no exception');

  Assert.IsTrue(ToastFitText(Tpl, LongPath, 0) = '', 'zero width -> empty');
end;

procedure TestBounds;
var
  R: TRectI;
begin
  R := ToastBounds(20, 100, 30);
  Assert.IsTrue(R.Width = 24, 'box = text + frame + padding');
  Assert.IsTrue(R.Height = 3, 'three rows');
  Assert.IsTrue(R.Right = 97, 'right margin 2');
  Assert.IsTrue(R.Bottom = 25, 'bottom frame above panel frame / cmdline');

  R := ToastBounds(20, 10, 30);
  Assert.IsTrue(R.Width <= 0, 'too narrow -> empty');
  R := ToastBounds(20, 100, 5);
  Assert.IsTrue(R.Width <= 0, 'too low -> empty');
  R := ToastBounds(0, 100, 30);
  Assert.IsTrue(R.Width <= 0, 'no text -> empty');

  Assert.IsTrue(ToastMaxTextLen(100) + 4 + 2 < 100, 'max text leaves room for frame and margin');

  // A hint line grows the box upwards; the bottom stays put.
  R := ToastBounds(20, 100, 30, 2);
  Assert.IsTrue(R.Height = 4, 'two text rows + frame');
  Assert.IsTrue(R.Bottom = 25, 'same bottom as one line');
  Assert.IsTrue(R.Width = 24, 'width from the longer line');
  R := ToastBounds(20, 100, 10, 2);
  Assert.IsTrue(R.Width <= 0, 'no room for the second line -> empty');
end;

{ TTestToast }

procedure TTestToast.TestFitText;
begin
  TestToast.TestFitText;
end;

procedure TTestToast.TestBounds;
begin
  TestToast.TestBounds;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestToast);

end.
