# SimulateX — plan de v0.7 (resto) a v0.10

Decisiones del usuario (29-09-2026) sobre `mejoras-v0.8.INVESTIGACION.md`.
Repo: `/home/stark/Repos/addons/SimulateX`. Addon en `Addon/SimulateX/`.

## Reglas transversales

- **Todo configurable**: cada función nueva lleva opción en el panel
  (`SimulateXOptions.lua`) para activar/desactivar y ajustar parámetros;
  valores en `SimulateX_DB` (SavedVariables), con valor por defecto.
- Datos solo reales (DBC/BD del servidor, presets de wowsims); nunca inventados.
- Cada cambio actualiza `README.md`, `README.en.md`, `CHANGELOG.md`, `CLAUDE.md`.
- Git: commit/push solo cuando el usuario lo pida (`CLAUDE.md`). Excepción
  acordada: datos v0.4 de una clase completada → consolidar + commit + push.
- Modelo por bloque: anunciarlo y pausar antes de empezar cada bloque; el
  usuario cambia de modelo.
- Pruebas: mocks de Lua solo detectan errores de ejecución; la prueba real
  la hace el usuario en el juego (layout, API real).
- Reinicio del servidor a las 04:00: todo proceso largo debe ser reanudable.

## Bloque 2 — Arreglos + carga por clase (Sonnet, esfuerzo medio)

1. `UI/Comparador.lua` ~l.734: el texto "Para este hueco solo hay % total…"
   se corta. Darle ancho fijo con dos anclajes y ajuste de línea
   (`SetWordWrap(true)`, altura suficiente o `SetHeight` según texto).
2. Cabecera de la ventana: versión leída con
   `GetAddOnMetadata("SimulateX", "Version")`, no fija en código.
3. Carga bajo demanda por clase:
   - Un sub-addon por clase `SimulateX_<Clase>/` (hermano de
     `Addon/SimulateX/`) con `.toc`: `## LoadOnDemand: 1`,
     `## Dependencies: SimulateX`, y sus ficheros
     `SimulateX_Data_<Clase>.lua`, `SimulateX_Talentos_<Clase>.lua`,
     `SimulateX_ArbolTalentos_<Clase>.lua` (+ glifos, bloque 3).
   - `SimulateX.lua` llama `LoadAddOn("SimulateX_" .. classFile)` al
     cargar (clase de `UnitClass("player")`), antes de usar los datos.
   - Antes de mover nada, comprobar con `grep` si algún código usa datos de
     una clase distinta a la del jugador (tooltip, comparador, talentos); si
     lo hay, decidir con el usuario.
   - Ajustar rutas de salida de `Tools/generar_db_addon.py`,
     `generar_db_talentos.py`, `generar_arbol_talentos.py`.
   - Actualizar instrucciones de instalación del README (ahora son varias
     carpetas) y cualquier empaquetado existente.
   - El `.toc` principal deja de listar los datos por clase.
4. Medir antes/después: `UpdateAddOnMemoryUsage()` /
   `GetAddOnMemoryUsage("SimulateX")` (el usuario lo mira en el juego).

## Bloque 3 — Utilidades + recompensa + glifos (Sonnet, esfuerzo medio)

Cada punto con su opción en el panel.

1. **Vender grises** (`MERCHANT_SHOW`): recorrer bolsas, calidad 0
   (`GetItemInfo`), `UseContainerItem`; saltar la lista blanca. Lista
   blanca en `SimulateX_DB`, editable en el panel y con atajo de clic
   modificado sobre el objeto en la bolsa (elegir uno que no choque con
   Mayús+clic, ya usado por el comparador). Mensaje en chat con lo ganado
   (opcional).
2. **Reparar** (`MERCHANT_SHOW`, `CanMerchantRepair()`,
   `GetRepairAllCost()`). Opción de modo: desactivado / fondos propios /
   hermandad y si no propios / solo hermandad. Hermandad solo si
   `IsInGuild()`, `CanGuildBankRepair()` y
   `GetGuildBankWithdrawMoney()` (−1 = sin límite) cubre el coste:
   `RepairAllItems(1)`; propios: `RepairAllItems()`. Mensaje con el coste.
