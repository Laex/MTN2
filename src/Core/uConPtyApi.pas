unit uConPtyApi;

{ Windows ConPTY (Pseudo Console) API bindings.
  Not present in Delphi's Winapi.Windows.pas (added to Windows 10 SDK in
  build 17763 / Oct 2018 Update, RTL headers have not caught up). Requires
  Windows 10 1809+ at runtime — every currently supported Windows version. }

interface

uses
  Winapi.Windows;

type
  HPCON = THandle;

  TStartupInfoExW = record
    StartupInfo: TStartupInfoW;
    lpAttributeList: PProcThreadAttributeList;
  end;
  PStartupInfoExW = ^TStartupInfoExW;

const
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = $00020016;

function CreatePseudoConsole(size: TCoord; hInput, hOutput: THandle;
  dwFlags: DWORD; out phPC: HPCON): HRESULT; stdcall;
function ResizePseudoConsole(hPC: HPCON; size: TCoord): HRESULT; stdcall;
procedure ClosePseudoConsole(hPC: HPCON); stdcall;

// Winapi.Windows declares lpReturnSize as a non-nilable `var NativeUInt`, but
// kernel32 rejects PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE with
// ERROR_INVALID_PARAMETER (87) unless lpReturnSize is a true NULL pointer
// (confirmed empirically) -- the real Win32 signature takes PSIZE_T, which is
// documented optional. Shadows Winapi.Windows.UpdateProcThreadAttribute for
// any unit that uses this one after Winapi.Windows.
function UpdateProcThreadAttribute(lpAttributeList: PProcThreadAttributeList;
  dwFlags: DWORD; Attribute: NativeUInt; lpValue: Pointer; cbSize: NativeUInt;
  lpPreviousValue: Pointer; lpReturnSize: PSIZE_T): ByteBool; stdcall;

implementation

function CreatePseudoConsole; external 'kernel32.dll' name 'CreatePseudoConsole';
function ResizePseudoConsole; external 'kernel32.dll' name 'ResizePseudoConsole';
procedure ClosePseudoConsole; external 'kernel32.dll' name 'ClosePseudoConsole';
function UpdateProcThreadAttribute; external 'kernel32.dll' name 'UpdateProcThreadAttribute';

end.
