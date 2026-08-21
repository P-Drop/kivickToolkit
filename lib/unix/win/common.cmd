@echo off
:: =============================================================================
::  Kivick Toolbox - Nucleo comun para Windows (CMD)
::
::  Este archivo se carga con CALL, NO se ejecuta directamente.
::  Equivalente Windows de lib/unix/common.sh
::
::  Uso desde otro script:
::    call "%~dp0..\..\lib\win\common.cmd"
:: =============================================================================

:: Si ya se cargo antes, salir sin hacer nada. Evita redefinir variables
:: cuando varios scripts hacen CALL de esta libreria.
if defined KIVICK_COMMON_LOADED exit /b 0
set "KIVICK_COMMON_LOADED=1"

:: Raiz del proyecto. %~dp0 es la ruta de ESTE archivo (con barra final).
:: Como estamos en <raiz>\lib\win\, subimos dos niveles con ..\..\
for %%I in ("%~dp0..\..") do set "KIVICK_ROOT=%%~fI"

:: --- Configuracion (se puede sobrescribir desde el entorno) -----------------
if not defined KIVICK_DRYRUN  set "KIVICK_DRYRUN=0"
if not defined KIVICK_LANG    set "KIVICK_LANG=en"
if not defined KIVICK_LOG     set "KIVICK_LOG="
set "KIVICK_CATALOG="
set "KIVICK_SECRET="

:: =============================================================================
::  i18n
:: =============================================================================

:: kv_load_catalog
:: Carga el catalogo de idioma en KIVICK_CATALOG (ruta al archivo .properties).
:: En CMD no hay arrays asociativos; kv_t lee el archivo linea a linea.
:kv_load_catalog
    set "_cat_file=%KIVICK_ROOT%\i18n\%KIVICK_LANG%.properties"
    if not exist "%_cat_file%" (
        echo kivick: catalog not found: %_cat_file% 1>&2
        if /i not "%KIVICK_LANG%"=="en" (
            set "KIVICK_LANG=en"
            set "_cat_file=%KIVICK_ROOT%\i18n\en.properties"
            if not exist "%_cat_file%" exit /b 1
        ) else (
            exit /b 1
        )
    )
    set "KIVICK_CATALOG=%_cat_file%"
    set "_cat_file="
    exit /b 0

:: kv_t CLAVE RESULTADO_VAR
:: Busca CLAVE en el catalogo y deja el valor en la variable nombrada por
:: RESULTADO_VAR. Si no existe devuelve !CLAVE! y codigo 1.
:kv_t
    set "_kv_key=%~1"
    set "_kv_var=%~2"
    set "%_kv_var%="
    if not exist "%KIVICK_CATALOG%" (
        set "%_kv_var%=!%_kv_key%!"
        exit /b 1
    )
    for /f "usebackq tokens=1,* delims==" %%A in ("%KIVICK_CATALOG%") do (
        if "%%A"=="%_kv_key%" (
            set "%_kv_var%=%%B"
            set "_kv_key="
            goto :kv_t_found
        )
    )
    echo kivick: missing translation key: %_kv_key% 1>&2
    set "%_kv_var%=!%_kv_key%!"
    set "_kv_key="
    exit /b 1
:kv_t_found
    set "_kv_key="
    exit /b 0

:: say CLAVE [arg1]
:: Imprime la traduccion de CLAVE seguida de salto de linea.
:say
    set "_say_key=%~1"
    call :kv_t "%_say_key%" _say_msg
    echo %_say_msg%
    set "_say_key="
    set "_say_msg="
    exit /b 0

:: =============================================================================
::  Registro de sesion
:: =============================================================================

:: kv_now -> deja la fecha/hora ISO-8601 en KV_NOW
:kv_now
    for /f "tokens=1-6 delims=/:. " %%A in ('wmic os get LocalDateTime /value ^| find "="') do (
        set "_kv_dt=%%B"
    )
    :: Formato YYYYmmddHHMMSS desde LocalDateTime (20260817143022.000000+000)
    set "_ldt=%_kv_dt%"
    set "KV_NOW=%_ldt:~0,4%-%_ldt:~4,2%-%_ldt:~6,2%T%_ldt:~8,2%:%_ldt:~10,2%:%_ldt:~12,2%"
    set "_kv_dt=" & set "_ldt="
    exit /b 0

:: kv_init_log
:: Crea el directorio de logs y el archivo de sesion en
:: %LOCALAPPDATA%\kivick\session-YYYYMMDD-HHMMSS-PID.log
:kv_init_log
    set "_log_dir=%LOCALAPPDATA%\kivick"
    if not exist "%_log_dir%" mkdir "%_log_dir%" 2>nul
    if not exist "%_log_dir%" (
        echo kivick: cannot create log directory: %_log_dir% 1>&2
        exit /b 1
    )
    :: Marca de tiempo para el nombre del log
    for /f "tokens=2 delims==" %%A in ('wmic os get LocalDateTime /value ^| find "="') do set "_ldt=%%A"
    set "_stamp=%_ldt:~0,8%-%_ldt:~8,6%"
    set "KIVICK_LOG=%_log_dir%\session-%_stamp%-%RANDOM%.log"
    type nul >> "%KIVICK_LOG%" 2>nul || (echo kivick: cannot create log file 1>&2 & exit /b 1)
    set "_log_dir=" & set "_ldt=" & set "_stamp="
    exit /b 0

