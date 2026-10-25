unit uTuiMain;

{ Entry point of the text-terminal host: opens the terminal, runs the event
  loop (input, timers, background results, drawing) and puts the terminal back
  when it ends. }

interface

/// <summary>Runs the program; the result is the process exit code.</summary>
function RunTui: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  uTerminalTypes, uTermInput, uAnsiFrame, uAnsiTerm, uAnsiClipboard, uHostShell,
  uCoreTimer, uPlatformInfo, uUpdater, uConfigLocation, uResourceAccess, uSelfCheck,
  uPlatformUpdate, uThemeDrawing, uStrings, uDisplaySettings;

const
  cEscapeWaitMs = 30;
  cIdleWaitMs = 20;
  // A frame is drawn at most this often, so a burst of output from the shell
  // does not cost a screen per chunk.
  cMinFrameMs = 12;

type
  TTuiOptions = record
    ShowVersion: Boolean;
    ShowHelp: Boolean;
    Dump: Boolean;
    DumpCols: Integer;
    DumpRows: Integer;
    Mouse: Boolean;
    Colors: string;
    Path: string;
  end;

function ParseOptions: TTuiOptions;
var
  I: Integer;
  Arg: string;
begin
  Result := Default(TTuiOptions);
  Result.Mouse := True;
  Result.DumpCols := 100;
  Result.DumpRows := 30;
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '--version') or (Arg = '-v') then
      Result.ShowVersion := True
    else if (Arg = '--help') or (Arg = '-h') then
      Result.ShowHelp := True
    else if Arg = '--no-mouse' then
      Result.Mouse := False
    else if Arg.StartsWith('--colors=') then
      Result.Colors := LowerCase(Copy(Arg, Length('--colors=') + 1, MaxInt))
    else if Arg = '--dump' then
    begin
      Result.Dump := True;
      if (I + 2 <= ParamCount) and (StrToIntDef(ParamStr(I + 1), 0) > 0) and
         (StrToIntDef(ParamStr(I + 2), 0) > 0) then
      begin
        Result.DumpCols := StrToInt(ParamStr(I + 1));
        Result.DumpRows := StrToInt(ParamStr(I + 2));
        Inc(I, 2);
      end;
    end
    else if (Arg <> '') and (Arg[1] <> '-') and (Result.Path = '') then
      Result.Path := Arg;
    Inc(I);
  end;
end;

procedure WriteLine(const AText: string);
begin
  PlatformWriteStdOut(AText + #10);
end;

procedure ShowUsage;
begin
  WriteLine('Usage: mtn2-tui [options] [folder]');
  WriteLine('  --no-mouse     do not ask the terminal for mouse events');
  WriteLine('  --colors=MODE  truecolor, 256 or 16 (default: from COLORTERM and TERM)');
  WriteLine('  --dump [W H]   draw one screen as plain text to standard output and exit');
  WriteLine('  --self-check   check the files next to the program and exit');
  WriteLine('  --version      show the version');
  WriteLine('  --help         show this help');
end;

// Draws one screen as plain text; for checks without a terminal.
function PluginsDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(PlatformExePath), 'plugins');
end;

function RunDump(const AOptions: TTuiOptions): Integer;
var
  Shell: THostShell;
  Grid: TTerminalGrid;
  Y, X: Integer;
  Line: string;
begin
  Shell := THostShell.Create(AOptions.DumpCols, AOptions.DumpRows);
  Shell.AttachPlugins(PluginsDir);
  try
    if AOptions.Path <> '' then
      Shell.DualPanel.OpenPathAsNewTab(AOptions.Path);
    // Let the panels finish reading their folders.
    for Y := 1 to 40 do
    begin
      CheckSynchronize(25);
      ProcessCoreTimers;
    end;
    Grid := Shell.Compose;
    for Y := 0 to High(Grid) do
    begin
      Line := '';
      for X := 0 to High(Grid[Y]) do
        if ccaWideTail in Grid[Y][X].Attributes then
          Continue
        else if Grid[Y][X].CharValue < ' ' then
          Line := Line + ' '
        else
          Line := Line + Grid[Y][X].CharValue;
      WriteLine(TrimRight(Line));
    end;
    Result := 0;
  finally
    Shell.DetachPlugins;
    Shell.Free;
  end;
end;

procedure LogError(const AMessage: string);
begin
  try
    TFile.AppendAllText(TPath.Combine(GetConfigDirectory, 'tui-error.log'),
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + AMessage + sLineBreak,
      TEncoding.UTF8);
  except
  end;
end;

function ChooseColorMode(const AOptions: TTuiOptions): TAnsiColorMode;
begin
  if AOptions.Colors = 'truecolor' then
    Exit(acmTrueColor);
  if AOptions.Colors = '256' then
    Exit(acm256);
  if AOptions.Colors = '16' then
    Exit(acm16);
  // Windows Terminal does not announce 24-bit color but draws it.
  if GetEnvironmentVariable('WT_SESSION') <> '' then
    Exit(acmTrueColor);
  Result := DetectColorMode(GetEnvironmentVariable('COLORTERM'),
    GetEnvironmentVariable('TERM'));
end;

