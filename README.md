# Kivick Toolbox

Herramienta de línea de comandos para operaciones básicas de administración del sistema, con un menú de texto e implementaciones nativas para cada sistema operativo.

Nació como una utilidad de Windows escrita en batch. Esta versión la lleva a Linux y macOS
conservando el menú original.

## Estado

| Plataforma | Estado |
|---|---|
| Linux | Funcional y probado |
| macOS | Implementado, **sin verificar en máquina real** |
| Windows | Pendiente — ver [docs/TODO_WINDOWS.md](docs/TODO_WINDOWS.md) |

La versión original de Windows se conserva en [`legacy/`](legacy/) como referencia histórica. No se ejecuta.

## Requisitos

- **Bash 3.2 o superior.** Es la versión que trae macOS; el código evita deliberadamente las características de Bash 4 para no romper ahí.
- `sudo` para las operaciones que requieren privilegios.
- Opcionalmente `smartmontools` en Linux, para el diagnóstico SMART del disco.

## Uso

```bash
git clone https://github.com/P-Drop/kivickToolkit.git
cd baseCommandsTool
chmod +x kivick.sh
./kivick.sh
```

### Opciones

| Opción | Efecto |
|---|---|
| `--dry-run` | Muestra los comandos sin ejecutarlos |
| `--lang=en\|es` | Fuerza el idioma de la interfaz |
| `-h`, `--help` | Muestra la ayuda |

Sin `--lang`, el idioma se deduce de `LC_ALL`, `LC_MESSAGES` o `LANG`, con inglés como alternativa por defecto.

**Empieza siempre por `--dry-run`.** Muestra exactamente qué se ejecutaría sin tocar el sistema, y es la única forma segura de probar la opción de apagado.

## Las cinco operaciones

| # | Operación | Linux | macOS | Windows |
|---|---|---|---|---|
| 1 | Cambiar contraseña | `passwd` | `passwd` | `net user "%USERNAME%" *` |
| 2 | Comprobar disco | `df -h` + `smartctl -H` | `diskutil verifyVolume /` | `chkdsk C: /scan` |
| 3 | Comprobar sistema | `dpkg -V` / `rpm -Va` / `pacman -Qkk` + `journalctl` | `log show` | `DISM /ScanHealth` + `sfc /scannow` |
| 4 | Crear usuario | `useradd -m` + `chpasswd` | `sysadminctl -addUser` | `net user "%name%" * /add` |
| 5 | Apagar | `systemctl poweroff` | `shutdown -h now` | `shutdown /s /t 0` |

Cuando falta una herramienta opcional (por ejemplo `smartctl`), la operación **avisa y continúa** con lo que sí puede hacer. Nunca falla en silencio.

Las opciones 1, 4 y 5 exigen confirmación escrita completa: hay que teclear `yes` o `si`, no basta con una letra.

## Registro de sesión

Cada ejecución escribe un log en `${XDG_STATE_HOME:-~/.local/state}/kivick/`, con el formato:

```
2026-08-03T14:27:47+0200 | usuario | EXEC   | crear usuario :: useradd -m pepe
2026-08-03T14:27:47+0200 | usuario | RESULT | crear usuario :: exit=0
```

El archivo se crea con permisos `600` (solo su propietario puede leerlo) y **nunca contiene contraseñas**: los secretos se transmiten por la entrada estándar y en el registro aparecen
como `***REDACTED***`.

## Cómo se tratan las contraseñas

Es la parte que más cuidado ha requerido, y el criterio es simple: **cuanto menos toque el programa una contraseña, mejor**.

- La opción 1 delega en `passwd`, que ya oculta la entrada y exige la contraseña actual. El programa nunca llega a ver el secreto.
- En la opción 4, la contraseña viaja a `chpasswd` por la entrada estándar, jamás como argumento: los argumentos de un proceso son visibles con un simple `ps`.
- La entrada por teclado se lee sin eco, y una interrupción con `Ctrl+C` restaura el terminal.

## Desarrollo

### Estructura

```
kivick.sh              Lanzador y menú
lib/unix/common.sh     Núcleo: i18n, registro, ejecución, confirmación, privilegios
lib/unix/platform.sh   Detección de sistema operativo (único archivo con ramas por SO)
scripts/unix/*.sh      Las cinco operaciones, como módulos que se cargan con source
i18n/*.properties      Textos de la interfaz, compartidos con la futura versión de Windows
tests/run_tests.sh     Suite de pruebas
legacy/                Versión original de Windows, no se ejecuta
```

### Invariantes

Cuatro reglas que el código respeta sin excepción:

1. **Nada se ejecuta fuera de `run_cmd`** y sus variantes.
2. **Los comandos viajan como lista de argumentos**, nunca como cadena. No hay `eval` ni `sh -c`, así que un argumento con `;` o `&` es solo texto: la inyección de comandos es imposible por construcción.
3. **Ningún texto visible al usuario está escrito en el código.** Todo pasa por el catálogo.
4. **Los secretos no aparecen en `argv` ni en los registros.**

Hay tres ejecutores según el tipo de comando:

| Ejecutor | Para | Salida |
|---|---|---|
| `run_cmd` | Comandos que informan | Pantalla y registro |
| `run_cmd_stdin` | Comandos que reciben un secreto | Descartada |
| `run_cmd_tty` | Comandos interactivos | Solo pantalla |

### Pruebas

```bash
bash tests/run_tests.sh
```

Nueve grupos, sin más dependencias que bash. Si `shellcheck` está instalado, se usa; si no, ese grupo se omite con un aviso.

La suite se ha validado por mutación: cada comprobación se verificó rompiendo el código a propósito para confirmar que se pone en rojo. Un test que nunca falla no comprueba nada.

### Añadir un texto nuevo

Añádelo a `i18n/en.properties` **y** a `i18n/es.properties`. La suite falla si una clave existe
en un catálogo y falta en el otro.

Los valores no llevan tildes ni eñes a propósito: el mismo archivo lo leerá la versión de
Windows, y la consola de `cmd.exe` usa una página de códigos distinta de UTF-8.

### Convenciones

**El idioma del proyecto es el español.** Se escriben en español los mensajes de commit, los
comentarios del código, la documentación y los nombres de las ramas cuando llevan descripción.

Quedan **en inglés**, y esto no es una excepción arbitraria:

- Los identificadores del código (funciones, variables, claves del catálogo). Cambiarlos
  obligaría a renombrar toda la API interna y a mezclar idiomas dentro de una misma línea.
- Los prefijos de commit y de rama: `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`.
  Son etiquetas de [Conventional Commits](https://www.conventionalcommits.org/es/), no texto.
- Los textos de `i18n/en.properties`, evidentemente.

Los mensajes de commit anteriores a la versión 0.2.0 están mezclados en ambos idiomas: la
convención se fijó después y reescribir la historia publicada habría costado más de lo que
aporta.

## Licencia

MIT — ver [LICENSE](LICENSE).
