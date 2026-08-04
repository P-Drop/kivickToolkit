# Implementar la parte Windows del Toolbox

Este documento describe **qué** hay que construir, **dónde** colocarlo y **cómo** debe funcionar. Lo he hecho para que escribas tú el código para Windows, ya que la herramienta original es tuya. 

Hay alguna modificación respecto al código original que escribiste (que se encuentra en la carpeta `legacy/`). Esto se debe a algunas correcciones y mejoras que he detectado.

No hace falta que sepas Bash. Si dudas sobre el comportamiento esperado, tienes el equivalente ya funcionando en `lib/unix/` y `scripts/unix/`, y este documento te lo traduce.

---

## 1. Qué ha pasado con el proyecto

Kivick Toolbox era una herramienta de Windows. Se ha portado a Linux y macOS conservando el menú y las cinco operaciones. Para no reescribirlo todo en un lenguaje nuevo, se optó por **dos implementaciones paralelas**: Bash para Unix, batch para Windows.

Tu versión original **no se ha borrado**: está en `legacy/`, con su historial de git intacto, y la etiqueta (tag) `v0.1.0` apunta al commit donde se importó tal cual la escribiste. Pero `legacy/` ya no se ejecuta; queda como referencia.

Lo único que se comparte entre ambos mundos son los **textos de la interfaz** (en español y en inglés), en `i18n/en.properties` y `i18n/es.properties`. Ese formato se eligió precisamente para que tanto Bash como `for /f` de batch puedan leerlo.

---

## 2. Qué tienes que crear

```
lib/win/common.cmd                  <- el núcleo: log, i18n, ejecución, confirmación
scripts/win/change_password.cmd     <- opción 1
scripts/win/check_disk.cmd          <- opción 2
scripts/win/check_os.cmd            <- opción 3
scripts/win/create_user.cmd         <- opción 4
scripts/win/shutdown_pc.cmd         <- opción 5
kivick.cmd                          <- el menú (reemplaza a legacy/gui.cmd)
```

Empieza por `lib/win/common.cmd`: todo lo demás depende de él.

---

## 3. El contrato de `lib/win/common.cmd`

Las rutinas que necesitas. Los nombres son orientativos; lo que importa es el comportamiento. En Bash son funciones; en batch serán etiquetas invocadas con `call :nombre`.

| Rutina | Qué hace | Equivalente Bash |
|---|---|---|
| `:kv_init` | Carga el catálogo de idioma y abre el log de sesión | `kv_init` |
| `:t` | Devuelve el texto de una clave del catálogo | `t` |
| `:log_event` | Añade una línea al log: fecha, usuario, nivel, mensaje | `log_event` |
| `:run_cmd` | **Único** punto de ejecución. Respeta el modo simulación, registra y muestra la salida | `run_cmd` |
| `:confirm` | Muestra el comando y exige la palabra completa (`yes`/`si`) | `confirm` |
| `:require_admin` | Comprueba privilegios; si faltan, explica cómo obtenerlos | `require_root` |

Variables globales, con los mismos nombres que en Unix:

| Variable | Valores | Para qué |
|---|---|---|
| `KIVICK_ROOT` | ruta | Raíz del proyecto |
| `KIVICK_LANG` | `en` / `es` | Catálogo activo |
| `KIVICK_DRYRUN` | `0` / `1` | Modo simulación |
| `KIVICK_LOG` | ruta | Log de la sesión actual |

---

## 4. Las cuatro reglas del proyecto

Son invariantes: todo lo demás es negociable; esto no.
Criterios de diseño de seguridad.

1. **Nada se ejecuta fuera de `:run_cmd`.** Ni un `mkdir` suelto en un script de operación.
2. **Todas las variables van entrecomilladas.** Siempre `"%name%"`, nunca `%name%`.
3. **Ningún texto visible al usuario está escrito en el código.** Todo sale del catálogo.
4. **Las contraseñas no se manejan.** Ver la sección 6: Windows ya trae la solución.

