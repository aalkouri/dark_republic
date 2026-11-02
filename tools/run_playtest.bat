@echo off
rem ===========================================================================
rem  Dark Republic playtest runner (Windows). Runs the playtest bot headless on
rem  this PC, one Godot process per character, all at the same time, then
rem  prints every result and opens the summary.
rem
rem  Usage (double-click uses the defaults below):
rem    run_playtest.bat  CHARACTERS  RUNS  MAP
rem    run_playtest.bat  ghast,vicki,ice_wizard  3  swamp
rem
rem  Maps: swamp forest castle desert graveyard
rem  Results: playtest_results\<map>_<date-time>\  (results.txt, one .txt and
rem  .jsonl per character). Tell Claude the folder name when it's done.
rem ===========================================================================
setlocal EnableDelayedExpansion

set "CHARS=%~1"
set "RUNS=%~2"
set "MAP=%~3"
if "%CHARS%"=="" set "CHARS=fire_wizard,ice_wizard,ghast"
if "%RUNS%"=="" set "RUNS=3"
if "%MAP%"=="" set "MAP=swamp"

rem --- Godot: the console build if it's there (shows output), else the normal one
set "GDIR=%USERPROFILE%\Downloads\godot_v4.7.2-stable_win64.exe"
set "GODOT=%GDIR%\godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=%GDIR%\godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
	echo Could not find Godot in %GDIR%
	echo Edit GDIR at the top of this file to point at your Godot folder.
	pause
	exit /b 1
)

rem --- the project is the folder above this file
pushd "%~dp0.."
set "PROJ=%CD%"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "TS=%%i"
set "OUT=%PROJ%\playtest_results\%MAP%_%TS%"
mkdir "%OUT%" 2>nul

echo.
echo  Dark Republic playtest
echo  Characters: %CHARS%
echo  Runs each : %RUNS%
echo  Map       : %MAP%
echo  Results   : %OUT%
echo.

rem --- one background process per character
set /a N=0
for %%c in (%CHARS:,= %) do (
	set /a N+=1
	echo  starting %%c ...
	start "playtest %%c" /min cmd /c ""%GODOT%" --headless --fixed-fps 60 --path "%PROJ%" res://tools/playtest.tscn -- --chars=%%c --runs=%RUNS% --map=%MAP% --out="%OUT%\%%c.txt" > "%OUT%\%%c.log" 2>&1 & echo done> "%OUT%\%%c.done""
)

rem --- wait for all of them
echo.
echo  Running %N% characters in the background. You can keep using the PC.
:wait
set /a D=0
for %%f in ("%OUT%\*.done") do set /a D+=1
if !D! LSS %N% (
	timeout /t 15 /nobreak >nul
	echo  ... !D! of %N% finished
	goto wait
)

rem --- gather the results
(
	echo Dark Republic playtest  -  %MAP%  -  %RUNS% runs each  -  %TS%
	echo.
	for %%c in (%CHARS:,= %) do (
		if exist "%OUT%\%%c.txt" (type "%OUT%\%%c.txt") else (echo %%c: no results - see %%c.log)
	)
) > "%OUT%\results.txt"
del "%OUT%\*.done" 2>nul

echo.
type "%OUT%\results.txt"
echo.
echo  All done. Results are in:
echo  %OUT%
start "" notepad "%OUT%\results.txt"
popd
pause
