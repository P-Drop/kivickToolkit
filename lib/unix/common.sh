#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Kivick Toolbox - Nucleo comun para Unix (Linux / macOS)
#
#  Este archivo se carga con `source`, NO se ejecuta directamente.
#  Compatible con Bash 3.2 (la version que trae macOS por licencia):
#  sin arrays asociativos, sin ${var,,}, sin mapfile.
# =============================================================================

# Si ya se cargo antes, salir sin hacer nada. Evita redefinir funciones
# cuando varios scripts hacen source de esta libreria.
[ -n "${KIVICK_COMMON_LOADED:-}" ] && return 0
KIVICK_COMMON_LOADED=1

# Raiz del proyecto. BASH_SOURCE[0] es la ruta de ESTE archivo (a diferencia
# de $0, que seria la del script que nos ha cargado). Como estamos en
# <raiz>/lib/unix/, subimos dos niveles.
KIVICK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# --- Configuracion (se puede sobrescribir desde el entorno) ------------------
KIVICK_DRYRUN="${KIVICK_DRYRUN:-0}"   # 1 = simular, no ejecutar
KIVICK_LANG="${KIVICK_LANG:-en}"      # catalogo de idioma a usar
KIVICK_LOG="${KIVICK_LOG:-}"          # ruta del log; la fija kv_init_log
KIVICK_CATALOG=""                     # catalogo cargado en memoria
KIVICK_SECRET=""                      # ultimo secreto leido por read_secret

# =============================================================================
#  i18n
# =============================================================================

# Carga el catalogo entero en una variable de texto.
# En Bash 3.2 no hay arrays asociativos, asi que buscamos por linea.
kv_load_catalog() {
    local file="$KIVICK_ROOT/i18n/${KIVICK_LANG}.properties"

    if [ ! -r "$file" ]; then
        printf 'kivick: catalog not found: %s\n' "$file" >&2
        # Fallback a inglés por defecto
        if [ "$KIVICK_LANG" != "en" ]; then
            KIVICK_LANG="en"
            file="$KIVICK_ROOT/i18n/en.properties"
            [ -r "$file" ] || return 1
        else
            return 1
        fi
    fi

    KIVICK_CATALOG=$(cat "$file")
}

# t CLAVE [args...] -> escribe el texto traducido SIN salto de linea final.
# Si la clave no existe devuelve !CLAVE! y avisa por stderr: un fallo
# visible es mejor que un texto vacio que nadie detecta.
t() {
    local key="$1"; shift
    local line fmt found=""

    # Comparación literal, sin expresiones regulares: el '.' de las claves
    # es un metacaracter para grep y "log.started" matchearía también "logXstarted"
    while IFS= read -r line; do
        case "$line" in
            "${key}="*) found="$line"; break ;;
        esac
    done <<< "$KIVICK_CATALOG"

    if [ -z "$found" ]; then
        printf 'kivick: missing translation key: %s\n' "$key" >&2
        printf '!%s!' "$key"
        return 1
    fi

    fmt="${found#*=}"          # quitar todo hasta el primer '='
    # shellcheck disable=SC2059
    # Intencional: el formato viene del catalogo, que controlamos nosotros.
    # NUNCA pasar datos del usuario como primer argumento de printf.
    printf "$fmt" "$@"
}

# say = t + salto de linea. Es lo que usaras casi siempre.
say() {
    printf '%s\n' "$(t "$@")"
}

# =============================================================================
#  Registro de sesion
# =============================================================================

# Fecha ISO-8601 portable. Ojo: `date -Iseconds` es de GNU y NO existe
# en macOS, que usa la version BSD. Por eso el formato explicito.
kv_now() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

kv_init_log() {
    local dir stamp
    dir="${XDG_STATE_HOME:-$HOME/.local/state}/kivick"

    # El umask va DENTRO del subshell y ANTES del mkdir para que el
    # directorio nazca privado, en lugar de crearlo abierto y arreglarlo
    # despues (entre ambos momentos habria una ventana de exposicion).
    (umask 077; mkdir -p "$dir") || {
        printf 'kivick: cannot create log directory: %s\n' "$dir" >&2
        return 1
    }

    stamp=$(date '+%Y%m%d-%H%M%S')
    KIVICK_LOG="$dir/session-${stamp}-$$.log"
    (umask 077; : >> "$KIVICK_LOG") || return 1
    chmod 600 "$KIVICK_LOG" 2>/dev/null
}

