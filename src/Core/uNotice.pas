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

  TNoticeRequest = record
    /// <summary>May hold one %s for Arg (see Notice).</summary>
    Template: string;
    Arg: string;
    /// <summary>Optional second line in the hint colour, e.g. how to turn
    /// the notice off. '' = one-line toast.</summary>
    Hint: string;
    Kind: TToastKind;
    /// <summary>Shown even with "Show notifications" off: for notices the
    /// user must not miss, such as the program going online.</summary>
    Always: Boolean;
    /// <summary>How long the toast stays up; 0 = the default for Kind.</summary>
    DurationMs: Integer;
    /// <summary>Optional id for NoticeDismiss: a notice about something in
    /// progress can be taken down as soon as it is over. '' = none.</summary>
    Tag: string;
    class function Make(const ATemplate: string; const AArg: string = '';
      AKind: TToastKind = tkInfo): TNoticeRequest; static;
  end;

  TNoticeHandler = reference to procedure(const ARequest: TNoticeRequest);
  TNoticeDismissHandler = reference to procedure(const ATag: string);

/// <summary>ATemplate may hold one %s for AArg (a path or a name): the
/// toast shortens AArg to fit the window, so pass it separately rather than
/// Format()ing it in.</summary>
procedure Notice(const ATemplate: string; const AArg: string = '';
  AKind: TToastKind = tkInfo);
/// <summary>Full form: a hint line, Always, a duration.</summary>
procedure NoticeRequest(const ARequest: TNoticeRequest);
/// <summary>Hides the notice shown with this Tag if it is still the one on
/// screen; a notice that has replaced it stays.</summary>
procedure NoticeDismiss(const ATag: string);
procedure SetNoticeHandler(const AHandler: TNoticeHandler;
  const ADismiss: TNoticeDismissHandler = nil);

implementation

var
  GHandler: TNoticeHandler;
  GDismiss: TNoticeDismissHandler;

class function TNoticeRequest.Make(const ATemplate, AArg: string;
  AKind: TToastKind): TNoticeRequest;
begin
  Result := Default(TNoticeRequest);
  Result.Template := ATemplate;
  Result.Arg := AArg;
  Result.Kind := AKind;
end;

procedure NoticeRequest(const ARequest: TNoticeRequest);
begin
  if Assigned(GHandler) then
    GHandler(ARequest);
end;

procedure Notice(const ATemplate, AArg: string; AKind: TToastKind);
begin
  NoticeRequest(TNoticeRequest.Make(ATemplate, AArg, AKind));
end;

procedure NoticeDismiss(const ATag: string);
begin
  if (ATag <> '') and Assigned(GDismiss) then
    GDismiss(ATag);
end;

procedure SetNoticeHandler(const AHandler: TNoticeHandler;
  const ADismiss: TNoticeDismissHandler);
begin
  GHandler := AHandler;
  GDismiss := ADismiss;
end;

initialization

finalization
  GHandler := nil;
  GDismiss := nil;

end.
