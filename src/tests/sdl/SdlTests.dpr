program SdlTests;

{ DUnitX runner for the SDL host tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  uFakeGlyphs in 'uFakeGlyphs.pas',
  TestBoxGlyphs in 'TestBoxGlyphs.pas',
  TestFreeTypeGlyphs in 'TestFreeTypeGlyphs.pas',
  TestOverlayModel in 'TestOverlayModel.pas',
  TestPixelBlit in 'TestPixelBlit.pas',
  TestPixelGrid in 'TestPixelGrid.pas',
  TestSdlInput in 'TestSdlInput.pas',
  TestSdlShell in 'TestSdlShell.pas',
  TestSdlSurfaceMouse in 'TestSdlSurfaceMouse.pas',
  TestSdlWindow in 'TestSdlWindow.pas';

begin
  RunRegisteredTests;
end.
