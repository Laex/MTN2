unit uElevation;

{ The rights this process runs with. A program started "as administrator" shows
  that in its window title and needs no helper for file operations; one that
  runs as an ordinary user starts the administrator helper (uElevatedVfs) when
  an operation needs it. }

interface

type
  TProcessRights = (prUser, prAdministrator);

/// <summary>True when the process token is elevated (UAC would add nothing).</summary>
function IsProcessElevated: Boolean;
function CurrentProcessRights: TProcessRights;
/// <summary>Short label for the window title: "Administrator", or '' for a user.</summary>
function ProcessRightsLabel(ARights: TProcessRights): string;

implementation

uses
  Winapi.Windows;

function IsProcessElevated: Boolean;
var
  Token: THandle;
  Elev: TOKEN_ELEVATION;
  Size: DWORD;
begin
  Result := False;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    Exit;
  try
    if GetTokenInformation(Token, TokenElevation, @Elev, SizeOf(Elev), Size) then
      Result := Elev.TokenIsElevated <> 0;
  finally
    CloseHandle(Token);
  end;
end;

function CurrentProcessRights: TProcessRights;
begin
  if IsProcessElevated then
    Result := prAdministrator
  else
    Result := prUser;
end;

function ProcessRightsLabel(ARights: TProcessRights): string;
begin
  if ARights = prAdministrator then
    Result := 'Administrator'
  else
    Result := '';
end;

end.
