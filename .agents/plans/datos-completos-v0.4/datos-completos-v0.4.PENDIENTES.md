# Datos completos v0.4 — PENDIENTES (traspaso a sesión nueva)

Plan: `datos-completos-v0.4.PLAN.md` (mismo directorio). Auditoría de errores E1-E8:
`.agents/plans/auditoria-v0.3/auditoria-v0.3.REVIEW.md`. Pasos 1-6 hechos y pusheados
(último commit `aee3dc8`); paso 7 sin empezar. Todo validado solo con `feral_druid`.

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
- Procesos largos: `nohup ... &` en background da "completed" al instante (solo el desacople);
  vigilar el fin real con Monitor + `while pgrep -f ...; do sleep 10; done`.

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
cubre armas no entrenadas (p. ej. guerrero sin armas de asta). Pendiente de confirmar en juego que
el rojo nativo vuelve. Posible mejora a valorar: a
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

### F2 — Penetración de armadura a nivel 80 no cuadra
`gtCombatRatings.dbc` da 15.40 (CR_ARMOR_PENETRATION=24, fila 24×100+79); el plan esperaba ≈13.99.
Factor de clase `gtOCTClassCombatRatingScalar.dbc` (record 8 bytes, ratio en 2º float,
índice `(clase−1)×32 + cr + 1`) da 1.0 para druida. Crítico/golpe/celeridad (45.91/32.79) y
druida 83.33 agi/1 % sí cuadran. Averiguar si 13.99 es de otra fuente/clase o si falta un factor.

### F3 — Flecha de mejora demasiado sutil (petición del usuario)
`SimulateX.lua::UpdateUpgradeIcon`: textura `Interface\Buttons\UI-SortArrow` 14×14 (verde) /
10×10 (naranja) en BOTTOMLEFT; en juego pasa inadvertida. Darle más cuerpo (tamaño, contorno/
sombra o textura más visible). Verificar en FrameXML 3.3.5a
(`git clone --depth 1 https://github.com/wowgaming/3.3.5-interface-files` en el scratchpad)
que la textura elegida existe; no suponer rutas.

## Pendientes conocidos (no son fallos)

- Solo `feral_druid` tiene datos → el tooltip no muestra "Otras: …" (Equilibrio, Guardián,
  Restauración se simulan en el paso 7).
- `Data/sims/feral_druid/p1..p4.json` son del pipeline anterior al fix E1 (sesgados);
  `preraid.json` es post-E1 pero solo 800 candidatos a 100 it. Resimular en el paso 7.
- `simular_builds.py`: dos builds con el mismo `gear_file` y distinto APL escriben el mismo
  `Data/sims/<spec>/<gear_file>.json` (la segunda pisa la primera).
- Sin probar en juego: hooks de vendedor/banco, tooltip de tanque (Supervivencia + Amenaza),
  objetos con sufijo aleatorio, detección de rojo con el pecho de malla del bug v0.2.
- Documentación del proyecto (`README.md`, `README.en.md`, `CHANGELOG.md`) sin actualizar
  para los pasos 1-6 (regla del `CLAUDE.md`: docs vivas en cada cambio). `.toc` sigue en 0.3.0
  (sube a 0.4.0 en el paso 7.2).
- `procesar_objetos.py`/`items_procesados.json` quedaron obsoletos (sustituidos por
  `extraer_objetos_bd.py`); no se han borrado.

## Paso 7 (resto del plan)
Tras arreglar F1 (y F3), el usuario vuelve a probar Feral en juego (nivel 28 con EP;
`/simulatex nivel 80` para la lógica de 80) y da el visto bueno antes de seguir con 7.2-7.4.

## Preferencias del usuario
- Hablar siempre en castellano.
- Dudas y fallos se resuelven con Opus; al cambiar de paso, anunciar modelo/esfuerzo y esperar.
- Commit y push solo cuando el usuario lo pide para esa acción; commits sin atribución a IA.
- Avisar cuando haya algo descargable y probable en juego.
