# Changelog

Todos los cambios notables de este proyecto se documentan aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

## [Unreleased]

Soporte para Linux y macOS. La herramienta deja de ser exclusiva de Windows.

### Añadido

- Implementación para Unix con las mismas cinco operaciones del menú original:
  `kivick.sh` como lanzador, `lib/unix/` como núcleo y `scripts/unix/` como módulos de
  operación.
- Detección automática de sistema operativo (`lib/unix/platform.sh`), único archivo con
  ramas por plataforma.
- Interfaz bilingüe español/inglés con detección del idioma del sistema y opción `--lang`
  para forzarlo. Los catálogos (`i18n/*.properties`) están en un formato que también podrá
  leer la futura implementación de Windows.
- Modo simulación `--dry-run`: muestra los comandos sin ejecutarlos. Es la única forma segura
  de probar la opción de apagado.
- Registro de sesión en `${XDG_STATE_HOME:-~/.local/state}/kivick/`, con fecha, usuario,
  comando y código de salida. Se crea con permisos `600`.
- Confirmación escrita obligatoria antes de crear un usuario, cambiar una contraseña o apagar
  el equipo. Exige la palabra completa; una sola letra cancela.
- Comprobación de privilegios que indica el `sudo` concreto a ejecutar, en lugar de fallar con
  un error del sistema a mitad de operación.
- Suite de pruebas (`tests/run_tests.sh`) con nueve grupos y sin dependencias externas.
  Validada por mutación: cada comprobación se verificó rompiendo el código a propósito.
- Especificación para portar la herramienta a Windows en `docs/TODO_WINDOWS.md`.
- `.gitattributes` con reglas de fin de línea por tipo de archivo, necesarias al trabajar
  entre Linux y Windows. `legacy/` queda excluido para preservarlo byte a byte.

### Cambiado

- **La opción 2 comprueba el disco de verdad.** Antes ejecutaba `sfc /scannow`, que verifica
  los archivos de sistema, no el disco. Ahora usa `smartctl`, `diskutil` o `chkdsk` según la
  plataforma. La verificación de integridad del sistema pasa a la opción 3, que es donde el
  menú la anuncia.
- La verificación del sistema (opción 3) solo diagnostica: usa `DISM /ScanHealth` en lugar de
  `/RestoreHealth`. Si detecta corrupción, informa de cómo repararla en vez de hacerlo por su
  cuenta.
- La versión original de Windows se traslada a `legacy/`. Se conserva íntegra y con su
  historial, pero ya no se ejecuta.
- El proyecto pasa a vivir en la raíz del repositorio.

### Corregido

- **Inyección de comandos al crear un usuario.** `create_user.bat` interpolaba el nombre sin
  comillas en `net user %name% %passw% /add`, de modo que un valor como `pepe & calc`
  ejecutaba código arbitrario. En la versión Unix es imposible por construcción: los
  argumentos viajan como lista y ningún shell los reinterpreta. Además, el nombre de usuario
  se valida antes de usarse.
- **Contraseñas visibles.** Se leían con `set /p`, que las muestra en pantalla, y se pasaban
  como argumento a `net user`, donde quedaban visibles en la lista de procesos. Ahora la
  entrada es sin eco y los secretos viajan por la entrada estándar.
- **Falta de comprobación de privilegios.** Las cinco operaciones requieren permisos elevados
  y ninguna lo verificaba.
- Cuatro de los cinco scripts originales carecían de `@echo off`.
- El README y el CHANGELOG originales hacían referencia a un `script.bat` y a un directorio
  `assets/` que no existían.

### Seguridad

- Los secretos nunca aparecen en `argv` ni en los registros. Las contraseñas se transmiten por
  la entrada estándar y en el log figuran como `***REDACTED***`. Hay una prueba automática que
  falla si un secreto llega a algún archivo de registro.
- Los archivos de registro se crean con `umask 077` antes de existir, no ajustando los permisos
  después: así no hay ningún instante en que el archivo esté expuesto.

### Pendiente

- La implementación para Windows la desarrollará el autor original siguiendo
  `docs/TODO_WINDOWS.md`.
- La versión de macOS está escrita pero **no se ha verificado en una máquina real**.

## [0.1.0] - 2026-07-30

Versión original, exclusiva de Windows, tal como se recibió. Se conserva en `legacy/` y está
etiquetada como `v0.1.0`.

### Añadido

- `gui.cmd` — menú de texto con cinco opciones.
- `scripts/change_password.bat`, `check_disk.bat`, `check_windows.bat`, `create_user.bat`,
  `shutdown_pc.bat`.
