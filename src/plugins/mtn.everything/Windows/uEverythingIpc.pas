unit uEverythingIpc;

{ A search through the window of the running Everything program (its IPC by WM_COPYDATA),
  so the Everything SDK library is not needed. The query is sent from a window created
  here; Everything answers with a WM_COPYDATA message to that window while the sending
  call is still waiting, on the same thread. }

interface

uses
  uEverythingFormat;

/// <summary>Runs the query; True with the first AMaxResults items, or False with the reason in AError
/// (Everything is not running, or does not answer).</summary>
function EverythingSearch(const AQuery: string; AMaxResults: Integer; out AItems: TEvItems;
  out AError: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils;

const
  cQueryMessage = 2;      // EVERYTHING_IPC_COPYDATAQUERYW
  cReplyMessage = 0;
  cClassName14 = 'EVERYTHING_TASKBAR_NOTIFICATION';
  cClassName15 = 'EVERYTHING_TASKBAR_NOTIFICATION_(1.5a)';
  cReplyClass = 'MTN2EverythingReply';

threadvar
  // The reply of the query being run on this thread.
  GReply: TEvItems;
  GGotReply: Boolean;

function ReplyProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  Data: PCopyDataStruct;
begin
  if AMsg = WM_COPYDATA then
  begin
    Data := PCopyDataStruct(ALParam);
    if (Data <> nil) and (Data.dwData = cReplyMessage) then
      GGotReply := ParseIpcList(Data.lpData, Data.cbData, GReply);
    Exit(1);
  end;
  Result := DefWindowProc(AWnd, AMsg, AWParam, ALParam);
end;

function FindEverything: HWND;
begin
  Result := FindWindow(cClassName14, nil);
  if Result = 0 then
    Result := FindWindow(cClassName15, nil);
end;

function ReplyWindow: HWND;
var
  WC: TWndClass;
begin
  if not GetClassInfo(HInstance, cReplyClass, WC) then
  begin
    WC := Default(TWndClass);
    WC.lpfnWndProc := @ReplyProc;
    WC.hInstance := HInstance;
    WC.lpszClassName := cReplyClass;
    RegisterClass(WC);
  end;
  Result := CreateWindowEx(0, cReplyClass, nil, 0, 0, 0, 0, 0, HWND_MESSAGE, 0, HInstance, nil);
end;

function EverythingSearch(const AQuery: string; AMaxResults: Integer; out AItems: TEvItems;
  out AError: string): Boolean;
var
  Target, Wnd: HWND;
  Query: TArray<Byte>;
  Data: TCopyDataStruct;
begin
  AItems := nil;
  AError := '';
  Result := False;
  Target := FindEverything;
  if Target = 0 then
  begin
    AError := 'Everything is not running';
    Exit;
  end;
  Wnd := ReplyWindow;
  if Wnd = 0 then
  begin
    AError := 'Cannot create the reply window';
    Exit;
  end;
  try
    GGotReply := False;
    GReply := nil;
    // The reply window handle goes in as 32 bits, as the IPC structure holds it.
    Query := BuildIpcQuery(Cardinal(Wnd), cReplyMessage, Cardinal(AMaxResults), AQuery);
    Data.dwData := cQueryMessage;
    Data.cbData := Length(Query);
    Data.lpData := @Query[0];
    if SendMessage(Target, WM_COPYDATA, WPARAM(Wnd), LPARAM(@Data)) = 0 then
    begin
      AError := 'Everything did not accept the query';
      Exit;
    end;
    if not GGotReply then
    begin
      AError := 'Everything gave no answer';
      Exit;
    end;
    AItems := GReply;
    Result := True;
  finally
    DestroyWindow(Wnd);
  end;
end;

end.
