@echo off
:: ======================================================================
::  Opcion 1 del menu: cambiar la contrasena del usuario actual
::
::  El original (legacy/scripts/change_password.bat) leia la contrasena
::  con `set /p`, que la muestra en pantalla, y la pasaba como argumento
::  a `net user`, donde queda visible en la lista de procesos.
::
::  Aqui usamos `net user "%USERNAME%" *`: el asterisco hace que net user
::  pida la contrasena el mismo, la oculta al teclearla, la pide dos
::  veces para confirmar y nunca pasa por una variable ni por la linea
::  de comandos. No manejamos el secreto en ningun momento.
:: ======================================================================

exit /b 0

:kv_op_change_password
    call :confirm confirm.changepass "%USERNAME%"
    if errorlevel 1 exit /b 1

    call :run_cmd "cambiar contrasena" net user "%USERNAME%" *
    exit /b %ERRORLEVEL%
