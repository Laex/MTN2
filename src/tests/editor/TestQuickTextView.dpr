program TestQuickTextView;

{$APPTYPE CONSOLE}

{ Ctrl+Q text Quick View (uQuickTextView + TEditorWindow.Chromeless):
  which rows get a preview, text / Markdown / hex / streamed big file drawn
  inside the panel frame without touching it, scrolling, Clear, and that a
  previewed file (small or streamed) can still be deleted. Temp files only.
  Build with -U"..\..\Core;..\..\Themes". }
uses
  System.SysUtils, System.Classes, System.IOUtils,
  uTerminalTypes, uThemeTypes, uDualPanelTypes, uVfsTypes, uNDNTheme, uQuickTextView;

var
  Grid: TTerminalGrid;
  QV: TQuickTextView;
  Bounds: TRectI;
  Fails, Changes: Integer;

type
  TSink = class
    procedure Changed(Sender: TObject);
  end;

procedure TSink.Changed(Sender: TObject);
begin
  Inc(Changes);
end;

procedure Check(ACond: Boolean; const AWhat: string);
begin
  if ACond then
    Writeln('  [PASS] ', AWhat)
  else
  begin
    Writeln('  [FAIL] ', AWhat);
    Inc(Fails);
  end;
end;

procedure Pump(AMs: Integer = 600);
var
  T: UInt64;
begin
  T := TThread.GetTickCount64 + UInt64(AMs);
  while TThread.GetTickCount64 < T do
  begin
    CheckSynchronize(10);
    Sleep(5);
  end;
end;

procedure ResetGrid;
var
  X, Y: Integer;
begin
  SetLength(Grid, 24);
  for Y := 0 to High(Grid) do
  begin
    SetLength(Grid[Y], 60);
    for X := 0 to High(Grid[Y]) do
      Grid[Y][X].CharValue := '#'; // stands for "the panel's frame / outside"
  end;
end;