# log_event NIVEL MENSAJE
log_event() {
    local level="$1"; shift
    [ -n "$KIVICK_LOG" ] || return 0
    printf '%s | %s | %-6s | %s\n' \
        "$(kv_now)" "${USER:-$(id -un)}" "$level" "$*" >> "$KIVICK_LOG"
}

# =============================================================================
#  Mensajes al usuario
# =============================================================================

# Nota de estilo: `local msg; msg=$(...)` en DOS lineas, nunca
# `local msg=$(...)`. En una sola linea, el codigo de salida que ves es el
# de `local` (siempre 0), no el del comando. Es una trampa clasica de shell.
info() {
    local msg; msg=$(t "$@")
    printf '%s\n' "$msg"
    log_event INFO "$msg"
}

warn() {
    local msg; msg=$(t "$@")
    printf '%s\n' "$msg" >&2
    log_event WARN "$msg"
}

die() {
    local msg; msg=$(t "$@")
    printf '%s\n' "$msg" >&2
    log_event FATAL "$msg"
    exit 1
}

# =============================================================================
#  Ejecucion de comandos
# =============================================================================

# Representacion legible del comando para el log y la pantalla.
# Solo entrecomilla lo que lo necesita, para que se lea bien.
kv_quote() {
    local arg out=""
    for arg in "$@"; do
        case "$arg" in
            '') out="$out ''" ;;
            *[!A-Za-z0-9._/-]*) out="$out '$arg'" ;;
            *) out="$out $arg" ;;
        esac
    done
    printf '%s' "${out# }"      # quitar el espacio inicial sobrante
}

# run_cmd DESCRIPCION -- comando arg1 arg2...
#
# UNICO punto de ejecucion del proyecto. Nada se ejecuta fuera de aqui.
# Los argumentos viajan como lista y se invocan con "$@": no hay ningun
# shell intermedio que reinterprete nada, asi que un argumento con ';' o
# '&' es solo texto. Esto cierra por construccion el bug de inyeccion
# que tenia legacy/scripts/create_user.bat.
run_cmd() {
    local desc="$1"; shift
    [ "${1:-}" = "--" ] && shift
    local pretty rc

    pretty=$(kv_quote "$@")

    if [ "$KIVICK_DRYRUN" = "1" ]; then
        say dryrun.would "$pretty"
        log_event DRYRUN "$desc :: $pretty"
        return 0
    fi

    log_event EXEC "$desc :: $pretty"

    # tee muestra la salida y la guarda a la vez. Pero al usar una tuberia,
    # $? seria el codigo de tee (casi siempre 0) y creeriamos que todo fue
    # bien. PIPESTATUS guarda el codigo de cada elemento de la tuberia;
    # el [0] es el de nuestro comando.
    "$@" 2>&1 | tee -a "${KIVICK_LOG:-/dev/null}"
    rc=${PIPESTATUS[0]}

    log_event RESULT "$desc :: exit=$rc"
    return "$rc"
}

# run_cmd_stdin DESCRIPCION -- comando arg1 arg2...
#
# Igual que run_cmd, pero para comandos que reciben un SECRETO por stdin
# (chpasswd, dscl...). Dos diferencias deliberadas:
#   1. En el log, stdin aparece como ***REDACTED***.
#   2. La salida NO se registra ni se muestra: un mensaje de error podria
#      citar la contrasena y acabariamos escribiendola en el log, que es
#      justo lo que intentamos evitar. Solo guardamos el codigo de salida.
run_cmd_stdin() {
    local desc="$1"; shift
    [ "${1:-}" = "--" ] && shift
    local pretty rc

    pretty="$(kv_quote "$@") <stdin: ***REDACTED***>"

    if [ "$KIVICK_DRYRUN" = "1" ]; then
        say dryrun.would "$pretty"
        log_event DRYRUN "$desc :: $pretty"
        cat > /dev/null     # consumir stdin: si no, el que nos escribe
        return 0            # recibiria un SIGPIPE al cerrarse la tuberia
    fi

    log_event EXEC "$desc :: $pretty"
    "$@" > /dev/null 2>&1
    rc=$?
    log_event RESULT "$desc :: exit=$rc"
    return "$rc"
}

