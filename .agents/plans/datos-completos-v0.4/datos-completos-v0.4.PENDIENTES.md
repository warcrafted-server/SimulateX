# Datos completos v0.4 — PENDIENTES (traspaso a sesión nueva)

Plan: `datos-completos-v0.4.PLAN.md` (mismo directorio). Auditoría de errores E1-E8:
`.agents/plans/auditoria-v0.3/auditoria-v0.3.REVIEW.md`. Pasos 1-6 hechos y pusheados
(últimos commits en `master`: `ee03215`, `6c45465`, `961acae`, `06292b2`, `b7addc8`,
`1f834bb`). F1/F3 corregidos, probados en juego y ya en `master`. `.toc` en 0.4.0.

**Estado exacto (2026-09-28 13:10): paso 7.2 de datos COMPLETO.**
- Las 4 specs de druida están simuladas correctamente y consolidadas:
  `feral_druid` (10/10 builds), `balance_druid` (21/21), `feral_tank_druid` (4/4),
  `restoration_druid` (5/5), todas `status: ok`. `SimulateX_Data_Druid.lua` regenerado
  con `generar_db_addon.py` (sin `--spec`): 40 builds, verificado por spec. De paso
  también regeneró `SimulateX_Data_Paladin.lua` y creó `SimulateX_Data_Priest.lua`
  (datos válidos de sesiones anteriores, el usuario decidió dejarlos en el mismo cambio).
- README.md/README.en.md tienen la línea de "Datos Reales por Especialización y Nivel";
  CHANGELOG.md tiene la entrada `## v0.4.0 - 2026-09-28`. **Nada de esto tiene commit
  todavía** — pedir permiso explícito antes de commit + push.
- **Dos bugs encontrados y corregidos esta sesión en el pipeline de simulación**:
  1. Bug de build_id (builds con mismo `gear_file` y distinto APL se pisaban el mismo
     fichero) — fix ya documentado abajo, aplicado en `simular_builds.py` y
     `generar_db_addon.py` el 2026-09-27.
  2. **Bug nuevo en la validación de objetos base** (`simular_builds.py::main`, línea
     ~444): reconstruía el nombre del fichero temporal `_base.json` con
     `build['gear_file']` a secas, sin el sufijo de APL, mientras que `simulate_build`
     sí lo escribía con sufijo → `FileNotFoundError` en cualquier build con colisión de
     `gear_file` (afectó a `feral_druid` y `balance_druid` al relanzarlas). Fix: usar
     `result['build_id']` (ya con el sufijo correcto) en vez de reconstruirlo. Sin este
     fix, cualquier spec con variantes de APL reales por gear_file fallará igual al
     re-simular (ojo con el resto de clases en el paso 7.3).
  3. Los relanzamientos dejaron ficheros viejos sin sufijo mezclados con los nuevos en
     `Data/sims/feral_druid/` y `Data/sims/balance_druid/` (restos de antes del fix de
     build_id) — se borraron a mano tras confirmar la fecha (27 = viejo, 28 = nuevo).
     Si se re-simula cualquier otra spec afectada por el mismo bug, revisar y limpiar
     `Data/sims/<spec>/` de la misma forma antes de consolidar.
- **Mejora en `generar_db_addon.py`**: ahora imprime `*** AVISO: [spec] 0/N builds
  consolidados ***` cuando una spec entera se queda fuera del `.lua` regenerado (así se
  detectó el bug de build_id en `feral_druid`/`balance_druid` la segunda vez, en vez de
  pasar desapercibido entre las líneas de log).
- **Reanudación en `simular_builds.py`** (2026-09-28, por el reinicio diario del
  servidor a las 04:00): antes de simular cada build, comprueba si
  `Data/sims/<spec>/<build_id>.json` ya existe con `status: ok` y lo salta si es así.
  Relanzar el mismo comando tras una interrupción retoma justo donde se quedó, sin
  volver a gastar CPU en lo ya hecho. `--force` repite todo desde cero si hace falta.
- **Sin hacer todavía**: commit + push (pedir permiso primero); pruebas en juego de
  Equilibrio/Guardián/Restauración.

## Entorno

- BD: `source ~/.simx_env` (vars `SIMX_DB_*`, usuario `simulatex`, solo SELECT sobre
  `acore_world` de **producción**; el usuario lo autorizó).
- DBC: `SIMX_DBC_DIR=/home/stark/Servers/acore-playerbots/data/dbc` (solo lectura; leer
  fuera de `~/Repos/addons` requiere permiso explícito cada vez, también `acore-playerbots/src`).
