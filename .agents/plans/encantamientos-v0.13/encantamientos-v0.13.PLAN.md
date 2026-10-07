# SimulateX v0.13 — encantamientos recomendados por hueco

Repo `/home/stark/Repos/addons/SimulateX`. Mejora nº 1 del `TODO.md`; el usuario pidió seguir con las mejoras propuestas (2026-10-07) sin poder probar en juego, así que todo se valida con el arnés lupa.

## Hechos verificados
- `Tools/wowsimcli-src/assets/database/db.json` → `enchants` (225): `effectId` (id de `SpellItemEnchantment`, el que va en el enlace del objeto), `spellId`, `name` (inglés), `type` (hueco, enum `ItemType` de `proto/common.proto`), `stats` (índice de `STAT_TO_ITEM_MOD`, igual que gemas), `quality`, `requiredProfession` (34 de 225). Muchos encantamientos con efecto (proc) no traen estadísticas: no se puntúan.
- El enlace de objeto del cliente lleva el `effectId` del encantamiento actual en su segundo campo (`item:id:encantamiento:...`).
- Nombres esES: `GetSpellInfo(spellId)` del cliente, nunca traducidos a mano (como las profesiones).
- Modelo a copiar: `Tools/generar_gemas.py` (→ `Data/SimulateX_Gemas.lua`) y `GemValues`/`IdealColoredSocketsValue` en `SimulateX.lua`.

## Diseño
Valor de un encantamiento = suma de sus estadísticas × pesos reales del jugador (con los topes de golpe/pericia como en las gemas). Para cada hueco equipado se compara el encantamiento puesto con el mejor disponible para la spec activa; si el mejor gana más que el umbral de ruido, se propone en la pestaña Mejoras (grupo «Encantamientos») con el % de mejora y el requisito (profesión y habilidad, o «pergamino»). Sin estadísticas simuladas → sin valor, nunca se inventa.

## Pasos
1. `Tools/generar_encantamientos.py` → `Addon/SimulateX/Data/SimulateX_Encantamientos.lua` (+ `.toc`): por hueco, lista de `{ effect, spell, stats = {ITEM_MOD…}, prof, skill }`, solo los válidos en 3.3.5a. **(delegable)**
2. Addon: valorar y proponer en Mejoras, casilla en el panel, comprobar con lupa. **(delegable, esfuerzo alto)**
3. Docs, versión 0.13.0, TODO.
