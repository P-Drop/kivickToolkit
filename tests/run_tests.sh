#!/usr/bin/env bash
# shellcheck shell=bash
# ===================================================================
#  Kivick Toolbox - Suite de pruebas
#
#  Sin dependencias: solo bash. ShellCheck se usa si esta instalado.
#  Uso: bash tests/run_tests.sh
#  Salida: 0 si todo pasa, 1 si algo falla.
# ===================================================================

# -u caza el uso de variables sin definir
# pipefail propaga fallos en tuberias
# NO se incluye -e: un test que falla no debe abortar la suite
# Se opta por ver TODOS los fallos de una pasada
set -uo pipefail

KIVICK_HOME=$(cd "$(dirname "$0")/.." && pwd)
cd "$KIVICK_HOME" || exit 1

TESTS_RUN=0
TESTS_FAILED=0

# Colores solo si la salida va a un terminal.
# Si se redirige a un archivo o a un sistema de CI, sin colores
# los codigos de escape ensuciarian el texto
if [ -t 1 ]; then
    C_OK=$'\033[32m'; C_KO=$'\033[31m'; C_HD=$'\033[1m'; C_NO=$'\033[0m'
else
    C_OK=''; C_KO='', C_HD=''; C_NO=''
fi

group() { printf '\n%s%s%s\n' "$C_HD" "$1" "$C_NO"; }

ok() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf '    %sPASS%s  %s\n' "$C_OK" "$C_NO" "$1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '    %sFAIL%s  %s\n' "$C_KO" "$C_NO" "$1"
    [ -n "${2:-}" ] && printf '        %s\n' "$2"
    return 0
}

# assert_eq ESPERADO OBTENIDO DESCRIPCION
assert_eq() {
    if [ "$1" = "$2" ]; then
        ok "$3"
    else
        fail "$3" "esperado [$1] pero se obtuvo [$2]"
    fi
}

# =======================================================================
#  Entorno aislado
# =======================================================================

# Los logs de la suite van a un directorio temporal propio: las pruebas
# no deben ensuciar ~/.local/state del usuario ni leer sus sesiones.
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/kivick-tests.XXXXXX")
export XDG_STATE_HOME=$TEST_TMP/state

# El trap garantiza la limpieza aunque la suite falle o se interrumpa.
trap 'rm -rf "$TEST_TMP"' EXIT

# =======================================================================
group "1. Sintaxis"
# =======================================================================

