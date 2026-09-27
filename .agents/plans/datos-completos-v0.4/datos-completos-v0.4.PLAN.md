# Datos completos, todas las clases (v0.4) — PLAN

Objetivo: datos correctos y completos para las 10 clases y 21 specs,
niveles 1-80, solo objetos que el personaje puede equipar, y flechas +
tooltip funcionando a cualquier nivel. **Orden: Druida completo primero
(Feral DPS antes que nada, es el personaje de pruebas del usuario, nivel 25),
luego el resto de clases.** Contexto de errores:
`.agents/plans/auditoria-v0.3/auditoria-v0.3.REVIEW.md`. Pipeline previo:
`.agents/plans/simulacion-wowsims/simulacion-wowsims.PLAN.md`.

Todo `Data/sims/` actual está sesgado (E1) y se regenera. El lote antiguo
(`/tmp/simular_resto*.sh`) está parado y no se relanza.

## Decisiones de diseño (cerradas, no reabrir)

1. **Puntuación en tiempo real con pesos (EP) en el addon**, leyendo las
   estadísticas del objeto con `GetItemStats(link, tabla)` (existe en 3.3.5a;
   confirmado en RatingBuster, Interface 30300). Sustituye a `lowLevelScores`
   (se elimina). Cubre cualquier objeto, incluidos sufijos aleatorios.
2. **Pesos por spec y build calculados con wowsims** (`core.StatWeights`, no
   expuesto en el CLI: se llama desde un test Go generado, mismo patrón que
   `zzz_gen_extractor_test.go`). Nada de pesos a mano.
3. **Excepción, specs de sanador sin rotación en wowsims**: `restoration_druid`
   y `holy_paladin` simulan con 0 HPS (rotación vacía en wowsims, comprobado:
   0 de 302 deltas ≠ 0). Comprobar `restoration_shaman` igual (base_hps = 0).
   Para ellas: sin simulación por objeto; pesos = `epWeights` por defecto de
   `ui/<spec>/sim.ts` (son de wowsims, no inventados), siempre "estimado". No
   gastar CPU simulándolas.
4. **Escalado por nivel con las tablas reales del juego**: DBC del servidor
   `gtCombatRatings.dbc`, `gtChanceToMeleeCrit.dbc`, `gtChanceToSpellCrit.dbc`
   (solo lectura, env `SIMX_DBC_DIR`, ej.
   `/home/stark/Servers/acore-playerbots/data/dbc`). Verificado: crit melee
   45.91 índice/1 % a nivel 80 y 4.58 a 25; druida 83.33 agi/1 % crit a 80 y
   15.85 a 25 (coincide con RatingBuster en juego).
5. **Nivel 80: delta exacto simulado** cuando el objeto está en el catálogo
   simulado de la build; si no, EP. Una comparación nunca mezcla exacto y EP.
6. **Se compara contra lo equipado**, no contra el BiS de referencia.
7. **Usabilidad en el addon = lo que el juego pinta en rojo** en el tooltip
   (tipo de armadura/arma, "Clases:", habilidad no aprendida), leído con un
   tooltip oculto. Independiente del idioma y del nivel (cubre malla antes de
   40, etc.). El requisito de nivel se trata aparte (dato sí, flecha no).
8. **Catálogo de simulación a 80 solo con el tipo de armadura principal** de
   la clase (más capas, cuello, anillos, abalorios, armas, reliquias). El resto
   queda cubierto por EP.
9. **Clave de spec en el addon = spec wowsims + árbol**, no solo árbol:
   `smite_priest` y la variante disciplina de `healing_priest` comparten árbol
   y hoy se pisan en `GetBestBuildPerSpec`.

## Tabla de usabilidad por clase (catálogo de nivel 80)

`Tools/usabilidad_clase.py`. Subclases de `item_template`. Armadura: 0 varios,
1 tela, 2 cuero, 3 malla, 4 placas, 6 escudo, 7 tratado, 8 ídolo, 9 tótem,
10 sigilo. Armas: 0/1 hacha 1M/2M, 2 arco, 3 arma de fuego, 4/5 maza 1M/2M,
6 arma de asta, 7/8 espada 1M/2M, 10 bastón, 13 puño, 15 daga, 16
arrojadiza, 18 ballesta, 19 varita. Además `AllowableClass` = -1 o con el
bit de la clase. En caso de duda, incluir: solo cuesta tiempo de simulación.