function RunTerminal(const AOptions: TTuiOptions): Integer;
var
  Term: TAnsiTerm;
  Shell: THostShell;
  Parser: TTermInputParser;
  Events: TList<TTermEvent>;
  Writer: TAnsiFrameWriter;
  Buf: TBytes;
  N, Cols, Rows, NewCols, NewRows, WaitMs, NextTimer: Integer;
  E: TTermEvent;
  LastInput, LastFrame, Now64: UInt64;
  Bytes: TBytes;
  Title, ShownTitle: string;
begin
  Result := 0;
  GFontSettingsApply := False;
  Term := TAnsiTerm.Create;
  Parser := TTermInputParser.Create;
  Events := TList<TTermEvent>.Create;
  Writer := TAnsiFrameWriter.Create;
  Writer.ColorMode := ChooseColorMode(AOptions);
  Shell := nil;
  SetLength(Buf, 4096);
  try
    InstallTerminationHandlers;
    Term.QuerySize(Cols, Rows);
    Term.EnterRaw;
    Term.WriteText(AnsiEnterSequence(AOptions.Mouse) + #27'[22;2t'#27']2;MTN2'#7);
    try
      InstallAnsiClipboard(
        procedure(const AText: string)
        begin
          Term.WriteText(AText);
        end);
      Shell := THostShell.Create(Cols, Rows);
      Shell.AttachPlugins(PluginsDir);
      Shell.AttachUpdater;
      if AOptions.Path <> '' then
        Shell.DualPanel.OpenPathAsNewTab(AOptions.Path);
      LastInput := PlatformTickCount64;
      LastFrame := 0;
      ShownTitle := '';
      while not Shell.Quit and not TerminationRequested do
      begin
        CheckSynchronize(0);
        ProcessCoreTimers;
        if Term.QuerySize(NewCols, NewRows) and ((NewCols <> Cols) or (NewRows <> Rows)) then
        begin
          Cols := NewCols;
          Rows := NewRows;
          Shell.Resize(Cols, Rows);
          Writer.Invalidate;
          Term.WriteText(#27'[2J');
        end;
        Now64 := PlatformTickCount64;
        if Shell.Dirty then
        begin
          WaitMs := 0;
          if Now64 - LastFrame < cMinFrameMs then
            WaitMs := Integer(cMinFrameMs - (Now64 - LastFrame));
        end
        else
        begin
          WaitMs := cIdleWaitMs;
          NextTimer := CoreTimersNextDueMs;
          if (NextTimer >= 0) and (NextTimer < WaitMs) then
            WaitMs := NextTimer;
        end;
        N := Term.Read(Buf, WaitMs);
        if N > 0 then
        begin
          LastInput := PlatformTickCount64;
          Parser.Feed(Buf, N, Events);
        end
        else if Parser.HasPending and (PlatformTickCount64 - LastInput >= cEscapeWaitMs) then
          Parser.FlushPending(Events);
        for E in Events do
          try
            if E.Kind = tekCapabilities then
            begin
              // Without the kitty protocol ask xterm-like terminals for
              // distinguishable modified keys.
              if not E.KittyKeyboard then
                Term.WriteText(#27'[>4;2m');
            end
            else
              Shell.HandleEvent(E);
          except
            on Ex: Exception do
              LogError(Ex.ClassName + ': ' + Ex.Message);
          end;
        Events.Clear;
        if Shell.Dirty and (PlatformTickCount64 - LastFrame >= cMinFrameMs) then
        begin
          LastFrame := PlatformTickCount64;
          Bytes := Writer.Render(Shell.Compose);
          if Length(Bytes) > 0 then
            Term.Write(Bytes);
          Title := Shell.Title;
          if Title <> ShownTitle then
          begin
            ShownTitle := Title;
            Term.WriteText(#27']2;' + Title + #7);
          end;
        end;
      end;
      Shell.PersistSession;
    finally
      // The terminal is put back even when tearing the shell down raises.
      try
        if Assigned(Shell) then
        begin
          Shell.DetachUpdater;
          Shell.DetachPlugins;
        end;
        Shell.Free;
      finally
        Term.WriteText(#27'[>4;0m' + AnsiLeaveSequence + #27'[23;2t');
        Term.LeaveRaw;
      end;
    end;
  finally
    Writer.Free;
    Events.Free;
    Parser.Free;
    Term.Free;
  end;
  // An update that asked for a restart starts here, on the restored terminal.
  PlatformExecPendingStart;
end;

function RunTui: Integer;
var
  Opts: TTuiOptions;
begin
  GGraphicsEngineLabel :=
    function: string
    begin
      Result := T('ui.about.engine.tui', 'Graphics Engine: text terminal');
    end;
  Opts := ParseOptions;
  if Opts.ShowHelp then
  begin
    ShowUsage;
    Exit(0);
  end;
  if Opts.ShowVersion then
  begin
    WriteLine('mtn2-tui ' + AppVersionString);
    Exit(0);
  end;
  if SelfCheckRequested then
    Exit(RunSelfCheckToStdOut);
  if Opts.Dump then
    Exit(RunDump(Opts));
  if not TAnsiTerm.IsTerminal then
  begin
    WriteLine('mtn2-tui needs a terminal on standard input and output.');
    Exit(1);
  end;
  Result := RunTerminal(Opts);
end;

end.
