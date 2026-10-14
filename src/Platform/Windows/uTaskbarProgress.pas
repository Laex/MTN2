unit uTaskbarProgress;

{ Progress on the application's taskbar button (ITaskbarList3). Every call is
  best effort: without a taskbar button, or when COM is unavailable, nothing
  is shown and nothing fails. }

interface

uses
  Winapi.Windows, uDualPanelJobRules;

type
  TTaskbarProgress = class
  private
    FList: IInterface;
    FInitTried: Boolean;
    FState: TJobTaskbarState;
    FPercent: Integer;
    FHwnd: HWND;
    function List: IInterface;
  public
    /// <summary>Shows AState (and APercent for the normal state) on AHwnd's
    /// button; repeating the shown values costs nothing.</summary>
    procedure Update(AHwnd: HWND; AState: TJobTaskbarState; APercent: Integer);
  end;

implementation

uses
  System.SysUtils, Winapi.ShlObj, Winapi.ActiveX;

function TTaskbarProgress.List: IInterface;
var
  Taskbar: ITaskbarList3;
begin
  if not FInitTried then
  begin
    FInitTried := True;
    if Succeeded(CoCreateInstance(CLSID_TaskbarList, nil, CLSCTX_INPROC_SERVER,
      ITaskbarList3, Taskbar)) then
    begin
      if Succeeded(Taskbar.HrInit) then
        FList := Taskbar;
    end;
  end;
  Result := FList;
end;

procedure TTaskbarProgress.Update(AHwnd: HWND; AState: TJobTaskbarState;
  APercent: Integer);
var
  Taskbar: ITaskbarList3;
begin
  if AHwnd = 0 then
    Exit;
  if not (AState in [jtsNormal, jtsPaused, jtsError]) then
    APercent := 0;
  if (AHwnd = FHwnd) and (AState = FState) and (APercent = FPercent) then
    Exit;
  if (AState = jtsNone) and (FState = jtsNone) then
    Exit;
  if not Supports(List, ITaskbarList3, Taskbar) then
    Exit;
  case AState of
    jtsNone: Taskbar.SetProgressState(AHwnd, TBPF_NOPROGRESS);
    jtsIndeterminate: Taskbar.SetProgressState(AHwnd, TBPF_INDETERMINATE);
    jtsNormal: Taskbar.SetProgressState(AHwnd, TBPF_NORMAL);
    jtsPaused: Taskbar.SetProgressState(AHwnd, TBPF_PAUSED);
    jtsError: Taskbar.SetProgressState(AHwnd, TBPF_ERROR);
  end;
  if AState in [jtsNormal, jtsPaused, jtsError] then
    Taskbar.SetProgressValue(AHwnd, APercent, 100);
  FHwnd := AHwnd;
  FState := AState;
  FPercent := APercent;
end;

end.