| Clase (bit) | Armadura | Armas | Otros |
|---|---|---|---|
| Guerrero (1) | 4, 6 | 0,1,2,3,4,5,6,7,8,10,13,15,16,18 | |
| Paladín (2) | 4, 6 | 0,1,4,5,6,7,8 | 7 tratado, sostener |
| Cazador (4) | 3 | 0,1,2,3,6,7,8,10,13,15,16,18 | |
| Pícaro (8) | 2 | 0,2,3,4,7,13,15,16,18 | |
| Sacerdote (16) | 1 | 4,10,15,19 | sostener |
| DK (32) | 4 | 0,1,4,5,6,7,8 | 10 sigilo |
| Chamán (64) | 3, 6 | 0,1,4,5,10,13,15 | 9 tótem, sostener |
| Mago (128) | 1 | 7,10,15,19 | sostener |
| Brujo (256) | 1 | 7,10,15,19 | sostener |
| Druida (1024) | 2 | 4,5,6,10,13,15 | 8 ídolo, sostener |

Capas (armadura subclase 1, InventoryType 16) valen para todas: hoy el filtro
de nivel bajo las excluye por ser "tela" (solo 7 de 886 puntuadas para
druida), fallo que desaparece con este diseño.

## Formato de datos de cada build en `SimulateX_Data_<Clase>.lua`

```lua
["feral_druid_p1"] = {
  spec = "feral_druid", role = "dps", phase = 1, specLabel = "...", talentTree = 1,
  avgItemLevel = 213.4,
  base = { dps = 5123.4, hps = 0, tps = 0, dtps = 0 },
  weights = { ITEM_MOD_AGILITY_SHORT = 1.52, ... },   -- métrica/punto a nivel 80
  weightsKind = "sim",              -- "sim" o "preset" (decisión 3)
  critComponent = { melee = x, spell = y },
  socketValue = 12.3, metaSocketValue = 20.1,
  items = { [40473] = { dps = -1.2, dpsOH = nil, hps = 0, tps = 0, dtps = 0 }, ... },
},
```
`SimulateX_Levels.lua` (nuevo, compartido): índice por 1 % por nivel y agi/int
por 1 % de crit por clase y nivel.

## Pasos

Cada paso termina en un punto de control: mostrar resultados al usuario y
**parar antes de cualquier commit/push** (pedir confirmación explícita).
Los pasos 1-6 se construyen genéricos para todas las clases, pero se
ejecutan y validan primero con `feral_druid`.

### 1. Gemas y encantamientos al sustituir (arregla E1) — `Tools/simular_builds.py`
- Extraer de `item_template` también `Quality, socketColor_1..3,
  socketBonus, armor, dmg_min1, dmg_max1, delay` (ampliar
  `extraer_objetos_bd.py`; credenciales solo por env `SIMX_DB_*`, solo SELECT).
- `swap_item_in_gear`: conservar `enchant` del slot base; rellenar cada hueco
  del candidato: color 1 (meta) → gema meta del gearset base; resto → "gema
  principal" = gema no-meta más frecuente del gearset base. Cinturón: si el
  base tiene más gemas que huecos (hebilla), añadir una principal. Se ignora
  la bonificación de ranura (igual que Pawn por defecto).
- Simular también cada objeto del propio gearset base con esta regla (hace de
  "equipado" en el addon).
- **Doble empuñadura** (pícaro, chamán mejora, guerrero furia incl. Titan's
  Grip, DK escarcha): si el gearset base tiene arma en mano izquierda, simular
  las armas candidatas también en ese slot y guardar `dpsOH`.
- Extraer `tps` y `dtps` del resultado, no solo dps/hps.
- **Validación por spec**: ≥ 90 % de objetos base con |delta| < 0.5 % de la
  métrica base. Si falla, parar y revisar antes de seguir.

### 2. Catálogo completo de nivel 80 (arregla E7)
- Nueva consulta (opción de `extraer_objetos_bd.py`, salida
  `Data/catalogo_80.json`): `RequiredLevel = 80`, `Quality IN (3,4)`,
  `ItemLevel >= 180`, `InventoryType != 0`.
