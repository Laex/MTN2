@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"
set FAILED=0
for %%T in (TestConsoleBuffer TestConPtyEncoding TestPtyLifecycle TestLineBufferedBackspace TestCdDirQuote TestPtySession TestFindEncoding TestPsPersistent TestPsLineBuffered TestCmdBackspaceFlow TestANSIParser TestShellProfiles) do (
  echo === %%T ===
  dcc32 -B -Q -U"..\Core" %%T.dpr
  if errorlevel 1 set FAILED=1 & goto done
  %%T.exe
  if errorlevel 1 set FAILED=1 & goto done
)
:done
if %FAILED%==1 exit /b 1
echo ALL CONSOLE TESTS PASSED
exit /b 0
