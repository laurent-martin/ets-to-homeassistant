@echo off
where ruby >nul 2>nul
if %errorlevel% neq 0 (
    echo Ruby is not installed or not in the PATH.
    exit /b 1
)
set script_path=%~dp0
set script_name=%~n0
ruby "%script_path%%script_name%" "%*"