- Regenerar, en orden (desde `Tools/`):
  1. `python3 extraer_objetos_bd.py --max-level 80` → `Data/items_bd.json`
  2. `python3 extraer_objetos_bd.py --catalogo-80` → `Data/catalogo_80.json` (por clase)
  3. `python3 generar_extractores_go.py` → `zzz_gen_extractor_test.go` + `zzz_gen_stat_weights_test.go` por spec
  4. `python3 simular_builds.py --spec X [--limit-items N --iterations N]` → `Data/sims/<spec>/<build>.json` (catálogo completo = horas)
  5. `SIMX_DBC_DIR=... python3 generar_tablas_nivel.py` → `Addon/.../SimulateX_Levels.lua`
  6. `python3 generar_db_addon.py --spec X` → `Addon/.../SimulateX_Data_<Clase>.lua` (~20 min feral: 5 builds × TestGenStatWeights 5000 it.)
  7. `python3 generar_tipos_objeto.py` → `Addon/.../SimulateX_ItemTypes.lua` (tras regenerar `items_bd.json`)
  8. `SIMX_DBC_DIR=... python3 generar_estadisticas_objeto.py` → `Addon/.../SimulateX_ItemStats.lua` (tras regenerar `items_bd.json`)
- Procesos largos: `nohup ... &` en background da "completed" al instante (solo el desacople);
  vigilar el fin real con Monitor + `while pgrep -f ...; do sleep 10; done`. Comando exacto
  usado para `restoration_druid` (pesos preset, decisión 3, no necesita muchas iteraciones):
  `SIMX_DBC_DIR=/home/stark/Servers/acore-playerbots/data/dbc python3 simular_builds.py --spec restoration_druid --iterations 100`

## Fallos confirmados (resolver con Opus, esfuerzo alto)

**Estado (2026-09-27): F1 y F3 hechos, sin commit, pendientes de prueba en juego.** F1: `pseudoStats`
→ `weaponDps = {mainHand|offHand|ranged}` por build + `feralWeaponAp = {base = 767, perDps = 14}`
en specs ferales (fórmula del core `ItemTemplate::getFeralBonus`, recorta a 0); addon
`ScoreWeaponDps`. Peso real preraid 8.72 dps/DPS de arma = 16.8 × PA (14 × 1.2 Golpes
depredadores). EP vs delta simulado en 2M a 80: pendiente 1.02, r 0.97 (antes 4.04). F3: textura
`Interface\Buttons\Arrow-Up-Up` desaturada y teñida, 20/15 px, silueta negra, marco hijo por encima.

**Tras la 1ª prueba en juego (commit `ee03215`):** flecha poco visible → brillo
`UI-ActionButton-Border` (ADD) + flecha sin desaturar; usabilidad nunca detectaba rojo (tooltip
oculto sin dueño → 0 líneas) → `SetOwner` por escaneo, no cachear con 0 líneas; mano izquierda
con 2M equipada → se compara contra la 2M. Sin cambio (correcto): DPS de arma < 54.8 vale 0 para
Feral, así que espada (+1 fue) > bastón (agu/esp) y roble = fresno.

**Tras la 2ª prueba (commit `6c45465`):** con SimulateX activo el cliente no pinta el rojo de
"no usable" ni en el tooltip visible ni en el oculto (debug: 9 líneas, ninguna roja); sin el
addon sí. Causa: construir el tooltip oculto (`SetOwner`/`SetHyperlink`) dentro de
`OnTooltipSetItem` y en las actualizaciones de bolsas. Decisión 7 sustituida: el addon no
construye tooltips. Usabilidad = `SimulateX_ItemTypes` (id → clase×100+subclase) +
`SimulateX_ItemClasses` (AllowableClass restringido), ambos de `generar_tipos_objeto.py`, +
`CLASS_PROFICIENCIES` en `SimulateX.lua` (malla/placas a 40) + nivel mínimo de `GetItemInfo`. No
cubre armas no entrenadas (p. ej. guerrero sin armas de asta). Tras la 3ª prueba (commit `961acae`) el rojo
seguía perdiéndose. Hipótesis: `GetItemStats` (única API que usa SimulateX y no los demás addons
de tooltip; que haga falta borrar Cache apunta a la caché de objetos del cliente). El usuario no
quiso hacer la prueba aislada. Decisión 1 cambiada: sin `GetItemStats`; estadísticas desde
`SimulateX_ItemStats.lua` (`generar_estadisticas_objeto.py`: item_template + DBC
RandPropPoints/SpellItemEnchantment/ItemRandomProperties/ItemRandomSuffix/ScalingStat*,
fórmulas del core). APIs de cliente que quedan: `GetItemInfo`, `tooltip:GetItem()` (las usan
también sus otros addons). Pendiente de confirmar en juego. Posible mejora a valorar: a
nivel < 80 el % es sobre el EP del equipo, no sobre el DPS real, e infla las cifras.