for f in kivick.sh lib/unix/*.sh scripts/unix/*.sh tests/*.sh; do
    if bash -n "$f" 2>/dev/null; then
        ok "sintaxis: $f"
    else
        fail "sintaxis: $f" "$(bash -n "$f" 2>&1 | head -2)"
    fi
done

# =======================================================================
group "2. ShellCheck"
# =======================================================================

# ShellCheck detecta lo que `bash -n` no puede: erratas en nombres de 
# comandos, variables sin commillas, comparacios sospechosas...
if command -v shellcheck >/dev/null 2>&1; then
    for f in kivick.sh lib/unix/*.sh scripts/unix/*.sh; do
        if shellcheck -x "$f" >/dev/null 2>&1; then
            ok "shellcheck: $f"
        else
            fail "shellcheck: $f" "$(shellcheck -x "$f" 2>&1 | sed -n '3p')"
        fi
    done
else
    printf '    SKIP   shellcheck no instalado (apt install shellcheck)\n'
fi

# =======================================================================
group "3. Catalogos de idioma"
# =======================================================================

keys_of() { grep -o '^[a-z][a-z0-9_.]*=' "$1" | sed 's/=$//' | LC_ALL=C sort; }

en_keys=$(keys_of i18n/en.properties)
es_keys=$(keys_of i18n/es.properties)

if [ "$en_keys" = "$es_keys" ]; then
    ok "en y es tienen las mismas claves"
else
    fail "en y es tienen las mismas claves" \
        "$(diff <(printf '%s\n' "$en_keys") <(printf '%s\n' "$es_keys") | head -5 | tr '\n' ' ')"
fi

# Toda clave usada en el codigo debe existir en el catalogo. Sin esto,
# una errata al escribir una clave solo se descubre cuando un usuario
# ve "!menu.optn" en pantalla.

used=$(grep -rhoE '\b(t|say|warn|info|die|confirm) +[a-z]+\.[a-z0-9_.]+' \
    kivick.sh lib/unix/*.sh scripts/unix/*.sh | awk '{print $2}' | LC_ALL=C sort -u)

missing=$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$en_keys"))

if [ -z "$missing" ]; then
    ok "todas las claves usadas existen en el catalogo"
else
    fail "todas las claves usadas existen en el catalogo" "faltan: $(echo "$missing" | tr '\n' ' ')"
fi

# =======================================================================
group "4. Nucleo (common.sh)"
# =======================================================================

# shellcheck source=../lib/unix/common.sh
source lib/unix/common.sh
# shellcheck source=../lib/unix/platform.sh
source lib/unix/platform.sh


kv_init >/dev/null 2>&1
kv_platform_init        # <-- sin esto, KIVICK_OS queda vacio

if [ "$KIVICK_OS" = "linux" ] || [ "$KIVICK_OS" = "macos" ]; then
    ok "la plataforma se detecta correctamente"
else
    fail "la plataforma se detecta correctamente" "KIVICK_OK=[$KIVICK_OS]"
fi

# Carga de modulos
for f in scripts/unix/*.sh; do
    # shellcheck source=/dev/null
    source "$f"
done

for op in kv_op_change_password kv_op_check_disk kv_op_check_os \
    kv_op_create_user kv_op_shutdown; do
    if declare -F "$op" >/dev/null; then
        ok "$op esta definida"
    else
        fail "$op esta definida" "falta el source del modulo"
    fi
done

assert_eq "Session started" "$(KIVICK_LANG=en; kv_load_catalog; t log.started)" \
    "t devuelve el texto de una clave existente"

assert_eq '!clave.inexistente!' "$(t clave.inexistente 2>/dev/null)" \
    "t marca visiblemente una clave que falta"

# Regresion: el '.' de las claves se trataba como metacaracter de
# expresion regular, y "log.started" matcheaba con "logXstarted".
saved_catalog="$KIVICK_CATALOG"
KIVICK_CATALOG="logXstarted=FALSA
log.started=BUENA"
assert_eq "BUENA" "$(t log.started)" "t no confunde claves que difieren en un punto"
KIVICK_CATALOG="$saved_catalog"

# =======================================================================
group "5. Ejecucion de comandos"
# =======================================================================

witness="$TEST_TMP/testigo"

# En simulacion NO debe ejecutarse absolutamente nada
rm -f "$witness"
KIVICK_DRYRUN=1 run_cmd "prueba" -- touch "$witness" >/dev/null 2>&1
if [ -f "$witness" ]; then
    fail "dry-run no ejecuta el comando" "el archivo testigo fue creado"
else
    ok "dry-run no ejecuta el comando"
fi

# Y sin simulacion si debe ejecutarse
rm -f "$witness"
KIVICK_DRYRUN=0 run_cmd "prueba" -- touch "$witness" >/dev/null 2>&1
if [ -f "$witness" ]; then
    ok "sin dry-run el comando si se ejecuta"
else
    fail "sin dry-run el comando si se ejecuta" "el testigo no se creo"
fi

# Regresion: con `cmd | tee`, $? es el codigo de tee (0 casi siempre)
# Se desactiva pipefail solo aqui: con la opcion activa, la tuberia ya
# devuelve el codigo del comando que falla y el test pasaria incluso con
# run_cmd roto.
set +o pipefail
KIVICK_DRYRUN=0 run_cmd "prueba" -- sh -c 'exit 7' >/dev/null 2>&1
assert_eq "7" "$?" "run_cmd propaga el codigo de salida real"

set -o pipefail
# Anti-inyeccion: los metacaracteres deben llegar como texto literal.
out=$(KIVICK_DRYRUN=0 run_cmd "prueba" -- echo 'a; rm -rf /tmp/nada' 2>/dev/null)
assert_eq 'a; rm -rf /tmp/nada' "$out" "los metacaracteres no se interpretan"

# El log puede contener rutas y nombres de usuario: solo permisos propietario
assert_eq "600" "$(stat -c '%a' "$KIVICK_LOG" 2>/dev/null)" \
    "el log se crea con permisos 600"

# =======================================================================
group "6. Validacion y confirmacion"
# =======================================================================
for name in pepe juan_2 _sys ana-b; do
    if kv_valid_username "$name"; then ok "acepta usuario valido: $name"
    else fail "acepta usuario valido: $name"; fi
done

for name in Pepe 1juan 'pepe;ls' 'pepe rm' '' 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; do
    if kv_valid_username "$name"; then fail "rechaza usuario invalido: [$name]"
    else ok "rechaza usuario invalido: [$name]"; fi
done

# confirm solo debe aceptar la palabra completa del idioma activo.
KIVICK_LANG=en; kv_load_catalog
if printf 'yes\n' | confirm confirm.shutdown >/dev/null 2>&1; then
    ok "confirm acepta la palabra completa"
else
    fail "confirm acepta la palabra completa"
fi

for answer in y no '' YES_NO; do
    if  printf '%s\n' "$answer" | confirm confirm.shutdown >/dev/null 2>&1; then
        fail "confirm rechaza [$answer]"
    else
        ok "confirm rechaza [$answer]"
    fi
done

# =======================================================================
group "7. Tratamiento de secretos"
# =======================================================================

# Se espia lo que create_user envia por stdin sustituyendo run_cmd y
# run_cmd_stdin por versiones que solo registran. Asi se comprueba el
# formato exacto SIN crear ningun usuario.
#
# Regresion: `printf 's:%s\n'` (sin el primer %) generaba dos lineas
# "s:usuario" y "s:contrasena", y chpasswd habria intentado cambiar la
# contrasena de un usuario llamado "s".

# Fijar el idioma para el test para mantener el requerimiento de que cada
# grupo sea independiente del estado de otro. Si no, heredaria el idioma
# del grupo anterior
KIVICK_LANG=en
kv_load_catalog

spy_stdin="$TEST_TMP/spy_stdin"
: > "$spy_stdin"

run_cmd()       { return 0; }
run_cmd_stdin() { cat >> "$spy_stdin"; return 0; }
require_root()  { return 0; }
read_secret()   { KIVICK_SECRET="CLAVE_DE_PRUEBA_9Z"; }

printf 'usuariotest\n%s\n' "$(t confirm.word)" | kv_op_create_user >/dev/null 2>&1

assert_eq "usuariotest:CLAVE_DE_PRUEBA_9Z" "$(head -1 "$spy_stdin")" \
    "chpasswd recibe exactamente una linea usuario:contrasena"

assert_eq "1" "$(wc -l < "$spy_stdin")" \
    "chpasswd recibe una sola linea"

# La prueba mas importante: el secreto no puede estar en ningun log.
if grep -rq 'CLAVE_DE_PRUEBA_9Z' "$XDG_STATE_HOME" 2>/dev/null; then
    fail "el secreto no aparece en los logs" "encontrado en $XDG_STATE_HOME"
else
    ok "el secreto no aparece en los logs"
fi

# =======================================================================
group "8. Lanzador"
# =======================================================================

./kivick.sh --help >/dev/null 2>&1
assert_eq "0" "$?" "--help termina con codigo 0"

./kivick.sh --opcion-que-no-existe >/dev/null 2>&1
assert_eq "2" "$?" "una opcion desconocida termina con codigo 2"

printf '0\n' | ./kivick.sh --dry-run >/dev/null 2>&1
assert_eq "0" "$?" "el menu sale limpiamente con la opcion 0"

printf '' | ./kivick.sh --dry-run >/dev/null 2>&1
assert_eq "0" "$?" "el menu sale limpiamente al cerrarse la entrada"

# =======================================================================
group "9. Rutas de ejecucion"
# =======================================================================

# Ni ShellCheck ni `bash -n` detectan erratas en NOMBRES de comandos
# por ejemplo `ruturn 1` es sintaxis valida y podria ser un ejecutable
# del sistema. Solo se descubre EJECUTANDO esa linea.
#
# Por eso se ejecutan tambien las rutas de ERROR: un typo en la rama
# que solo se recorre cuando algo va mal se podria quedar oculto
#
# check_route DESCRIPCION ENTRADA OPERACION
# 
# Lanza un bash NUEVO: el grupo 7 dejo espias instalados y aqui hacen
# falta otros. Dentro se espian require_root y read_secret para poder
# alcanzar ramas que de otro modo exigirian ser root o teclear de verdad.
# 
# `export LC_ALL=C`, no `LC_ALL=C comando`: bash emite el diagnostico
# con la locale (idioma) que ya tenia cargada, un prefijo de asignacion
# solo afecta al entorno del comando, no matchearia.
#
# `2>&1 >/dev/null` captura SOLO stderr (primero stderr va a donde
# apunta stdout ahora, despues stdout va a /dev/null).
check_route() {
    local desc="$1" input="$2" op="$3"
    local err

    err=$(printf '%b' "$input" | bash -c "
        export LC_ALL=C
        export KIVICK_LANG=en
        source lib/unix/common.sh
        source lib/unix/platform.sh
        for f in scripts/unix/*.sh; do source \"\$f\"; done
        kv_init >/dev/null 2>&1
        kv_platform_init
        require_root()  { return 0; }
        read_secret()   { KIVICK_SECRET='ClaveDePrueba'; }
        run_cmd()       { return 0; }
        run_cmd_stdin() { cat >/dev/null; return 0; }
        run_cmd_tty()   { return 0; }
        KIVICK_DRYRUN=1 $op
    " 2>&1 >/dev/null)

    if printf '%s' "$err" | grep -q 'command not found'; then
        fail "$desc" "$(printf '%s' "$err" | grep 'command not found' | head -1)"
    else
        ok "$desc"
    fi
}

check_route "check_disk"                    ""                      kv_op_check_disk
check_route "check_os"                      ""                      kv_op_check_os
check_route "shutdown confirmado"           "yes\n"                 kv_op_shutdown
check_route "shutdown cancelado"            "no\n"                  kv_op_shutdown
check_route "change_password"               "yes\n"                 kv_op_change_password
check_route "create_user flujo completo"    "usuariotest\nyes\n"    kv_op_create_user
check_route "create_user nombre invalido"   "NOMBRE_INCORRECTO\n"   kv_op_create_user
check_route "create_user cancelado"         "usuariotest\nno\n"     kv_op_create_user


# =======================================================================
#  Resumen
# =======================================================================

printf '\n%s' "$C_HD"
printf '%.0s=' $(seq 50)
printf '%s\n' "$C_NO"

if [ "$TESTS_FAILED" -eq 0 ]; then
    printf '%s%d pruebas, todas correctas%s\n\n' "$C_OK" "$TESTS_RUN" "$C_NO"
    exit 0
else
    printf '%s%d pruebas, %d fallos%s\n\n' "$C_KO" "$TESTS_RUN" "$TESTS_FAILED" "$C_NO"
    exit 1
fi