- Filtro por clase con la tabla de arriba (`usabilidad_clase.py`).
- `simular_builds.py` lee candidatos de este catálogo (margen ±20 ilvl).
  Objetos que no existen en la BD de wowsims se omiten y se cuentan.
- Antes de lanzar cada spec: imprimir nº de candidatos por build y medir una
  simulación. Iteraciones 1000 si la spec cabe en ~6 h, si no 500. Semilla
  fija (ya lo está: 101).

### 3. Pesos por build — `Tools/generar_extractores_go.py`
- Generar `TestGenStatWeights`: `StatWeightsRequest` con el mismo
  jugador/buffs/encuentro que el extractor, `stats_to_weigh` y
  `ep_reference_stat` leídos de `ui/<spec>/sim.ts` (`epStats`,
  `epReferenceStat`; parsear, no transcribir), 5000 iteraciones (env
  `SIMX_SW_ITERATIONS`), volcar `core.StatWeights(...)` a JSON.
- Guardar pesos **brutos** (métrica por punto) de dps, hps, tps y dtps.
- Specs de la decisión 3: leer `epWeights` de `sim.ts` en su lugar
  (`weightsKind = "preset"`).
- Mapear `Stat` de wowsims → claves de `GetItemStats`: primarias →
  `ITEM_MOD_*_SHORT`; crítico, golpe y celeridad del objeto cuentan para
  melee, distancia y hechizo: peso = suma de los que existan; pericia,
  penetración de armadura, poder de ataque (y a distancia para cazador),
  poder con hechizos, mp5, defensa, esquivar, parar, bloqueo, valor de
  bloqueo, armadura (`RESISTANCE0_NAME`). Comprobar en `proto/common.proto`
  si existe `FeralAttackPower`; si no, el PA feral del arma usa el peso de
  PA. Constantes de PA feral desde DPS de arma: buscarlas en wowsims
  (`grep -rn "54.8"`), no suponerlas. DPS de arma para el resto de clases:
  lo recoge la simulación exacta a 80; en EP, peso del DPS de arma solo si
  wowsims lo incluye en `epStats`/pseudo-stats (`pseudo_stats_to_weigh`).
- Valor de hueco: EP de la gema principal y de la meta del paso 1, con las
  estadísticas de gema de la BD de wowsims (`assets/database`), no a mano.

### 4. Tablas por nivel — `Tools/generar_tablas_nivel.py` (nuevo)
- WDBC: cabecera `<4s4I` (firma, registros, campos, tamaño registro, bloque
  de cadenas), un float por registro. `gtCombatRatings`: fila = (CR_lua − 1)
  × 100 + (nivel − 1). `gtChanceTo*Crit`: (clase − 1) × 100 + (nivel − 1),
  valor = fracción de crit por punto.
- Salida `Addon/SimulateX/Data/SimulateX_Levels.lua` con los CR usados y
  agi/int por 1 % de crit para las 10 clases.
- Comprobaciones a 80: crit 45.91, golpe melee 32.79, celeridad 32.79,
  penetración ≈ 13.99; druida 83.33 agi/1 % crit.

### 5. Consolidación — `Tools/generar_db_addon.py`
- Emitir el formato de arriba para cada clase con datos. Eliminar
  `lowLevelScores`, `calcular_score_bajo_nivel.py` y
  `Data/scores_bajo_nivel_*.json`.
- `critComponent`: w_critPct = w_critRating × índicePor1%(80), melee y
  hechizo; el addon lo usa para reescalar agilidad/intelecto.
- Añadir `SimulateX_Levels.lua` al `.toc` antes de los datos de clase.

### 6. Addon — `SimulateX.lua` (mantener los hooks existentes, ya verificados)
- **Usabilidad**: `GameTooltip` oculto (`GameTooltipTemplate`,
  `SetOwner(WorldFrame, "ANCHOR_NONE")`, `SetHyperlink`), revisar líneas
  izquierda y derecha: rojo = `RED_FONT_COLOR` (1, 0.125, 0.125) con
  tolerancia. Línea que encaja con `ITEM_MIN_LEVEL` → bloqueado solo por
  nivel. Caché por link; vaciar en `PLAYER_LEVEL_UP`, `SKILL_LINES_CHANGED`.
- **Build por spec** (clave = decisión 9): a nivel 80, la de `avgItemLevel`
  más cercana por debajo de la media equipada + 10 (2M cuenta doble; sin
  camisa/tabardo); si ninguna, la de fase más baja. Por debajo de 80, la de
  fase más baja.
