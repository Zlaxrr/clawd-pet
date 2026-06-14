@echo off
rem Written by the Claude Code hook; read by clawd-pet.ps1 (the "Claude Watch" feature).
rem Arg 1 = activity token (think|bash|edit|read|web|task|notify|done).
>"%TEMP%\clawd-status.txt" echo %~1
