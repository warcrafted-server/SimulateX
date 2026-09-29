# SimulateX v0.10 — Lista de la compra (diseño)

Bloque 6 de `mejoras-v0.8.PLAN.md`. Repo: `/home/stark/Repos/addons/SimulateX`.
Objetivo: por cada hueco, las mejores mejoras para la spec activa y dónde
conseguirlas (jefe, vendedor, misión), también mientras se sube de nivel.

## Hechos verificados en acore_world (29-09-2026, usuario accesodb)

- Botín: `creature_loot_template` 93.648 filas, `gameobject_loot_template`
  17.964, `reference_loot_template` 24.104. El botín de banda va por
  referencias anidadas (ej. objeto 50073 → referencia 34248 →
  `creature_loot_template.entry` 38401): resolver recursivamente.
- La entrada de botín suele ser la de la dificultad (38401 = "Prince Valanar
  (1)", sin nombre esES): subir a la criatura base vía
  `creature_template.difficulty_entry_1..3` para nombre esES
  (`creature_template_locale`, 23.052 filas) y dificultad (10/25, normal/heroico).
- Vendedores: `npc_vendor` 37.897 filas; coste en emblemas por
  `ExtendedCost` → `ItemExtendedCost.dbc`.
- Misiones: `quest_template` (3.778 con recompensa de objeto),
  `quest_template_locale` esES 9.458.
- `Map.dbc` del servidor solo tiene nombres en inglés: no se muestran nombres
  de mazmorra/banda (mezclaría idiomas); el jefe y la dificultad bastan.

## Datos

- Sub-addon común `SimulateX_Origenes` (LoadOnDemand, se carga al abrir la
  pestaña): por objeto equipable, nivel requerido, tipo de inventario y
  orígenes compactos: jefe (id → nombre esES, dificultad, probabilidad),
  vendedor (nombre esES, coste en oro o emblemas), misión (nombre esES,
  nivel, facción por `AllowableRaces`).
- Generador nuevo `Tools/generar_origenes.py` (solo lectura con accesodb y
  DBC del servidor).

## Addon

- Pestaña nueva "Mejoras" en la ventana del comparador: una fila por hueco
  con las N mejores mejoras (N configurable, por defecto 3) para la spec
  activa, con % y origen. Reutiliza `GetItemEvaluations` (mismo motor que el
  tooltip: topes, gemas, niveles).
- Candidatos: nivel 80 → catálogo simulado de la build (`build.items`);
  por debajo → objetos con nivel requerido entre nivel − 5 y nivel + 2.
- Opciones: activar la pestaña, N por hueco, incluir heroico/25, incluir
  vendedores y misiones, ocultar objetos de la otra facción.

## Preguntas abiertas

- Botín de criaturas normales (no jefes): ¿incluir o solo jefes y cofres?
  Propuesta: solo jefes (`rank` ≥ 3 o `ScriptName` de jefe) y cofres, para no
  llenar la lista de drops de mundo al 0,01 %.
