unit TestToast;

{ uToast: text fitting and placement, and a TToast drawing the two-line
  "Always" notice the update check uses. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestToast = class
  public
    [Test] procedure TestFitText;
    [Test] procedure TestBounds;
    [Test] procedure TestAlwaysNoticeDraws;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uThemeTypes, uTerminalTypes, uNotice, uToast;

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

function GridText(const AGrid: TTerminalGrid): string;
var
  X, Y: Integer;
begin
  Result := '';
  for Y := 0 to High(AGrid) do
  begin
    for X := 0 to High(AGrid[Y]) do
      Result := Result + AGrid[Y][X].CharValue;
    Result := Result + #10;
  end;
end;

procedure TestAlwaysNoticeDraws;
var
  Toast: TToast;
  Grid: TTerminalGrid;
  Req: TNoticeRequest;
  Saved: Boolean;
  Text: string;
begin
  Saved := GShowToasts;
  Toast := TToast.Create(nil);
  try
    // The update check's notice: two lines, and shown with notices off.
    GShowToasts := False;
    Req := TNoticeRequest.Make('Checking github.com for MTN2 updates...');
    Req.Hint := 'Turn off: F9 > menu > Check for updates';
    Req.Always := True;
    Toast.ShowRequest(Req);
    Assert.IsTrue(Toast.Visible, 'Always notice shown with notifications off');
    AllocTerminalGrid(Grid, 100, 30);
    ClearTerminalGrid(Grid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
    Toast.Draw(Grid, nil, 100, 30);
    Text := GridText(Grid);
    Assert.IsTrue(Pos('Checking github.com', Text) > 0, 'first line drawn');
    Assert.IsTrue(Pos('Turn off: F9', Text) > 0, 'hint line drawn');
    // Dismissed by its tag only: another tag leaves it up.
    Req.Tag := 'update.check';
    Toast.ShowRequest(Req);
    Toast.HideTag('something.else');
    Assert.IsTrue(Toast.Visible, 'other tag does not hide it');
    Toast.HideTag('update.check');
    Assert.IsTrue(not Toast.Visible, 'own tag hides it');
    // A newer notice without the tag survives the dismissal.
    Toast.ShowRequest(Req);
    GShowToasts := True;
    Toast.Show('Path copied');
    Toast.HideTag('update.check');
    Assert.IsTrue(Toast.Visible, 'a notice that replaced it stays');
    GShowToasts := False;
    // A plain notice still obeys the switch.
    Toast.Hide;
    Toast.Show('Panel refreshed');
    Assert.IsTrue(not Toast.Visible, 'ordinary notice suppressed with notifications off');
  finally
    GShowToasts := Saved;
    Toast.Free;
  end;
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

procedure TTestToast.TestAlwaysNoticeDraws;
begin
  TestToast.TestAlwaysNoticeDraws;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestToast);

end.