---

## 5. Mapa de comandos

Lo que hace cada opción en cada sistema. Fíjate en la columna de Windows para implementar.

| Opción | Windows | Linux | macOS |
|---|---|---|---|
| 1 Cambiar contraseña | `net user "%USERNAME%" *` | `passwd` | `passwd` |
| 2 Comprobar disco | `chkdsk C: /scan` | `smartctl -H` | `diskutil verifyVolume /` |
| 3 Comprobar sistema | `DISM /Online /Cleanup-Image /ScanHealth` y `sfc /scannow` | `dpkg -V` / `rpm -Va` + `journalctl` | `log show` |
| 4 Crear usuario | `net user "%name%" * /add` | `useradd -m` + `chpasswd` | `sysadminctl -addUser` |
| 5 Apagar | `shutdown /s /t 0` | `systemctl poweroff` | `shutdown -h now` |

Tres cambios respecto a tu versión original, con su motivo:

- **Opción 2**: antes ejecutaba `sfc /scannow`, que verifica los archivos del sistema, no el disco. Ahora usa `chkdsk C: /scan`, que es la que examina el disco y además es la variante **online** (no pide reiniciar, a diferencia de `/f`). La verificación de archivos del sistema es la opción 3, según el menú.
- **Opción 3**: `/ScanHealth` en lugar de `/RestoreHealth`. El menú dice "comprobar", así que mejor solo diagnosticar. Si detecta corrupción, informa de que existe `/RestoreHealth` en vez de ejecutarlo.
- **Opciones 1 y 4**: el asterisco de `net user X *`. Es **CLAVE**. Lo explico en la siguiente sección.

---

## 6. Las contraseñas: el asterisco lo resuelve

La versión original hacía esto:

```bat
set /p passw= Please insert the password for the account....
net user  %name%  %passw% /add
```

Tiene tres problemas — son trampas que batch pone muy difíciles de evitar:

1. `set /p` **muestra en pantalla** lo que se escribe. Quien pase por detrás lee la contraseña.
2. La contraseña acaba en la **línea de comandos** de `net user`. Mientras ese proceso vive,
   cualquiera puede verla con el Administrador de tareas o `wmic process get commandline`.
3. Sin comillas, un nombre como `juan & dir` ejecuta `dir`. Es una inyección de comandos.

**Windows ya trae la solución y es más simple que todo eso:**

```bat
net user "%name%" * /add
```

El `*` hace que `net user` pida la contraseña **él mismo**: la oculta al teclearla, la pide dos
veces para confirmar y nunca pasa por una variable ni por la línea de comandos. Los tres
problemas desaparecen de golpe, y además escribes menos código.

Lo mismo para la opción 1: `net user "%USERNAME%" *`.

En Unix se hizo exactamente lo mismo delegando en `passwd`. **La regla general es: cuanto menos toque tu programa una contraseña, mejor.** La mejor forma de no filtrar un secreto es no
tenerlo nunca.

---

## 7. Trampas de batch que te vas a encontrar

### 7.1 Leer el catálogo de idioma

```bat
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%KIVICK_ROOT%\i18n\%KIVICK_LANG%.properties") do (
    set "KV_%%a=%%b"
)
```

- `eol=#` salta las líneas de comentario del archivo.
- `delims==` parte por el signo igual; `tokens=1,*` deja la clave en `%%a` y **todo** el resto
  en `%%b`, aunque el texto contenga más signos igual.
- Los nombres de variable admiten puntos, así que `menu.opt1` se convierte en `KV_menu.opt1`.

Recuerda que dentro de un script se escribe `%%a` y en la línea de comandos `%a`.

### 7.2 La expansión retardada (la trampa clásica)

