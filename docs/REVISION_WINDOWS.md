# Revisión del port a Windows (PR #3)

Kivick, he revisado el PR y **he tenido que revertir el merge en `main`**. No es un rechazo del
trabajo: el diseño de las operaciones está bien y las tres correcciones de seguridad que te pedí
las has aplicado correctamente. El problema es que el código, tal como está, **no llega a
arrancar**, y en el camino se han vuelto a abrir dos agujeros que la versión Unix ya tenía
cerrados.

Tu rama `feat/windows-port-v3.0` **está intacta**. Todo lo que sigue se corrige sobre ella.

Este documento va en el mismo orden que necesitas para arreglarlo: primero lo que ya está bien,
luego el fallo de fondo (uno solo, del que cuelgan casi todos los demás), y después el resto por
severidad. Cada punto lleva el porqué y el código correcto.

Las rutas que cito son las de tu rama, no las de `main`.

---

## 1. Lo que está bien y hay que conservar

Empiezo por aquí porque es lo que no debes tocar al rehacerlo:

- **El mapa de comandos es correcto.** `chkdsk C: /scan` en la opción 2, `DISM /ScanHealth` en la
  3 y el `*` de `net user` en la 1 y la 4. Has entendido y aplicado las tres correcciones.
- **El `*` de `net user` es la decisión más importante del port** y está bien puesta en las dos
  operaciones que tocan contraseñas. Es lo que hace que el secreto no pase nunca por tu código.
- **Los comentarios explican el porqué** y citan el bug original. Es exactamente el estilo del
  resto del proyecto.
- **Los finales de línea funcionan.** Tus `.cmd` están en CRLF en disco y LF en el índice, como
  se diseñó en `.gitattributes`. Eso salió perfecto.
- **La estructura conceptual es la correcta**: núcleo, módulos de operación y catálogo
  compartido. Lo que falla es la traducción de esa idea a los mecanismos reales de batch.

---

## 2. El fallo de fondo: batch no puede importar funciones

Este es el punto clave. Si entiendes solo uno de este documento, que sea este, porque de él
cuelgan casi todos los demás.

En Bash, `source lib/unix/common.sh` mete las funciones de ese archivo en el ámbito del script
que lo carga, y a partir de ahí `run_cmd` se llama como si estuviera escrito ahí mismo. Es lo que
hace `kivick.sh`.

**Batch no tiene ese mecanismo.** `call :etiqueta` busca la etiqueta **en el propio archivo, y
solo ahí**. Que `kivick.cmd` haga `call "lib\win\common.cmd"` no importa nada: ejecuta ese
archivo como un programa aparte y vuelve. Las etiquetas de dentro siguen siendo invisibles.

Consecuencia directa en tu código:

- En `kivick.cmd`, ninguna de estas llamadas puede funcionar: `call :say`, `call :kv_t`,
  `call :kv_init`, `call :warn`, `call :kv_finish`. Todas fallan con «no se encuentra el archivo
  por lotes especificado».
- El bucle que carga los módulos:

  ```bat
  for %%M in ("%KIVICK_HOME%\scripts\win\*.cmd") do call "%%M"
  ```

  no define nada. Tus cinco scripts empiezan con `exit /b 0` y colocan la etiqueta `:kv_op_*`
  debajo, así que ese `call` ejecuta el `exit /b 0` y vuelve. No queda rastro de la etiqueta.
- Por tanto `call :kv_op_change_password` y sus cuatro hermanas tampoco existen.
- Y dentro de los propios scripts de operación, `call :confirm`, `call :run_cmd` y
  `call :require_admin` fallan por lo mismo.

No hay una línea del núcleo que sea alcanzable. No es un bug que se parchee: hay que cambiar cómo
se invoca.

### La solución: un dispatcher en el núcleo

Batch sí permite ejecutar una etiqueta concreta de otro archivo, si el archivo colabora. Se hace
poniendo un pequeño despachador en la primera línea útil:

