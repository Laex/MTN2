unit uStartupTargets;

{ Paths named on the command line: every host (Windows, text terminal, SDL
  window) turns its arguments into a list of targets, opens them in the
  running program and hands the same list to a window that is already open.

    mtn2 <path> [<path> ...]    each folder opens in a new panel tab; a file
                                opens its folder with the cursor on it
    mtn2 --view <file>          the file opens in the viewer
    mtn2 --edit <file>          the file opens in the editor (-e, --edit=<file>)

  Relative paths are made absolute against the current folder when the
  argument is read, because a window that is already open has another one. }

interface

type
  TStartupMode = (smOpen, smView, smEdit);

  TStartupTarget = record
    Path: string;
    Mode: TStartupMode;
  end;

  TStartupTargets = TArray<TStartupTarget>;

  /// <summary>Collects targets argument by argument. A host feeds it every
  /// argument its own switches did not take.</summary>
  TStartupTargetParser = record
  private
    FPendingMode: TStartupMode;
    FAwaitingFile: Boolean;
    procedure Add(const APath: string; AMode: TStartupMode);
  public
    Targets: TStartupTargets;
    /// <summary>True when AArg belonged to a target (a path, a mode switch or
    /// the file after one); False for any other switch, which the host handles
    /// or ignores.</summary>
    function Take(const AArg: string): Boolean;
  end;

/// <summary>Joins the targets into one line for a window that is already open
/// (a Unix socket line or a WM_COPYDATA text); '' for no targets.</summary>
function EncodeStartupTargets(const ATargets: TStartupTargets): string;
/// <summary>Inverse of EncodeStartupTargets; a piece it does not understand
/// is dropped.</summary>
function DecodeStartupTargets(const AText: string): TStartupTargets;

implementation

uses
  System.SysUtils;

const
  // Unit separator: never part of a path in practice, and not a line break.
  cSeparator = #31;
  cModeChars: array[TStartupMode] of Char = ('O', 'V', 'E');

// --view / --edit / -e, with the file after "=" when it is given there.
function ModeOfSwitch(const AArg: string; out AMode: TStartupMode;
  out AValue: string): Boolean;
var
  P: Integer;
  Name: string;
begin
  P := Pos('=', AArg);
  if P > 0 then
  begin
    Name := Copy(AArg, 1, P - 1);
    AValue := Copy(AArg, P + 1, MaxInt);
  end
  else
  begin
    Name := AArg;
    AValue := '';
  end;
  Result := True;
  if SameText(Name, '--view') then
    AMode := smView
  else if SameText(Name, '--edit') or (Name = '-e') then
    AMode := smEdit
  else
    Result := False;
end;

procedure TStartupTargetParser.Add(const APath: string; AMode: TStartupMode);
var
  Target: TStartupTarget;
begin
  Target.Path := ExpandFileName(APath);
  Target.Mode := AMode;
  Targets := Targets + [Target];
end;

function TStartupTargetParser.Take(const AArg: string): Boolean;
var
  Mode: TStartupMode;
  Value: string;
begin
  if AArg = '' then
    Exit(False);
  if FAwaitingFile then
  begin
    FAwaitingFile := False;
    Add(AArg, FPendingMode);
    Exit(True);
  end;
  if AArg[1] = '-' then
  begin
    if not ModeOfSwitch(AArg, Mode, Value) then
      Exit(False);
    if Value = '' then
    begin
      FPendingMode := Mode;
      FAwaitingFile := True;
    end
    else
      Add(Value, Mode);
    Exit(True);
  end;
  Add(AArg, smOpen);
  Result := True;
end;

function EncodeStartupTargets(const ATargets: TStartupTargets): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ATargets) do
  begin
    if I > 0 then
      Result := Result + cSeparator;
    Result := Result + cModeChars[ATargets[I].Mode] + ATargets[I].Path;
  end;
end;

function DecodeStartupTargets(const AText: string): TStartupTargets;
var
  Piece: string;
  Mode: TStartupMode;
  Target: TStartupTarget;
  Found: Boolean;
begin
  Result := nil;
  if AText = '' then
    Exit;
  for Piece in AText.Split([cSeparator]) do
  begin
    if Length(Piece) < 2 then
      Continue;
    Found := False;
    for Mode := Low(TStartupMode) to High(TStartupMode) do
      if Piece[1] = cModeChars[Mode] then
      begin
        Target.Mode := Mode;
        Found := True;
        Break;
      end;
    if not Found then
      Continue;
    Target.Path := Copy(Piece, 2, MaxInt);
    Result := Result + [Target];
  end;
end;

end.