Batch expande `%variable%` cuando **lee** el bloque completo, no cuando lo ejecuta. Dentro de un `for` o un `if`, una variable que cambia en el propio bloque conserva su valor viejo. Por eso
hace falta:

```bat
setlocal enabledelayedexpansion
```

y usar `!variable!` en lugar de `%variable%` dentro de bloques.

**Pero cuidado con el efecto secundario**: con la expansión retardada activa, un signo `!` en el *contenido* de una variable se interpreta y desaparece. Si alguna vez lees texto del usuario con `set /p` mientras está activa, un texto con `!` se corrompe. Es otro motivo más para no leer contraseñas nunca: `Passw0rd!` se convertiría en `Passw0rd`.

### 7.3 Comprobar privilegios de administrador

```bat
fltmc >nul 2>&1
if errorlevel 1 (
    rem no somos administrador
)
```

`fltmc` es más fiable que el clásico `net session`, que depende de que el servicio Server esté arrancado. Las cinco operaciones necesitan privilegios elevados, así que comprueba pronto y
explica cómo conseguirlos ("clic derecho → Ejecutar como administrador") en vez de dejar que el comando falle con un error críptico.

### 7.4 `errorlevel` no es lo que parece

`if errorlevel 1` significa **"el código de salida es mayor o igual que 1"**, no "igual a 1". Es la fuente de bugs más común en batch. Para comparar un valor exacto:

```bat
if "%errorlevel%"=="0" ( ... )
```

Y dentro de un bloque con expansión retardada, `!errorlevel!`.

### 7.5 La fecha para el nombre del log

`%date%` y `%time%` cambian de formato según la configuración regional: lo que funciona en tu máquina falla en otra. Lo fiable:

```bat
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%i"
```

Arranca PowerShell, así que tarda un momento, pero solo se hace una vez al iniciar la sesión.
Batch no tiene equivalente al PID del proceso; añade `%RANDOM%` al nombre para que dos sesiones lanzadas en el mismo segundo no compartan archivo.

