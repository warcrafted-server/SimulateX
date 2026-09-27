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

**Alcance confirmado: solo PvE.** El motor de wowsims/wotlk no tiene modo de
simulación PvP (está diseñado exclusivamente para encuentros de raid/mazmorra PvE).
Investigar una alternativa para PvP queda como línea de trabajo separada, fuera de
este pipeline (ver sección "PvP — pendiente de investigación" al final).

Se usan directamente las 24 combinaciones de spec que el propio repo de wowsims
organiza en `ui/<spec>/gear_sets/`, cada una con su rol implícito:

```
balance_druid, feral_druid, feral_tank_druid, restoration_druid,
hunter (mm y sv comparten directorio),
rogue (assassination/combat/hemosub),
mage (arcane/fire/frost/ffb),
warlock (affliction/demodestro/destro),
warrior (arms/fury), protection_warrior,
holy_paladin, protection_paladin, retribution_paladin,
healing_priest (disc/holy), shadow_priest, smite_priest,
elemental_shaman, enhancement_shaman, restoration_shaman,
deathknight (blood/frost/uh), tank_deathknight
```

**Todas las fases disponibles, no solo la más alta.** Para cada spec se genera una
build de referencia por cada fase de contenido que tenga gearset propio (`preraid`,
`p1` … `p5`, según disponga esa spec — no todas llegan a P5). Motivo: un jugador
en progresión necesita saber qué mejora *para su punto de progresión actual*, no
solo el salto final a equipo end-game que aún no puede alcanzar. Esto multiplica el
número de builds de referencia (spec × fases disponibles, variable por spec, entre
5 y 7 cada una) pero es necesario para que el addon sea útil en cualquier momento
de la progresión del jugador, no solo al final.

Nomenclatura de fase de contenido 3.3.5a (para referencia): P1 = Naxxramas/Malygos/
Sartharion, P2 = Ulduar, P3 = Trial of the Crusader, P4 = Icecrown Citadel,
P5 = Rubí Santuario.

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

## Estado del lote completo de simulación (actualizar tras cada reinicio del servidor)

Lanzado en background con `nohup /tmp/simular_resto.sh > /tmp/simular_resto.log 2>&1 &`
(script no versionado, se genera con el bucle `for spec in ...`, ver
`Tools/simular_builds.py --spec <spec> --iterations 300`). Morirá con
cualquier reinicio del servidor — no hay forma de que sobreviva a un reinicio
real, solo hay que relanzarlo después.

Para retomar tras un reinicio: comprobar qué specs ya tienen resultados en
`Data/sims/<spec>/` (si tiene tantos ficheros .json como builds "ok" en
`Tools/builds/_mapeo/<spec>.json`, esa spec está completa) y relanzar el
bucle solo para las que falten. `simular_builds.py` no tiene lógica de
"reanudar"/saltar builds ya hechas dentro de una misma spec — si una spec
quedó a medias, hay que borrar su carpeta en `Data/sims/<spec>/` y volver a
lanzarla entera para esa spec.

Nota: algunas specs (ej. balance_druid) generan el triple de builds de lo
esperado por "variantes" de rotación sin filtro claro (ver sección de
ambigüedad de builds) — tardan proporcionalmente más, es esperado.

## Nota sobre el lote preliminar (2026-09-26)

Primer lote de datos generado con el catálogo de objetos aún incompleto
(descarga en curso durante la simulación) y pocas iteraciones (200, no las
2000 de wowsims por defecto) para tener el addon funcionando de extremo a
extremo rápido. Cubre solo hunter/mage/warrior. **Pendiente**: relanzar
`simular_builds.py` para las 20 specs con el catálogo de objetos completo
(1071 ids) y con iteraciones altas (2000+) para el dato final de producción;
el preliminar es válido para probar el addon, no para publicarlo como
definitivo.

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

2. **(Hecho)** Generar la matriz de builds de referencia de nivel 80:
   - `Tools/generar_builds.py` parsea los 21 ficheros `ui/<spec>/presets.ts` del
     código fuente clonado y extrae, sin transcripción manual, cada gearset con
     sus talentos y rotaciones (APL) candidatos → `Tools/builds/<spec>.json`.
   - `Tools/emparejar_builds.py` empareja cada gearset con su set de talentos y
     rotación correcto, por convención de nombre de fichero (ej. `p1_mm` →
     `MarksmanTalents`), con reglas en cascada: coincidencia exacta de sub-spec,
     luego por fase de contenido, luego única opción en toda la spec. Cuando hay
     más de una combinación igualmente válida (ej. dos estilos de runa en un
     Caballero de la Muerte Escarcha), se generan **todas** como builds de
     referencia distintas en vez de forzar una elección arbitraria — prioridad:
     máxima cobertura, cero pérdida de precisión.
   - Resultado: **429 builds de referencia** cubriendo 196 de los 197 gearsets
     detectados (queda fuera solo `warlock/swp`, un preset anecdótico sin fase
     de contenido asociada, "Straight Outa SWP").
   - Salida en `Tools/builds/_mapeo/<spec>.json` (no versionado, es intermedio
     de generación): cada entrada indica `gear_file`, `talent_set`, `apl`,
     `phase`, `faction` y si es una `variante` de un gearset con varias
     combinaciones válidas.

