# SimulateX v0.12 — valorar las reliquias (ídolos, tótems, libramientos, sigilos)

Repo: `/home/stark/Repos/addons/SimulateX`. Decidido por el usuario el 2026-10-07: simular cada reliquia.

## Hechos verificados
- Las reliquias (`item_template.InventoryType = 28`, class 4, subclass 7 libram / 8 idol / 9 totem / 10 sigil) **no tienen estadísticas** (`stat_value1 = 0`); su efecto es un hechizo (`spellid_1`). Con pesos EP valdrían 0.
- Hueco real: `RangedSlot` (proto `ItemSlot_ItemSlotRanged`). BD: 261 reliquias, 109 con nivel requerido 80.
- wowsims las implementa por id con `core.NewItemEffect(<id>, ...)` en `Tools/wowsimcli-src/sim/{druid,shaman,paladin,deathknight}/items.go`. Solo las que tienen efecto simulado cambian el resultado (~10 Druida, 7 Chamán, 13 Paladín, varios sigilos de DK). Las demás: valor desconocido.
- En el código del addon «reliquias» también nombra los objetos heredados (`AddScalingStats`): no confundir.
- Mapa actual: `INVTYPE_TO_SLOTS` (`SimulateX.lua` ~706) no tiene `INVTYPE_RELIC`; `SLOT_GROUPS` (`UI/Mejoras.lua` ~16) tampoco.

## Diseño
Valor de una reliquia = % de DPS sobre la misma build **sin reliquia**, simulado con la build de referencia de la spec (`simular_talentos.pick_reference_build`) cambiando solo el objeto de `RangedSlot`. Solo specs DPS (tanques y sanadores quedan fuera, como en Nivel 3). Una reliquia sin efecto simulado no se puntúa ni se propone (el tooltip no inventa un valor).

## Pasos
1. `Tools/simular_reliquias.py --spec <spec>`: detecta los ids con efecto en el simulador, simula cada uno + línea base sin reliquia, 5000 it., semilla fija, reanudable en `Data/reliquias/<spec>.json` (ignorado por git). **(delegable, esfuerzo alto)**
2. Lanzar el lote para las specs DPS de Druida, Chamán, Paladín y DK (`nice`, uno a la vez, antes del reinicio de las 04:00). **(lo hace la sesión principal)**
3. `Tools/generar_db_reliquias.py`: vuelca a `Addon/SimulateX_<Clase>/Data/SimulateX_Reliquias_<Clase>.lua` (id → % por spec) y lo lista en el `.toc` de la clase (`rutas_addon.ensure_class_addon_toc`). **(delegable)**
4. Addon: `INVTYPE_RELIC` → `RangedSlot`; evaluación de reliquia con esa tabla en tooltip y comparador (contra la equipada); grupo en `SLOT_GROUPS` de Mejoras; opción de configuración; sin dato → sin valor. **(delegable, esfuerzo medio, probar con `Tools/probar_mejoras_lupa.py`)**
5. Docs: README (es/en), CHANGELOG, versión 0.12.0 (`rutas_addon.VERSION` y `.toc`), `CLAUDE.md` y `TODO.md`. Si cambia el `.toc`, avisar: reiniciar el cliente completo.

Estado: hecho el 2026-10-07 (pasos 1-5, versión 0.12.0).