3. **Precio de venta en tooltip**: `GetItemInfo` (valor 11, precio de
   venta); en bolsas, multiplicar por la pila. `GetCoinTextureString`.
   Activado por defecto, desactivable.
4. **Mejor recompensa de misión** (`QUEST_COMPLETE`, `GetNumQuestChoices`,
   `GetQuestItemLink("choice", i)`): marcar la mejor para la spec activa
   reutilizando el overlay de recompensa de v0.2; si ninguna mejora,
   marcar la de mayor precio de venta con otra marca (moneda).
5. **Glifos**: extraer de `Tools/wowsimcli-src/ui/<clase>/presets.ts`
   (bloques `Glyphs.create({major1…, minor…})`) y resolver cada nombre de
   enum a su id de objeto con los `.proto` de wowsims. Script nuevo en
   `Tools/`, salida al sub-addon de la clase. Mostrar en la pestaña
   Talentos junto a la distribución elegida (icono + nombre, tooltip del
   objeto). Si un preset no trae glifos, no mostrar nada.

## Bloque 4 — Precisión v0.9 (Opus, esfuerzo alto)

Diseñar en `mejoras-v0.8/precision-v0.9.DISEÑO.md` antes de código.
Alcance fijado:
- Caps a nivel 80: golpe melee 8 %, hechizo 17 %, pericia 26 (DPS) /
  56 (tanque). Golpe/pericia actual del jugador desde la API
  (`GetCombatRatingBonus`, `GetExpertise`) + talentos con golpe
  (`ArbolTalentos` + rango aprendido). Peso por tramos: completo hasta el
  cap, 0 encima. Por debajo de 80, sin caps.
- ArP: solo aviso al llegar a 1400; no modelar soft cap (sin dato fiable).
- Gemas: estadísticas desde `item_template` + `GemProperties.dbc` /
  `SpellItemEnchantment.dbc`; referencia de gemas por spec/fase en
  `gear_sets/*.gear.json`. Por hueco: max(mejor gema del color +
  bonus/nº huecos, mejor gema pura). Aplicar igual al objeto equipado.
- BiS: objetos de `gear_sets/*.gear.json` por spec y fase. Tooltip:
  "BiS P3 y P4 para Puntería" (fases donde aparece). Opción de fase
  activa en configuración (por defecto: todas), para reinos con
  `mod-individual-progression` (hoy desactivado en IceTracks).
- Bonus de conjunto: aviso cuando equipar el objeto rompería un bonus de
  2/4 piezas activo (conjuntos desde `ItemSet.dbc` / `item_template.itemset`).
  Sin valorarlo en la puntuación.

## Bloque 5 — Talentos Nivel 3 (Opus, esfuerzo alto)

Diseñar antes de código (espacio de búsqueda, poda, criterio de parada,
coste en simulaciones), reanudable tras las 04:00 como
`simular_talentos.py`. Empieza por Druida (datos completos ya); después
cada clase en cuanto termine su simulación de equipo. Contexto previo:
`.agents/plans/estado-proyecto-2026-09-29/` y `Tools/NOTAS_TALENTOS_NIVEL2.md`.

## Bloque 6 — Lista de la compra v0.10 (Opus medio diseño, Sonnet implementación)

Mejor mejora por ranura para la spec activa, con origen desde la BD del
servidor (`creature_loot_template`, `npc_vendor`, recompensas de misión) y
filtro por nivel para quien sube. Diseño y requisitos antes de código.

## Paralelo: cola de simulación v0.4

`Tools/lote_simulaciones.sh` (en marcha). Al terminar cada clase:
`python3 Tools/generar_db_addon.py --clase <Clase>` en segundo plano, commit
+ push. Tras el bloque 2 la salida va al sub-addon de la clase.