3. **(Hecho)** Generar y validar el `RaidSimRequest` completo por spec (no solo
   el gearset: también talentos, consumibles y opciones de spec como munición/
   tótems/sellos, que en wowsims viven en TypeScript con enums, no en JSON
   parseable con regex de forma fiable):
   - `Tools/generar_extractores_go.py` copia, para cada una de las 20 specs
     (paquete Go, no 21: `warrior` y `deathknight` comparten paquete Go entre
     varias sub-specs), el bloque `CharacterSuiteConfig{...}` de su `_test.go`
     oficial a un nuevo fichero `zzz_gen_extractor_test.go` **en el mismo
     paquete** (mismo directorio, mismo `package X`), evitando así reimportar
     o retraducir a mano los identificadores de talentos/consumibles/opciones
     de spec — se resuelven directamente porque son del mismo paquete Go.
   - El test generado llama `generator.GetTest(generator.NumTests() - 1)` (el
     subtest "Average": el `RaidSimRequest` base con opciones de simulación
     completas) y vuelca el resultado a `input.json` en ese mismo directorio.
   - Validado ejecutando `go test -tags with_db -run TestGenExtractor
     ./sim/<paquete>/...` + `wowsimcli sim` para las 20 specs: **17/20 dan
     DPS/HPS reales coherentes** (hunter ~6402, mage ~11069, warlock ~15180,
     deathknight dps ~11017, healing_priest ~3821 HPS, tanques con DPS de
     amenaza 2000-3600, etc.). Las 3 restantes (holy_paladin,
     restoration_druid, restoration_shaman) dan 0 por una limitación real del
     propio wowsims, no de este pipeline (ver sección siguiente).
   - Estos ficheros Go generados y sus `input.json` viven dentro de
     `Tools/wowsimcli-src/` (ya excluido completo de git); no se versionan.
2. Definir la matriz de builds de referencia (`Tools/builds/*.json`) — requiere
   revisar los presets de talentos/gear que ya trae wowsims por clase/spec para no
   inventar builds poco realistas.
3. Implementar `simular_builds.py`: generación de `RaidSimRequest`, invocación de
   `wowsimcli`, guardado de resultados crudos.
4. Implementar `generar_db_addon.py`: consolidación a los `.lua` finales por clase.
5. Ejecutar el pipeline completo para un subconjunto pequeño (1-2 clases) como prueba
   de extremo a extremo antes de lanzarlo para las 10 clases completas.
6. Integrar la lectura de estos datos en `SimulateX.lua` (hook de tooltip).

## Limitación descubierta: base de datos de objetos incompleta para algunos gearsets

La base de datos de objetos incluida en el repo (`assets/database/db.bin`)
puede no contener todos los ítems que referencian los propios gearsets del
mismo repo — confirmado con el gearset `preraid` de Sacerdote Smite (ítem
43792, `panic: No item with id`). Parece más frecuente en gearsets `preraid`
(equipo más antiguo/heirloom). No es un fallo de este pipeline: es un
desajuste interno del propio proyecto wowsims entre su base de datos y sus
presets de gearset.

**Implicación de diseño para `simular_builds.py`:** debe tratar el fallo de
una build individual (proceso `wowsimcli` que termina con panic/código de
error) como un dato ausente para esa build concreta, seguir con el resto del
lote, y registrar qué builds fallaron y por qué — nunca debe abortar el
proceso completo por el fallo de una sola build.

## Specs de sanador: había un bug de compilación Go y además la limitación de wowsims

Actualización posterior (2026-09-27): con el bug de compilación arreglado,
`restoration_druid` y `holy_paladin` simulan pero dan 0 HPS en todo (rotación
vacía en wowsims), así que la limitación original también era real. Solución
en `.agents/plans/datos-completos-v0.4/` (decisión 3: pesos `epWeights` de
`sim.ts`). Lo de abajo describe solo el bug de compilación.

Se había concluido antes que **holy_paladin, restoration_druid,
restoration_shaman** daban 0.0 por un placeholder vacío de `DefaultRotation`
en wowsims — conclusión incorrecta, nunca se llegó a ejecutar la simulación
real. El fallo real (confirmado 2026-09-27) era de compilación Go en
`generar_extractores_go.py`: cuando el `_test.go` original de la spec no usa
el patrón `Rotation: core.GetAplRotation(aplDir, aplFile)` (holy_paladin y
restoration_druid usan `core.RotationCombo{...}` en su lugar), `ROTATION_FIELD_RE`
no matcheaba y las variables `aplDir`/`aplFile` quedaban declaradas sin usar
en el `zzz_gen_extractor_test.go` generado — Go no compila con variables
declaradas y no usadas, así que `go test` fallaba antes de generar ningún
`RaidSimRequest` (de ahí el log `ERROR: fallo generando RaidSimRequest base
(0 objetos)`, no un 0.0 de DPS/HPS real).

