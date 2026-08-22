@echo off
:: ====================================================
::  Opcion 2 del menu: comprobar el estado del disco
::
::  chkdsk C: /scan hace una comprobacion online: no pide reiniciar
::  a diferencia de /f. No requiere administrador.
::
::  El original (legacy) ejecutaba sfc /scannow aqui, que revisa
::  archivos de sistema, no el disco. Eso es la opcion 3.
:: ====================================================

exit /b 0

:kv_op_check_disk
    call :run_cmd "comprobar disco" chkdsk C: /scan
    exit /b %ERRORLEVEL%
