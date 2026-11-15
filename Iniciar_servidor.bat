@echo off
cd /d "%~dp0"
set "TRIVIA_ROLE=servidor"
echo Iniciando servidor de Trivia...
call elixir.bat --sname servidor --cookie trivia_local -S mix run --no-halt
pause
