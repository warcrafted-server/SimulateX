# SimulateX v0.11 — plan de mejoras

Repo: `/home/stark/Repos/addons/SimulateX`. Parte de la v0.10 hecha (pestaña
Mejoras, `Tools/generar_origenes.py`, sub-addon `SimulateX_Origenes`).
Reglas de trabajo: `CLAUDE.md` del repo y
`.agents/plans/estado-proyecto-2026-09-29/estado-proyecto-2026-09-29.PENDIENTES.md`
(commit por cambio sin preguntar, push solo si el usuario lo pide, validar Lua
con luaparser y probar lógica con lupa, ver Pruebas).

Orden: primero lo que necesita Opus alto; al acabar, avisar al usuario para
bajar de modelo.

## Fases

| # | Mejora | Modelo |
|---|--------|--------|
| A | Profesiones como origen en Mejoras (generador + UI + opciones) | Opus alto |
| B | Golpe de talentos del jugador en los topes | Opus alto |
| C | Gemas ideales con el golpe/pericia que le falta al jugador | Opus alto |
| D | Reliquias (ídolos, tótems, libros, sigilos) en tooltip, comparador y Mejoras | Opus medio |
| E | Sufijos aleatorios en Mejoras (mejor sufijo posible para la spec) | Opus medio |
| F | Bolsas de recompensa (`item_loot_template`) como origen | Opus medio |
| G | Nombres de mazmorra/banda en esES si el cliente los trae | Opus medio |
| H | Documentación: README v0.8-v0.11, versión 0.11.0 en `.toc` y `rutas_addon.VERSION` | Sonnet |

## Hechos verificados (29-09-2026)

**A. Profesiones**
- `Spell.dbc` (core `DBCStructure.h::SpellEntry`): `Effect` 71-73,
  `EffectItemType` 107-109, `SpellName` 136-151. `SPELL_EFFECT_CREATE_ITEM` = 24.
- `SkillLineAbility.dbc`: 1 SkillLine, 2 Spell, 7 MinSkillLineRank,
  9 AcquireMethod, 10/11 TrivialSkillLineRankHigh/Low.
- Profesiones de equipo: 164 Herrería, 165 Peletería, 197 Sastrería,
  202 Ingeniería, 755 Joyería, 773 Inscripción. Nombre en el cliente:
  `GetSpellInfo(<hechizo de la profesión>)`, nunca traducido a mano.
- Recetas: `item_template` class 9 con `spellid_2` = hechizo de fabricar (2035).
  Instructores: `trainer_spell` (TrainerId, SpellId, MoneyCost, ReqSkillLine,
  ReqSkillRank, ReqLevel) + `creature_default_trainer`.
- Origen nuevo `p<hechizo>:<skillLine>:<habilidad>:<receta|0>`. El origen de
  la receta (vendedor, botín, misión) sale de las mismas funciones de
  `generar_origenes.py`, guardado aparte por id de receta.
- UI: "Profesión: <nombre> (<habilidad>) · instructor" o "· receta de <origen>".
  Opciones: incluir profesiones (sí), solo mis profesiones (no; lee
  `GetSkillLineInfo`).

**B. Golpe de talentos**: hecho. `Tools/generar_golpe_talentos.py` →
`Addon/SimulateX/Data/SimulateX_GolpeTalentos.lua` (auras 54, 55, 199 y 107 con
SPELLMOD 16 sobre uno mismo). Motor: `max(0, nonGear − preset) + jugador`.

**C. Gemas y topes**: hecho sin regenerar datos de clase. `Tools/generar_gemas.py`
→ `Addon/SimulateX/Data/SimulateX_Gemas.lua` (mismo filtro que `ideal_gems`,
stats en claves ITEM_MOD); `GemValues` en el motor elige por color con los pesos
reales y los de tope según le falte al jugador. `build.gems` queda de respaldo.

**D. Reliquias**
- `build.items` ya trae reliquias (p. ej. 50456, 50454 en Druida). Falta
  `INVTYPE_RELIC = { "RangedSlot" }` en `INVTYPE_TO_SLOTS` y el grupo en Mejoras.
  Clases: druida, chamán, paladín, DK.

**E. Sufijos**: `item_enchantment_template` (entry, ench, chance); 3467 objetos
equipables con `RandomProperty`/`RandomSuffix`.

**F. Bolsas**: 823 objetos equipables en 80 contenedores de `item_loot_template`.

**G. Nombres de zona e instancia**: hecho. `Tools/extraer_dbc_cliente.py` lee
`Map.dbc`/`AreaTable.dbc` de los MPQ esES del cliente (esES en el campo 11/17);
zona de cada PNJ por posición con `WorldMapArea.dbc` (+ `DungeonMap.dbc` para
Dalaran).

## Pruebas

`Tools/probar_mejoras_lupa.py <Clase> <nivel> <Alliance|Horde>` (lupa): carga el
addon con la API de WoW simulada (sin equipo, `UnitStat` = 60, nada en caché) y
lista las mejoras por hueco. Venv con luaparser y lupa: crear en el scratchpad
(`python3 -m venv <scratch>/venv && <scratch>/venv/bin/pip install luaparser lupa`).
