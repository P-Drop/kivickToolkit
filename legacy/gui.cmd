@echo off
:: Corrige el directorio de trabajo para que no se pierda al ejecutar como admin
cd /d "%~dp0"
title Kivick Toolbox
color 1

:MENU
cls
echo.
echo  ==========================================
echo                 Kivick Toolbox
echo  ==========================================
echo.
echo   [1] Change current user password
echo   [2] Check internal hard drive errors
echo   [3] Check Windows errors
echo   [4] Create a new user
echo   [5] Shut down the PC
echo.
echo   [0] Exit
echo.
set /p OPCION="  Option: "

if "%OPCION%"=="1" (
    call "scripts\change_password.bat"
    goto MENU
)

if "%OPCION%"=="2" (
    call "scripts\check_disk.bat"
    goto MENU
)

if "%OPCION%"=="3" (
    call "scripts\check_windows.bat"
    goto MENU
)

if "%OPCION%"=="4" (
    call "scripts\create_user.bat"
    goto MENU
)

if "%OPCION%"=="5" (
    call "scripts\shutdown_pc.bat"
    goto MENU
)

if "%OPCION%"=="0" goto EXIT

echo.
echo Invalid option.
pause
goto MENU

:EXIT
exit /b 0
