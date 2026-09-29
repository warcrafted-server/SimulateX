# SimulateX — estado del proyecto (29-09-2026, antes de un /clear)

Adaptador de WoW WotLK 3.3.5a. Compara equipo, colorea tooltips y ahora
empieza a comparar árboles de talentos, todo con datos de simulación real
(wowsims) y DBC reales del servidor, nunca inventados. Este documento es
autocontenible: una sesión nueva puede retomar el trabajo solo con esto,
sin releer la conversación anterior.

## 1. Qué hay hecho y publicado

### v0.2–v0.6 — Base del addon (cerradas, no tocar sin pedirlo)
- Tooltip multi-spec con flecha de mejora e icono overlay en bolsas/botín.
- Panel de configuración (Interfaz > AddOns).
- **v0.4**: motor de puntuación en tiempo real desde datos propios del
  servidor (sin `GetItemStats` propio, para no romper el coloreado nativo
  del cliente). Pesos EP por spec, simulados con wowsims. Catálogo de
  nivel 80. *(Datos de v0.4 en progreso por clase, ver sección 2.)*
- **v0.6**: Comparador de equipo (`/simulatex comparar`, botón en la hoja
  de personaje, icono de minimapa, barra de wcdpanel). Ventana con 3
  pestañas: Comparador, Talentos (nueva, v0.7), Configuración.
  - Dos huecos (A y B, o A contra lo equipado si B vacío).
  - Anillos y abalorios: tercera casilla automática, comparación contra
    los dos equipados a la vez.
  - Tarjeta con icono, nombre coloreado por calidad, nivel, tipo, ranura,
    todas las estadísticas (verde/rojo según mejora o empeora).
  - % por especialización, desglose de qué estadística marca la
    diferencia, aviso si el objeto trae gemas/encantamiento (no cuentan).
  - Ventana ampliada a 940×600 para que quepan los 3 árboles de talentos.

### v0.7 — Pestaña Talentos (en marcha)
**Nivel 1/2** (comparar unas pocas distribuciones de talentos ya
simuladas, no explorar el árbol entero): implementado y funcionando.
- `Tools/talentos_referencia/` — extracción de `Talent.dbc`/`TalentTab.dbc`
  reales del servidor (aportada por el usuario, no generada por el
  agente): fila, columna, rango máximo, prerrequisitos de cada talento de
  las 10 clases. Única fuente de verdad; ninguna variante se inventa.
- `Tools/validar_talentos.py` — valida cualquier cadena de talentos
  (formato wowhead) contra esa extracción antes de simular nada. Tolera
  bloques truncados (formato real de wowsims) y dos prerrequisitos rotos
  conocidos en las DBC (`KNOWN_BROKEN_PREREQUISITES`).
- `Tools/buscar_margen_talentos.py` — cruza los talentos con margen
  (por debajo de su máximo) contra los campos `Talents.X` que el motor Go
  de wowsims realmente usa, para no tener que leer el árbol entero a mano
  por cada spec.
- `Tools/simular_talentos.py` — simula variantes de talentos con el mismo
  gear/APL ya elegido para una build (reutiliza `SIMX_TALENTS`). Guarda el
  resultado tras cada variante (reanudable si el reinicio de las 04:00
  corta el proceso a medias); `--force` repite lo ya hecho.
- `Tools/generar_arbol_talentos.py` / `Tools/generar_db_talentos.py` —
  consolidan a `Addon/SimulateX/Data/SimulateX_ArbolTalentos_<Clase>.lua`
  (estructura fija de las 10 clases, generado de una vez) y
  `SimulateX_Talentos_<Clase>.lua` (variantes por spec, solo donde hay
  algo que simular).
- `Addon/SimulateX/UI/Talentos.lua` — dibuja los 3 árboles reales con
  iconos del juego a tamaño real (32px), líneas de conexión con las
  texturas nativas de Blizzard, borde dorado fino en los talentos con
  puntos. Desplegable (no pestañas, para aguantar el Nivel 3) a la derecha
  del título, con el valor de cada distribución integrado en la opción.
  Reacciona a `UPDATE_SHAPESHIFT_FORM` (Druida cambia de árbol al
  cambiar de forma).

**Nivel 3** (búsqueda combinatoria real de la mejor distribución): no
empezado. Ver sección 3.

## 2. Datos de simulación por clase (v0.4 + v0.7 Nivel 1/2)

Cola de gear: `Tools/lote_simulaciones.sh`, reanudable tras el reinicio
del servidor a las 04:00 (no repite lo ya simulado). Se relanza con:
```
cd /home/stark/Repos/addons/SimulateX && nohup nice -n 10 Tools/lote_simulaciones.sh > Data/logs/lote.log 2>&1 & disown
```

| Clase | Gear (v0.4) | Talentos Nivel 1/2 (v0.7) |
|---|---|---|
| Druida | Completo, 4 specs | **Cerrado.** Feral tiene 2 variantes reales (empatan en DPS: la build estándar ya está al óptimo). Equilibrio/Restauración/Guardián sin variante posible (detalle abajo). |
| Paladín | Completo, 3 specs | **Cerrado**, sin variante real en ninguna spec. Reprensión tiene un prerrequisito roto en las DBC (documentado, no adivinado). |
| Sacerdote | Completo, 4 specs | **Cerrado**, sin variante real en ninguna spec (Sagrado sí tiene candidatos con efecto en HPS, pero sin punto de bajada disponible sin romper la cascada del árbol; ver nota). |
| Chamán | Elemental completo, Mejora y Restauración con varias fases | Elemental **cerrado** (sin variante). Mejora/Restauración: no investigadas todavía. |
| Cazador | **Recién consolidado** (12 builds, Puntería+Supervivencia, preraid-p5) | No empezado |
| Mago, Pícaro, Brujo, Guerrero, Caballero de la Muerte | Sin datos de gear todavía; siguientes en la cola | No empezado |