Ubicación del log: `%LOCALAPPDATA%\Kivick\logs\`.

### 7.6 Proteger el log

En Unix el log se crea con permisos `600`: solo su dueño puede leerlo. El equivalente en Windows:

```bat
icacls "%KIVICK_LOG%" /inheritance:r /grant:r "%USERNAME%":F >nul
```

`/inheritance:r` corta los permisos heredados de la carpeta y `/grant:r` deja al usuario actual como único con acceso.

### 7.7 Lo que batch no puede garantizar

Conviene que lo sepas porque afecta a cuánto puedes confiar en `:run_cmd`.

En Bash, los argumentos de un comando viajan como una **lista**: un argumento que contenga `&` o `;` es texto y punto, porque no hay ningún shell que lo reinterprete. La inyección es imposible por construcción.

**Batch no tiene listas de argumentos.** `:run_cmd` recibirá la orden como una cadena y la ejecutará, con lo que los caracteres especiales de batch (`&`, `|`, `^`, `<`, `>`, `%`) siguen siendo peligrosos. No se puede replicar esa garantía. Lo que sí puedes hacer:

1. Entrecomillar **siempre** las variables.
2. **Validar** la entrada antes de usarla (siguiente punto).
3. No interpolar nunca secretos: el `*` de `net user` lo evita.

### 7.8 Validar el nombre de usuario

Batch no tiene expresiones regulares, pero `findstr` sí:

```bat
echo %name%| findstr /r /c:"^[a-zA-Z0-9_-][a-zA-Z0-9_-]*$" >nul
if errorlevel 1 (
    rem nombre no válido: rechazar
)
```

En Unix se rechaza todo lo que no sean minúsculas, dígitos, `-` y `_`, con un máximo de 32 caracteres. Windows es más permisivo con los nombres de cuenta, aunque conviene ser estricto: es la última línea de defensa que mencionaba el punto anterior.

---

## 8. El modo simulación (`--dry-run`)

`kivick.cmd` debe aceptar los mismos parámetros que la versión Unix:

| Parámetro | Efecto |
|---|---|
| `--dry-run` | Muestra los comandos sin ejecutarlos |
| `--lang=en` / `--lang=es` | Fuerza el idioma |
| `-h`, `--help` | Muestra la ayuda |

El modo simulación no es un adorno: es la única forma de probar la opción "apagar el equipo" sin apagarlo. `:run_cmd` debe comprobar `KIVICK_DRYRUN` **antes** de ejecutar nada y limitarse a imprimir el comando usando la clave `dryrun.would` del catálogo.

Para detectar el idioma automáticamente, `%USERPROFILE%`, la variable `%LANG%` si existe, o:

```bat
for /f "tokens=2 delims==" %%i in ('wmic os get oslanguage /value 2^>nul') do set "OSLANG=%%i"
```

Si te complica, empieza con inglés por defecto y `--lang` para cambiarlo; la detección se puede añadir después.

---

## 9. Los textos y el catálogo compartido

**No escribas ningún texto de interfaz en el código.** Todo sale de `i18n/en.properties` y `i18n/es.properties`, que ya están completos.

Si necesitas un texto nuevo, añádelo **a los dos archivos**. Hay un test automático que falla si una clave existe en uno y falta en el otro.

Dos detalles del formato:

- Los valores **no llevan tildes ni eñes**, a propósito. La consola de Windows usa una página de códigos distinta de UTF-8 y los acentos se ven como símbolos raros. Si quieres tildes, habría que emitir `chcp 65001` al arrancar y comprobar que se ve bien en Windows 10 y 11.
- Un `%` literal se escribe `%%`. En batch, además, tendrás que tener cuidado con los `%` al pasar textos entre rutinas.

---

## 10. Cómo saber si está bien

Criterios de aceptación, en orden:

1. `kivick.cmd --help` muestra la ayuda en el idioma por defecto.
2. `kivick.cmd --dry-run` recorre las cinco opciones **sin ejecutar nada**. Compruébalo con la opción 5: si el equipo se apaga, el modo simulación está mal.
3. Una opción inválida vuelve al menú sin romperlo.
4. Sin privilegios de administrador, cada operación explica cómo obtenerlos en lugar de fallar con un error del sistema.
5. Las opciones 4 y 5 exigen confirmación escrita completa. Con `s` o `y` a secas debe **cancelar**.
6. El log de sesión existe en `%LOCALAPPDATA%\Kivick\logs\`, registra cada comando con su código de salida y **no contiene ninguna contraseña**. Créate un usuario de prueba con una contraseña reconocible y búscala en el log: no debe aparecer.
7. El menú ofrece las mismas cinco opciones, en el mismo orden, que `./kivick.sh` en Linux.

---

## 11. Dónde mirar cuando dudes

| Duda | Archivo de referencia |
|---|---|
| Estructura el núcleo | `lib/unix/common.sh` |
| Registrar un comando | `run_cmd` en `lib/unix/common.sh` |
| Menú y sus parámetros | `kivick.sh` |
| Operaciones | `scripts/unix/*.sh` |
| Textos disponibles | `i18n/en.properties` |
| Versión original | `legacy/` |

Los archivos de Bash están comentados en español con un enfoque bastante didáctico: aunque no entiendas la sintaxis, el comentario te puede indicar **por qué** se implementa y cómo replicarlo.

---

## 12. Antes de empezar

Comprueba que existe un `.gitattributes` en la raíz con las reglas de fin de línea. Sin él, tus archivos `.cmd` con CRLF y los `.sh` con LF se van a pisar en cada commit entre tu máquina y la de Linux — y un `.bat` guardado con finales de línea LF puede fallar directamente en `cmd.exe`.

Cualquier duda sobre diseño o decisiones que he tomado, pregunta antes de reimplementarla: casi todas están razonadas en los comentarios del código de Unix.