# run_cmd_tty DESCRIPCION -- comando arg1 arg2...
#
# Para comandos INTERACTIVOS (passwd, sysadminctl...). A diferencia de 
# run_cmd, no captura la salida: la deja ir directa al terminal, porque
# el comando necesita dialogar con el usuario y una tuberia bufferiza los
# hasta hacerlos inservibles.
#
# El precio es que la salida no queda en el log. Se registra el comando
# y el codigo de salida, que es lo que importa para la auditoria; el
# contenido del dialogo puede incluir avisos sobre la contrasena y
# tampoco querriamos guardarlo.
run_cmd_tty() {
    local desc="$1"; shift
    [ "${1:-}" = "--" ] && shift
    local pretty rc

    pretty=$(kv_quote "$@")

    if [ "$KIVICK_DRYRUN" = "1" ]; then
        say dryrun.would "$pretty"
        log_event DRYRUN "$desc :: $pretty"
        return 0
    fi

    log_event EXEC "$desc :: $pretty (interactivo, salida no capturada)"
    "$@"
    rc=$?
    log_event RESULT "$desc :: exit=$rc"
    return "$rc"
}

# =============================================================================
#  Interaccion con el usuario
# =============================================================================

# confirm CLAVE_TEXTO [args...] -> 0 si el usuario confirma, 1 si no.
# Exige la palabra completa ('yes' / 'si'), no una sola letra: obliga a
# un acto consciente antes de apagar el equipo o crear una cuenta.
confirm() {
    local key="$1"; shift
    local word answer

    word=$(t confirm.word)

    say "$key" "$@"
    printf '%s ' "$(t confirm.prompt "$word")"

    # IFS= y -r para no perder espacios ni interpretar barras invertidas.
    IFS= read -r answer || answer=""

    # Bash 3.2 no tiene ${answer,,}, asi que minusculas con tr.
    answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')

    case "$answer" in
        "$word"|yes|si|sí)  log_event CONFIRM "accepted: $key"
                            return 0 ;;
        *)                  log_event CONFIRM "declined: $key"
                            say confirm.cancelled
                            return 1 ;;
    esac
}

# require_root [sugerencia] -> 0 si somos root, 1 si no.
require_root() {
    local hint="${1:-sudo $KIVICK_ROOT/kivick.sh}"
    [ "$(id -u)" -eq 0 ] && return 0
    say error.needroot "$hint"
    log_event ERROR "root required"
    return 1
}

# read_secret CLAVE_PROMPT -> deja el valor leido en $KIVICK_SECRET.
# Devolvemos por variable global en vez de por stdout a proposito: si lo
# imprimieramos, el secreto pasaria por una tuberia y podria acabar en un
# log o en el historial.
read_secret() {
    local prompt_key="$1"
    local value=""

    printf '%s ' "$(t "$prompt_key")"

    # Si el usuario pulsa Ctrl+C mientras escribe, sin esta trampa el eco
    # se queda desactivado y su terminal parece rota hasta reiniciarla.
    trap 'stty echo 2>/dev/null; printf "\n"' INT
    stty -echo 2>/dev/null
    IFS= read -r value
    stty echo 2>/dev/null
    trap - INT

    printf '\n'

    # shellcheck disable=SC2034
    # Se lee desde los scripts de operacion (otro archivo, ShellCheck no
    # lo ve). Deliberadamente NO se exporta: una variable exportada pasa
    # al entorno de todos los procesos hijos, y un secreto no debe viajar ahi.
    KIVICK_SECRET="$value"
}

# =============================================================================
#  Ciclo de vida
# =============================================================================

kv_init() {
    kv_load_catalog || {
        printf 'kivick: no usable language catalog, aborting\n' >&2
        return 1
    }
    kv_init_log || return 1
    log_event INFO "$(t log.started)"

    [ "$KIVICK_DRYRUN" = "1" ] && say dryrun.notice

    # return 0 explicito: sin el, la funcion devolveria el codigo del [ ]
    # anterior, que es 1 cuando NO estamos en dry-run. El llamador creeria
    # que kv_init ha fallado.
    return 0
}

kv_finish() {
    log_event INFO "$(t log.finished)"
}