### F1 — DPS de arma ignorado en la puntuación (confirmado en juego)
`/simulatex debug` sobre un arma devuelve `ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10.999…`
(float). Ninguna parte lo usa: `SimulateX.lua` no lo tiene en `DIRECT_WEIGHT_KEYS`/
`SCALABLE_BY_LEVEL`, y `generar_db_addon.py::compute_stat_weights` descarta `pseudoStats`
(solo lee `dps.weights.stats`). Síntoma: dos bastones de DPS muy distinto salen "≈ igual" para Feral.
- Propagar `pseudoStats` (índices proto: 0 MainHandDps, 1 OffHandDps, 2 RangedDps) a `weights`
  como `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`, eligiendo según slot (arma a distancia → RangedDps,
  p. ej. cazador). Hoy `pseudo_stats_to_weigh` sale de `epPseudoStats` de `ui/<spec>/sim.ts`.
- Feral: peso MainHandDps medido ≈ 3.13 dps/pt con AP ≈ 0.224 → 3.13 ≈ 14 × 0.224, es decir el
  pseudo-peso ya incluye el PA feral de `druid/forms.go` (`fap = floor((dps − 54.8) × 14)`).
  **Pero** por debajo de 54.8 DPS de arma el PA feral es ≤ 0: a nivel bajo el DPS de arma no
  debería valer nada para Feral (a nivel 28 las armas rondan 11-26 DPS). Verificar el
  comportamiento real en el core (`StatSystem.cpp`, ¿se recorta a 0?) y modelarlo en el addon
  (peso lineal solo por encima del umbral). `mapeo_stats.py::feral_attack_power` hoy no se usa.
- El porcentaje (`ComputePercent`) y el "equipado" también cambian al arreglarlo; revalidar.

### F2 — Penetración de armadura a nivel 80 no cuadra (cerrado, no reproducible)
`gtCombatRatings.dbc` da 15.40 (CR_ARMOR_PENETRATION=24, fila 24×100+79); el plan esperaba ≈13.99.
Reverificado con la fórmula exacta del core (`Player::GetRatingMultiplier`,
`sGtOCTClassCombatRatingScalarStore.LookupEntry((clase−1)×32 + cr + 1)`, ratio en el 2º float
del registro): el factor de clase da 1.0 para las 10 clases jugables en `CR_ARMOR_PENETRATION`,
igual que en crítico/golpe/celeridad (que sí cuadran: 45.91/32.79, y druida 83.33 agi/1 %). El
13.99 del plan no cita ninguna fuente (ni una auditoría previa, ni un enlace, ni una comprobación
en juego); no se ha podido reproducir con ninguna combinación de estas DBCs. Se deja como está
(15.40 real), documentado en `generar_tablas_nivel.py`. No bloquea nada del resto de la tabla.

### F3 — Flecha de mejora demasiado sutil (petición del usuario)
`SimulateX.lua::UpdateUpgradeIcon`: textura `Interface\Buttons\UI-SortArrow` 14×14 (verde) /
10×10 (naranja) en BOTTOMLEFT; en juego pasa inadvertida. Darle más cuerpo (tamaño, contorno/
sombra o textura más visible). Verificar en FrameXML 3.3.5a
(`git clone --depth 1 https://github.com/wowgaming/3.3.5-interface-files` en el scratchpad)
que la textura elegida existe; no suponer rutas.

## Pendientes conocidos (no son fallos)

- **Bug de build_id y su fix derivado**: resuelto, ver estado exacto arriba (dos bugs
  distintos, ambos corregidos y verificados con las 4 specs de druida completas).
- Sin probar en juego: hooks de vendedor/banco, tooltip de tanque (Supervivencia + Amenaza),
  objetos con sufijo aleatorio, detección de rojo con el pecho de malla del bug v0.2, y
  las 3 specs nuevas (Equilibrio/Guardián/Restauración) recién consolidadas.

## Paso 7 (resto del plan)
F1/F3 probados en juego y aprobados por el usuario. **7.2 completo**: las 4 specs de
druida simuladas y consolidadas en `SimulateX_Data_Druid.lua` (ver estado arriba). Falta
el commit + push (pedir permiso) y que el usuario pruebe en juego. Después: 7.3-7.4
(resto de clases — ojo con el bug #2 de validación de objetos base si alguna otra spec
tiene variantes de APL por gear_file, ya corregido en el código pero vigilar el primer
relanzamiento de cada una).

## Preferencias del usuario
- Hablar siempre en castellano.
- Dudas y fallos se resuelven con Opus; al cambiar de paso, anunciar modelo/esfuerzo y esperar.
- Commit y push solo cuando el usuario lo pide para esa acción; commits sin atribución a IA.
- Avisar cuando haya algo descargable y probable en juego.