:: log_event NIVEL MENSAJE
:log_event
    if "%KIVICK_LOG%"=="" exit /b 0
    call :kv_now
    echo %KV_NOW% ^| %USERNAME% ^| %-6s ^| %~2>> "%KIVICK_LOG%"
    exit /b 0

:: =============================================================================
::  Mensajes al usuario
:: =============================================================================

:info
    call :kv_t "%~1" _info_msg
    echo %_info_msg%
    call :log_event INFO "%_info_msg%"
    set "_info_msg="
    exit /b 0

:warn
    call :kv_t "%~1" _warn_msg
    echo %_warn_msg% 1>&2
    call :log_event WARN "%_warn_msg%"
    set "_warn_msg="
    exit /b 0

:: die CLAVE -> imprime error, registra FATAL y termina con codigo 1
:die
    call :kv_t "%~1" _die_msg
    echo %_die_msg% 1>&2
    call :log_event FATAL "%_die_msg%"
    set "_die_msg="
    exit /b 1

:: =============================================================================
::  Ejecucion de comandos
:: =============================================================================

:: run_cmd DESCRIPCION COMANDO [ARGS...]
:: Unico punto de ejecucion del proyecto.
:: Si KIVICK_DRYRUN=1 solo registra sin ejecutar.
:run_cmd
    set "_rc_desc=%~1"
    shift
    :: Los argumentos restantes son el comando a ejecutar
    set "_rc_cmd=%*"
    if "%KIVICK_DRYRUN%"=="1" (
        call :kv_t dryrun.would _rc_dry
        echo %_rc_dry%: %_rc_cmd%
        call :log_event DRYRUN "%_rc_desc% :: %_rc_cmd%"
        set "_rc_desc=" & set "_rc_cmd=" & set "_rc_dry="
        exit /b 0
    )
    call :log_event EXEC "%_rc_desc% :: %_rc_cmd%"
    %_rc_cmd% >> "%KIVICK_LOG%" 2>&1
    set "_rc_exit=%ERRORLEVEL%"
    call :log_event RESULT "%_rc_desc% :: exit=%_rc_exit%"
    set "_rc_desc=" & set "_rc_cmd="
    exit /b %_rc_exit%

:: =============================================================================
::  Interaccion con el usuario
:: =============================================================================

:: confirm CLAVE_TEXTO -> 0 si el usuario confirma, 1 si no.
:: Exige escribir la palabra de confirmacion completa.
:confirm
    call :kv_t "%~1" _cf_msg
    call :kv_t confirm.word _cf_word
    call :kv_t confirm.prompt _cf_prompt
    echo %_cf_msg%
    set /p "_cf_answer=%_cf_prompt% [%_cf_word%]: "
    if /i "%_cf_answer%"=="%_cf_word%" (
        call :log_event CONFIRM "accepted: %~1"
        set "_cf_msg=" & set "_cf_word=" & set "_cf_prompt=" & set "_cf_answer="
        exit /b 0
    )
    if /i "%_cf_answer%"=="yes" (
        call :log_event CONFIRM "accepted: %~1"
        set "_cf_msg=" & set "_cf_word=" & set "_cf_prompt=" & set "_cf_answer="
        exit /b 0
    )
    if /i "%_cf_answer%"=="si" (
        call :log_event CONFIRM "accepted: %~1"
        set "_cf_msg=" & set "_cf_word=" & set "_cf_prompt=" & set "_cf_answer="
        exit /b 0
    )
    call :say confirm.cancelled
    call :log_event CONFIRM "declined: %~1"
    set "_cf_msg=" & set "_cf_word=" & set "_cf_prompt=" & set "_cf_answer="
    exit /b 1

:: require_admin -> 0 si el proceso tiene privilegios de administrador, 1 si no.
:: Equivalente Windows de require_root.
:require_admin
    net session >nul 2>&1
    if %ERRORLEVEL% equ 0 exit /b 0
    call :kv_t error.needroot _ra_hint
    echo %_ra_hint% 1>&2
    call :log_event ERROR "admin required"
    set "_ra_hint="
    exit /b 1

:: read_secret CLAVE_PROMPT -> deja el valor en KIVICK_SECRET.
:: CMD no tiene modo silencioso nativo; se usa PowerShell para ocultar la entrada.
:read_secret
    call :kv_t "%~1" _rs_prompt
    set "KIVICK_SECRET="
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command ^
        "$p = Read-Host '%_rs_prompt%' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"`) do (
        set "KIVICK_SECRET=%%P"
    )
    set "_rs_prompt="
    exit /b 0

:: =============================================================================
::  Ciclo de vida
:: =============================================================================

:kv_init
    call :kv_load_catalog
    if errorlevel 1 (
        echo kivick: no usable language catalog, aborting 1>&2
        exit /b 1
    )
    call :kv_init_log
    if errorlevel 1 exit /b 1
    call :kv_t log.started _ki_msg
    call :log_event INFO "%_ki_msg%"
    set "_ki_msg="
    if "%KIVICK_DRYRUN%"=="1" call :say dryrun.notice
    exit /b 0

:kv_finish
    call :kv_t log.finished _kf_msg
    call :log_event INFO "%_kf_msg%"
    set "_kf_msg="
    exit /b 0
