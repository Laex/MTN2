unit TestEditorLoadCancel;

{ Esc while a file is still loading cancels the load and closes the tab. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorLoadCancel = class
  public
    [Test] procedure TestEscapeWhileLoadingClosesTheTab;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uVfsTypes, uThemeRegistry, uEditorWindow;

var
  GClosed: Integer;

type
  TCloseCounter = class
    procedure OnClose(ASender: TObject);
  end;

procedure TCloseCounter.OnClose(ASender: TObject);
begin
  Inc(GClosed);
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

procedure PressEscape(AView: TEditorWindow);
var
  K: Word;
  Ch: Char;
begin
  K := vkEscape;
  Ch := #0;
  AView.HandleInput(K, [], Ch);
end;

procedure TTestEditorLoadCancel.TestEscapeWhileLoadingClosesTheTab;
var
  Dir: string;
  View: TEditorWindow;
  Counter: TCloseCounter;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-loadcancel-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  TFile.WriteAllText(TPath.Combine(Dir, 'a.txt'), 'text', TEncoding.UTF8);
  Counter := TCloseCounter.Create;
  View := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  try
    GClosed := 0;
    View.OnCloseRequest := Counter.OnClose;
    // The load completes on the main thread, which is not pumped yet.
    View.Open(PathToFileUri(TPath.Combine(Dir, 'a.txt')), True);
    Assert.IsFalse(View.DocReady, 'still loading');
    PressEscape(View);
    Assert.AreEqual(1, GClosed, 'Esc closed the tab while it was loading');
    Pump(200);
    Assert.IsFalse(View.DocReady, 'the cancelled load never completes');
  finally
    View.Free;
    Counter.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorLoadCancel);

end.
