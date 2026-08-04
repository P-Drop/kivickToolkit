#!/usr/bin/env bash
# shellcheck shell=bash
# ==================================================================
#  Kivick Toolbox - Deteccion de plataforma
#
#  UNICO lugar del proyecto donde se ramifica por sistema operativo.
#  Requiere que common.sh este cargado (usa die y log_event)
# ==================================================================

[ -n "${KIVICK_PLATFORM_LOADED:-}" ] && return 0
KIVICK_PLATFORM_LOADED=1

KIVICK_OS=""        # linux | macos | unsupported
KIVICK_PKG=""       # dpkg | rpm | pacman | unknown

# have COMANDO -> 0 si el comando existe en el PATH
# `command -v` es POSIX y esta integrado en el shell. Evitamos `which`,
# que no es estandar, no existe en algunos sistemas minimo y devuelve 
# codigos de salida incosistentes entre distribuciones
have() {
    command -v "$1" >/dev/null 2>&1
}

# uname -s devuelve "Linux" o "Darwin" (el núcleo de macOS).
detect_os() {
    case "$(uname -s)" in
        Linux)  KIVICK_OS="linux" ;;
        Darwin) KIVICK_OS="macos" ;;
        *)      KIVICK_OS="unsupported" ;;   
    esac
}

# Que gestor de paquetes hay. Lo usa la opcion 3 (comprobar el sistema)
# para verificar la integridad de los paquetes instalados
detect_pkg_manager() {
    if   have dpkg;     then KIVICK_PKG="dpkg"
    elif have rpm;      then KIVICK_PKG="rpm"
    elif have pacman;   then KIVICK_PKG="pacman"
    else                     KIVICK_PKG="unknown"
    fi
}

# systemd presente? Determina si apagamos con systemctl o con shutdown.
# Comprobamos el directorio en lugar de que exista el binario: systemctl
# puede estar instalado en un contenedor donde systemd no es el init.
have_systemd() {
    [ -d /run/systemd/system ]
}

# Dispositivo que smartctl examina, uno por linea, con el formato
# "<dispositivo> -d <tipo>".
#
# smartctl resuelve el sistema de ficheros raiz aunque este sobre
# LVM, LUKS o RAID (no fisico). --scan resuelve todas esas capas
# y ademas dice el tipo (-d nvme, -d scsi...), que smartctl requiere.
kv_smart_targets() {
    have smartctl || return 1
    # --scan imprime "/dev/nvme0 -d nvme # comentario"
    # quitar el comentario para quedarnos con los argumentos
    smartctl --scan 2>/dev/null | sed 's/#.*//'
}

kv_platform_init() {
    detect_os
    [ "$KIVICK_OS" = "unsupported" ] && die error.unsupported "$(uname -s)"

    detect_pkg_manager
    log_event INFO "platform: os=$KIVICK_OS pkg=$KIVICK_PKG systemd=$(have_systemd && echo yes || echo no)"
    return 0
}
