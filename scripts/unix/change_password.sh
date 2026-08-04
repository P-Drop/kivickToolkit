#!/usr/bin/env bash
# shellcheck shell=bash
# ======================================================================
#  Opcion 1 del menu: cambiar la contrasena del usuario actual
#
#  El original (legacy/scripts/change_password.bat) leia la contrasena
#  con `set /p`, que la muestra en pantalla, y la pasaba como argumento
#  a `net user`, donde queda visible en la lista de procesos.
#
#  Aqui delegamos en `passwd`, que ya hace lo correcto: oculta la
#  entrada, pide la contrasena actual antes de permitir el cambio y
#  aplica las politicas de complejidad del sistema. No manejamos el
#  secreto en ningun momento: es la forma mas segura de tratarlo.
# ======================================================================

kv_op_change_password() {
    local user="${USER:-$(id -un)}"

    confirm confirm.changepass "$user" || return 1

    # Interactivo: passwd dialoga con el usuario, asi que run_cmd_tty
    run_cmd_tty "cambiar contrasena" -- passwd
}