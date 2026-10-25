unit uSdlMain;

{ Entry point of the graphical SDL host: reads the command line, then opens
  the window (uSdlHost). }

interface

/// <summary>Runs the program; the result is the process exit code.</summary>
function RunSdl: Integer;

implementation

uses
  System.SysUtils, uPlatformInfo, uPlatformUpdate, uUpdater, uSelfCheck, uThemeDrawing, uStrings, uPlatformFonts, uSdlApi, uFreeTypeApi, uSdlHost, uInstanceSocket, uStartupTargets, uUpdateCli, uDesktopEntry;

type
  TSdlOptions = record
    ShowVersion: Boolean;
    ShowHelp: Boolean;
    Host: TSdlHostOptions;
  end;

function ParseOptions: TSdlOptions;
var
  I: Integer;
  Arg: string;
  Parser: TStartupTargetParser;

  function ValueOf(const APrefix: string): string;
  begin
    Result := Copy(Arg, Length(APrefix) + 1, MaxInt);
  end;

begin
  Result := Default(TSdlOptions);
  Parser := Default(TStartupTargetParser);
  for I := 1 to ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '--version') or (Arg = '-v') then
      Result.ShowVersion := True
    else if (Arg = '--help') or (Arg = '-h') then
      Result.ShowHelp := True
    else if Arg.StartsWith('--font=') then
      Result.Host.FontName := ValueOf('--font=')
    else if Arg.StartsWith('--size=') then
      Result.Host.FontSize := StrToIntDef(ValueOf('--size='), 0)
    else if Arg.StartsWith('--cols=') then
      Result.Host.Cols := StrToIntDef(ValueOf('--cols='), 0)
    else if Arg.StartsWith('--rows=') then
      Result.Host.Rows := StrToIntDef(ValueOf('--rows='), 0)
    else if Arg = '--new-window' then
      Result.Host.NewWindow := True
    else if Arg.StartsWith('--snapshot=') then
      Result.Host.SnapshotFile := ValueOf('--snapshot=')
    else
      Parser.Take(Arg);
  end;
  Result.Host.Targets := Parser.Targets;
end;

procedure WriteLine(const AText: string);
begin
  PlatformWriteStdOut(AText + #10);
end;

procedure ShowUsage;
begin
  WriteLine('Usage: mtn2-sdl [options] [path ...]');
  WriteLine('  path              a folder opens in a new tab; a file opens its folder with the cursor on it');
  WriteLine('  --view FILE       open the file in the viewer');
  WriteLine('  --edit FILE       open the file in the editor (-e FILE)');
  WriteLine('  --update [CH]     download and install the latest version, CH is stable or nightly (kept for next time)');
  WriteLine('  --font=NAME       font family (default: the monospace family of the system)');
  WriteLine('  --size=PX         glyph height in pixels (default 16)');
  WriteLine('  --cols=N --rows=N initial window size in cells');
  WriteLine('  --install-desktop    write the menu entry and icon to ~/.local/share (--uninstall-desktop removes them)');
  WriteLine('  --new-window      do not hand the folder over to a window that is already open');
  WriteLine('  --snapshot=FILE   draw one screen to a PNG file and exit, without a window');
  WriteLine('  --self-check      check the files next to the program and exit');
  WriteLine('  --version         show the version');
  WriteLine('  --help            show this help');
  WriteLine('Ctrl + wheel, Ctrl + and Ctrl - change the size, Ctrl 0 resets it.');
end;

// The checks of the shared files plus the libraries and the font the window needs.
function RunSdlSelfCheck: Integer;
var
  Err, FontFile: string;
begin
  Result := RunSelfCheckToStdOut;
  if LoadSdl(Err) then
    WriteLine('OK   libSDL2')
  else
  begin
    WriteLine('FAIL ' + Err);
    Result := 1;
  end;
  if SdlLoaded then
    if SdlImageLoaded then
      WriteLine('OK   libSDL2_image')
    else
      WriteLine('WARN libSDL2_image not found: pictures are shown only for BMP files');
  if LoadFreeType(Err) then
    WriteLine('OK   libfreetype')
  else
  begin
    WriteLine('FAIL ' + Err);
    Result := 1;
  end;
  FontFile := PlatformFontFile(PlatformDefaultMonoFont, False, False);
  if FontFile <> '' then
    WriteLine('OK   font ' + FontFile)
  else
  begin
    WriteLine('FAIL no font file for ' + PlatformDefaultMonoFont);
    Result := 1;
  end;
  if Result = 0 then
    WriteLine('mtn2-sdl self-check passed');
end;

function RunSdl: Integer;
var
  Opts: TSdlOptions;
  Channel: string;
begin
  // Glyph edges are smooth, as under Skia: a stronger dim and a lighter shadow strip.
  GModalDimPercent := 88;
  GShadowCover := 168;
  GGraphicsEngineLabel :=
    function: string
    begin
      Result := T('ui.about.engine.sdl', 'Graphics Engine: SDL2 + FreeType');
    end;
  Opts := ParseOptions;
  if Opts.ShowHelp then
  begin
    ShowUsage;
    Exit(0);
  end;
  if Opts.ShowVersion then
  begin
    WriteLine('mtn2-sdl ' + AppVersionString);
    Exit(0);
  end;
  if SelfCheckRequested then
    Exit(RunSdlSelfCheck);
  if UpdateRequested(Channel) then
    Exit(RunUpdateCommand(Channel, WriteLine));
  if InstallDesktopRequested then
    Exit(RunDesktopCommand(dekSdl, True, WriteLine));
  if UninstallDesktopRequested then
    Exit(RunDesktopCommand(dekSdl, False, WriteLine));
  if Opts.Host.SnapshotFile <> '' then
    Exit(RunSdlSnapshot(Opts.Host));
  // A window that is already open takes the paths and comes to the front.
  if not Opts.Host.NewWindow then
    if InstanceTryHandOver('sdl', EncodeStartupTargets(Opts.Host.Targets)) then
      Exit(0);
  Result := RunSdlHost(Opts.Host);
  // An update that asked for a restart starts here.
  PlatformExecPendingStart;
end;

end.
