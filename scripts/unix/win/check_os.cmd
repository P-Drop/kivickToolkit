@echo off
:: =================================================================
::  Opcion 3 del menu: comprobar la integridad del sistema operativo
::
::  DISM /ScanHealth detecta corrupcion en la imagen del sistema sin
::  repararla (/ScanHealth en lugar de /RestoreHealth: el menu dice
::  "comprobar"). Si detecta algo, avisa de que existe /RestoreHealth.
::  sfc /scannow verifica la integridad de los archivos de sistema.
::  Ambos requieren administrador.
:: =================================================================

exit /b 0

:kv_op_check_os
    call :require_admin
    if errorlevel 1 exit /b 1

    call :run_cmd "DISM ScanHealth" DISM /Online /Cleanup-Image /ScanHealth
    set "_dism_rc=%ERRORLEVEL%"

    call :run_cmd "sfc scannow" sfc /scannow

    if not "%_dism_rc%"=="0" call :warn opos.dismfound
    set "_dism_rc="
    exit /b 0
