unit uSystemClipboard;

{ Files on the desktop clipboard (POSIX build). A terminal program cannot own
  a clipboard selection of its own, so the standard helper of the session does
  it: wl-copy and wl-paste under Wayland, xclip under X11. The list goes out
  as x-special/gnome-copied-files (GTK file managers: Nautilus, Nemo, Thunar,
  Caja, PCManFM; it carries copy or cut) or, on KDE, as text/uri-list. A
  clipboard owner offers one type only, so what MTN2 puts there is a file
  list and nothing else. Without a helper or a display everything reports
  "not available" and the caller keeps its own copy. }

interface

/// <summary>True when a helper program and a display of the session exist.</summary>
function SystemFileClipAvailable: Boolean;

/// <summary>Offers the file URIs to other programs; False when no helper can.</summary>
function SystemFileClipSet(const AUris: TArray<string>; ACut: Boolean): Boolean;

/// <summary>Reads a file list another program (or this one) put on the
/// clipboard; False when the clipboard holds none.</summary>
function SystemFileClipGet(out AUris: TArray<string>; out ACut: Boolean): Boolean;

/// <summary>Empties the clipboard so that a cut list cannot be pasted twice.</summary>
procedure SystemFileClipClear;

/// <summary>Fingerprint of the file list on the clipboard; 0 when there is none
/// or the clipboard cannot be read.</summary>
function SystemFileClipSignature: Cardinal;

/// <summary>Hands text to the clipboard facilities a terminal escape cannot
/// reach: the buffer of the tmux session this program runs in (tmux then also
/// forwards it to the outer terminal) and the clipboard of a desktop session
/// (wl-copy or xclip). True when at least one of them took it.</summary>
function SystemTextClipSet(const AText: string): Boolean;

implementation

uses
  System.SysUtils, uPlatformProcess;

const
  cGnomeType = 'x-special/gnome-copied-files';
  cUriListType = 'text/uri-list';
  cTimeoutMs = 3000;

type
  TClipTool = (ctNone, ctWayland, ctX11);

function FindTool(const AName: string): Boolean;
begin
  Result := FileSearch(AName, GetEnvironmentVariable('PATH')) <> '';
end;

function CurrentTool: TClipTool;
begin
  if (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '') and FindTool('wl-copy') and
     FindTool('wl-paste') then
    Exit(ctWayland);
  if (GetEnvironmentVariable('DISPLAY') <> '') and FindTool('xclip') then
    Exit(ctX11);
  Result := ctNone;
end;

function UsesUriListType: Boolean;
begin
  Result := Pos('KDE', UpperCase(GetEnvironmentVariable('XDG_CURRENT_DESKTOP'))) > 0;
end;

function WriteClipboard(ATool: TClipTool; const AType, APayload: string): Boolean;
var
  Cmd, Output: string;
  Code: Cardinal;
