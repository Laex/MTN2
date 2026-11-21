unit TestDialogScreenFit;

{ Every built-in dialog, in every shipped language, fits an 80x24 terminal:
  no control loses width to the screen (height may scroll). A dialog wider
  than the screen would cut its fields and buttons at the right edge. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogScreenFit = class
  public
    [Test] procedure TestEveryDialogFitsEightyByTwentyFour;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Math, uThemeTypes, uDialogTypes,
  uDialogV2Layout, uDialogTabs, uDialogResources, uStrings, uCharWidth, TestDialogAlignment;

const
  cScreenW = 80;
  // A caption may lose this many cells when the dialog is too tight to keep it
  // whole (the edge cell that keeps text off the border counts).
  cCutAllowed = 2;

// Width a control has when the dialog keeps its authored width, against the
// width it has in the frame the screen allows.
procedure CheckDeclaration(const AName, ALocale: string; const ADecl: TDialogDeclaration;
  AReport: TStrings);
var
  Decl: TDialogDeclaration;
  Wide, Narrow: TDialogV2Layout;
  Page, I, Pages, FullH, W: Integer;
  Strip, NW, WW: Integer;
  Msg: string;
begin
  Decl := ADecl;
  W := Min(Decl.Width, cScreenW - 2);
  Strip := DialogTabStripIndex(Decl.Controls);
  Pages := 1;
  if Strip >= 0 then
    Pages := Max(Length(Decl.Controls[Strip].Items), 1);
  for Page := 0 to Pages - 1 do
  begin
    if Strip >= 0 then
      Decl.Controls[Strip].SelectedIndex := Page;
    FullH := 2;
    for I := 0 to High(Decl.Controls) do
      FullH := Max(FullH, Max(Decl.Controls[I].Row, 0) + Max(Decl.Controls[I].BoxH, 1) +
        ControlRowSpan(Decl.Controls[I]) + 2);
    Wide := LayoutDialogV2(Decl.Controls, TRectI.Make(0, 0, Decl.Width - 1, FullH - 1), -1, 0, -1);
    Narrow := LayoutDialogV2(Decl.Controls, TRectI.Make(0, 0, W - 1, FullH - 1), -1, 0, -1);
    for I := 0 to High(Decl.Controls) do
      if not DialogControlHiddenByTab(Decl.Controls, I) then
      begin
        Msg := '';
        NW := Narrow.Bounds[I].Right - Narrow.Bounds[I].Left + 1;
        WW := Wide.Bounds[I].Right - Wide.Bounds[I].Left + 1;
        if (Narrow.Bounds[I].Left < 1) or (Narrow.Bounds[I].Right > W - 2) then
          Msg := 'outside the frame'
        else
          case Decl.Controls[I].Kind of
            dckInput, dckList:
              if NW < Min(WW, ControlMinWidth(Decl.Controls[I])) then
                Msg := 'too narrow';
            dckLabel, dckStatus:
              if (NW < Min(ControlMinWidth(Decl.Controls[I]), W - 2 - Narrow.Bounds[I].Left) - cCutAllowed) and
                 not IsHRuleText(Decl.Controls[I].Text) then
                Msg := 'caption cut';
          else
            // Buttons, check boxes, drop-downs: at least their caption or items.
            if NW < Min(WW, ControlMinWidth(Decl.Controls[I])) - cCutAllowed then
              Msg := 'squeezed';
          end;
        if Msg <> '' then
          AReport.Add(Format('%s [%s] page %d: %s (%s) %s: %d..%d of %d, wide %d..%d',
            [AName, ALocale, Page, Decl.Controls[I].Id, Decl.Controls[I].Text, Msg,
             Narrow.Bounds[I].Left, Narrow.Bounds[I].Right, W,
             Wide.Bounds[I].Left, Wide.Bounds[I].Right]));
      end;
  end;
end;

procedure TTestDialogScreenFit.TestEveryDialogFitsEightyByTwentyFour;
var
  Report: TStringList;
  Loc, Name: string;
  Decl: TDialogDeclaration;
begin
  Report := TStringList.Create;
  try
    for Loc in ['', 'ru', 'de', 'zh'] do
    begin
      SetLocale(Loc);
      try
        for Name in DialogResourceNames do
          if TryLoadDialogResource(Name, Decl) then
            CheckDeclaration(Name, Loc, Decl, Report)
          else
            Report.Add(Name + ': not loaded');
      finally
        SetLocale('');
      end;
    end;
    Assert.AreEqual(0, Report.Count, sLineBreak + Report.Text);
  finally
    Report.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogScreenFit);

end.
