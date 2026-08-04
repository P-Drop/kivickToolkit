#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
# =====================================================
#  Kivick Toolbox - Lanzador para Unix (Linux / macOS)
#
#  Equivalente multiplataforma de legacy/gui.cmd
#
#  set -euo pipefail solo aqui, nunca en las librerias:
#    -e aborta si un comando falla sin que se compruebe su resultado
#    -u error al usar una variable no definida (caza erratas en nombres)
#    -o pipefail una tuberia falla si falla cualquiera de sus tramos
#  En un archivo que se carga con `source` contaminaria el shell
#  del usuario, por eso va en el ejecutable y no en common.sh
# =======================================================

# Aqui SI se usa $0 en lugar de BASH_SOURCE: este archivo se ejecuta
# no se carga con source, asi que $0 es su propia ruta.
KIVICK_HOME=$(cd "$(dirname "$0")" && pwd)

# shellcheck source=lib/unix/common.sh
source "$KIVICK_HOME/lib/unix/common.sh"
# shellcheck source=lib/unix/platform.sh
source "$KIVICK_HOME/lib/unix/platform.sh"

# Modulos de operacion: definen las funciones kv_op_*
for kv_module in "$KIVICK_HOME"/scripts/unix/*.sh; do
    # shellcheck source=/dev/null
    source "$kv_module"
done
unset kv_module

# --------------------------------------------------------
#  Idioma
# --------------------------------------------------------

# Deduce el idioma de las variables de entorno de locale. El orden
# LC_ALL > LC_MESSAGES > LANG es el que define POSIX: LC_ALL manda
# sobre todo lo demas, LANG es el valor por defecto.
kv_detect_lang() {
    local loc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    case "$loc" in
        es*|ES*) printf 'es' ;;
        *)       printf 'en' ;;
    esac
}

# --------------------------------------------------------
#  Argumentos
# --------------------------------------------------------

kv_usage() {
    say usage.header
    say usage.dryrun
    say usage.lang
    say usage.help
}

kv_parse_args() {
    local want_help=0

    while [ $# -gt 0 ]; do
        case "$1" in
            
            --dry-run)  # shellcheck disable=SC2034
                        KIVICK_DRYRUN=1 ;;
            --lang=*)   KIVICK_LANG="${1#--lang=}" ;;
            --lang)     shift; KIVICK_LANG="${1:-en}" ;;
            -h|--help)  want_help=1 ;;
            *)
                printf 'kivick: unknown option: %s\n' "$1" >&2
                kv_load_catalog && kv_usage
                exit 2
                ;;
        esac
        shift
    done

    if [ "$want_help" = "1" ]; then
        # Cargamos solo el catalogo, no el log: mostrar la ayuda no es
        # una sesion de trabajo y no deberia dejar rastro en disco.
        kv_load_catalog && kv_usage
        exit 0
    fi
}

# --------------------------------------------------------
#  Menu
# --------------------------------------------------------

kv_show_menu() {
    printf '\n'
    printf '  ===============================================\n'
    printf '                   %s\n' "$(t menu.title)"
    printf '  ===============================================\n\n'
    printf '     [1] %s\n' "$(t menu.opt1)"
    printf '     [2] %s\n' "$(t menu.opt2)"
    printf '     [3] %s\n' "$(t menu.opt3)"
    printf '     [4] %s\n' "$(t menu.opt4)"
    printf '     [5] %s\n' "$(t menu.opt5)"
    printf '\n     [0] %s\n\n'  "$(t menu.exit)"
}

kv_menu_loop() {
    local opt

    while :; do
        kv_show_menu
        printf '  %s ' "$(t menu.prompt)"

        # El `|| break` gestiona el fin de entrada (Ctrl+D o stdin
        # cerrado). Sin el, read fallaria una y otra vez sin consumir
        # nada y el bucle giraria para siempre.
        IFS= read -r opt || break

        # El `|| true` en cada rama: con `set -e`, que una operacion
        # devuelva un codigo distinto de cero (el usuario cancela una
        # confirmacion, por ejemplo) abortaria el programa entero.
        # Aqui una operacion fallida solo debe volver al menu.
        case "$opt" in
            1) kv_op_change_password    || true ;;
            2) kv_op_check_disk         || true ;;
            3) kv_op_check_os           || true ;;
            4) kv_op_create_user        || true ;;
            5) kv_op_shutdown           || true ;;
            0) break ;;
            '') continue ;;
            *) warn menu.invalid ;;
        esac

        printf '\n %s ' "$(t menu.pause)"
        IFS= read -r _ || break
    done
}

# --------------------------------------------------------
#  Punto de entrada
# --------------------------------------------------------

main() {
    # shellcheck disable=SC2034
    # La lee common.sh (ShellCheck no lo ve). No se exporta.
    KIVICK_LANG=$(kv_detect_lang)
    kv_parse_args "$@"

    kv_init || exit 1
    kv_platform_init

    # Si el usuario interrumpe, cerramos el log antes de salir para que
    # la sesion quede bien registrada. 130 es la convencion para
    # "terminado por Ctrl+C" (128 + senal 2).
    trap 'printf "\n"; kv_finish; exit 130' INT TERM

    kv_menu_loop

    say menu.bye
    kv_finish
}

main "$@"
