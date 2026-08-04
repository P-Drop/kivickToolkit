#!/usr/bin/env bash
# shellcheck shell=bash
# ======================================================================
#  Opcion 4 del menu: crear un usuario nuevo
#
#  El original (legacy/scripts/create_user.bat) hacia:
#      net user %name% %passw% /add
#  sin comillas, de modo que un nombre como `pepe & calc` ejecutaba
#  comandos arbitrarios. Aqui eso es imposible por construccion: los
#  argumentos viajan como lista y ningun shell los reinterpreta.
# ======================================================================

# Un nombre de usuario valido en POSIX: empieza por letra minuscula o
# guion bajo, y sigue con minusculas, digitos, guion o guion bajo.
# Aunque no hay riesgo de inyeccion, validar sigue siendo necesario:
# useradd aceptaria nombres que luego dan problemas en el sistema.
kv_valid_username() {
    case "$1" in
        ''|*[!a-z0-9_-]*)   return 1 ;;     # vacio o con caracteres no permitidos
        [!a-z_]*)           return 1 ;;     # no empieza por letra o _
    esac
    [ "${#1}" -le 32 ]      # limite habitual en Linux
}

kv_op_create_user() {
    require_root "sudo $KIVICK_ROOT/kivick.sh" || return 1

    local name pass1 pass2

    printf '%s ' "$(t prompt.username)"
    IFS= read -r name

    if ! kv_valid_username "$name"; then
        warn error.badusername
        return 1
    fi

    read_secret prompt.secret
    pass1="$KIVICK_SECRET"
    read_secret prompt.secret2
    pass2="$KIVICK_SECRET"
    KIVICK_SECRET=""        # vaciar variable para no dejar colgando en la global

    if [ -z "$pass1" ]; then
        warn error.passempty
        return 1
    fi

    if [ "$pass1" != "$pass2" ]; then
        warn error.passmismatch
        return 1
    fi

    confirm confirm.createuser "$name" || return 1

    case "$KIVICK_OS" in
        linux)
            run_cmd "crear usuario" -- useradd -m "$name" || return 1

            # La contraseña va por STDIN, nunca como argumento: los
            # argumentos de un proceso son visibles para cualquiera con
            # un `ps` mientras el proceso vive.
            printf '%s:%s\n' "$name" "$pass1" \
                | run_cmd_stdin "asignar contrasena" -- chpasswd
            ;;

        macos)
            # `-password -` hace que sysadminctl la pida interactivamente
            # en lugar de aceptarla por argumento, que seria visible.
            run_cmd_tty "crear usuario" -- \
                sysadminctl -addUser "$name" -password -
            ;;
    esac
}
