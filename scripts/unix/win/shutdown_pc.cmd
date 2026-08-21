@echo off
:: ======================================================================
::  Opcion 5 del menu: apagar el equipo
::
::  La unica operacion verdaderamente irreversible del menu: si el
::  usuario tiene trabajo sin guardar, lo pierde. Se confirma SIEMPRE
::  antes de ejecutar nada.
:: ======================================================================

exit /b 0

:kv_op_shutdown
    :: Confirmacion obligatoria ANTES de ejecutar nada.
    :: La operacion es irreversible: trabajo sin guardar se pierde.
    call :confirm confirm.shutdown
    if errorlevel 1 exit /b 1

    call :run_cmd "apagar equipo" shutdown /s /t 0
    exit /b %ERRORLEVEL%
