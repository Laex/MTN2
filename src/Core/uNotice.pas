unit uNotice;

{ Fire-and-forget user notices ("path copied", "restored from Recycle Bin").
  Any unit can call Notice without knowing who shows it: TDualPanelWindow
  registers the handler that turns it into a toast (uToast). No handler --
  tests, a window that is not up yet -- and a notice is simply dropped. }

interface

uses
  System.SysUtils;

type
  TToastKind = (tkInfo, tkWarning);

  TNoticeHandler = reference to procedure(const ATemplate, AArg: string;
    AKind: TToastKind);

/// <summary>ATemplate may hold one %s for AArg (a path or a name): the
/// toast shortens AArg to fit the window, so pass it separately rather than
/// Format()ing it in.</summary>
procedure Notice(const ATemplate: string; const AArg: string = '';
  AKind: TToastKind = tkInfo);
procedure SetNoticeHandler(const AHandler: TNoticeHandler);

implementation

var
  GHandler: TNoticeHandler;

procedure Notice(const ATemplate, AArg: string; AKind: TToastKind);
begin
  if Assigned(GHandler) then
    GHandler(ATemplate, AArg, AKind);
end;

procedure SetNoticeHandler(const AHandler: TNoticeHandler);
begin
  GHandler := AHandler;
end;

initialization

finalization
  GHandler := nil;

end.
