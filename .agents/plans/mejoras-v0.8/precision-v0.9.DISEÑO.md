# SimulateX v0.9 — diseño de precisión (caps, gemas, BiS, bonus de conjunto)

Diseño antes de tocar código, según el plan (`mejoras-v0.8.PLAN.md`, bloque
4). Repo: `/home/stark/Repos/addons/SimulateX`.

## 1. Caps de golpe/pericia (nivel 80 solo)

**Datos ya disponibles**: ninguno nuevo hace falta del lado de extracción.
La API del cliente 3.3.5a da directamente el valor actual del jugador:
- Golpe melee: `GetCombatRatingBonus(CR_HIT_MELEE)` (índice 16) → % ya
  aplicado, o `GetHitModifier()` si existe en esta build del cliente
  (confirmar en el juego; usar `GetCombatRatingBonus` como base segura).
- Golpe a distancia: `CR_HIT_RANGED` (17).
- Golpe de hechizo: `CR_HIT_SPELL` (18).
- Pericia: `GetExpertise()` devuelve el valor ya convertido a "puntos de
  expertise" (no rating), comparar contra el cap en puntos, no en rating.

**Talentos que dan golpe fijo**: hay que sumarlos al % ya mostrado por la
API (que solo cuenta equipo, no talentos con bonus plano de golpe). Fuente:
`SimulateX_ArbolTalentos_<Clase>.lua` ya tiene fila/columna/rango de cada
talento; falta identificar cuáles dan golpe y su cantidad. **Sin datos
DBC de "este talento da X% de golpe"**: habría que leerlo del texto del
hechizo o mantenerlo a mano por clase, con riesgo de inventar. Decisión:
**diferir esto** a una iteración posterior; v0.9 solo usa
`GetCombatRatingBonus`/`GetExpertise`, que YA incluye el bonus de talentos
que el juego aplica como parte del rating final (confirmar: en WotLK,
`GetCombatRatingBonus` refleja el rating tras talentos con
`SPELL_AURA_MOD_RATING`, pero no los que dan % de golpe plano vía
`SPELL_AURA_MOD_SPELL_HIT_CHANCE`/similar — este segundo tipo si existe
en algún talento no se reflejaría). Documentar la limitación en vez de
adivinar.

**Caps** (nivel 80, DBC/reglas conocidas de 3.3.5a, no inventadas):
- Golpe melee/distancia: 8 %.
- Golpe hechizo: 17 % (con Encantamiento arcano u otros bonus de
  reducción de nivel de boss ya asumidos igual que hace wowsims).
- Pericia: 26 puntos (elimina glancing blows en un boss de nivel 83), 56
  para eliminar dodge también (relevante para tanques con Maza contundente
  o talento de "no se puede esquivar").
- Penetración de armadura: sin cap real por rating (escala hasta 100% de
  reducción con suficiente ArP + debuffs), pero el hard cap de referencia
  de wowsims es 1400 de rating (ahí el marginal cae mucho salvo debuffs de
  raid). Solo un **aviso**, no un tramo a cero.

**Cómo afecta a la puntuación**: el peso de golpe/pericia de la build
(`weights.ITEM_MOD_HIT_RATING_SHORT`, etc.) se pone a 0 en
`GetWeightsAtLevel` (SimulateX.lua) cuando `level == 80` y
`GetEffectivePlayerHitPercent(role) + ítem nuevo > cap`. Necesita
recalcular "cuánto golpe ya tengo" cada vez que se abre el comparador o se
pinta un tooltip (cachear por combate/reload, invalidar en
`PLAYER_EQUIPMENT_CHANGED` como ya hace el resto del addon).
**Por debajo de nivel 80: sin caps** (el jugador no ha llegado al cap
posible a ese nivel, y el propio motor de nivel bajo ya es una
estimación).

## 2. Gemas ideales + bonificación de ranura

**Datos ya disponibles y verificados**:
- `Tools/wowsimcli-src/assets/database/db.json` → `gems`: 366 gemas, cada
  una con `id`, `color`, `stats` (vector de 35 posiciones, mismo índice que
  `Tools/mapeo_stats.py::STAT_TO_ITEM_MOD`), `phase`, `quality`.
  `Tools/simular_builds.py::load_gem_colors()` ya lee esta fuente para el
  color; falta extraer también `stats`.
- `item_template.socketBonus` (BD del servidor): id de
  `SpellItemEnchantment`, mismo mecanismo que un encantamiento de objeto.
  `Tools/generar_estadisticas_objeto.py::enchant_stats()` ya resuelve un
  `SpellItemEnchantment` a `[(clave, cantidad)]`; falta aplicarlo a
  `socketBonus` (hoy `item_entry()` solo guarda los colores de hueco, no
  el bonus).

**Nuevo fichero de datos**: `Addon/SimulateX/Data/SimulateX_Gemas.lua`
(común a las 10 clases, como `SimulateX_ItemStats.lua`; no depende de
clase). Formato comprimido igual que `SimulateX_ItemStats.lua`
(`[id]="color;a=X,b=Y"`), generado por un script nuevo
`Tools/generar_gemas.py` que lee `wowsimcli-src/assets/database/db.json`.

**Extender `Tools/generar_estadisticas_objeto.py`**: añadir `sb=<key>=<val>,...`
a `item_entry()` cuando el objeto tiene `socketBonus` y colores de hueco
(sin bonus no compensa nunca ignorar el color por razones ajenas al
cálculo, así que sin socketBonus no hace falta el campo).