```bat
@echo off
:: Si nos llaman con un argumento que empieza por ':', saltamos a esa etiqueta.
:: Si nos llaman sin argumentos, solo inicializamos y volvemos.
if not "%~1"=="" goto %~1

:: --- inicializacion (solo al cargar) ---
if defined KIVICK_COMMON_LOADED exit /b 0
set "KIVICK_COMMON_LOADED=1"
for %%I in ("%~dp0..\..") do set "KIVICK_ROOT=%%~fI"
...
goto :eof          <-- IMPRESCINDIBLE: corta antes de caer en la primera etiqueta

:run_cmd
    ...
    exit /b %_rc_exit%
```

Y desde fuera se llama con la ruta del archivo por delante:

```bat
set "KV=%KIVICK_HOME%\lib\win\common.cmd"
call "%KV%" :kv_init
call "%KV%" :run_cmd "apagar equipo" shutdown /s /t 0
```

Ese `goto :eof` es obligatorio y ahora mismo te falta. Sin él, al hacer `call "common.cmd"` la
ejecución cae de la inicialización directamente dentro de `:kv_load_catalog` y lo ejecuta sin que
nadie lo haya pedido.

Dos cosas a tu favor: `call archivo.cmd` **no** crea un `setlocal`, así que las variables que
fije el núcleo (`KIVICK_ROOT`, `KIVICK_LOG`...) sobreviven al volver. Y el `exit /b N` de la
etiqueta llega al llamador como `ERRORLEVEL`, así que los códigos de salida se propagan bien.

### Y los módulos de operación: scripts, no funciones

La otra mitad del arreglo. En lugar de fingir que son funciones importadas, que sean lo que
batch sí sabe ejecutar: **scripts normales**. Quita el `exit /b 0` de arriba y la etiqueta
`:kv_op_*`, deja el cuerpo directamente en el archivo, y que el menú los llame por ruta:

```bat
if "!_opt!"=="5" call "%KIVICK_HOME%\scripts\win\shutdown_pc.cmd"
```

Cada script recibe `KIVICK_ROOT` y `KIVICK_LOG` por entorno (ya están fijadas) y llama al núcleo
con el dispatcher. Es más simple que lo que tienes ahora y es el idioma nativo de batch.

---

## 3. Bloqueantes de arranque

Además del punto 2, hay tres razones independientes por las que `kivick.cmd` no llega a mostrar
el menú.

### 3.1 Las rutas no apuntan a donde están los archivos