function Row(AY: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := 0 to High(Grid[AY]) do
    Result := Result + Grid[AY][X].CharValue;
end;

function GridHas(const S: string): Boolean;
var
  Y: Integer;
begin
  for Y := 0 to High(Grid) do
    if Pos(S, Row(Y)) > 0 then
      Exit(True);
  Result := False;
end;

procedure ShowAndPaint(const APath: string);
begin
  QV.ShowFile(PathToFileUri(APath));
  Pump;
  ResetGrid;
  QV.Paint(Grid, Bounds, 0, 0);
end;

function FrameIntact: Boolean;
var
  X, Y: Integer;
begin
  Result := True;
  for Y := Bounds.Top to Bounds.Bottom do
    for X := Bounds.Left to Bounds.Right do
      if ((Y = Bounds.Top) or (Y = Bounds.Bottom) or (X = Bounds.Left) or (X = Bounds.Right)) and
         (Grid[Y][X].CharValue <> '#') then
        Exit(False);
  // outside untouched too
  if (Grid[0][0].CharValue <> '#') or (Grid[23][59].CharValue <> '#') then
    Exit(False);
end;

function MkRow(const AUri: string; ADir: Boolean; ASize: Int64): TPanelRow;
begin
  Result := Default(TPanelRow);
  Result.URI := AUri;
  Result.IsDirectory := ADir;
  Result.Size := ASize;
end;

var
  Dir, Txt, Md, Bin, Big: string;
  Sink: TSink;
  B: TBytes;
  I: Integer;
  SL: TStringList;
begin
  Fails := 0;
  Writeln('PreviewKind');
  Check(TQuickTextView.PreviewKind(False, Default(TPanelRow)) = qtpNone, 'no row -> none');
  Check(TQuickTextView.PreviewKind(True, MkRow('file:///C:/x', True, 0)) = qtpNone, 'folder -> none');
  Check(TQuickTextView.PreviewKind(True, MkRow('file:///C:/x.txt', False, 10)) = qtpText, 'local file -> text');
  Check(TQuickTextView.PreviewKind(True, MkRow('file:///C:/a.zip!/b.txt', False, 1000)) = qtpText, 'small archive member -> text');
  Check(TQuickTextView.PreviewKind(True, MkRow('file:///C:/a.zip!/b.iso', False, 100 * 1024 * 1024)) = qtpAskF3, 'big archive member -> F3');
  Check(TQuickTextView.PreviewKind(True, MkRow('sftp://host/home/a.txt', False, 10)) = qtpAskF3, 'SFTP -> F3');

  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-qv-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  Txt := TPath.Combine(Dir, 'notes.txt');
  Md := TPath.Combine(Dir, 'readme.md');
  Bin := TPath.Combine(Dir, 'blob.bin');
  Big := TPath.Combine(Dir, 'big.log');
  TFile.WriteAllText(Txt, 'first line of notes'#13#10'second line', TEncoding.UTF8);
  TFile.WriteAllText(Md, '# Title'#13#10#13#10'Some **bold** text and a [link](x.md).', TEncoding.UTF8);
  SetLength(B, 256);
  for I := 0 to 255 do
    B[I] := I;
  TFile.WriteAllBytes(Bin, B);
  SL := TStringList.Create;
  try
    for I := 1 to 400000 do
      SL.Add(Format('log line %d ..................................', [I]));
    SL.SaveToFile(Big); // ~20 MB: above the whole-buffer limit -> streaming
  finally
    SL.Free;
  end;

  Bounds := TRectI.Make(5, 2, 44, 20);
  Sink := TSink.Create;
  QV := TQuickTextView.Create(TNDNTheme.Create);
  try
    QV.OnChanged := Sink.Changed;

    Writeln('Text');
    Changes := 0;
    ShowAndPaint(Txt);
    Check(GridHas('first line of notes') and GridHas('second line'), 'text shown');
    Check(FrameIntact, 'panel frame and outside untouched');
    Check(Changes > 0, 'load completion notifies the host');
    Check(Pos('first line', Row(Bounds.Top + 1)) = Bounds.Left + 2, 'text starts inside the frame (row 1, col 1)');

    Writeln('Markdown');
    ShowAndPaint(Md);
    Check(GridHas('Title') and not GridHas('# Title'), 'heading rendered');
    Check(GridHas('Some bold text and a link.'), 'emphasis and link rendered');

    Writeln('Binary');
    ShowAndPaint(Bin);
    Check(GridHas('00 01 02 03'), 'hex dump');

    Writeln('Streaming big file');
    ShowAndPaint(Big);
    Pump(1500);
    ResetGrid;
    QV.Paint(Grid, Bounds, 0, 0);
    Check(GridHas('log line 1 '), 'first lines of a 20 MB file');
    QV.ScrollBy(3);
    ResetGrid;
    QV.Paint(Grid, Bounds, 0, 0);
    Check(GridHas('log line 4 ') and not GridHas('log line 1 '), 'ScrollBy scrolls');

    Writeln('Files stay deletable');
    ShowAndPaint(Txt);
    try
      TFile.Delete(Txt);
      Check(not TFile.Exists(Txt), 'previewed text file deleted');
    except
      on E: Exception do
        Check(False, 'delete previewed text file: ' + E.Message);
    end;
    ShowAndPaint(Big);
    Pump(2500);
    try
      TFile.Delete(Big);
      Check(not TFile.Exists(Big), 'previewed streaming file deleted');
    except
      on E: Exception do
        Check(False, 'delete previewed streaming file: ' + E.Message);
    end;

    Writeln('Clear');
    Changes := 0;
    QV.Clear;
    ResetGrid;
    QV.Paint(Grid, Bounds, 0, 0);
    Check((QV.Uri = '') and FrameIntact and not GridHas('log line'), 'cleared: paints nothing');
    Check(Changes = 0, 'Clear does not ask for a repaint');
  finally
    QV.Free;
    Sink.Free;
    TDirectory.Delete(Dir, True);
  end;
  Writeln(Format('Failures: %d', [Fails]));
  if Fails > 0 then
    Halt(1);
end.