**Patrón repetido en las 13 specs ya investigadas** (documentado en
`Tools/NOTAS_TALENTOS_NIVEL2.md`, que también explica el porqué
talento por talento): la build `StandardTalents` de wowsims casi siempre
ya está en un óptimo local dentro de su propio total de puntos. Mover 1-2
talentos sueltos no mejora nada, porque:
1. El único margen disponible suele ser un talento sin implementar en
   wowsims (rango de hechizo, amenaza, duración de CC…), o
2. Mover un punto rompe la cascada de puntos-por-fila de otra parte del
   árbol.
Esto no es "no hay nada que optimizar", es "un simple intercambio de 1-2
puntos no basta": encontrar algo mejor exige redistribuir varias filas a
la vez, que es exactamente el problema del **Nivel 3**.

## 3. Pendiente

### Inmediato
- Terminar la cola de gear v0.4: Mago, Pícaro, Brujo, Guerrero, Caballero
  de la Muerte (y Mejora/Restauración de Chamán si no llegaron completas).
- Seguir Nivel 1/2 de talentos en Cazador y en cada clase según vaya
  teniendo datos de gear.
- **Confirmación pendiente del usuario**: la pestaña Talentos rediseñada
  (desplegable a la derecha, iconos más pequeños, borde sutil) se subió
  pero no se ha visto todavía en el juego tras el último cambio.

### Nivel 3 (diseño, no empezado)
Búsqueda combinatoria real: encontrar la mejor distribución de talentos
explorando más allá de mover 1-2 puntos. Acordado con el usuario:
- Empezar por Druida, seguir por el resto de clases.
- El script debe guardar progreso y poder reanudarse tras el reinicio de
  las 04:00 (mismo patrón que `simular_talentos.py`/`simular_builds.py`
  ya usan).
- Antes de escribir código: pausar y proponer modelo/esfuerzo (es un
  problema de otra escala: miles de simulaciones, poda, criterios de
  parada), como ya se acordó para este tipo de tarea.

## 4. Decisiones y reglas aprendidas en esta sesión (no repetir el error)

- **Nunca inventar una distribución de talentos.** Ni deducir máximos de
  rango de fórmulas del código Go del motor, ni de conocimiento general
  del juego. Única fuente: `Tools/talentos_referencia/` (extracción de
  DBC reales, aportada por el usuario) vía `validar_talentos.py`.
- Un talento "sin efecto en DPS/HPS/TPS" (la métrica que mide wowsims) no
  es "irrelevante": puede ahorrar maná, reducir amenaza, dar CC o
  movilidad. Se documenta como "utilidad secundaria", nunca se descarta
  sin más.
- El formato de cadena de wowhead trunca bloques/ceros finales: una
  cadena con menos de 3 bloques `-`, o más corta que el árbol, es válida.
- Dentro de la misma fila de un árbol, una columna puede depender de otra
  de esa misma fila con índice mayor (bug real que hubo que corregir en
  el validador: no comprobar prerrequisitos incrementalmente en orden
  columna, sino contra el estado final del árbol).
- `UIDropDownMenu_Initialize` con la función completa que rellena las
  opciones se llama **una sola vez**, al construir el frame — nunca en
  cada refresco de la UI (reinicializa frames globales compartidos de
  todo el juego y puede cortar la ejecución a medias).
- Un frame sin anclaje de ancho explícito (o sin dos anclajes opuestos)
  se queda con ancho 0 y el juego no lo dibuja, ni tampoco lo que esté
  anclado a su borde.
- Las pruebas con mocks (`test_ventana.py`, `test_comparador.py` en el
  scratchpad de la sesión, no en el repo) verifican que el motor/UI no
  lanza errores de Lua, pero no detectan fallos de layout real
  (anchos/posiciones) ni problemas de la API real del juego que el mock
  simplifica. La prueba de verdad es el usuario en el juego.
- Commits y push de datos de clase (v0.4) completada: autorizado sin
  preguntar cada vez, según acuerdo previo del usuario ("cuando termines
  una rama/clase, commit y push"). Cambios de código/UI: sí llevan commit
  normal, también ya autorizado en esta sesión para v0.7.

## 5. Cómo retomar

1. Comprobar si `Tools/lote_simulaciones.sh` sigue vivo
   (`pgrep -f lote_simulaciones.sh`) y si no, relanzarlo (comando arriba).
2. Mirar `Data/logs/lote.log` para ver la última clase terminada.
3. Consolidar con `python3 Tools/generar_db_addon.py --clase <Clase>`
   (puede tardar más de 2 minutos con clases grandes: lanzar con `nohup`
   en segundo plano, no bloquear el turno).
4. Para talentos de una clase nueva: `Tools/buscar_margen_talentos.py`
   para ver candidatos, revisarlos contra el código Go de wowsims
   (`Tools/wowsimcli-src/sim/<clase>/`), y solo si hay margen real
   construir la variante con `Tools/validar_talentos.py` antes de
   simular. Documentar el resultado (haya o no variante) en
   `Tools/NOTAS_TALENTOS_NIVEL2.md`.
