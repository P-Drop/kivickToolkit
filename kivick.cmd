@echo off
setlocal enabledelayedexpansion
:: =====================================================
::  Kivick Toolbox - Lanzador para Windows (CMD)
::
::  Equivalente Windows de kivick.sh
::
::  setlocal enabledelayedexpansion permite usar !VAR! para leer
::  variables modificadas dentro de bloques if/for, igual que los
::  subshells de Bash. Se usa SOLO aqui, no en las librerias.
:: =====================================================

:: Raiz del proyecto: directorio donde vive este archivo.
set "KIVICK_HOME=%~dp0"
:: Quitar la barra final que %~dp0 incluye
if "%KIVICK_HOME:~-1%"=="\" set "KIVICK_HOME=%KIVICK_HOME:~0,-1%"

:: Cargar nucleo comun
call "%KIVICK_HOME%\lib\win\common.cmd"
if errorlevel 1 (
    echo kivick: failed to load common library 1>&2
    exit /b 1
)

:: Cargar modulos de operacion: cada .cmd define sus etiquetas kv_op_*
for %%M in ("%KIVICK_HOME%\scripts\win\*.cmd") do (
    call "%%M"
)

:: --------------------------------------------------------
::  Idioma
:: --------------------------------------------------------

:: Deduce el idioma a partir de la variable de entorno del sistema.
:: Equivalente de kv_detect_lang() en el .sh.
:kv_detect_lang
    set "KIVICK_LANG=en"
    :: LANG puede estar definida (Git Bash, Cygwin, etc.)
    if defined LANG (
        echo !LANG! | findstr /i "^es" >nul 2>&1 && set "KIVICK_LANG=es"
        goto :kv_detect_lang_done
    )
    :: Fallback: Get-Culture de PowerShell para leer el locale del sistema
    for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command ^
        "(Get-Culture).TwoLetterISOLanguageName"`) do set "_sys_lang=%%L"
    if /i "%_sys_lang%"=="es" set "KIVICK_LANG=es"
    set "_sys_lang="
:kv_detect_lang_done
    exit /b 0

:: --------------------------------------------------------
::  Argumentos
:: --------------------------------------------------------

:kv_usage
    call :say usage.header
    call :say usage.dryrun
    call :say usage.lang
    call :say usage.help
    exit /b 0

:kv_parse_args
    set "_want_help=0"
:_parse_loop
    if "%~1"=="" goto :_parse_done
    if "%~1"=="--dry-run" (
        set "KIVICK_DRYRUN=1"
        shift & goto :_parse_loop
    )
    :: --lang=es  o  --lang es
    echo "%~1" | findstr /r "^\"--lang=." >nul 2>&1
    if not errorlevel 1 (
        set "_tmp=%~1"
        set "KIVICK_LANG=!_tmp:~7!"
        set "_tmp="
        shift & goto :_parse_loop
    )
    if "%~1"=="--lang" (
        set "KIVICK_LANG=%~2"
        shift & shift & goto :_parse_loop
    )
    if "%~1"=="-h" (set "_want_help=1" & shift & goto :_parse_loop)
    if "%~1"=="--help" (set "_want_help=1" & shift & goto :_parse_loop)
    echo kivick: unknown option: %~1 1>&2
    call :kv_load_catalog
    call :kv_usage
    exit /b 2
:_parse_done
    if "%_want_help%"=="1" (
        call :kv_load_catalog
        call :kv_usage
        set "_want_help="
        exit /b 0
    )
    set "_want_help="
    exit /b 0

:: --------------------------------------------------------
::  Menu
:: --------------------------------------------------------

:kv_show_menu
    call :kv_t menu.title  _m_title
    call :kv_t menu.opt1   _m_opt1
    call :kv_t menu.opt2   _m_opt2
    call :kv_t menu.opt3   _m_opt3
    call :kv_t menu.opt4   _m_opt4
    call :kv_t menu.opt5   _m_opt5
    call :kv_t menu.exit   _m_exit
    echo.
    echo   ===============================================
    echo                    %_m_title%
    echo   ===============================================
    echo.
    echo      [1] %_m_opt1%
    echo      [2] %_m_opt2%
    echo      [3] %_m_opt3%
    echo      [4] %_m_opt4%
    echo      [5] %_m_opt5%
    echo.
    echo      [0] %_m_exit%
    echo.
    set "_m_title=" & set "_m_opt1=" & set "_m_opt2=" & set "_m_opt3="
    set "_m_opt4=" & set "_m_opt5=" & set "_m_exit="
    exit /b 0

:kv_menu_loop
    call :kv_t menu.prompt _mp
    call :kv_t menu.pause  _mpause
:_menu_top
    call :kv_show_menu
    set "_opt="
    set /p "_opt=  %_mp% "
    if "!_opt!"=="0" goto :_menu_done
    if "!_opt!"=="1" (call :kv_op_change_password & goto :_menu_pause)
    if "!_opt!"=="2" (call :kv_op_check_disk      & goto :_menu_pause)
    if "!_opt!"=="3" (call :kv_op_check_os        & goto :_menu_pause)
    if "!_opt!"=="4" (call :kv_op_create_user     & goto :_menu_pause)
    if "!_opt!"=="5" (call :kv_op_shutdown        & goto :_menu_pause)
    if "!_opt!"==""  goto :_menu_top
    call :warn menu.invalid
:_menu_pause
    set /p "_dummy=  %_mpause% "
    goto :_menu_top
:_menu_done
    set "_opt=" & set "_mp=" & set "_mpause=" & set "_dummy="
    exit /b 0

:: --------------------------------------------------------
::  Punto de entrada
:: --------------------------------------------------------

:main
    call :kv_detect_lang
    call :kv_parse_args %*
    if errorlevel 1 exit /b %ERRORLEVEL%

    call :kv_init
    if errorlevel 1 exit /b 1

    call :kv_menu_loop

    call :say menu.bye
    call :kv_finish
    endlocal
    exit /b 0

call :main %*
