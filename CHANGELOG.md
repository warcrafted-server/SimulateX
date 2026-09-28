# Changelog - SimulateX

Todos los cambios notables de este proyecto serán documentados en este archivo.

## Sin publicar
### Añadido
- Comparador de equipo (v0.6): pon dos objetos, uno en cada hueco (arrastrando o con Mayús+clic), y compáralos entre sí o, si dejas el segundo vacío, contra lo que llevas puesto. Muestra el % de cada especialización y, para la tuya, en qué estadísticas se nota la diferencia. Se abre con `/simulatex comparar`, desde un botón en la hoja de personaje (junto al icono de cerrar), desde un icono en el minimapa, o desde la barra de wcdpanel si la tienes instalada.
- Icono propio de SimulateX (antes usaba uno genérico).
- Opción en el panel para quitar la flecha naranja (la que sale cuando el objeto solo mejora otra especialización). Activada por defecto.
- Opción en el panel para quitar el icono del minimapa.
### Cambiado
- Tooltip más claro: una línea por especialización con un único % de mejora o pérdida (verde/rojo, "≈ igual" en gris), sin unidades ni líneas de Supervivencia/Amenaza. La cabecera indica contra qué objeto equipado se compara.
- Por debajo de nivel 80 el % se calcula sobre el personaje entero (equipo puesto más estadísticas base), no solo sobre el equipo. Antes daba cifras infladas (p. ej. +115 % en Restauración por 15 de espíritu).
- Los tanques se valoran con la media de amenaza y supervivencia, igual que los pesos de tanque por defecto de wowsims. Sus simulaciones ahora usan el jefe y la curación por defecto de la interfaz de wowsims: sin curación el tanque moría y el daño recibido no medía lo que aguanta.
- Los sanadores con pesos simulados (Sanación de sacerdote) usaban por error los pesos de daño; ahora usan los de curación.
### Añadido (herramientas)
- `Tools/lote_simulaciones.sh`: cola de simulaciones en segundo plano que se puede relanzar tras un reinicio sin repetir lo hecho.
- `generar_extractores_go.py --spec` para regenerar una sola spec.
### Corregido
- Feral y Guardián contaban las dos como "tu spec" (comparten árbol de talentos), así que dos objetos podían salir como mejora el uno del otro. Ahora decide la forma: oso = Guardián, felina = Feral; en forma humanoide se usa la última forma.
- La flecha de mejora salía en casi cualquier objeto: por debajo de 80, Supervivencia y Amenaza eran la misma cifra con el signo cambiado, así que una de las dos siempre parecía mejorar.

## v0.3.0 - 2026-09-27
### Añadido
- Panel de configuración en Interfaz > AddOns (`/simulatexconfig` como alternativa): activar/desactivar el modo estimado de nivel 1-79, y elegir qué sub-especializaciones de la clase se muestran en el tooltip.

## v0.4.0 - 2026-09-28
### Añadido
- Puntuación en tiempo real por EP (puntos de equipo): pesos por estadística calculados con simulaciones reales de combate (motor wowsims) por spec y build, sustituyendo a `lowLevelScores`. Cubre cualquier objeto, incluidos sufijos aleatorios.
- Catálogo completo de nivel 80 filtrado por clase (tipo de armadura y arma que cada clase puede usar), en vez del catálogo parcial anterior.
- Escalado de pesos por nivel (`SimulateX_Levels.lua`) desde las tablas del propio servidor (`gtCombatRatings.dbc`, `gtChanceToMeleeCrit.dbc`, `gtChanceToSpellCrit.dbc`), no aproximaciones genéricas.
- Flecha de mejora también en la Casa de Subastas (buscar, mis pujas, mis subastas) y en el correo (bandeja y carta abierta).
- Datos reales de Druida: `feral_druid` (DPS), `balance_druid` (DPS), `feral_tank_druid` (tanque) simulados con el catálogo completo; `restoration_druid` (sanador) con pesos preset de wowsims, ya que su rotación en el motor de simulación da 0 HPS.
### Cambiado
- Marca de mejora más visible: brillo alrededor del icono (`UI-ActionButton-Border`) del color de calidad del objeto, para no confundir un objeto azul o morado con uno verde; la flecha sigue siendo verde para la spec activa y naranja para otra spec y flecha `Interface\Buttons\Arrow-Up-Up` teñida con contorno negro, por encima del borde del botón.
- `/simulatex debug` muestra si la clase tiene competencia con el tipo de objeto y si está en su lista de clases.
### Corregido
- La flecha de la Casa de Subastas no salía nunca: la interfaz de subasta se carga al abrirla por primera vez y el enganche se hacía antes. Además no tenía en cuenta el desplazamiento de la lista.
- Con el addon activo el juego dejaba de pintar en rojo lo no usable (p. ej. "Escudo" para druida). El addon ya no llama a `GetItemStats` ni construye tooltips: las estadísticas de cada objeto salen de la nueva tabla `SimulateX_ItemStats.lua` (item_template y DBC del servidor, generada con `Tools/generar_estadisticas_objeto.py`), incluidos sufijos y propiedades aleatorias ("del oso") y reliquias que escalan con el nivel. La usabilidad sale de `SimulateX_ItemTypes.lua` (tipo de objeto y clases permitidas, `Tools/generar_tipos_objeto.py`), de las competencias de cada clase (malla y placas a partir de nivel 40 donde toca) y del nivel mínimo de `GetItemInfo`.
- Un objeto con varios huecos de gema del mismo color contaba como uno solo en la puntuación.
- Una mano izquierda (escudo, sostener, arma de mano izquierda) con una 2M equipada se comparaba como hueco vacío; ahora se compara contra la 2M.
- El DPS de arma no contaba en la puntuación EP: dos armas con DPS muy distinto salían "≈ igual". Ahora se usan los pesos de DPS de arma de wowsims (`pseudoStats`: mano principal, mano izquierda o a distancia según el hueco). En Feral el DPS de arma solo aporta PA feral, que el servidor calcula como `int(dps × 14) − 767` sin bajar de 0, así que por debajo de ~54.8 DPS el arma no suma nada.
- La extracción de objetos de nivel 1-79 (`extraer_objetos_bd.py`) excluía por error todos los objetos con `RequiredLevel = 0` en `item_template` (frecuente en objetos de misión/mundo antiguos, ej. Bastón del purificador, Cinturón acuario). Regenerados los datos de Druida: 13569 objetos puntuados (antes 7963).
- La generación de simulación de nivel 80 fallaba para holy_paladin y restoration_druid: `generar_extractores_go.py` dejaba variables sin usar en el código Go generado cuando la spec no usa rotación por APL, y Go no compila con eso. No era una limitación de wowsims (como se documentó por error antes), sino un bug propio del generador.

