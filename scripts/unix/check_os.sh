#!/usr/bin/env bash
# shellcheck shell=bash
# =================================================================
#  Opcion 3 del menu: comprobar la integridad del sistema.
#
#  Equivalente a DISM /RestoreHealth + sfc /scannow en Windows: verifica
#  que los archivos instalados coinciden con lo que el gestor de paquetes
#  espera, y revisa los errores recientes del sistema.
# =================================================================

kv_op_check_os() {
    say opos.start

    case "$KIVICK_OS" in
        linux)
            # Verificacion de integridad segun el gestor de paquetes.
            case "$KIVICK_PKG" in
                dpkg)   run_cmd "verificar paquetes" -- dpkg -V ;;
                rpm)    run_cmd "verificar paquetes" -- rpm -Va ;;
                pacman) run_cmd "verificar paquetes" -- pacman -Qkk ;;
                *)      warn opos.nopkgmanager ;;
            esac

            # Errores del arranque actual. --no-pager es imprescindible:
            # sin el, journalctl abriria `less` y se quedaria bloqueado
            # esperando una tecla dentro de la tuberia de run_cmd.
            if have journalctl; then
                run_cmd "errores recientes" -- \
                    journalctl -p 3 -b --no--pager
            else
                warn opos.nojournal
            fi
            ;;

        macos)
            run_cmd "errores recientes" -- \
                log show --last 1h --predicate 'messageType >= 16'
                ;;
    esac
}