`kivick.cmd` busca `lib\win\common.cmd` y `scripts\win\*.cmd`. Los archivos están commiteados en
`lib\unix\win\` y `scripts\unix\win\`. El primer `call` falla.

Lo curioso es que **el lanzador tiene razón y la ubicación está mal**: tu propio comentario en
`common.cmd` documenta la ruta buena:

```bat
::  Uso desde otro script:
::    call "%~dp0..\..\lib\win\common.cmd"
```

La estructura correcta es la de la especificación (§2), en paralelo a Unix, no anidada dentro:

```
lib/win/common.cmd              <- no lib/unix/win/
scripts/win/*.cmd               <- no scripts/unix/win/
```

`lib/unix/win/` se lee como «la parte de Windows de Unix», que no significa nada. Windows y Unix
son hermanos, no uno hijo del otro.

### 3.2 `KIVICK_ROOT` se calcula mal por lo mismo

```bat
for %%I in ("%~dp0..\..") do set "KIVICK_ROOT=%%~fI"
```

Sube dos niveles, que es correcto **si el archivo está en `<raíz>\lib\win\`**. Desde
`<raíz>\lib\unix\win\` te deja en `<raíz>\lib`, y entonces el catálogo se busca en
`<raíz>\lib\i18n\en.properties`, que no existe. Se arregla solo al mover el archivo a su sitio.

### 3.3 El punto de entrada es inalcanzable

`kivick.cmd` termina con `call :main %*` en la última línea, pero no hay ningún `goto :main`
antes que lleve hasta ahí. Batch ejecuta de arriba abajo: después del `for` que carga los
módulos, la ejecución **cae dentro de la etiqueta `:kv_detect_lang`** y muere en su `exit /b 0`,
porque fuera de un contexto `call` ese `exit /b` termina el script entero.

La línea `call :main %*` nunca se ejecuta. El arreglo es una línea:

```bat
:: ... despues de cargar los modulos
goto :main          <-- esto es lo que falta

:kv_detect_lang
...
```

Es la misma trampa que el `goto :eof` del punto 2: en batch, **toda sección de código lineal
tiene que terminar con un salto explícito antes de la primera etiqueta**, o se cae dentro de
ella.

---

## 4. Seguridad: dos cosas que hay que volver a cerrar

Estas dos son las que más me preocupan, porque son justo las que motivaron el port.

### 4.1 La inyección de comandos de `create_user` sigue viva

Es **el bug original** de `legacy/scripts/create_user.bat`, el que empezó todo esto. Tu
`create_user.cmd` lee el nombre así:

```bat
call :kv_t prompt.username _cu_prompt
set /p "_cu_name=%_cu_prompt% "
call :run_cmd "crear usuario" net user "%_cu_name%" * /add
```

**Falta la validación entera.** La especificación (§7.8) te daba el código literal y no está en
ninguna parte del PR. Y como `run_cmd` acaba ejecutando una cadena (`%_rc_cmd%`), un nombre como:

```
pepe & shutdown /s /t 0
```

apaga el equipo. Las comillas alrededor de `"%_cu_name%"` no bastan: protegen los espacios, no
los metacaracteres, porque el `&` se interpreta al expandir la variable dentro de la línea que se
ejecuta.

En Unix esto es imposible por dos capas independientes: los argumentos viajan como lista (ningún
shell los reinterpreta) **y además** se valida el nombre. En batch la primera capa no existe —
ya te lo avisaba §7.7 — así que la validación deja de ser un extra y pasa a ser **la única
defensa que tienes**. No es opcional:

```bat
echo(%_cu_name%| findstr /r /c:"^[a-zA-Z0-9_-][a-zA-Z0-9_-]*$" >nul
if errorlevel 1 (
    call "%KV%" :warn error.badusername
    exit /b 1
)
```

La clave `error.badusername` ya existe en los dos catálogos, no tienes que añadir nada.

### 4.2 `:read_secret` hace justo lo que la regla 4 prohíbe

```bat
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command ^
    "$p = Read-Host '%_rs_prompt%' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto(...)"`) do (
    set "KIVICK_SECRET=%%P"
)
```

Empieza bien (`-AsSecureString` no muestra lo que se teclea) y a continuación deshace toda la
protección: **convierte el SecureString a texto plano**, lo saca por una tubería y lo deja en una
variable del entorno, que heredan todos los procesos hijos. Es exactamente el patrón que la
regla 4 descarta y que la versión Unix evita.

Y lo más importante: **es código muerto**. Ningún script lo llama, porque el `*` de `net user` ya
resuelve el problema. La corrección no es arreglarlo, es **borrar la rutina entera**. Código que
maneja secretos y que nadie usa es solo superficie de ataque esperando a que alguien lo llame.

> La mejor forma de no filtrar un secreto es no tenerlo nunca. Eso ya lo conseguiste con el `*`;
> esta rutina lo estropea.

### 4.3 El log no se protege

`kv_init_log` crea el archivo y ahí lo deja. Falta el `icacls` de §7.6:

```bat
icacls "%KIVICK_LOG%" /inheritance:r /grant:r "%USERNAME%":F >nul 2>&1
```

En Unix el log nace con permisos `600` y hay un test que lo comprueba. El log lleva nombres de
usuario y comandos ejecutados: no debe ser legible por otras cuentas de la máquina.

### 4.4 Falta `require_admin` en cuatro de las cinco operaciones

Solo `check_os.cmd` lo llama. `create_user`, `change_password`, `shutdown_pc` y `check_disk` lo
omiten, y las cuatro necesitan elevación. Ojo con el comentario de `check_disk.cmd`:

```bat
::  chkdsk C: /scan hace una comprobacion online: no pide reiniciar
::  a diferencia de /f. No requiere administrador.
```

La primera frase es correcta, la segunda no: `/scan` es online, pero **sí necesita
administrador**. Es el criterio de aceptación §10.4 — sin privilegios, cada operación debe
explicar cómo obtenerlos, no fallar con un error del sistema.

### 4.5 `net session` en lugar de `fltmc`

```bat
:require_admin
    net session >nul 2>&1
```

Es justo el método que §7.3 descartaba: depende de que el servicio Server esté arrancado, y si
está parado te dirá que no eres administrador aunque lo seas. Usa `fltmc >nul 2>&1`.

### 4.6 Falta la confirmación al crear usuario

`create_user.cmd` no llama a `:confirm`. El criterio §10.5 pide confirmación escrita en las
opciones 4 y 5, y la clave `confirm.createuser` ya está en los dos catálogos sin usar.

---

## 5. Defectos del núcleo

Estos aparecerán en cuanto el programa arranque.

### 5.1 `run_cmd` ejecuta la descripción en lugar del comando

```bat
:run_cmd
    set "_rc_desc=%~1"
    shift
    set "_rc_cmd=%*"
```

**`%*` no se ve afectado por `shift`.** Es una de las trampas más conocidas de batch: `shift`
mueve `%1`, `%2`... pero `%*` sigue devolviendo la línea de argumentos original, completa. Así
que `_rc_cmd` acaba valiendo `"apagar equipo" shutdown /s /t 0` e intenta ejecutar la
descripción.

Para quedarte con «todo menos el primero» hay que construirlo a mano:

```bat
:run_cmd
    set "_rc_desc=%~1"
    shift
    set "_rc_cmd="
:_rc_collect
    if "%~1"=="" goto :_rc_ready
    if defined _rc_cmd (set "_rc_cmd=%_rc_cmd% %1") else (set "_rc_cmd=%1")
    shift
    goto :_rc_collect
:_rc_ready
```

(Uso `%1` y no `%~1` a propósito: conserva las comillas de los argumentos que las llevaban.)

### 5.2 `run_cmd` esconde toda la salida, y eso cuelga las opciones 1 y 4

```bat
%_rc_cmd% >> "%KIVICK_LOG%" 2>&1
```

Todo va al archivo y no se ve nada en pantalla. En Unix, `run_cmd` usa `tee`: muestra **y**
registra. Aquí el usuario lanza `chkdsk` y se queda mirando una pantalla en blanco varios
minutos.

Pero hay un caso peor. `net user "%USERNAME%" *` es **interactivo**: su gracia es que pide la
contraseña él mismo. Con esa redirección, la petición de contraseña se escribe en el log y el
usuario ve la consola congelada sin saber que le están pidiendo algo.

Necesitas el equivalente de `run_cmd_tty` de Unix: una variante que **no redirige nada** y deja
que el comando hable con el terminal. Se registra el comando y el código de salida, que es lo
que importa para la auditoría. Úsala en las opciones 1 y 4.

Y un detalle: si `KIVICK_LOG` está vacía, `>> ""` es un error de sintaxis. Comprueba antes.

### 5.3 `log_event` nunca escribe el nivel

```bat
echo %KV_NOW% ^| %USERNAME% ^| %-6s ^| %~2>> "%KIVICK_LOG%"
```

`%-6s` es un formato de `printf` que se te ha colado de la versión Bash. Batch lo imprime tal
cual, y el nivel real (`%~1`) se descarta: todas las líneas del log salen sin EXEC/RESULT/ERROR.
Para alinear en batch hay que rellenar a mano:

```bat
set "_lv=%~1        "
set "_lv=%_lv:~0,6%"
```

Segundo problema en la misma línea: `%~2>>`. Si el mensaje termina en un dígito, cmd lee ese
dígito como número de handle y lo interpreta como redirección, comiéndose el último carácter.
Mete un espacio antes del `>>`, o mejor, usa una variable intermedia.

### 5.4 `kv_now` devuelve basura

```bat
for /f "tokens=1-6 delims=/:. " %%A in ('wmic os get LocalDateTime /value ^| find "="') do (
    set "_kv_dt=%%B"
)
```

La línea que llega es `LocalDateTime=20260817143022.000000+000`. Como `=` **no** está entre los
delimitadores, `%%A` se queda con `LocalDateTime=20260817143022` y `%%B` con `000000+000`. La
fecha del log sale mal.

Lo gracioso es que en `kv_init_log`, veinte líneas más abajo, lo haces bien:
`tokens=2 delims==`. Es solo inconsistencia entre las dos rutinas.

Pero hay dos problemas mayores en esa misma rutina:

- **`kv_now` se llama en cada `log_event`**, y cada llamada arranca un proceso `wmic`. Son
  cientos de milisegundos **por línea de log**. §7.5 decía explícitamente que la marca de tiempo
  se calcula **una vez al iniciar la sesión**.
- **`wmic` está deprecado y ya no viene instalado** en Windows 11 24H2 ni en Server 2025. En esas
  máquinas el programa no registra nada. Usa PowerShell, como decía la especificación:

  ```bat
  for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%i"
  ```

  Para la marca de cada línea del log, calcula la hora con `%TIME%` o acepta la resolución de
  sesión; lo que no puede es lanzar un proceso por línea.

### 5.5 Los `%s` del catálogo no se sustituyen nunca

Los textos del catálogo son plantillas de `printf`. En Unix, `t CLAVE arg` rellena el `%s` con el
argumento. Tu `:kv_t` devuelve el texto crudo, así que en pantalla se lee:

```
Would run: %s: net user "pepe" * /add
This operation requires root privileges. Try: %s
About to change the password for user '%s'
```

En el primer caso además se duplica el separador, porque `run_cmd` hace
`echo %_rc_dry%: %_rc_cmd%` cuando el `: %s` ya estaba en la plantilla.

Y `change_password.cmd` pasa el usuario como segundo argumento (`call :confirm confirm.changepass
"%USERNAME%"`), pero `:confirm` lo ignora: solo lee `%~1`.

Necesitas sustitución de un argumento en `:kv_t` y que `:say`, `:confirm`, `:info` y `:warn` lo
pasen. Con un solo `%s` basta para todo el catálogo actual:

```bat
:kv_t   CLAVE VAR_RESULTADO [ARG]
    ...
    if not "%~3"=="" call set "%_kv_var%=%%%_kv_var%:^%s=%~3%%"
```

### 5.6 La marca de traducción ausente desaparece

```bat
set "%_kv_var%=!%_kv_key%!"
```

La intención es buena — devolver `!menu.title!` para que un texto que falta se vea a simple vista,
igual que en Unix. Pero `kivick.cmd` activa `setlocal enabledelayedexpansion` y esa opción se
hereda por el `call`, así que `!...!` se interpreta como *expansión retardada de una variable
llamada `menu.title`*, que no existe, y el resultado es **cadena vacía**. El fallo visible se
convierte en un texto en blanco, que es justo lo que se quería evitar.

Escápalos: `^!%_kv_key%^!`, o construye la marca con una variable auxiliar.

### 5.7 `--help` no termina el programa

`:kv_parse_args` hace `exit /b 0` tras mostrar la ayuda, pero como está dentro de un `call`, eso
solo vuelve a `:main`, que sigue adelante y abre el menú. En Unix `--help` sale con 0 y sin
abrir siquiera el log, porque mostrar la ayuda no es una sesión de trabajo y no debe dejar rastro
en disco. Es el criterio §10.1.

Devuelve un código distinto (por ejemplo `exit /b 3`) y que `:main` lo distinga de un error real.

### 5.8 Falta la clave `opos.dismfound`

`check_os.cmd` usa `call :warn opos.dismfound` y esa clave **no existe** en `en.properties` ni en
`es.properties`. Hay que añadirla a los dos (§9). El test de paridad no la detectó porque falta
en ambos, y el test de claves usadas solo escanea archivos `.sh` — otro motivo para el punto 7.

### 5.9 Detalles menores

- **`echo %var%` con la variable vacía imprime «ECHO está activado»**, y revienta si el texto
  lleva `&`, `<`, `>` o `|`. La forma segura es `echo(%var%` — sin espacio, con paréntesis. Afecta
  a `:say`, `:info`, `:warn`, `:die` y a todo el menú.
- **`usage.header` dice `Usage: kivick.sh`** también en Windows. Necesita una clave propia
  (`usage.header.win`) o que el nombre del programa entre como argumento.
- **`check_os.cmd` termina siempre con `exit /b 0`**, así que un fallo de `sfc` se pierde.
- **`:confirm` con `set /p` y expansión retardada activa**: si el usuario escribe un `!`, se lo
  come. Es la misma trampa de §7.2 que te llevó a no leer contraseñas nunca.

---

## 6. Versionado, estructura y alcance del PR

### 6.1 La versión: `0.3.0`, no `3.0.0`

El CHANGELOG declara `[3.0.0]`. Debería ser **`0.3.0`**.

Añadir una plataforma sobre un proyecto que va por `0.2.0` es un cambio **minor**: suma
funcionalidad y no rompe nada de lo existente. El salto a `3.0.0` es un major, y además se salta
`1.0.0` y `2.0.0` enteros. El propio CHANGELOG declara adherirse a
[SemVer](https://semver.org/lang/es/).

Sospecho que viene de contar «versión 3» como «la tercera entrega». No es eso: en SemVer el
primer número solo sube cuando rompes compatibilidad, y mientras esté en `0.x` el proyecto se
considera en desarrollo inicial.

Efecto secundario: los enlaces del pie del CHANGELOG quedaron apuntando a `compare/v3.0.0...HEAD`,
un tag que no existe. Los tags publicados son `v0.1.0` y `v0.2.0`.

Hay que corregirlo en el CHANGELOG, en el nombre de la rama y en el mensaje del commit.

### 6.2 La estructura: `lib/win/`, no `lib/unix/win/`

Ya está explicado en 3.1 y 3.2, con la diferencia de que no es solo cuestión de orden: es la
causa directa de dos de los tres bloqueantes de arranque. Al mover los archivos a su sitio, esos
dos se arreglan solos.

Hay que actualizar también la sección «Estructura» del README, que documenta las rutas
equivocadas.

### 6.3 `legacy/`: fuera del alcance de este PR

El PR borra los 14 archivos de `legacy/`. **Hablamos de esto por separado**: la eliminación en sí
me parece bien, y la vas a hacer tú, pero no en el mismo commit que la feature. Dos motivos:

1. Un PR que añade una plataforma no debería borrar otra cosa a la vez. Si hay que revertirlo
   —como ha pasado— se revierten las dos cosas juntas.
2. `legacy/` está referenciada desde `docs/TODO_WINDOWS.md` (cuatro veces), desde cuatro puntos
   del CHANGELOG y desde los comentarios de tus propios scripts nuevos, que citan
   `legacy/scripts/create_user.bat` como el bug a evitar. Al borrarla, toda esa documentación
   pasa a mentir.

**De la coherencia de esas referencias me encargo yo.** Tú, en tu PR, deja `legacy/` en paz; lo
retiramos después, en un commit propio.

### 6.4 El PR se dio por cerrado antes de tiempo

El mensaje del commit dice «Cierra la especificación de `docs/TODO_WINDOWS.md`». De los siete
criterios de aceptación de §10, ninguno se cumple todavía, porque el programa no arranca. No es
un reproche —es fácil darlo por hecho cuando el código «se ve» completo—, pero de ahí sale el
punto siguiente.

---

## 7. Faltan las pruebas de Windows

`tests/run_tests.sh` solo recorre archivos `.sh`. Los 63 tests pasan en verde **sin tocar una
sola línea de batch**. Por eso nada avisó de que el programa no arranca.

No espero que montes un framework de tests en batch. Pero varios de los fallos de este documento
los caza un script de Bash que se limite a leer los archivos, y ese sí corre en el CI de Linux:

- Que exista `lib/win/common.cmd` y los cinco `scripts/win/*.cmd`.
- Que las rutas que cita `kivick.cmd` **existan de verdad** (habría cazado el bloqueante 3.1).
- Que toda clave `KV_*` o clave de catálogo usada en los `.cmd` exista en `en.properties` y en
  `es.properties` (habría cazado 5.8). Es extender el grupo 3 de la suite, que ya hace justo eso
  para los `.sh`.
- Que ningún `.cmd` invoque un comando fuera de `:run_cmd` (regla 1).
- Que `create_user.cmd` contenga la validación con `findstr` (habría cazado 4.1).
- Que no aparezca `set /p` asociado a contraseñas en ningún `.cmd` (regla 4).
- Que los `.cmd` estén en CRLF en el índice.

Con eso y una pasada manual de los siete criterios de §10 en una máquina Windows real, vamos
servidos.

---

## 8. Checklist para el nuevo PR

Por orden de dependencia: sin los cuatro primeros, no puedes probar nada de lo demás.

**Arranque**

- [ ] Mover a `lib/win/common.cmd` y `scripts/win/*.cmd` *(3.1, 6.2)*
- [ ] Dispatcher `if not "%~1"=="" goto %~1` + `goto :eof` en el núcleo *(2)*
- [ ] Módulos de operación como scripts ejecutables, llamados por ruta *(2)*
- [ ] `goto :main` antes de la primera etiqueta de `kivick.cmd` *(3.3)*

**Seguridad**

- [ ] Validar el nombre de usuario con `findstr` *(4.1)* ← **el bug original**
- [ ] Borrar `:read_secret` entera *(4.2)*
- [ ] `icacls` sobre el log recién creado *(4.3)*
- [ ] `require_admin` en las cinco operaciones *(4.4)*
- [ ] `fltmc` en lugar de `net session` *(4.5)*
- [ ] `:confirm` en `create_user` *(4.6)*

**Núcleo**

- [ ] `run_cmd`: recoger los argumentos sin depender de `%*` tras `shift` *(5.1)*
- [ ] Variante tipo `run_cmd_tty` para las opciones 1 y 4 *(5.2)*
- [ ] `log_event`: escribir el nivel de verdad *(5.3)*
- [ ] `kv_now`: `delims==`, una vez por sesión, sin `wmic` *(5.4)*
- [ ] Sustituir el `%s` de las plantillas *(5.5)*
- [ ] Escapar la marca `!CLAVE!` *(5.6)*
- [ ] `--help` termina el programa *(5.7)*
- [ ] Añadir `opos.dismfound` a los dos catálogos *(5.8)*
- [ ] `echo(` en todas las salidas de texto *(5.9)*

**Entrega**

- [ ] Versión `0.3.0` en CHANGELOG, rama y commit *(6.1)*
- [ ] Actualizar la estructura del README *(6.2)*
- [ ] No tocar `legacy/` *(6.3)*
- [ ] Comprobaciones de los `.cmd` en `tests/run_tests.sh` *(7)*
- [ ] Recorrer los siete criterios de §10 en una máquina Windows real

---

## 9. Una última cosa

Los fallos de este documento son casi todos de la **misma familia**: batch tiene un modelo de
ejecución distinto del de Bash, y el código está escrito traduciendo Bash línea a línea. El
`%-6s` de `printf`, el `source` que no existe, `%*` que ignora `shift`, la caída dentro de la
primera etiqueta, `!` que se evapora... son las trampas de §7 de la especificación, casi una por
una.

No es falta de criterio: las decisiones de diseño —qué comandos usar, delegar la contraseña en el
`*`, no tocar nunca el secreto— **están bien tomadas**, y esa es la parte difícil y la que sabes
tú mejor que nadie. Lo que falla es la mecánica del lenguaje.

Si algo de aquí no te cuadra o crees que me he equivocado, dímelo antes de reimplementarlo.
Prefiero discutirlo a que rehagas trabajo dos veces.