**Cálculo en el addon** (`SimulateX.lua`, extensión de `ScoreItemBreakdown`):
por cada hueco vacío de una pieza candidata:
1. Mejor gema de ese color exacto, según los pesos de la build activa
   (`Σ peso_stat × stats_gema`, mismo tipo de cálculo que ya hace
   `ScoreItem` para el resto).
2. Mejor gema "pura" (sin restricción de color) ignorando ese hueco.
3. Si respetar TODOS los colores completa el bonus: comparar
   `Σ(mejor gema de color) + bonus/nºhuecos` contra `Σ(mejor gema pura)`,
   elegir el máximo total sumando todos los huecos a la vez (no hueco a
   hueco, porque el bonus solo se activa con la combinación completa).
   Con más de 2 huecos por pieza esto es enumeración simple (máximo 3
   huecos reales en WotLK), no combinatoria pesada.
4. Igual se aplica al objeto YA equipado en el comparador (hoy no cuenta
   sus gemas: bug ya detectado en la sesión anterior, se corrige aquí).

**No se implementa**: elegir la gema real y aplicarla (fuera del alcance
de un addon: eso lo hace el jugador en el joyero). El resultado es solo
para puntuar.

## 3. Indicador BiS

**Fuente real**: `Tools/wowsimcli-src/ui/<spec>/gear_sets/*.gear.json`, ya
en local, uno por fase (`p1`...`p5`, `preraid`). Mapeo fase → item ya
existe indirectamente vía `Tools/builds/<spec>.json::gear_presets` (mismo
gear_file que ya usa `simular_builds.py`).

**Nuevo dato por build**: en `SimulateX_Data_<Clase>.lua`, cada build YA
tiene `items` (mapa itemId → deltas de esa build). Añadir un flag
`isBis = true` a la entrada del objeto cuando ese itemId aparece en el
gear_set de esa fase/spec exacta (generado en
`Tools/generar_db_addon.py::build_entry`, leyendo el `.gear.json` de la
build en curso, que el pipeline ya carga para calcular pesos).

**Tooltip**: nueva línea "BiS <fases> para <spec>" cuando el objeto es BiS
en 1+ build de la spec activa. Agrupar fases contiguas de la misma spec
en una sola línea (p. ej. "BiS P3-P4 para Puntería"), nunca "BiS
absoluto" sin matizar la fuente.

**Opción de fase activa** (pedida por el usuario, para
`mod-individual-progression`, hoy desactivado en IceTracks pero
"probable en un segundo reino"): selector en el panel
(`SimulateXOptions.lua`) con las fases de la clase activa + "Todas"
(por defecto). Si se fija una fase, el tooltip/BiS solo considera esa
fase y las anteriores (no tiene sentido marcar BiS de contenido no
accesible). Guardar en `SimulateX_DB.maxPhase` (string tipo `"p3"` o
`nil` = todas).

## 4. Aviso de bonus de conjunto roto

**Datos**: `item_template.itemset` (id de `ItemSet.dbc`) ya en la BD del
servidor, no extraído todavía. `ItemSet.dbc` da: número de piezas
necesarias para cada bonus (2/4/6/8) y el/los `spellId` de cada bonus (no
hace falta resolverlos a texto: `GetSpellInfo(spellId)` ya da el nombre
en el cliente, igual que talentos/glifos).

**Nuevo campo en `SimulateX_ItemStats.lua`**: `si=<itemset_id>` en
`item_entry()` cuando `itemset != 0` (extraído de `item_template`, ya
disponible en `Data/items_bd.json` si se añade la columna a
`extraer_objetos_bd.py`, o consulta aparte).

**Nuevo fichero**: `SimulateX_ItemSets.lua` (común): por cada
`itemset_id`, lista de `itemId` que pertenecen al set y qué piezas activan
cada bonus (de `ItemSet.dbc`: hasta 10 `itemID` + hasta 8
`(threshold, spellId)`).

**Lógica en el comparador**: al evaluar un cambio de pieza (A vs
equipado), si la pieza equipada pertenece a un set con un bonus
actualmente activo (contar piezas equipadas del mismo `itemset_id`) y la
pieza nueva NO pertenece al mismo set, comprobar si el cambio baja el
recuento por debajo de un umbral de bonus. Si es así: aviso en rojo
"Rompe el bonus de N piezas de <nombre del set>" (nombre del set: no lo
tenemos guardado, usar `GetSpellInfo` sobre el `spellId` del bonus como
referencia, o el nombre del propio `ItemSet.dbc` si el WDBC lo trae como
string — verificar antes de escribir el extractor). **Sin valorar el
bonus en la puntuación** (acordado: solo aviso, no EP).

## Orden de implementación sugerido

1. Caps de golpe/pericia (autocontenido, sin datos nuevos que extraer).
2. Gemas + bonificación de ranura (dato nuevo pero ya localizado).
3. BiS (reutiliza gear_sets ya en local, cambio pequeño en el pipeline).
4. Bonus de conjunto (el que más depende de verificar cómo da el nombre
   `ItemSet.dbc`; si no lo da, aviso genérico sin nombre del set).

## Preguntas que quedan para cuando se implemente

- Confirmar en el juego real si `GetCombatRatingBonus` ya refleja el
  bonus de talentos con rating (probable) o haría falta sumar algo más.
- Verificar si `ItemSet.dbc` trae un campo de nombre localizado en
  esES, o si solo tiene el `spellId` del bonus para identificarlo.