**Fix aplicado:** en `generar_extractores_go.py`, tras leer `aplDir`/`aplFile`
de las variables de entorno, se añade `_, _ = aplDir, aplFile` para
descartarlas explícitamente cuando la spec no las use vía `GetAplRotation`.
Regenerados los 21 ficheros con `python3 Tools/generar_extractores_go.py`.
Confirmado que `restoration_druid` compila tras el fix.

**(Hecho 2026-09-27, tras reinicio del servidor)** `restoration_druid` ya
está simulada completa con el fix (5/5 fases OK). `holy_paladin` se borró
(sus datos previos eran del bug) y se relanzó junto al resto de specs
pendientes en `/tmp/simular_resto2.sh` (no versionado, mismo patrón que el
lote anterior): holy_paladin, healing_priest, shadow_priest, smite_priest,
elemental_shaman, enhancement_shaman, restoration_shaman, hunter, mage,
rogue, warlock, warrior, protection_warrior, deathknight, tank_deathknight.
Pendiente comprobar si `restoration_shaman` tiene el mismo patrón de bug
(usa `core.RotationCombo{}` en vez de `GetAplRotation`) — el fix ya está
aplicado de forma general en `generar_extractores_go.py`, así que si el
patrón es el mismo debería resolverse solo al llegarle el turno en el lote.

## Nivel 80 vs niveles bajos — alcance de wowsims

wowsims/wotlk solo tiene gearsets/talentos/rotaciones para nivel 80 (fases de
contenido de raid P1-P5). No existe ningún dato de simulación para niveles 1-79
(mazmorras normales, misiones, leveleo).

**Decisión: para niveles 1-79 no se simula, se usa una aproximación honesta tipo
GearScore.** Se investigó y confirmó que ningún addon de comparación de equipo
(Pawn, GearScore, AtlasLoot, Cymry) usa simulación de combate fuera de end-game;
todos degeneran a `ilvl × modificador de slot × multiplicador de rareza` +
prioridad de estadística principal por clase/spec.

**(Hecho, implementado para feral_druid)**: en vez de scrapear db.warcrafted.com
para descubrir objetos de nivel bajo (AoWoW no expone un listado/búsqueda vía
export XML/JSON, solo consulta por ID conocido), se usa acceso de solo lectura
(usuario MySQL con permiso `SELECT` únicamente sobre `acore_world`, credenciales
nunca escritas en el repo, solo como variables de entorno en el momento de
ejecutar) a la tabla `item_template` del propio servidor. Da datos ya
estructurados (stats en columnas, no HTML a parsear): `Tools/extraer_objetos_bd.py`
extrae objetos por rango de `RequiredLevel`, `Tools/calcular_score_bajo_nivel.py`
calcula el score ponderado por spec, aplicando el mismo filtro de compatibilidad
armadura↔clase que en nivel 80 (ver limitación de armadura más abajo).
Extraídos 15308 objetos de nivel 1-79; 7963 compatibles con Feral Druida.

El addon muestra el resultado de nivel bajo como diferencia frente al objeto ya
equipado en el mismo slot (`GetInventoryItemLink`), marcado explícitamente como
"(estimado)" en el tooltip, para no aparentar la misma precisión que el dato de
nivel 80. Pendiente extender a las 19 specs restantes (la fórmula es genérica,
solo falta añadir sus pesos de estadística a `STAT_WEIGHTS_BY_SPEC`).

## PvP — investigado, enfoque distinto al de PvE

wowsims/wotlk no simula PvP. Se investigó si existía una vía de calidad equivalente
a la de PvE y la conclusión es que no la hay:

- Existe un fork comunitario no oficial ("WoWSims 3.3.5 Backport", de Poli93/
  Jarjkeqt, específico para servidores Warmane) con lógica PvP experimental
  (resiliencia, tabla de ataque PvP, stuns). No está mantenido por el proyecto
  oficial, su cobertura de clases no está confirmada y su continuidad depende de
  un solo colaborador externo — no es una base fiable para construir sobre ella.
- No existe otro simulador de combate PvP de calidad para 3.3.5a (SimulationCraft
  es retail-only).

**Decisión: PvP se resuelve con stat weights ordinales de la comunidad, no con
simulación.** Fuente: guías PvP de Icy Veins específicas de WotLK Classic, por
clase/spec, que dan una prioridad de estadísticas clara (Resiliencia primero, con
soft-cap ~1400-1414 según clase, seguida de Aguante/Penetración de armadura/
Crítico/Celeridad según rol). Es una aproximación lineal — el mismo tipo de
solución que se descartó para PvE por falta de precisión — pero aquí es la mejor
opción realista dado que no hay motor de simulación PvP maduro disponible. El
addon debe dejar claro en la UI que el dato PvP es una estimación por prioridad de
estadísticas, no una simulación de combate, a diferencia del dato PvE.

Esto es una línea de trabajo separada del pipeline PvE (que ya tiene datos
simulables con precisión) y se puede implementar en paralelo sin bloquear nada.

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
