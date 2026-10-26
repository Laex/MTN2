unit uAnsiClipboard;

{ The clipboard of the terminal host: copying asks the terminal emulator to
  store the text (OSC 52), and the tmux buffer and the desktop clipboard get it
  too when the session has them; pasting uses what this program copied last, because
  most terminals do not let a program read the system clipboard (the user
  pastes with the terminal's own shortcut, which arrives as a bracketed
  paste). }

interface

uses
  System.SysUtils, uClipboardService;

type
  TAnsiWriteProc = reference to procedure(const AText: string);

/// <summary>Registers the OSC 52 clipboard; AWrite sends text to the terminal.</summary>
procedure InstallAnsiClipboard(const AWrite: TAnsiWriteProc);

implementation

uses
{$IFDEF POSIX}
  uSystemClipboard,
{$ENDIF}
  System.NetEncoding;

type
  TAnsiClipboardService = class(TInterfacedObject, IClipboardService)
  private
    FWrite: TAnsiWriteProc;
    FText: string;
  public
    constructor Create(const AWrite: TAnsiWriteProc);
    function TryGetText(out AText: string): Boolean;
    function TrySetText(const AText: string): Boolean;
  end;

constructor TAnsiClipboardService.Create(const AWrite: TAnsiWriteProc);
begin
  inherited Create;
  FWrite := AWrite;
end;

function TAnsiClipboardService.TryGetText(out AText: string): Boolean;
begin
  AText := FText;
  Result := True;
end;

function TAnsiClipboardService.TrySetText(const AText: string): Boolean;
var
  Encoded: string;
begin
  FText := AText;
  Result := True;
  if not Assigned(FWrite) then
    Exit;
  Encoded := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(AText));
  // The encoder may wrap long text into lines; OSC 52 wants one run.
  Encoded := StringReplace(StringReplace(Encoded, #13, '', [rfReplaceAll]), #10, '',
    [rfReplaceAll]);
  FWrite(#27']52;c;' + Encoded + #27'\');
  // Terminals that ignore OSC 52 (PuTTY by default, tmux without passthrough)
  // are reached through the multiplexer or the desktop session instead.
{$IFDEF POSIX}
  SystemTextClipSet(AText);
{$ENDIF}
end;

procedure InstallAnsiClipboard(const AWrite: TAnsiWriteProc);
begin
  SetClipboardService(TAnsiClipboardService.Create(AWrite));
end;

end.
