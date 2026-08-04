#!/usr/bin/env bash
# shellcheck shell=bash
# ======================================================================
#  Opcion 5 el menu: apagar el equipo.
# ======================================================================

kv_op_shutdown() {
    # La unica operacion verdaderamente irreversible del menu: si el
    # usuario tiene trabajo sin guardar, lo pierde. Se confirma SIEMPRE
    # antes incluso de comprobar privilegios.
    confirm confirm.shutdown || return 1

    case "$KIVICK_OS" in
        linux)
            if have_systemd; then
                # systemctl consulta a polkit, que suele autorizar el
                # apagado a un usuario con sesion local sin pedir root.
                run_cmd "apagar" -- systemctl poweroff
            else
                require_root "sudo $KIVICK_ROOT/kivick.sh" || return 1
                run_cmd "apagar" -- shutdown -h now
            fi
            ;;

        macos)
            require_root "sudo $KIVICK_ROOT/kivick.sh" || return 1
            run_cmd "apagar" -- shutdown -h now
            ;;
    esac
}