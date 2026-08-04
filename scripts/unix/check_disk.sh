#!/usr/bin/env bash
# shellcheck shell=bash
# ====================================================
#  Opcion 2 del menu: comprobar el estado del disco
#
#  Modulo: se carga con `source` desde kivick.sh, no se ejecuta suelto.
#  Requiere common.sh y platform.sh ya cargados.
#
#  NOTA: el original (legacy/scripts/check_disk.bat) anunciaba una
#  comprobacion de disco pero ejecutaba sfc /scannow, que revisa los
#  archivos de sistema. Aqui se comprueba el disco propiamente; la
#  integridad del sistema es la opcion 3.
# ====================================================

kv_op_check_disk() {
    say opdisk.start

    case "$KIVICK_OS" in
        linux)
            # Uso de espacio: informativo y no necesita privilegios.
            run_cmd "uso de disco" -- df -h

            if ! have smartctl; then
                warn opdisk.nosmartctl
                return 0
            fi

            # SMART lee registros del firmware del disco: hace falta root
            if [ "$(id -u)" -ne 0 ]; then
                warn opdisk.smartneedsroot
                return 0
            fi

            local targets dev flag type
            targets=$(kv_smart_targets)

            if [ -z "$targets" ]; then
                warn opdisk.nodevice
                return 0
            fi

            # Here-string (<<<) en lugar de `echo "$targets" | while`;
            # con una tuberia, el while se ejecutaria en un SUBSHELL y
            # cualquier variable que modificase se perderia al terminar.
            # Con <<< el bucle corre en este mismo shell.
            while read -r dev flag type _; do
                [ -n "$dev" ] || continue
                if [ -n "$flag" ]; then
                    run_cmd "SMART $dev" -- smartctl -H "$dev" "$flag" "$type"
                else
                    run_cmd "SMART $dev" -- smartctl -H "$dev"
                fi
            done <<< "$targets"
            ;;

        macos)
            run_cmd "verificar volumen" -- diskutil verifyVolume /
            ;;
    esac
}