- **Pesos a nivel L**: índices: w(L) = w80 × índicePor1%(80) / índicePor1%(L).
  Agilidad: w_agi(L) = w_agi80 − critPct_melee/agiPor1%(80) +
  critPct_melee/agiPor1%(L); intelecto igual con crit de hechizo. Resto igual.
  `weightsKind = "preset"`: mismos ajustes, sin datos exactos.
- **Puntuación** = Σ peso × stat + huecos × valor de hueco.
- **Ganancia vs equipado**: anillos/abalorios contra el peor de los dos; 2M
  contra MP+MI; 1M con 2M equipada contra la 2M; doble empuñadura: arma 1M
  contra MP (`dps`) y contra MI (`dpsOH`), la mejor; slot vacío = puntuación
  completa. A 80 con ambos en `items`: delta(candidato) − delta(equipado).
- **%**: a 80 con `weightsKind = "sim"`, sobre `base`; si no, sobre la suma de
  puntuación del equipo actual.
- **Ruido**: exacto con |ganancia| < 0.3 % → "≈ igual".
- **Flecha**: verde si mejora la spec activa, naranja si solo otra; nunca si
  no es usable, ni bloqueado por nivel, ni "≈ igual".
- **Tooltip**:
  ```
  SimulateX · Feral (tu spec)       +3.2 %  (+142 DPS)   simulado
    vs. Guantes del Colmillo
    Otras: Equilibrio −0.4 %, Restauración +1.1 % HPS
  ```
  Tanque: "Supervivencia" (dtps, menor es mejor) y "Amenaza" (tps). Sin
  simulación exacta: etiqueta "estimado" y unidad "pts".
- **Refresco**: `PLAYER_EQUIPMENT_CHANGED`, `PLAYER_LEVEL_UP`,
  `PLAYER_TALENT_UPDATE` → vaciar caché y redibujar bolsas abiertas.
- Vendedor y banco: localizar los hooks en el FrameXML 3.3.5a
  (`git clone https://github.com/wowgaming/3.3.5-interface-files`) antes de
  usarlos; no suponer nombres.
- **Depuración**: `/simulatex debug` + link → claves de `GetItemStats`,
  usabilidad y puntuación por spec. `/simulatex nivel 80` fuerza la lógica
  de nivel 80 para probar sin un 80 (solo la sesión).
- Panel v0.3: mantener; la opción de nivel bajo pasa a "mostrar datos
  estimados".
- Actualizar el roadmap de `CLAUDE.md` (v0.4 datos, v0.5 comparación real,
  v0.6 comparador, v0.7 talentos); por la regla de docs de gobierno, pasar
  antes por `/compact-docs-writer`.

### 7. Ejecución (Druida primero)
1. `feral_druid`: pasos 1-6 completos → el usuario prueba en juego (nivel 25
   con EP; nivel 80 con `/simulatex nivel 80`). No seguir hasta su visto bueno.
2. `balance_druid`, `feral_tank_druid` (simulados); `restoration_druid`
   (preset). `.toc` 0.4.0 + CHANGELOG. Commit con permiso.
3. Resto, un lote en segundo plano (`nohup`, log en `/tmp/`), en este orden:
   paladín (holy preset, protection, retribution), sacerdote (healing_priest,
   shadow, smite), chamán (elemental, enhancement, restoration: comprobar si
   es preset), cazador, mago, pícaro, brujo, guerrero (dps, protection), DK
   (dps, tank). Validación del paso 1 por spec en el log; las que fallen se
   apartan y se revisan sin parar el resto.
4. Regenerar datos del addon por clase conforme terminen; commit por clase
   con permiso.

## A verificar en juego (con `/simulatex debug`)
- Claves reales de `GetItemStats` para DPS de arma y PA feral.
- Que los objetos con sufijo aleatorio devuelven las estadísticas del sufijo.
- Que la detección de rojo funciona con el pecho de malla del bug de v0.2.

## Modelo por paso
- 1, 2, 3 y 6: Sonnet, esfuerzo alto (corrección sutil).
- 4, 5 y 7: Sonnet, esfuerzo medio.
- Simulaciones: sin modelo (scripts en segundo plano).
