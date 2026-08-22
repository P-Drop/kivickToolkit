@echo off
:: ======================================================================
::  Opcion 4 del menu: crear un usuario nuevo
::
::  El asterisco de `net user "%name%" * /add` hace que net user pida
::  la contrasena el mismo: la oculta, la confirma dos veces y nunca
::  pasa por ninguna variable ni por la linea de comandos.
:: ======================================================================

exit /b 0

:kv_op_create_user
    call :kv_t prompt.username _cu_prompt
    set /p "_cu_name=%_cu_prompt% "
    set "_cu_prompt="

    call :run_cmd "crear usuario" net user "%_cu_name%" * /add
    set "_cu_name="
    exit /b %ERRORLEVEL%
