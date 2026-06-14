@echo off
rem Ditulis oleh hook Claude Code; dibaca oleh clawd-pet.ps1 (fitur "Claude Watch").
rem Arg 1 = token aktivitas (think|bash|edit|read|web|task|notify|done).
>"%TEMP%\clawd-status.txt" echo %~1
