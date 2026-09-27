# Auditoría SimulateX tras v0.3.0 (2026-09-27)

Revisión completa de pipeline de datos + addon. Todo lo marcado "confirmado" se
verificó contra los datos reales en `Data/` o el código actual.

## Errores (por gravedad)

### E1 — Deltas de nivel 80 sesgados: se pierden gemas y encantamiento (confirmado, crítico)
`Tools/simular_builds.py::swap_item_in_gear` sustituye el slot por `{"id": new_id}`,
descartando `enchant` y `gems` que sí lleva el objeto base del gearset
(ej. `feral_druid/p1`, slot 0: `{'id': 40473, 'enchant': 3817, 'gems': [41398, 39996]}`).
Prueba: el propio casco base 40473 sale con **−261 DPS respecto a sí mismo**;
254 de 302 candidatos de `feral_druid/p1` son negativos. Todos los datos de
nivel 80 ya simulados (incluido el lote en curso) están afectados.
Fix: al sustituir, conservar el `enchant` del slot base y rellenar los huecos
del candidato con las gemas estándar de la spec (las del propio gearset base;
meta solo en cabeza). Criterio de validación: delta del objeto base contra sí
mismo ≈ 0 (±ruido). Hay que re-simular todo tras el fix.

### E2 — Nivel 80 compara contra el gearset BiS de referencia, no contra lo equipado (confirmado por diseño)
El tooltip muestra "cambiar este slot en el BiS de la fase X", y además
`GetBestBuildPerSpec` elige siempre la fase más alta (P4/P5). Un 80 recién
subido ve casi todo en negativo. Fix: (a) mostrar `delta(candidato) −
delta(equipado)` en el mismo slot y build (ambos son sustituciones sobre la
misma base, así la diferencia es una buena aproximación); (b) elegir la fase
según el nivel de objeto medio equipado del jugador, no la más alta.

### E3 — Flechas nunca aparecen por debajo de nivel 80 (confirmado, causa del reporte)
`GetUpgradeMarker` devuelve `nil` si `UnitLevel < 80`. No es un fallo de los
hooks. Fix: marcador también en nivel bajo, comparando score vs equipado —
pero solo tras arreglar E4/E5, si no se marcarían como mejora objetos que el
druida ni puede usar.

### E4 — Puntuación de nivel bajo incluye objetos no usables (confirmado)
`calcular_score_bajo_nivel.py::is_compatible` deja pasar cualquier arma y
no usa `allowable_class_mask` (se extrae pero se ignora). Para Druida: 2927
armas no usables (hachas, espadas, arcos, armas de fuego, ballestas, varitas)
y 405 objetos restringidos a otras clases están puntuados. Fix: filtrar por
`allowable_class_mask` y por tabla de habilidades de arma por clase (3.3.5a).

### E5 — Puntuación de nivel bajo ignora la mayoría de estadísticas (confirmado)
Solo pondera ids 3,4,5,6,7 (agi/fue/int/esp/aguante) + ilvl. Ignora crítico
(32, 2656 objetos), resiliencia (35), golpe (31), celeridad (36), poder con
hechizos (45), poder de ataque (38), pericia (37), defensa/esquivar/parar
(12-15), y también armadura y DPS de arma. Ej.: Cinturón acuario (+6 crit,
+5 golpe) puntúa 21.0 = solo su ilvl. Además solo existen pesos de
`feral_druid` y se aplican a las 4 specs de Druida (Equilibrio/Restauración
reciben pesos feral).

### E6 — Comparación de slots dobles y armas (confirmado en código)
Anillos/abalorios se comparan solo contra `Finger0Slot`/`Trinket0Slot`
(debería ser contra el peor de los dos). Arma 2M vs 1M+mano izquierda no se
contempla. `GetItemInfo` puede devolver nil si el objeto no está en caché.

### E7 — Catálogo de nivel 80 muy reducido (confirmado)
`items_procesados.json` = 1071 objetos (los que aparecen en los gearsets de
wowsims, vía XML de AoWoW). Faltan recompensas de misión de 80, heroicas,
crafteos, emblemas… La mayoría de objetos de 80 que verá un jugador no
tendrá línea. Con acceso a `acore_world` se puede sacar el catálogo completo
(ilvl ≥ ~180) y filtrar por los que existan en la BD de wowsims.

### E8 — Menores
- Tanques muestran "DPS": para tanque el dato útil es TPS/daño recibido.
- 300 iteraciones: con semilla fija (101) hay números aleatorios comunes, pero
  deltas < ~0.5 % pueden ser ruido; marcarlos como "≈0" en vez de ±.
- Línea "SimulateX (estimado): 31 puntos" sin referencia no le dice nada al
  jugador (sale así cuando el equipado no está en datos o el slot está vacío).

## Rumbo: qué cambiaría
1. **Parar funcionalidad nueva (v0.4/v0.5) hasta arreglar la base de datos**:
   con E1/E2 los números de nivel 80 no son fiables, y un comparador o
   recomendador encima heredaría el error.
2. **Pesos de estadística derivados de simulación, por spec** (lo que supera a
   Pawn): Pawn usa escalas fijas de terceros. Con wowsims podemos calcular EP
   reales por spec y fase (+X de cada stat sobre el gearset base) y usarlos
   para puntuar **cualquier** objeto, de cualquier nivel, incluidos los que
   no están en el catálogo simulado. Arregla E5 y cubre E7 de paso; la
   simulación directa por objeto queda como dato "exacto" cuando existe.
3. Nuevo orden propuesto:
   - v0.4 — Datos correctos: E1 + E4 + E5 (pesos por spec simulados) + E7.
   - v0.5 — Comparación real contra equipado: E2 + E3 + E6, tooltip nuevo.
   - v0.6 — Comparador de equipo (antiguo v0.4).
   - v0.7 — Recomendador de talentos (antiguo v0.5).

## Funciones de Pawn (retail) a igualar o superar
- Flecha de mejora + % vs equipado en bolsas, botín, recompensas, vendedor,
  banco. (Añadir: ventana de vendedor/banco, no cubiertas hoy.)
- Comparar contra el peor de los 2 anillos/abalorios; 2M vs 1M+MI.
- Gemas: valor del objeto con las mejores gemas para la spec (opción de
  respetar o no la bonificación de ranura).
- "Mejor objeto en bolsas para este slot".
- Escalas por spec seleccionables; nosotros: derivadas de simulación y
  por fase (ventaja clara).
- Ventana de comparación de dos objetos (ya en roadmap).

## Tooltip propuesto
```
SimulateX — Feral (tu spec)          +3.2 %  (+142 DPS)
  vs. equipado: Guantes X             
  Otras specs: Equilibrio −0.4 %, Restauración +1.1 % HPS
```
- Una línea principal grande para la spec activa, % primero (comparable entre
  niveles), valor absoluto entre paréntesis.
- Resto de specs compactas en una línea, grises.
- Etiqueta de origen: "simulado" (dato exacto de wowsims) vs "estimado"
  (pesos), para que el jugador sepa cuánto fiarse.
- Deltas dentro del ruido → "≈ igual".

## Suficiencia de datos por spec (estado a 2026-09-27)
| Área | Estado |
|---|---|
| Nivel 80, 20 specs | Lote en curso; datos sesgados por E1, hay que re-simular tras el fix |
| Nivel 80, catálogo | 1071 objetos, insuficiente (E7) |
| Nivel 1-79 | Solo Druida, con pesos feral para las 4 specs, estadísticas parciales (E4/E5) |
| Resto de clases 1-79 | Sin datos |
