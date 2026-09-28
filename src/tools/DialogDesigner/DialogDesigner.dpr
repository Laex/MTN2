program DialogDesigner;

// RAD Studio 13 (Delphi 13, CompilerVersion 37) or later. Older compilers
// fail deep inside the units with confusing errors, so stop here with a
// clear message instead.
{$IF CompilerVersion < 37.0}
  {$MESSAGE FATAL 'MTN2 requires RAD Studio 13 (Delphi 13, Studio\37.0) or later. See docs/BUILDING.md.'}
{$IFEND}

uses
  System.StartUpCopy,
  FMX.Forms,
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uInputLine in '..\..\Core\uInputLine.pas',
  uFunctionBar in '..\..\Core\uFunctionBar.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uDialogJson in '..\..\Core\uDialogJson.pas',
  uDialogResources in '..\..\Core\uDialogResources.pas',
  uDialogHost in '..\..\Core\uDialogHost.pas',
  uNDNTheme in '..\..\Themes\uNDNTheme.pas',
  uTerminalRenderer in '..\..\Core\uTerminalRenderer.pas',
  uDialogDesignerForm in 'uDialogDesignerForm.pas';

begin
  Application.Initialize;
  Application.Title := 'MTN2 Dialog Designer';
  DialogDesignerForm := TDialogDesignerForm.Create(Application);
  Application.MainForm := DialogDesignerForm;
  DialogDesignerForm.Show;
  Application.Run;
end.