## v0.2.1 - 2026-09-27
### Añadido
- Icono overlay de mejora (flecha verde = mejora en la spec activa, naranja = mejora en otra sub-spec de la clase) sobre el icono del objeto en bolsas, botín y recompensa de misión.
### Corregido
- Se perdía el coloreado nativo del juego (ej. "Malla" en rojo cuando la clase no puede vestirla) en la ventana de recompensa de misión: `tooltip:GetItem()` es conocido por fallar en tooltips poblados con `SetQuestItem`/`SetQuestLogItem`; ahora se detecta ese origen y se usa la API de misión en su lugar.

## v0.2.0 - 2026-09-27
### Añadido
- Tooltip multi-spec: en vez de una sola línea, muestra el delta de cada sub-spec real de la clase (ej. Beast Mastery/Marksman/Survival en Cazador), con puntos y porcentaje de cambio (`%+.1f%%`), marcando con `*` la spec activa detectada por talentos.

## - 2026-09-26
### Añadido
- Esqueleto inicial del addon en `Addon/SimulateX/` (`SimulateX.toc`, `SimulateX.lua`, `SimulateX_DB.lua`).
- Primer script de extracción `Tools/extraer_objetos.py` (pendiente de implementar contra `db.warcrafted.com`).
- Inicialización del repositorio git local.
- Creación de la estructura base del repositorio del proyecto.
- Configuración del entorno de desarrollo guiado por Inteligencia Artificial mediante `CLAUDE.md`.
- Inclusión de filtros estrictos en `.gitignore` para proteger las herramientas de extracción de datos privadas.
- Documentación inicial del proyecto en castellano (`README.md`) e inglés (`README.en.md`).
- Establecidas las bases para la integración de datos locales procedentes de la base de datos de `db.warcrafted.com`.
- Pipeline completo de simulación de nivel 80 con el motor `wowsims/wotlk`: extracción de builds de referencia (`generar_builds.py`, `emparejar_builds.py`), generación de `RaidSimRequest` por spec (`generar_extractores_go.py`), procesado de objetos extraídos (`procesar_objetos.py`) y orquestador de simulación con cálculo de delta por objeto (`simular_builds.py`).
- Licencia del proyecto fijada en GPL-3.0 (`LICENSE`); añadida atribución obligatoria a wowsims (licencia MIT) en `README.md`/`README.en.md`, ya que sus resultados de simulación son la fuente de las estadísticas del addon.
- Lógica del addon (`SimulateX.lua`): hook de tooltip, detección automática de build por talentos activos (con opción de forzarla manualmente vía `/simulatex`), y comparación estimada para niveles 1-79 contra el equipo actual del jugador.
- Primeros datos reales generados para Druida Feral: 5 builds de nivel 80 simuladas con wowsims (`SimulateX_Data_Druid.lua`) y 7963 objetos de nivel 1-79 puntuados por prioridad de estadística, extraídos de `acore_world` (acceso de solo lectura).
- Corregido un fallo de precisión: los objetos de armadura (tela/cuero/malla/placas) sin restricción de clase listada explícitamente en el tooltip se consideraban compatibles con cualquier clase; ahora se infiere del subtipo de armadura.
