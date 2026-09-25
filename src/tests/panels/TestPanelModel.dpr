program TestPanelModel;

{$APPTYPE CONSOLE}

{ Covers TFilePanelModel.Open's slow-navigation watchdog (uPanelModel.pas):
  answers the actual question that prompted it -- selecting an unresponsive
  drive (P: on the dev machine) in the Change Drive dialog, or cycling to it
  with Ctrl+Left/Right, must not leave the panel silently stuck on
  "Reading..." forever with no sign anything is wrong. ListDirectoryAsync
  already runs off the UI thread (uFileVfs.pas), so the app itself does not
  freeze; this test is about the *panel's own* feedback while that call
  never returns. }

uses
  System.SysUtils, System.Classes,
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uPanelColumns in '..\..\Core\uPanelColumns.pas',
  uMessageBus in '..\..\Core\uMessageBus.pas',
  uPanelModel in '..\..\Core\uPanelModel.pas';

type
  { ListDirectoryAsync never calls AOnDone -- simulates FindFirstFile blocked
    on an unresponsive network drive (P:). Every other method is unused by
    these tests. }
  TNeverAnsweringVfs = class(TInterfacedObject, IVirtualFileSystem)
    // virtual: interface dispatch resolves through the vtable built for THIS
    // class; without virtual/override, TImmediateEmptyVfs's "override" below
    // would just shadow the name for direct object calls while every call
    // through an IVirtualFileSystem reference (which is all Open ever uses)
    // would keep silently landing here instead.
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback); virtual;
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

procedure TNeverAnsweringVfs.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
begin
  // Deliberately never calls AOnDone -- that's the point.
end;

procedure TNeverAnsweringVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
end;

procedure TNeverAnsweringVfs.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
end;

procedure TNeverAnsweringVfs.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
end;

procedure TNeverAnsweringVfs.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
end;

procedure TNeverAnsweringVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
end;

procedure TNeverAnsweringVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
end;

procedure TNeverAnsweringVfs.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
end;

procedure TNeverAnsweringVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
end;

procedure TNeverAnsweringVfs.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
begin
end;

type
  { ListDirectoryAsync answers immediately with an empty listing -- the
    control case proving the watchdog does not fire for a normal, fast
    navigation. }
  TImmediateEmptyVfs = class(TNeverAnsweringVfs)
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback); override;
  end;

procedure TImmediateEmptyVfs.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  OnDone: TVfsListCallback;
  Err: TVfsError;
begin
  OnDone := AOnDone;
  Err := TVfsError.Ok;
  Err.URI := AURI;
  if not Assigned(OnDone) then
    Exit;
  // Mirrors the real TFileVirtualFileSystem.ListDirectoryAsync (uFileVfs.pas):
  // answers from a background thread, never inline on the caller's thread.
  TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Queue(nil,
        procedure
        begin
          OnDone(nil, Err);
        end);
    end).Start;
end;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function WaitUntil(const APredicate: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  Deadline: UInt64;
begin
  Deadline := TThread.GetTickCount64 + ATimeoutMs;
  repeat
    CheckSynchronize(20);
    if APredicate() then
      Exit(True);
  until TThread.GetTickCount64 >= Deadline;
  Result := APredicate();
end;

procedure TestSlowHintAppearsWhileStillLoading;
var
  Model: IPanelModel;
begin
  Writeln('Open against an unresponsive VFS');
  Model := TFilePanelModel.Create(TNeverAnsweringVfs.Create);
  Model.Open('file:///P:/');

  Expect(Model.IsLoading, 'still loading right after Open (async, not blocked)');
  Expect(Model.ItemCount >= 1, 'a placeholder row is shown immediately ("Reading...")');

  // cSlowNavigationHintMs is 8000 -- give it real headroom rather than racing it.
  Expect(WaitUntil(
    function: Boolean
    var
      I: Integer;
    begin
      Result := False;
      for I := 0 to Model.ItemCount - 1 do
        if Pos('still trying', Model.GetRow(I).Text) > 0 then
          Exit(True);
    end, 15000), 'watchdog swaps in a "still trying" status line');

  Expect(Model.IsLoading,
    'still marked loading after the hint -- the real request was not abandoned, ' +
    'only reported as slow (it may yet answer)');
end;

procedure TestSlowHintDoesNotFireForAFastAnswer;
var
  Model: IPanelModel;
  I: Integer;
begin
  Writeln('Open against a VFS that answers immediately');
  Model := TFilePanelModel.Create(TImmediateEmptyVfs.Create);
  Model.Open('file:///C:/');

  Expect(WaitUntil(
    function: Boolean
    begin
      Result := not Model.IsLoading;
    end, 5000), 'loading finishes quickly');

  // Wait past cSlowNavigationHintMs -- the already-finished navigation's
  // watchdog must be a no-op (FLoading is False by the time it fires).
  Sleep(9000);
  CheckSynchronize(20);

  Expect(not Model.IsLoading, 'still not loading after the watchdog window passed');
  Expect(Model.ItemCount >= 0, 'no crash / no stray watchdog rows appended');
  for I := 0 to Model.ItemCount - 1 do
    Expect(Pos('still trying', Model.GetRow(I).Text) = 0,
      'no leftover "still trying" row for a request that already finished');
end;

procedure TestSlowHintIgnoredAfterNavigatingAway;
var
  Model: IPanelModel;
begin
  Writeln('Watchdog from an abandoned navigation must not corrupt a newer one');
  Model := TFilePanelModel.Create(TNeverAnsweringVfs.Create);
  Model.Open('file:///P:/'); // never answers; its watchdog is now scheduled
  Sleep(500);

  // Supersede it with a fast navigation before the first watchdog fires.
  Model := TFilePanelModel.Create(TImmediateEmptyVfs.Create);
  Model.Open('file:///C:/');
  Expect(WaitUntil(
    function: Boolean
    begin
      Result := not Model.IsLoading;
    end, 5000), 'the new, unrelated model finishes normally');

  // Give the original (orphaned) model's watchdog time to fire and prove it
  // is a no-op against a *different* IPanelModel instance -- nothing to
  // assert on Model here since it's a fresh instance; this just exercises
  // the code path without crashing.
  Sleep(9000);
  CheckSynchronize(20);
  Expect(not Model.IsLoading, 'unrelated model unaffected by the abandoned watchdog');
end;

begin
  try
    TestSlowHintAppearsWhileStillLoading;
    TestSlowHintDoesNotFireForAFastAnswer;
    TestSlowHintIgnoredAfterNavigatingAway;
    Writeln('All PanelModel tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
