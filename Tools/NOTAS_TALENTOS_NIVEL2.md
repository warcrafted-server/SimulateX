# Notas de investigación — Nivel 1/2 de talentos (v0.7)

Registro de qué se comprobó por clase/spec al buscar variantes de talentos
con más DPS/HPS/TPS que la `StandardTalents` de wowsims, para no repetir la
investigación. Usa `Tools/buscar_margen_talentos.py --class-id X --game-class
Y --talents "..."` para listar los candidatos de una build nueva.

Un talento "sin efecto en la métrica primaria" (dps/hps/tps, la que mide
wowsims) no es lo mismo que "irrelevante": puede ahorrar maná, reducir
amenaza generada, dar control/CC, movilidad o supervivencia — cosas que la
simulación no puntúa pero sí importan en juego real. Cada candidato se
etiqueta como uno de:
- **DPS/HPS/TPS real** → variante de Nivel 2 legítima, se simula.
- **Utilidad secundaria** (maná, amenaza, CC, movilidad...) → no se simula
  como variante de rendimiento, pero se documenta qué aporta.
- **No implementado en wowsims** → no hay forma de medir su efecto con este
  motor, ni de rendimiento ni de utilidad.

## Druida

- **Feral (feral_druid)**: única variante de rendimiento real con esta build
  (`mas_potp`, mueve 2 puntos de un talento de maná a Protector de la manada
  + Tenacidad primigenia). Da el MISMO DPS hasta el decimal que la estándar:
  Protector de la manada solo afecta en forma de Oso (no de Gato). Tenacidad
  primigenia (Primal Tenacity) no aparece en wowsims — **utilidad**: en juego
  real reduce la duración de aturdimiento/miedo/desorientación sobre ti, CC
  que el motor no simula. Conclusión de rendimiento: la build estándar ya
  tiene todos los talentos ofensivos de Gato al máximo, sin ningún punto
  suelto con efecto real en DPS.
- **Equilibrio (balance_druid)**: sin variante posible. Candidatos con margen:
  Resplandor lunar (Moonglow) 1/3 — **utilidad**: -3% coste de maná de
  Fuego lunar/Fuerza estelar/Ira/Lluvia de estrellas por rango, implementado
  en el motor pero sin efecto en el DPS medido (solo en sostenibilidad de
  maná en encuentros largos); Alcance de la Naturaleza 1/2 y Frenesí de
  buhíco 1/3 sin implementar. Además, mover cualquiera rompe la cascada de
  puntos por fila (`required_points`) de una fila posterior: haría falta
  rediseñar varias filas a la vez, trabajo de Nivel 3.
- **Restauración (restoration_druid)**: sin variante de rendimiento. De los 4
  candidatos con margen: Sutileza (Subtlety) — **utilidad**: en juego real
  reduce la amenaza generada por las sanaciones (menos riesgo de robar aggro
  al tanque), sin implementar en wowsims. Alcance de la Naturaleza, Espíritu
  sosegado y Obsequio de la Naturaleza tampoco aparecen en el motor.
- **Guardián (feral_tank_druid)**: sin variante simple de rendimiento. Único
  candidato con margen es Furor (3/5, probabilidad de rabia extra al entrar
  en forma de Oso — sí implementado y con efecto real), pero está en la
  primera fila del árbol de Restauración de esta build y no hay ningún punto
  suelto en ese árbol para subirlo sin sacarlo de Feral, lo que rompería la
  cascada de Feral (que ya está también al óptimo, ver más arriba).

**Patrón repetido en las 4 specs de Druida**: la build estándar de wowsims ya
gasta sus puntos en un óptimo local dentro de su propio total. Encontrar algo
mejor exigiría permitir cambiar varias filas a la vez (más o menos puntos
totales, o redistribuciones de varias filas simultáneas), que es
precisamente el problema del Nivel 3 (búsqueda combinatoria), no del Nivel 2.

## Paladín

- **Sagrado (holy_paladin)**: cadena estándar tiene solo 2 bloques
  (`50350151020013053100515221-50023131203`), sin el tercer bloque de
  Reprensión: formato válido de wowsims (trunca el bloque entero si está
  vacío), ajustado `validar_talentos.py` para tolerarlo. Candidatos con
  margen: Anticipación (Anticipation, implementada) es +esquiva, sin aporte
  a HPS. Imposición de manos mejorada (Improved Lay on Hands) —
  **utilidad**: en juego real reduce el enfriamiento de Imposición de manos
  (salvavidas de emergencia para otro jugador), no implementado en wowsims.
  Consistencia sin implementar tampoco.
- **Protección (protection_paladin)**: candidatos: Armonización espiritual
  (`SpiritualAttunement`) sí implementada — **utilidad**: restaura maná al
  recibir daño, ayuda a sostener el maná del tanque en fights largos, sin
  efecto en amenaza/supervivencia medidas. Expiación, Oración y Sentencias
  mejoradas no aparecen en el motor (Oración/Sentencias mejoradas son de
  rango de bendiciones y menor coste de maná de Juicio, por lo que se sabe
  del talento real).
- **Reprensión (retribution_paladin)**: sin ningún candidato de subida (todo
  lo relevante ya está al máximo o a 0 sin puntos sueltos intermedios). Su
  cadena estándar además referencia un prerrequisito roto en las DBC
  (talento 1756 pide 1409, que no existe; ver validation.txt de la
  extracción) — añadido a `KNOWN_BROKEN_PREREQUISITES` en
  `validar_talentos.py` en vez de intentar adivinar el id correcto.

Mismo patrón que Druida: sin variante real de Nivel 2 en las 3 specs.
