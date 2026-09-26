# Plan: Pipeline de simulación WowSims para SimulateX

## Contexto

SimulateX es un addon para WoW 3.3.5a (esES) que muestra en el tooltip de un objeto
cuánto mejora (o empeora) el rendimiento del jugador si se lo equipa: DPS para roles
de daño, HPS para sanadores, y una métrica de supervivencia/mitigación para tanques.

El cálculo real no puede hacerse en el cliente del juego (Lua no puede simular un
combate completo con rotación de habilidades). Se genera **offline, una sola vez por
versión de contenido**, un fichero de datos con los resultados ya calculados, que el
addon simplemente lee en tiempo de juego. El addon nunca hace peticiones de red.

Motor de simulación: **wowsims/wotlk** (https://github.com/wowsims/wotlk), motor Go de
código abierto (MIT) que ya simula con precisión rotaciones, talentos y encuentros de
WotLK 3.3.5a. No se reimplementa la simulación: se compila su CLI (`wowsimcli`) y se
invoca como subproceso local desde scripts en `Tools/`.

## Decisiones de arquitectura

### 1. Nivel de precisión: simulación real, no pesos lineales aproximados

Se descartan los "stat weights" (pesos lineales por estadística) como única fuente de
datos: son razonables para DPS pero no son fiables para tanking (mitigación no lineal)
ni para healing (eficiencia de maná, prioridad de hechizos). En su lugar, cada objeto
candidato se simula de forma diferencial: `DPS/HPS/TMI(build + objeto en su slot) -
DPS/HPS/TMI(build base)`. Esto da un delta real y específico de esa build, no una
aproximación genérica.

### 2. Matriz de builds de referencia

Se simula cada combinación de:

- **Clase** (10): Guerrero, Paladín, Cazador, Pícaro, Sacerdote, Chamán, Mago, Brujo,
  Druida, Caballero de la Muerte.
- **Árbol de talentos principal** relevante para cada rol de esa clase (no todas las
  combinaciones posibles de talentos, solo los árboles "estándar" reconocidos por la
  comunidad para 3.3.5a — wowsims ya trae presets de talentos por spec en su UI, se
  reutilizan esos).
- **Rol**: DPS, Heal, Tank — solo para las combinaciones clase/árbol que ese rol permite
  (p. ej. Guerrero Armas = DPS, Guerrero Protección = Tank; Sacerdote Disciplina/Sagrado
  = Heal, Sacerdote Sombras = DPS).
- **Contexto**: PvE y PvP por separado (encuentro/objetivo de simulación distinto:
  PvE usa un dummy de raid tipo boss de referencia; PvP usa el modo de simulación
  PvP/arena que expone wowsims si está disponible para esa clase, o un encuentro de
  daño sostenido de referencia si no).

Total aproximado: ~30-35 combinaciones clase/árbol/rol × 2 contextos (PvE/PvP) ≈
60-70 "builds de referencia". Cada build de referencia tiene un gearset base
representativo de su fase de contenido (BiS típico reconocido por la comunidad; se
puede tomar directamente de los presets/ejemplos que trae el propio repo de wowsims
en `ui/<class>/presets.ts` o similar).

### 3. Selección de objetos candidatos por build

Para cada build de referencia, no se simulan todos los objetos del juego, solo los
relevantes: mismo slot de equipo que algo en el gearset base, y restricción de clase/
armadura/arma compatible con esa build (filtrable con los datos ya extraídos de
db.warcrafted.com, que incluyen clase permitida y tipo de objeto). Esto reduce el
volumen de miles a unos cientos de objetos candidatos por build.

### 4. Pipeline de scripts (todo en `Tools/`, todo offline)

```
Tools/
├── extraer_objetos.py       (ya existe) → Data/items/<id>.xml
├── wowsimcli/                (binario compilado de wowsims/wotlk, no versionado)
├── compilar_wowsimcli.sh     (nuevo) clona/compila wowsims/wotlk → Tools/wowsimcli/
├── definir_builds.py         (nuevo) matriz de builds de referencia (clase/árbol/rol/
│                              contexto) + su gearset base, como datos versionados
│                              en Tools/builds/*.json (NO son datos extraídos, son
│                              configuración del proyecto — sí se versionan)
├── simular_builds.py         (nuevo) por cada build × objeto candidato, genera el
│                              RaidSimRequest JSON, invoca wowsimcli, guarda resultado
│                              crudo → Data/sims/<build_id>/<item_id>.json
└── generar_db_addon.py       (nuevo) consolida Data/sims/**/*.json en los ficheros
                               finales que carga el addon
```

### 5. Formato y partición del fichero final para el addon

Dado que se acepta un tamaño de hasta varios MB, se prioriza tenerlo todo (no recortar
cobertura), partiendo en varios ficheros Lua para no cargar de golpe lo que no haga
falta:

```
Addon/SimulateX/Data/
├── SimulateX_Data_Warrior.lua
├── SimulateX_Data_Paladin.lua
├── ... (uno por clase, 10 ficheros)
```

Cada fichero contiene, por clase, todas sus builds (árbol/rol/contexto) y para cada
build la tabla `{ [item_id] = { dps = ..., hps = ..., tmi = ... } }` con solo los
campos aplicables al rol. El `.toc` los declara todos, pero Lua solo consume memoria
real cuando se accede a las tablas (no hay coste de parseo adicional relevante para
ficheros de este tamaño en el cliente).

Estimación de tamaño: ~65 builds × ~300 objetos candidato × 3 números ≈ decenas de
miles de entradas → fichero total probablemente en el rango de 1-5 MB en Lua. Se
mide con el primer lote real antes de confirmar que no hace falta recortar.

### 6. Qué se versiona en git y qué no

- **Sí se versiona**: `Tools/*.py`, `Tools/*.sh`, `Tools/builds/*.json` (definición de
  la matriz de builds, es configuración del proyecto, no datos extraídos ni secretos).
- **No se versiona** (ya cubierto por `.gitignore` existente): `Data/` (volcados
  crudos de extracción y simulación), `Tools/wowsimcli` (binario compilado).
- Los ficheros finales `Addon/SimulateX/Data/*.lua` **sí se versionan** — son el
  producto final que necesita el addon para funcionar en el cliente de otro jugador
  que descargue el addon desde GitHub.

## Pasos de ejecución

1. **(Hecho)** Compilar `wowsimcli`: clonado `wowsims/wotlk` en `Tools/wowsimcli-src/`
   (no versionado). Pasos exactos:
   - Generar el código proto: `protoc -I=./proto --go_out=./sim/core ./proto/*.proto`
     (requiere el plugin `protoc-gen-go`, instalable con
     `go install google.golang.org/protobuf/cmd/protoc-gen-go@latest`).
   - Compilar el CLI **con el tag `with_db`**, imprescindible o la base de datos de
     objetos queda vacía y la simulación falla con `panic: No item with id: ...`:
     `go build -tags with_db -o ../wowsimcli ./cmd/wowsimcli`.
   - La base de datos de objetos (`assets/database/db.bin`) ya viene incluida en el
     repo clonado; no hace falta generarla ni extraerla aparte para simular.
   - Validado con una build real (Cazador Supervivencia, gearset `p1_sv`, 2000
     iteraciones): resultado coherente (~7611 DPS de media, con distribución e
     intervalo realistas), confirmando que el pipeline `RaidSimRequest` JSON →
     `wowsimcli sim` → `RaidSimResult` JSON funciona de extremo a extremo.
2. Definir la matriz de builds de referencia (`Tools/builds/*.json`) — requiere
   revisar los presets de talentos/gear que ya trae wowsims por clase/spec para no
   inventar builds poco realistas.
3. Implementar `simular_builds.py`: generación de `RaidSimRequest`, invocación de
   `wowsimcli`, guardado de resultados crudos.
4. Implementar `generar_db_addon.py`: consolidación a los `.lua` finales por clase.
5. Ejecutar el pipeline completo para un subconjunto pequeño (1-2 clases) como prueba
   de extremo a extremo antes de lanzarlo para las 10 clases completas.
6. Integrar la lectura de estos datos en `SimulateX.lua` (hook de tooltip).

## Referencias técnicas (de investigación previa, confirmadas contra el repo)

- CLI: `cmd/wowsimcli/`, subcomando relevante `basic_sim.go` (lee `input.json`, escribe
  resultado con `--outfile`).
- Esquema de entrada/salida: `proto/api.proto` — `RaidSimRequest` → `RaidSimResult`
  (JSON vía protojson, tolerante a campos desconocidos).
- Función Go equivalente si se prefiriera vendorizar en vez de invocar binario:
  `core.RunRaidSim(request)` en `sim/core`.
- Build local: `make` (genera proto), `make wowsimwotlk` (binario standalone), o
  build directo del CLI con `go build ./cmd/wowsimcli`.
- Licencia MIT: requiere solo mantener aviso de copyright y, como cortesía pedida
  por el propio README, un enlace visible al proyecto original desde SimulateX
  (se añadirá en el README de SimulateX).
