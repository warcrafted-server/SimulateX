# SimulateX — estudio de mejoras post-v0.7 (29-09-2026)

Evaluación de las 6 propuestas del usuario + mejoras propias, contrastadas con
el código actual. Nada decidido: el usuario elige qué entra y en qué orden.

## Estado del código relevante (verificado)

- Puntuación lineal: `Σ peso × stat + DPS arma + huecos × socketValue`
  (`Addon/SimulateX/SimulateX.lua`, `ScoreItem` ~l.492). Pesos EP de wowsims,
  un valor marginal por stat, medido con el gear del preset de cada fase.
- Huecos de gema: valor medio fijo por build (`socketValue`,
  `metaSocketValue`); **ignora color y bonificación de ranura**.
- Sin tratamiento de caps (golpe, pericia, ArP) ni de bonificaciones de
  conjunto (tier 2p/4p): `grep` sin resultados.
- Comparador: gemas/encantamiento del link no cuentan (solo aviso, l.90).
- Presets de wowsims en local, `Tools/wowsimcli-src/ui/<clase>/gear_sets/*.gear.json`:
  por fase y spec traen objeto, **gemas por hueco** y encantamiento.
  `presets.ts` trae también **glifos**.
- Datos de clase: todos cargados en el `.toc` para cualquier personaje.
  Druida 5,5 MB, Chamán 3,7 MB, Sacerdote 2,7 MB…; con las 10 clases se
  estiman 30–40 MB de Lua cargados por todo jugador (cliente 32 bits).
- El `.toc` lista 5 `SimulateX_Data_<Clase>.lua` que aún no existen
  (Warrior, Rogue, Deathknight, Mage, Warlock): se crean al consolidar.
- Bug visible (captura del usuario): el texto de l.734 de `UI/Comparador.lua`
  ("Para este hueco solo hay % total…") se corta; falta ajuste de línea.
  La cabecera muestra `v0.6.0` aunque ya hay contenido de v0.7.

## Propuestas del usuario

| # | Propuesta | Encaje | Datos | Coste | Veredicto |
|---|---|---|---|---|---|
| 1 | Gemas ideales + bonificación de ranura | Núcleo | Estadísticas de gemas: `item_template` + `GemProperties.dbc`/`SpellItemEnchantment.dbc`. Referencia de elección: gemas de los presets | Medio | **Sí**. Por hueco: max(mejor gema del color + bonus/nº huecos, mejor gema pura). Meta: mejor meta del preset. Aplicar también a lo equipado (comparación justa) |
| 2 | Caps de golpe/pericia/ArP | Núcleo | API 3.3.5: `GetCombatRatingBonus(CR_HIT_*)`, `GetExpertise()`; talentos con golpe desde `ArbolTalentos` + rango aprendido | Medio | **Sí, a nivel 80**. Peso por tramos: completo hasta el cap, 0 por encima. Caps: 8 % melee, 17 % hechizo, pericia 26 (DPS) / 56 (tanque). ArP: solo tope duro 1400 con aviso; el soft cap con procs de abalorio no se modela sin inventar |
| 3 | Indicador BiS en tooltip | Núcleo | Presets de wowsims por fase: dato real, sin inventar | Bajo | **Sí**. Texto honesto: "En el set de referencia de wowsims (P3) para Puntería", no "BiS absoluto". Etiqueta de fase → contenido: preraid, P1 Naxx/EoE/OS, P2 Ulduar, P3 ToC, P4 ICC, P5 RS. Falta saber la fase activa en WarCrafted |
| 4 | Precio de venta, reparación, materiales | Fuera | El precio ya lo pone otro addon (captura). Reactivos de objetos no aprendidos: exige extraer `Spell.dbc` | Alto (materiales) | **No en SimulateX**. Como mucho, addon aparte |
| 5 | Receta "ya conocida" | Fuera | El cliente ya muestra "Ya aprendido" para el personaje actual; solo aporta valor para alts (guardar recetas al abrir la ventana de profesión) | Bajo-medio | **No en SimulateX**; addon aparte si interesa |
| 6 | Vender grises con lista blanca, reparar (propio/hermandad) | Fuera | `RepairAllItems(true)`, `CanGuildBankRepair()`, `GetGuildBankWithdrawMoney()`, `GetRepairAllCost()` | Bajo | **Addon aparte** (p. ej. `SimulateX_Utilidades` o independiente). Fácil, pero no tiene nada que ver con la simulación |

## Mejoras propias propuestas

| Id | Mejora | Por qué | Coste |
|---|---|---|---|
| M1 | Carga bajo demanda por clase (`LoadOnDemand`, un sub-addon por clase, `LoadAddOn` al entrar según `UnitClass`) | 30–40 MB de Lua para todos; tiempo de carga y memoria en cliente de 32 bits | Bajo-medio. **Prioritario antes de completar las 10 clases** |
| M2 | Lista de la compra (pilar 3 de `CLAUDE.md`, sin fase en el roadmap) | Mejor mejora por ranura, con origen (jefe/mazmorra, misión, vendedor) desde `creature_loot_template`, `npc_vendor`, recompensas de misión; incluye rango de nivel para quien sube | Alto. Candidata natural a v0.8/v0.9 |
| M3 | Marcar la mejor recompensa de misión (y, si ninguna mejora, la de más valor de venta) | Lo que más se usa al subir de nivel; el overlay de recompensa ya existe | Bajo |
| M4 | Bonificaciones de conjunto (tier 2p/4p) | Hoy una pieza de tier se infravalora | Alto: sin dato fiable por pieza; wowsims simula el bonus pero no lo da como EP. Estudiar aparte |
| M5 | Glifos recomendados en la pestaña Talentos | Dato real ya en `presets.ts`, trabajo casi nulo | Bajo |
| M6 | Inspeccionar bots de playerbots: comparar su equipo y proponer qué objeto de las bolsas darles | Propio de este servidor; ningún addon lo hace | Medio. `NotifyInspect` + `GetInventoryItemLink` sobre el bot |
| M7 | Mejor set de las bolsas por spec (doble especialización, `Equipment Manager`) | Al cambiar de spec, montar el mejor equipo disponible | Medio |
| M8 | Arreglos pequeños: ajuste de línea en `UI/Comparador.lua` l.734, versión de cabecera | Visible en la captura | Muy bajo |

## Orden recomendado

1. M8 + M1 (antes de consolidar las 5 clases que faltan).
2. v0.8 "precisión": #2 caps, #1 gemas (también en lo equipado), #3 BiS, M5 glifos.
3. v0.9: M2 lista de la compra (+ M3).
4. Luego: M6 bots, M7 sets. M4 solo si aparece fuente fiable.
5. #4, #5, #6: fuera de SimulateX.

## Preguntas abiertas para el usuario

- Fase de contenido activa en WarCrafted (para BiS y lista de la compra).
- ¿Utilidades de economía (#6) como addon aparte o se descartan?
- ¿Nivel 3 de talentos antes o después de la v0.8?
