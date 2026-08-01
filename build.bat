@echo off
rem ---------------------------------------------------------------------------
rem  Build MSSQLXDemo for Win32 and Win64.
rem
rem  Usage:  build.bat          - build both platforms
rem          build.bat 32       - Win32 only
rem          build.bat 64       - Win64 only
rem
rem  rsvars.bat puts the Studio 37.0 bin directory on PATH. dcc32/dcc64 then
rem  pick up bin\dcc32.cfg / dcc64.cfg, which already carry the -u switch for
rem  lib\win32\release and lib\win64\release -- covers every stock FireDAC
rem  unit. It does NOT cover this repo's own src\ folder, which is why -U
rem  below adds it explicitly: FireDAC.Phys.MSSQLXDef is referenced only
rem  transitively (from inside FireDAC.Phys.MSSQLX.pas, not from the .dpr
rem  itself), so it has no 'in' clause anywhere and can only be found via
rem  search path. Confirmed the hard way -- building with that path left out
rem  fails with F2613 Unit 'FireDAC.Phys.MSSQLXDef' not found, even though
rem  FireDAC.Phys.MSSQLX itself resolves fine via its own 'in' clause.
rem
rem  The project lives in demo\Console, not here -- pushd into it so its
rem  relative bin\<platform> / dcu\<platform> output lands in the same place
rem  an IDE or msbuild build of MSSQLXDemo.dproj would put it, rather than
rem  silently diverging into two different output trees for the same source.
rem
rem  Separate DCU output directories per platform: mixing Win32 and Win64 DCUs
rem  in one folder produces confusing "unit was compiled with a different
rem  version" errors.
rem ---------------------------------------------------------------------------
setlocal

set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat
rem %RSVARS% contains "(x86)". Inside a parenthesised if-block cmd expands the
rem variable before parsing, so a bare  echo %RSVARS%  lets that ')' close the
rem block early -- "\Embarcadero\...\rsvars.bat was unexpected at this time".
rem Quoting the expansion is what keeps the block intact.
if not exist "%RSVARS%" (
  echo ERROR: rsvars.bat not found at:
  echo   "%RSVARS%"
  echo Edit build.bat if RAD Studio is installed elsewhere.
  exit /b 1
)
call "%RSVARS%"

rem -B build all units    -Q quiet    -W warnings on    -H hints on
rem -E  exe output dir    -N0 dcu output dir    -U extra unit search path
set DCCOPTS=-B -Q -W -H
set UNITPATH=..\..\src

set DO32=1
set DO64=1
if "%~1"=="32" set DO64=0
if "%~1"=="64" set DO32=0

pushd demo\Console

if "%DO32%"=="1" (
  echo.
  echo ===== Win32 =====
  if not exist "bin\Win32" mkdir "bin\Win32"
  if not exist "dcu\Win32" mkdir "dcu\Win32"
  dcc32 %DCCOPTS% -E"bin\Win32" -N0"dcu\Win32" -U"%UNITPATH%" MSSQLXDemo.dpr
  if errorlevel 1 goto :failed
)

if "%DO64%"=="1" (
  echo.
  echo ===== Win64 =====
  if not exist "bin\Win64" mkdir "bin\Win64"
  if not exist "dcu\Win64" mkdir "dcu\Win64"
  dcc64 %DCCOPTS% -E"bin\Win64" -N0"dcu\Win64" -U"%UNITPATH%" MSSQLXDemo.dpr
  if errorlevel 1 goto :failed
)

popd

echo.
echo Build succeeded.
echo.
echo Run the smoke test with, for example:
echo   demo\Console\bin\Win32\MSSQLXDemo.exe .\SQLEXPRESS master
echo   demo\Console\bin\Win32\MSSQLXDemo.exe tcp:sql01,1433 Sales appuser s3cret
echo.
echo Note: ODBC driver bitness must match the exe. A Win64 build needs the
echo 64-bit "ODBC Driver 18 for SQL Server" installed.
exit /b 0

:failed
popd
echo.
echo BUILD FAILED - see the dcc output above.
exit /b 1
