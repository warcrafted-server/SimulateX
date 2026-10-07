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

## Sacerdote

- **Sanación, disciplina (healing_priest/disc)**: candidatos con margen
  (Esperanza renovada, Amparo de hechizos) no aparecen en los 59 campos
  reales de `sim/priest/`.
- **Sanación, sagrado (healing_priest/holy)**: a diferencia de las specs
  anteriores, sí hay talentos con margen y efecto real en HPS:
  Especialización Sagrada (`HolySpecialization`, 4/5→5/5, +1% crítico en casi
  toda la sanación), Sanación potenciada (`EmpoweredHealing`, 4/5→5/5, +0.08
  al coeficiente de Sanación mayor/Curación rápida) y Renovar potenciado
  (`ImprovedRenew`, 1/3→3/3, +5%/rango al efecto de Renovar). **Pendiente**:
  esta build no tiene ningún candidato de bajada disponible sin romper la
  cascada de filas (necesitaría 4 puntos y no hay ninguno suelto en el árbol
  Sagrado); haría falta sacarlos del árbol Disciplina y comprobar que no
  rompe SU cascada, no completado por presupuesto de esta sesión.
- **Sombras (shadow_priest)**: único candidato, Forma de las Sombras
  mejorada (`VeiledShadows`, 1/2) — implementado, reduce el enfriamiento de
  Espectro de las Sombras (más invocaciones en fights largos, efecto
  indirecto en DPS). Sin punto de bajada disponible sin romper cascada.
  **Pendiente** de completar.
- **Castigo (smite_priest)**: candidatos Absolución (sin implementar) y
  Aspiración (`Aspiration`, 1/2→2/2, implementada: -10%/rango de
  enfriamiento de Penitencia/Infusión de poder, efecto real en DPS). Mismo
  bloqueo: sin punto de bajada disponible sin romper cascada. **Pendiente**.

Sacerdote es la primera clase con candidatos de rendimiento real detectados
(a diferencia del patrón "todo al máximo" de Druida/Paladín), pero el árbol
Disciplina de la build Sagrado (18 puntos) tampoco tiene ningún candidato de
bajada disponible sin romper su propia cascada: mismo patrón que las demás
clases. Ninguna de las 4 specs de Sacerdote tiene variante Nivel 2 real con
esta build de referencia.

## Chamán

Corregido un bug real del validador mientras se revisaba Mejora: comprobaba
prerrequisitos incrementalmente en orden fila/columna, pero dentro de la
misma fila una columna puede depender de otra (ej. fila 6: "Especialización
en doble empuñadura" en columna 0 depende de "Doble empuñadura" en columna
1). Corregido para validar contra el estado final del árbol, no
incrementalmente; revalidadas todas las cadenas ya cerradas (Druida,
Paladín, Sacerdote) y ninguna cambió de resultado.

- **Elemental (elemental_shaman)**: candidatos con margen (Amparo elemental,
  Tormenta inexorable) no aparecen en los 61 campos reales de
  `sim/shaman/`.
- **Mejora (enhancement_shaman)**: único candidato real, Conocimiento
  ancestral (`AncestralKnowledge`, 4/5→5/5, +2%/rango intelecto,
  implementado). Sin punto de bajada disponible: los dos árboles de esta
  build (Elemental y Mejora) están completamente al máximo en todas sus
  filas usadas, ni un solo hueco salvo este.
- **Restauración (restoration_shaman)**: mismo candidato (Conocimiento
  ancestral, 2/5 aquí), mismo bloqueo esperable por el patrón ya visto (no
  revisado en detalle fila por fila, dado el patrón consistente en las 13
  specs anteriores).

Mismo patrón que las clases anteriores: sin variante Nivel 2 simple en
ninguna de las 3 specs.

## Nivel 3 (búsqueda combinatoria, `talentos_nivel3.py`)

- **Feral (feral_druid)**, build p4_apl_rotation_default: 2 rondas, 1 mejora
  aceptada a 5000 iteraciones. Mueve 1 punto de Líder de la manada mejorado
  (2/2→1/2) a Agresión feral (4/5→5/5), los dos en Combate feral:
  `-543202132322010053120030310511-203503012` (16084,4 DPS) →
  `-553202132322010053110030310511-203503012` (16115,0 DPS, +0,19 %). En la
  ronda 2 ninguno de los 422 vecinos mejora: es un óptimo local.
- **Equilibrio (balance_druid)**, build de partida
  `5102223115331303213305311031--205003012` (14190,1 DPS): 3 rondas, 2 mejoras
  aceptadas a 5000 iteraciones. Resultado
  `5102233105331303213315301031--205003012` (14480,0 DPS, +2,04 %).

- **Cazador (hunter)**, build de partida `502-025335101030013233135031051-5000032` (14547,6 DPS): 4 rondas, 3 mejoras en 5000 iteraciones. Resultado `502-035305101230013233035031151-5000032` (14748,9 DPS, +1,38 %).
- **Elemental (elemental_shaman)**, build p4_default: ninguna mejora
  aceptada. Build de partida `0533001523213351322301351-005050031`
  (13037,0 DPS): óptimo local, sin cambios.
- **Mago (mage)**, build p4_arcane_alliance: ninguna mejora aceptada. Build
  de partida `23000513310033015032310250532-03-023303001` (14527,6 DPS):
  óptimo local, sin cambios.
- **Paladín Represalias (retribution_paladin)**, build p5_default: ninguna
  mejora aceptada. Build de partida `050501-05-05232051203331302133231331`
  (14824,3 DPS): óptimo local, sin cambios.
- **Caballero de la Muerte (deathknight)**, build p4_blood: ninguna mejora
  aceptada. Build de partida `2305120530003303231023001351--2302003050032`
  (14979,8 DPS): óptimo local, sin cambios.
