@echo off
cd /d "%~dp0"
set "TRIVIA_ROLE=cliente"
echo Iniciando primer cliente de Trivia...
call elixir.bat --sname pedro --cookie trivia_local -S mix run -e "Trivia.Cliente.iniciar()"
pause