begin
  // The helper keeps running in the background to serve the selection, so its
  // output goes to /dev/null: a pipe it inherits would never reach its end.
  if ATool = ctWayland then
    Cmd := 'exec wl-copy --type ''' + AType + ''' >/dev/null 2>&1'
  else
    Cmd := 'exec xclip -selection clipboard -t ''' + AType + ''' -i >/dev/null 2>&1';
  Result := (PlatformRunCaptured('sh', ['-c', Cmd], APayload, cTimeoutMs, nil, Output, Code) = srOk) and
    (Code = 0);
end;

function ReadClipboard(ATool: TClipTool; const AType: string; out APayload: string): Boolean;
var
  Code: Cardinal;
begin
  if ATool = ctWayland then
    Result := PlatformRunCaptured('wl-paste', ['--no-newline', '--type', AType], '',
      cTimeoutMs, nil, APayload, Code) = srOk
  else
    Result := PlatformRunCaptured('xclip', ['-selection', 'clipboard', '-o', '-t', AType], '',
      cTimeoutMs, nil, APayload, Code) = srOk;
  Result := Result and (Code = 0) and (APayload <> '');
end;

function TmuxClipSet(const AText: string): Boolean;
var
  Output: string;
  Code: Cardinal;
begin
  Result := (GetEnvironmentVariable('TMUX') <> '') and FindTool('tmux') and
    (PlatformRunCaptured('tmux', ['load-buffer', '-w', '-'], AText, cTimeoutMs, nil, Output,
       Code) = srOk) and (Code = 0);
end;

function DesktopTextClipSet(const AText: string): Boolean;
var
  Tool: TClipTool;
  Cmd, Output: string;
  Code: Cardinal;
begin
  Tool := CurrentTool;
  if Tool = ctNone then
    Exit(False);
  // Same background-helper arrangement as WriteClipboard.
  if Tool = ctWayland then
    Cmd := 'exec wl-copy >/dev/null 2>&1'
  else
    Cmd := 'exec xclip -selection clipboard -i >/dev/null 2>&1';
  Result := (PlatformRunCaptured('sh', ['-c', Cmd], AText, cTimeoutMs, nil, Output, Code) = srOk) and
    (Code = 0);
end;

function SystemTextClipSet(const AText: string): Boolean;
begin
  if AText = '' then
    Exit(False);
  // Both run: inside tmux on a desktop either one alone may miss the program
  // the user pastes into.
  Result := TmuxClipSet(AText);
  if DesktopTextClipSet(AText) then
    Result := True;
end;

function SystemFileClipAvailable: Boolean;
begin
  Result := CurrentTool <> ctNone;
end;

function SystemFileClipSet(const AUris: TArray<string>; ACut: Boolean): Boolean;
var
  Tool: TClipTool;
  Payload, Uri: string;
begin
  Result := False;
  Tool := CurrentTool;
  if (Tool = ctNone) or (Length(AUris) = 0) then
    Exit;
  if UsesUriListType then
  begin
    Payload := '';
    for Uri in AUris do
      Payload := Payload + Uri + #13#10;
    Result := WriteClipboard(Tool, cUriListType, Payload);
    Exit;
  end;
  if ACut then
    Payload := 'cut'
  else
    Payload := 'copy';
  for Uri in AUris do
    Payload := Payload + #10 + Uri;
  Result := WriteClipboard(Tool, cGnomeType, Payload);
end;

// Keeps the file:// lines of a list; comment lines of text/uri-list are dropped.
function ParseUris(const ALines: TArray<string>; AFirst: Integer): TArray<string>;
var
  I, N: Integer;
  Line: string;
begin
  SetLength(Result, Length(ALines));
  N := 0;
  for I := AFirst to High(ALines) do
  begin
    Line := Trim(ALines[I]);
    if Line.StartsWith('file:', True) then
    begin
      Result[N] := Line;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function SystemFileClipGet(out AUris: TArray<string>; out ACut: Boolean): Boolean;
var
  Tool: TClipTool;
  Payload: string;
  Lines: TArray<string>;
begin
  SetLength(AUris, 0);
  ACut := False;
  Result := False;
  Tool := CurrentTool;
  if Tool = ctNone then
    Exit;
  if ReadClipboard(Tool, cGnomeType, Payload) then
  begin
    Lines := Payload.Split([#10, #13], TStringSplitOptions.ExcludeEmpty);
    if (Length(Lines) > 0) and (SameText(Trim(Lines[0]), 'cut') or SameText(Trim(Lines[0]), 'copy')) then
    begin
      ACut := SameText(Trim(Lines[0]), 'cut');
      AUris := ParseUris(Lines, 1);
      Exit(Length(AUris) > 0);
    end;
  end;
  if ReadClipboard(Tool, cUriListType, Payload) then
  begin
    AUris := ParseUris(Payload.Split([#10, #13], TStringSplitOptions.ExcludeEmpty), 0);
    Result := Length(AUris) > 0;
  end;
end;

procedure SystemFileClipClear;
var
  Tool: TClipTool;
  Output: string;
  Code: Cardinal;
begin
  Tool := CurrentTool;
  if Tool = ctWayland then
    PlatformRunCaptured('wl-copy', ['--clear'], '', cTimeoutMs, nil, Output, Code)
  else if Tool = ctX11 then
    WriteClipboard(Tool, 'text/plain', ' ');
end;

function SystemFileClipSignature: Cardinal;
var
  Uris: TArray<string>;
  Cut: Boolean;
  Uri: string;
  C: Char;
  Hash: UInt64;
begin
  Result := 0;
  if not SystemFileClipGet(Uris, Cut) then
    Exit;
  Hash := 2166136261;
  for Uri in Uris do
    for C in Uri do
      Hash := ((Hash xor Ord(C)) * 16777619) and $FFFFFFFF;
  if Cut then
    Hash := Hash xor $5A5A5A5A;
  if Hash = 0 then
    Hash := 1;
  Result := Cardinal(Hash);
end;

end.
